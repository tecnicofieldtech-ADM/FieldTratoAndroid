import "package:uuid/uuid.dart";

import "../constants/config_options.dart";
import "../db/app_db.dart";
import "../features/fabricacao/domain/fabricacao_flow.dart";
import "../repo/user_repo.dart";
import "../services/api_service.dart";
import "../services/session_service.dart";
import "../utils/ms_percent.dart";

class OutboxSync {
  final ApiService api;
  static const _uuid = Uuid();
  final UserRepo _userRepo = UserRepo();

  OutboxSync({required this.api});

  String _s(dynamic v) => (v ?? "").toString().trim();

  int _toInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.round();
    final t = _s(v).replaceAll(",", ".");
    if (t.isEmpty) return 0;
    final asInt = int.tryParse(t);
    if (asInt != null) return asInt;
    return double.tryParse(t)?.round() ?? 0;
  }

  Future<String> _fetchUsuarioNome(String id) async {
    final key = id.trim();
    if (key.isEmpty) return "";
    final row = await _userRepo.findById(key);
    return _s(row?["NOME"]);
  }

  String _motoristaNomeLogin() =>
      (SessionService.instance.current?.nome ?? "").trim();

  double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();

    var t = v.toString().trim();
    if (t.isEmpty || t.toLowerCase() == "null") return 0;

    final hasComma = t.contains(",");
    final hasDot = t.contains(".");

    if (hasComma && hasDot) {
      t = t.replaceAll(".", "").replaceAll(",", ".");
    } else if (hasComma) {
      t = t.replaceAll(",", ".");
    }

    return double.tryParse(t) ?? 0;
  }

  String _toBrIntStr(dynamic v) {
    final d = _toDouble(v);
    return d.round().toString();
  }

  String _br3(dynamic v) {
    final d = _toDouble(v);
    if (d == 0) return "0";
    return d.toStringAsFixed(3).replaceAll(".", ",");
  }

  String _br2(dynamic v) {
    final d = _toDouble(v);
    if (d == 0) return "0";
    return d.toStringAsFixed(2).replaceAll(".", ",");
  }

  /// MS fornecimento: fabricação (MS_REALIZADA) → dieta (DIETA.MS); 0 < MS <= 100.
  static const String _sqlMsFornecResolved = """
    CASE
      WHEN COALESCE(cfr.MS_REALIZADA, 0) > 0 AND COALESCE(cfr.MS_REALIZADA, 0) <= 100
        THEN cfr.MS_REALIZADA
      WHEN COALESCE(d.MS, 0) > 0 AND COALESCE(d.MS, 0) <= 100
        THEN d.MS
      ELSE 0
    END""";

  /// Fornecimento so sobe apos a fabricacao vinculada ter FLAG_SYNC=1 no tablet.
  static const String _sqlFornecFabSyncGate = """
    (
      TRIM(COALESCE(cf.ID_FABRICACAO, '')) = ''
      OR EXISTS (
        SELECT 1 FROM CADASTRO_FABRICA_RACAO cfr_gate
        WHERE TRIM(cfr_gate.ID) = TRIM(cf.ID_FABRICACAO)
          AND IFNULL(cfr_gate.FLAG_SYNC, 0) = 1
      )
    )""";

  /// Lote TGC (max 20) derivado do handoff/UUID — vincula CAD_BATIDA e CAD_FORNECIMENTO.
  String _tgcLoteFabricacao(String handoffOrUuid) {
    final compact =
        handoffOrUuid.replaceAll(RegExp(r"[\s\-]"), "").toUpperCase();
    if (compact.isEmpty) return "";
    final maxLen = ConfigOptions.tgcLoteFabricacaoMaxLen;
    if (compact.length <= maxLen) return compact;
    return compact.substring(0, maxLen);
  }

  void _putLoteTgc(Map<String, dynamic> map, String handoffId) {
    final lote = _tgcLoteFabricacao(handoffId);
    if (lote.isEmpty) return;
    map["lote_fabricacao"] = lote;
    map["CBT_LOTE_FABRICACAO"] = lote;
    map["CFORN_LOTE_FABRICACAO"] = lote;
  }

  Future<void> _marcarFornecimentoSyncOk(dynamic db, String idCadastro) async {
    final id = idCadastro.trim();
    if (id.isEmpty) return;

    final rows = await db.rawQuery("""
      SELECT
        COALESCE(ID_FORNECIMENTO, '') AS id_fornecimento,
        COALESCE(ID_BAIA, '') AS id_baia,
        COALESCE(TRATO, 0) AS trato,
        substr(COALESCE(DATA, ''), 1, 10) AS data_ymd,
        COALESCE(REALIZADO, 0) AS realizado,
        IFNULL(FLAG_SYNC, 0) AS flag_sync
      FROM CADASTRO_FORNECIMENTO
      WHERE ID = ?
      LIMIT 1
    """, [id]);
    if (rows.isEmpty) return;

    final alreadySynced =
        (int.tryParse("${rows.first["flag_sync"]}") ?? 0) == 1;
    if (alreadySynced) return;

    await db.update(
      "CADASTRO_FORNECIMENTO",
      {"FLAG_SYNC": 1},
      where: "ID = ?",
      whereArgs: [id],
    );

    final delta = _toDouble(rows.first["realizado"]);
    final idForn = _s(rows.first["id_fornecimento"]);
    final idBaia = _s(rows.first["id_baia"]);
    final trato = int.tryParse("${rows.first["trato"]}") ?? 0;
    final dataYmd = _s(rows.first["data_ymd"]);
    if (delta <= 0 || idForn.isEmpty || idBaia.isEmpty || trato <= 0) return;
    if (dataYmd.length != 10) return;

    // Absorve a sessão no acumulado da API para o mapa não perder kg
    // entre o FLAG_SYNC=1 e o próximo download da previsão.
    await db.rawUpdate("""
      UPDATE PREVISAO
      SET REALIZADO_KG = COALESCE(REALIZADO_KG, 0) + ?
      WHERE TRIM(ID_FORNECIMENTO) = TRIM(?)
        AND TRIM(ID_BAIA) = TRIM(?)
        AND TRATO = ?
        AND substr(COALESCE(DATA, ''), 1, 10) = ?
    """, [delta, idForn, idBaia, trato, dataYmd]);
  }

  Future<double> _fetchDietaMs(dynamic db, String idDieta) async {
    final id = idDieta.trim();
    if (id.isEmpty) return 0;
    final rows = await db.rawQuery(
      "SELECT COALESCE(MS, 0) AS ms FROM DIETA WHERE TRIM(ID) = TRIM(?) LIMIT 1",
      [id],
    );
    if (rows.isEmpty) return 0;
    final v = _toDouble(rows.first["ms"]);
    return MsPercent.isValid(v) ? v : 0;
  }

  double _resolveMsPayload({
    required double msFabricacao,
    required double msDieta,
  }) {
    return MsPercent.resolve(msFabricacao: msFabricacao, msDieta: msDieta);
  }

  String _toBrDate(dynamic v) {
    final t = _s(v);
    if (t.isEmpty) return "";
    final base = t.length >= 10 ? t.substring(0, 10) : t;

    if (base.length == 10 && base[2] == "/" && base[5] == "/") return base;

    if (base.length == 10 && base[4] == "-" && base[7] == "-") {
      final y = base.substring(0, 4);
      final m = base.substring(5, 7);
      final d = base.substring(8, 10);
      return "$d/$m/$y";
    }
    return t;
  }

  /// Normaliza hora do SQLite (HH:MM, HH:MM:SS ou ISO) para envio à API.
  String _toHora(dynamic v) {
    var t = _s(v);
    if (t.isEmpty) return "";

    if (t.contains("T")) {
      final parts = t.split("T");
      if (parts.length > 1) t = parts[1];
    } else if (t.contains(" ")) {
      final parts = t.split(" ");
      if (parts.length > 1) t = parts.last;
    }

    t = t.split(".").first.trim();
    final m = RegExp(r"^(\d{1,2}):(\d{2})(?::(\d{2}))?").firstMatch(t);
    if (m == null) return "";

    final hh = m.group(1)!.padLeft(2, "0");
    final mm = m.group(2)!.padLeft(2, "0");
    final ss = (m.group(3) ?? "00").padLeft(2, "0");
    return "$hh:$mm:$ss";
  }

  void _putHorasPayload(
    Map<String, dynamic> map, {
    required String horaInicio,
    required String horaFim,
    bool insumo = false,
  }) {
    if (horaInicio.isNotEmpty) {
      if (insumo) {
        map["hora_ini"] = horaInicio;
        map["HORA_INI"] = horaInicio;
      } else {
        map["hora_inicio"] = horaInicio;
        map["HORA_INICIO"] = horaInicio;
      }
    }
    if (horaFim.isNotEmpty) {
      if (insumo) {
        map["hora_fim"] = horaFim;
        map["HORA_FIM"] = horaFim;
      } else {
        map["hora_fim"] = horaFim;
        map["HORA_FIM"] = horaFim;
      }
    }
  }

  void _putHorasFornecimento(
    Map<String, dynamic> map, {
    required String horaInicio,
    required String horaFim,
  }) {
    if (horaInicio.isNotEmpty) {
      map["hora_inicio"] = horaInicio;
      map["HORA_INICIO"] = horaInicio;
    }
    final horaForn = horaFim.isNotEmpty ? horaFim : horaInicio;
    if (horaForn.isNotEmpty) {
      map["hora_forn"] = horaForn;
      map["HORA_FORN"] = horaForn;
      map["hora_fim"] = horaFim.isNotEmpty ? horaFim : horaForn;
      map["HORA_FIM"] = horaFim.isNotEmpty ? horaFim : horaForn;
    }
  }

  static const Set<String> _decimalKeys = {
    "qtde_prevista",
    "qtde_realizada",
    "qtd_realizada",
    "ms_insumo",
    "realizado",
    "ms_dieta_realizada",
    "ms_prevista",
    "ms_realizada",
  };

  String _fixDecimalToBr(dynamic v, {int decimals = 3}) {
    final d = _toDouble(v);
    if (d == 0) return "0";
    return d.toStringAsFixed(decimals).replaceAll(".", ",");
  }

  String _fixDecimalToDot(dynamic v, {int decimals = 3}) {
    final d = _toDouble(v);
    if (d == 0) return "0";
    return d.toStringAsFixed(decimals);
  }

  dynamic _fixBodyDecimals(dynamic node) {
    if (node is List) {
      return node.map(_fixBodyDecimals).toList();
    }
    if (node is Map) {
      final out = <String, dynamic>{};
      // Horse/Firebird: ponto decimal (vírgula gera SQL error -303).
      node.forEach((k, v) {
        final key = k.toString();
        if (_decimalKeys.contains(key)) {
          final dec = (key == "ms_prevista" || key == "ms_realizada") ? 2 : 3;
          out[key] = _fixDecimalToDot(v, decimals: dec);
        } else {
          out[key] = _fixBodyDecimals(v);
        }
      });
      return out;
    }
    return node;
  }

  Future<void> syncGravaTag(void Function(String) log) async {
    final db = await AppDb.instance.db;
    final rows = await db.query("GRAVA_TAG", where: "SYNC = 0");

    for (final r in rows) {
      final idRow = _s(r["ID"]);
      final idCurral = _s(r["ID_PASTO_CURRAL"]);
      final tag = _s(r["TAG"]);

      if (idCurral.isEmpty || tag.isEmpty) {
        log("GravaTag invalida (ID=$idRow): curral/tag vazio");
        continue;
      }

      final ok = await api.postGravaTag(
        {
          "ID_PASTO_CURRAL": idCurral,
          "TAG": tag,
        },
        log: log,
      );

      if (ok && idRow.isNotEmpty) {
        await db.update(
          "GRAVA_TAG",
          {"SYNC": 1},
          where: "ID = ?",
          whereArgs: [idRow],
        );
        log("GravaTag sync OK ID=$idRow");
      } else {
        log("Falha GravaTag ID=$idRow");
      }
    }
  }

  Future<void> syncFabricacao(
    void Function(String) log,
    String idVagaoCfg, {
    String idFazendaCfg = "",
    required FabricacaoFlowMode flowMode,
    required int tipoTrabalho,
  }) async {
    final db = await AppDb.instance.db;

    if (flowMode == FabricacaoFlowMode.startStationFinishTruck &&
        tipoTrabalho == 1) {
      log("Flow startStationFinishTruck: estacionario nao sincroniza fabricacao.");
      return;
    }

    final where = <String>[
      "STATUS=1",
      "IFNULL(FLAG_SYNC,0)=0",
    ];

    if (flowMode == FabricacaoFlowMode.startStationFinishTruck) {
      where.add("IFNULL(FAB_STATUS,0) = $fabricacaoStatusFinalizada");
      where.add("UPPER(TRIM(COALESCE(ORIGIN_DEVICE,''))) = 'CAMINHAO'");
    } else {
      where.add("IFNULL(QTD_REALIZADA,0)>0");
    }

    final fab = await db.query(
      "CADASTRO_FABRICA_RACAO",
      where: where.join(" AND "),
    );

    log(
      "Sync fabricacao: ${api.usesFabricacaoPacote ? "Pacote (POST /Post/Fabricacao)" : "Cabecalho + /Post/Fabricacao_Insumo"}",
    );

    final fazendaCfg = idFazendaCfg.trim();

    for (final f in fab) {
      final idFabricacao = _s(f["ID"]);
      var idFazenda = _s(f["ID_FAZENDA"]);
      var idFazendaNum = int.tryParse(idFazenda) ?? 0;
      if (idFazendaNum <= 0 && fazendaCfg.isNotEmpty) {
        idFazenda = fazendaCfg;
        idFazendaNum = int.tryParse(fazendaCfg) ?? 0;
      }
      var handoffId = _s(f["HANDOFF_ID"]);
      final usePacote = api.usesFabricacaoPacote;

      if (idFabricacao.isEmpty) {
        log("Pulando fabricacao sem ID");
        continue;
      }

      if (!api.ignoresFazendaId && idFazendaNum <= 0) {
        log(
          "Pulando fab $idFabricacao: id_fazenda/ID_PROPRIEDADE invalido "
          "(registro='${_s(f["ID_FAZENDA"])}' config='$fazendaCfg'). "
          "Confirme a fazenda em Config.",
        );
        continue;
      }

      if ((int.tryParse(_s(f["ID_FAZENDA"])) ?? 0) <= 0 && idFazendaNum > 0) {
        await db.update(
          "CADASTRO_FABRICA_RACAO",
          {"ID_FAZENDA": idFazendaNum.toString()},
          where: "ID=?",
          whereArgs: [idFabricacao],
        );
        log("ID_FAZENDA preenchido na fab $idFabricacao a partir da config.");
      }

      if (handoffId.isEmpty) {
        handoffId = _uuid.v4();
        await db.update(
          "CADASTRO_FABRICA_RACAO",
          {"HANDOFF_ID": handoffId},
          where: "ID=?",
          whereArgs: [idFabricacao],
        );
        log("handoff_id gerado para fab local $idFabricacao.");
      }

      final kgReal = _toDouble(f["QTD_REALIZADA"]);
      if (kgReal <= 0) {
        log("Pulando fab $idFabricacao: qtde_realizada=0");
        continue;
      }

      final msFabResolved = _resolveMsPayload(
        msFabricacao: _toDouble(f["MS_REALIZADA"]),
        msDieta: await _fetchDietaMs(db, _s(f["ID_DIETA"])),
      );

      final idOperadorFab = _s(f["ID_OPERADOR"]);
      final idUsuarioFab =
          api.isTgc ? "1" : _s(f["ID_USUARIO"]);

      if (api.isTgc && idOperadorFab.isEmpty) {
        log(
          "TGC fab $idFabricacao: ID_OPERADOR vazio em CADASTRO_FABRICA_RACAO — "
          "refaca a fabricacao selecionando o operador.",
        );
        continue;
      }

      var nomeOperadorFab = "";
      var nomeMotoristaFab = "";
      if (api.isTgc) {
        nomeOperadorFab = await _fetchUsuarioNome(idOperadorFab);
        nomeMotoristaFab = _motoristaNomeLogin();
        if (nomeMotoristaFab.isEmpty) {
          nomeMotoristaFab =
              await _fetchUsuarioNome(_s(f["ID_USUARIO"]));
        }
        if (nomeOperadorFab.isEmpty) {
          log(
            "TGC fab $idFabricacao: nome do operador nao encontrado "
            "(ID_OPERADOR=$idOperadorFab).",
          );
        }
        if (nomeMotoristaFab.isEmpty) {
          log(
            "TGC fab $idFabricacao: nome do motorista vazio "
            "(sessao/login).",
          );
        }
      }

      final payloadFab = <String, dynamic>{
        "handoff_id": handoffId,
        if (!api.ignoresFazendaId) ...{
          "id_fazenda": idFazendaNum.toString(),
          "ID_PROPRIEDADE": idFazendaNum.toString(),
          "id_propriedade": idFazendaNum.toString(),
        },
        "id_dieta": _s(f["ID_DIETA"]),
        "data": _toBrDate(f["DATA_FABRICACAO"]),
        "id_usuario": idUsuarioFab,
        "id_operador": idOperadorFab,
        if (api.isTgc) ...{
          "CBT_USUARIO": "1",
          "CBT_COD_OPERADOR_PA": idOperadorFab,
          if (nomeOperadorFab.isNotEmpty) ...{
            "nome_operador": nomeOperadorFab,
            "CBT_NOMEOPERADOR": nomeOperadorFab,
          },
          if (nomeMotoristaFab.isNotEmpty) ...{
            "nome_motorista": nomeMotoristaFab,
            "CBT_NOME_MOTORISTA": nomeMotoristaFab,
          },
        },
        "id_vagao": idVagaoCfg,
        "qtde_prevista": _toBrIntStr(f["QTD_PREVISTA"]),
        "qtde_realizada": _toBrIntStr(f["QTD_REALIZADA"]),
        "ms_prevista": _br2(f["MS_PREVISTA"]),
        "ms_realizada": _br2(msFabResolved),
      };
      _putHorasPayload(
        payloadFab,
        horaInicio: _toHora(f["HORA_INICIO"]),
        horaFim: _toHora(f["HORA_FIM"]),
      );
      if (usePacote) {
        payloadFab["id_local"] = idFabricacao;
        if (api.isTgc) {
          _putLoteTgc(payloadFab, handoffId);
        }
      } else {
        payloadFab["id"] = idFabricacao;
      }

      final payloadFabFixed =
          _fixBodyDecimals(payloadFab) as Map<String, dynamic>;

      final insumos = await db.query(
        "DETALHES_FABRICA_RACAO",
        where: "STATUS=1 AND ID_FABRICACAO=? AND IFNULL(FLAG_SYNC,0)=0",
        whereArgs: [idFabricacao],
      );
      final itens = <Map<String, dynamic>>[];

      log("insumos encontrados=${insumos.length} fab=$idFabricacao");

      final dataFabBr = _toBrDate(f["DATA_FABRICACAO"]);

      if (insumos.isNotEmpty) {
        for (final i in insumos) {
          final prevD = _toDouble(i["QTD_PREVISTA"]);
          if (prevD <= 0) {
            log("Pulando insumo ${_s(i["ID"])}: prev<=0");
            continue;
          }

          final item = <String, dynamic>{
            if (!usePacote) "id": _s(i["ID"]),
            if (usePacote) "id_local": _s(i["ID"]),
            if (!api.ignoresFazendaId) ...{
              "id_fazenda": idFazendaNum.toString(),
              "ID_PROPRIEDADE": idFazendaNum.toString(),
            },
            "id_insumo": _s(i["ID_INSUMO"]),
            "qtde_prevista": _br3(i["QTD_PREVISTA"]),
            "qtd_realizada": _br3(i["QTD_REALIZADA"]),
            "ms_insumo": _br3(i["MS_INSUMO"]),
            "id_operador": idOperadorFab,
            "id_usuario": idUsuarioFab,
            if (api.isTgc) ...{
              "data": dataFabBr,
              "DBT_MS": _br3(i["MS_INSUMO"]),
              "DBT_CODOPERADOR": idOperadorFab,
              "DBT_USUARIO": "1",
              "DBT_CODALIMENTO": _s(i["ID_INSUMO"]),
            },
          };
          _putHorasPayload(
            item,
            horaInicio: _toHora(i["HORA_INICIO"]),
            horaFim: _toHora(i["HORA_FIM"]),
            insumo: true,
          );
          itens.add(item);
        }
      }

      final fornecimentosVinculados = await db.rawQuery('''
        SELECT
          cf.ID_FORNECIMENTO                                          AS id_fornecimento,
          MAX(cf.ID_BAIA)                                             AS id_curral,
          MAX(COALESCE(cf.HORA_INICIO, ''))                           AS hora_inicio,
          MAX(COALESCE(cf.HORA_FIM, ''))                              AS hora_fim,
          MAX(cf.DATA)                                                AS data_forn,
          MAX(cf.TRATO)                                               AS trato,
          MAX(cf.ID_USUARIO)                                          AS id_usuario_lancamento,
          MAX(cf.ID_USUARIO)                                          AS id_tratador,
          MAX(COALESCE(cfr.ID_DIETA, cf.ID_DIETA))                    AS id_dieta_realizada,
          MAX(COALESCE(cf.ID_DIETA, cfr.ID_DIETA))                    AS id_racao,
          SUM(COALESCE(cf.REALIZADO,0))                               AS realizado,
          AVG($_sqlMsFornecResolved)                                  AS ms_dieta_realizada
        FROM CADASTRO_FORNECIMENTO cf
        LEFT JOIN CADASTRO_FABRICA_RACAO cfr ON cfr.ID = cf.ID_FABRICACAO
        LEFT JOIN DIETA d ON TRIM(d.ID) = TRIM(COALESCE(cf.ID_DIETA, cfr.ID_DIETA))
        WHERE TRIM(COALESCE(cf.ID_FABRICACAO,'')) = TRIM(?)
          AND COALESCE(cf.REALIZADO,0) > 0
          AND IFNULL(cf.FLAG_SYNC,0) = 0
          AND TRIM(COALESCE(cf.ID_FORNECIMENTO,'')) <> ''
        GROUP BY cf.ID_FORNECIMENTO
      ''', [idFabricacao]);

      final fornecimentos = <Map<String, dynamic>>[];
      for (final r in fornecimentosVinculados) {
        final idPrev = _s(r["id_fornecimento"]);
        if (idPrev.isEmpty) continue;

        final msForn = _toDouble(r["ms_dieta_realizada"]);
        if (!MsPercent.isValid(msForn)) {
          log(
            "Fornecimento id=$idPrev fab=$idFabricacao: MS invalida "
            "(fab/dieta; deve ser > 0 e <= 100). Pulando linha.",
          );
          continue;
        }

        final loteVinc = api.isTgc ? _tgcLoteFabricacao(handoffId) : "";
        fornecimentos.add({
          "id": idPrev,
          "id_fabricacao": idFabricacao,
          "handoff_id_fabricacao": handoffId,
          if (loteVinc.isNotEmpty) ...{
            "lote_fabricacao": loteVinc,
            "CFORN_LOTE_FABRICACAO": loteVinc,
          },
          "IDCURRAL": _s(r["id_curral"]),
          "id_baia": _s(r["id_curral"]),
          "id_racao": _s(r["id_racao"]),
          "DATA_FORN": _toBrDate(r["data_forn"]),
          "data": _toBrDate(r["data_forn"]),
          "TRATO": _s(r["trato"]),
          "trato": _s(r["trato"]),
          "id_usuario_lancamento": _s(r["id_usuario_lancamento"]),
          "id_tratador": _s(r["id_tratador"]),
          "id_dieta_realizada": _s(r["id_dieta_realizada"]),
          "realizado": _br3(r["realizado"]),
          "ms_dieta_realizada": _br3(msForn),
        });
        _putHorasFornecimento(
          fornecimentos.last,
          horaInicio: _toHora(r["hora_inicio"]),
          horaFim: _toHora(r["hora_fim"]),
        );
      }

      log(
        "fornecimentos vinculados=${fornecimentos.length} fab=$idFabricacao",
      );

      if (usePacote) {
        // FieldTrato: fabricação sobe só cabeçalho+insumos; tratos vão em syncFornecimento.
        final pacoteCompleto = <String, dynamic>{
          ...payloadFabFixed,
          "itens": itens,
        };

        log(
          api.isTgc
              ? "TGC: enviando fab lote=${_tgcLoteFabricacao(handoffId)} "
                  "(tratos=${fornecimentos.length} sobem apos fab)."
              : "Fieldpec: enviando fab sem fornecimentos no pacote "
                  "(tratos=${fornecimentos.length} sobem separado).",
        );

        final pacoteCompletoFixed =
            _fixBodyDecimals(pacoteCompleto) as Map<String, dynamic>;

        final okPacote =
            await api.postFabricacao(pacoteCompletoFixed, log: log);

        if (!okPacote) {
          log(
            api.isTgc
                ? "Falha Fabricacao TGC id=$idFabricacao "
                    "(verifique log HTTP /Post/Fabricacao)"
                : "Falha Fabricacao (pacote) id=$idFabricacao",
          );
          continue;
        }

        if (fornecimentos.isNotEmpty) {
          log(
            api.isTgc
                ? "TGC: ${fornecimentos.length} trato(s) vinculado(s) a fab "
                    "$idFabricacao (lote=${_tgcLoteFabricacao(handoffId)}) — "
                    "serao enviados apos sync da fabricacao."
                : "Fieldpec: ${fornecimentos.length} trato(s) vinculado(s) a fab $idFabricacao "
                    "serao enviados no passo Fornecimento (POST /Post/Fornecimento).",
          );
        }
      } else {
        final pacoteField = <String, dynamic>{
          ...payloadFabFixed,
          "itens": itens,
          "fornecimentos": fornecimentos,
        };
        final pacoteFieldFixed =
            _fixBodyDecimals(pacoteField) as Map<String, dynamic>;

        if (itens.isNotEmpty || fornecimentos.isNotEmpty) {
          final okFieldPacote = await api.postFabricacaoPacoteFieldpec(
            pacoteFieldFixed,
            log: log,
          );
          if (okFieldPacote) {
            log(
              "Fabricacao sincronizada via pacote Fieldpec (BACKEND estava CGPec).",
            );
            if (fornecimentos.isNotEmpty) {
              final pendingRows = await db.rawQuery(
                """
                SELECT ID
                FROM CADASTRO_FORNECIMENTO
                WHERE TRIM(COALESCE(ID_FABRICACAO,'')) = TRIM(?)
                  AND COALESCE(REALIZADO,0) > 0
                  AND IFNULL(FLAG_SYNC,0) = 0
                  AND TRIM(COALESCE(ID_FORNECIMENTO,'')) <> ''
                """,
                [idFabricacao],
              );
              for (final row in pendingRows) {
                await _marcarFornecimentoSyncOk(db, _s(row["ID"]));
              }
            }
          } else {
            final okFab = await api.postFabricacao(payloadFabFixed, log: log);
            if (!okFab) {
              log("Falha Fabricacao id=$idFabricacao");
              continue;
            }

            if (itens.isNotEmpty) {
              final bodyItensFixed =
                  _fixBodyDecimals({"itens": itens}) as Map<String, dynamic>;

              final okItens =
                  await api.postFabricacaoInsumo(bodyItensFixed, log: log);
              if (!okItens) {
                log("Falha Fabricacao_Insumo id=$idFabricacao");
                continue;
              }
            } else {
              log("Nenhum insumo valido para enviar na fab $idFabricacao");
            }
          }
        } else {
          final okFab = await api.postFabricacao(payloadFabFixed, log: log);
          if (!okFab) {
            log("Falha Fabricacao id=$idFabricacao");
            continue;
          }
        }
      }

      await db.update(
        "CADASTRO_FABRICA_RACAO",
        {"FLAG_SYNC": 1},
        where: "ID=?",
        whereArgs: [idFabricacao],
      );
      await db.update(
        "DETALHES_FABRICA_RACAO",
        {"FLAG_SYNC": 1},
        where: "ID_FABRICACAO=?",
        whereArgs: [idFabricacao],
      );

      log("Fabricacao sync OK $idFabricacao");

      if (api.isTgc) {
        // Nao aborta a fabricacao se um trato falhar — o passo
        // "Sincronizando Fornecimento" tenta o restante.
        try {
          await _syncFornecimentoTgc(
            log,
            onlyFabricacaoId: idFabricacao,
            throwOnFailure: false,
          );
        } catch (e) {
          log("TGC: aviso ao enviar tratos da fab $idFabricacao: $e");
        }
      }
    }
  }

  Future<void> syncFornecimento(void Function(String) log) async {
    if (api.isFieldpec) {
      await _syncFornecimentoFieldpec(log);
      return;
    }
    if (api.isTgc) {
      await _syncFornecimentoTgc(log);
      return;
    }

    final db = await AppDb.instance.db;

    final diag = await db.rawQuery("""
      SELECT COUNT(*) AS qtd
      FROM CADASTRO_FORNECIMENTO
      WHERE IFNULL(REALIZADO,0) > 0 AND IFNULL(FLAG_SYNC,0) = 0
    """);
    final qtdPend =
        diag.isNotEmpty ? int.tryParse("${diag.first["qtd"]}") ?? 0 : 0;
    log("CADASTRO_FORNECIMENTO pendentes = $qtdPend");

    final blockedFab = await db.rawQuery("""
      SELECT COUNT(*) AS qtd
      FROM CADASTRO_FORNECIMENTO cf
      WHERE COALESCE(cf.REALIZADO, 0) > 0
        AND IFNULL(cf.FLAG_SYNC, 0) = 0
        AND TRIM(COALESCE(cf.ID_FORNECIMENTO, '')) <> ''
        AND NOT $_sqlFornecFabSyncGate
    """);
    final qtdBlocked = blockedFab.isNotEmpty
        ? int.tryParse("${blockedFab.first["qtd"]}") ?? 0
        : 0;
    if (qtdBlocked > 0) {
      log(
        "Fornecimento: $qtdBlocked registro(s) aguardando fabricacao (FLAG_SYNC fab=0). "
        "Nao serao reenviados ate a fabricacao subir.",
      );
    }

    final rows = await db.rawQuery('''
      SELECT
        cf.ID                                                       AS id_cadastro,
        cf.ID_FORNECIMENTO                                          AS id_fornecimento,
        cf.ID_BAIA                                                  AS id_baia,
        cf.DATA                                                     AS data_forn,
        cf.HORA_INICIO                                              AS hora_inicio,
        cf.HORA_FIM                                                 AS hora_fim,
        cf.TRATO                                                    AS trato,
        cf.ID_FABRICACAO                                            AS id_fabricacao,
        cf.ID_USUARIO                                               AS id_usuario_lancamento,
        COALESCE(cf.ID_DIETA, cfr.ID_DIETA)                         AS id_dieta_realizada,
        COALESCE(cf.ID_DIETA, cfr.ID_DIETA)                         AS id_racao,
        COALESCE(cf.REALIZADO, 0)                                   AS delta_sessao,
        COALESCE(p.REALIZADO_KG, 0)                                 AS total_mapa,
        $_sqlMsFornecResolved                                        AS ms_dieta_realizada
      FROM CADASTRO_FORNECIMENTO cf
      LEFT JOIN CADASTRO_FABRICA_RACAO cfr ON cfr.ID = cf.ID_FABRICACAO
      LEFT JOIN DIETA d ON TRIM(d.ID) = TRIM(COALESCE(cf.ID_DIETA, cfr.ID_DIETA))
      LEFT JOIN PREVISAO p
        ON TRIM(p.ID_FORNECIMENTO) = TRIM(cf.ID_FORNECIMENTO)
       AND TRIM(p.ID_BAIA) = TRIM(cf.ID_BAIA)
       AND substr(p.DATA, 1, 10) = substr(cf.DATA, 1, 10)
       AND p.TRATO = cf.TRATO
      WHERE COALESCE(cf.REALIZADO, 0) > 0
        AND IFNULL(cf.FLAG_SYNC, 0) = 0
        AND TRIM(COALESCE(cf.ID_FORNECIMENTO, '')) <> ''
        AND $_sqlFornecFabSyncGate
      ORDER BY cf.HORA_INICIO ASC, cf.ID ASC
    ''');

    if (rows.isEmpty) {
      if (qtdBlocked > 0) {
        log(
          "Nenhum fornecimento elegivel agora (fabricacao pendente bloqueia envio).",
        );
      } else {
        log("Nenhum fornecimento pendente para enviar.");
      }
      return;
    }

    var syncedCount = 0;

    // 1 linha CADASTRO_FORNECIMENTO = 1 POST (delta da sessao).
    // API FornecimentoAcumulativo=1 soma; FLAG_SYNC deve subir logo apos cada OK.
    for (final r in rows) {
      final idPrev = _s(r["id_fornecimento"]);
      final idCad = _s(r["id_cadastro"]);
      final idBaia = _s(r["id_baia"]);
      final idRacao = _s(r["id_racao"]);
      final trato = int.tryParse(_s(r["trato"])) ?? 0;
      final dataRef = _toBrDate(r["data_forn"]);
      final deltaSessao = _toDouble(r["delta_sessao"]);
      if (idPrev.isEmpty || idCad.isEmpty || deltaSessao <= 0) continue;
      if (idBaia.isEmpty || idRacao.isEmpty || trato <= 0 || dataRef.isEmpty) {
        log(
          "Fornecimento chave natural incompleta: "
          "cadastro=$idCad idFornecimento=$idPrev "
          "baia=$idBaia racao=$idRacao trato=$trato data=$dataRef",
        );
        continue;
      }

      final msResolved = _toDouble(r["ms_dieta_realizada"]);
      if (!MsPercent.isValid(msResolved)) {
        log(
          "Fornecimento cadastro=$idCad: MS invalida (fab/dieta). "
          "Deve ser > 0 e <= 100. Sync abortada para esta linha.",
        );
        continue;
      }

      final payload = <String, dynamic>{
        // Chave natural primeiro na API; id e fallback se nao encontrar.
        "id": idPrev,
        "id_cadastro": idCad,
        "id_fornecimento": idPrev,
        "id_fabricacao": _s(r["id_fabricacao"]),
        "id_usuario_lancamento": _s(r["id_usuario_lancamento"]),
        "id_tratador": _s(r["id_usuario_lancamento"]),
        "id_dieta_realizada": _s(r["id_dieta_realizada"]),
        "id_baia": idBaia,
        "id_racao": idRacao,
        "trato": trato.toString(),
        "data": dataRef,
        "realizado": _br3(deltaSessao),
        "ms_dieta_realizada": _br3(msResolved),
      };
      _putHorasFornecimento(
        payload,
        horaInicio: _toHora(r["hora_inicio"]),
        horaFim: _toHora(r["hora_fim"]),
      );

      log(
        "Fornecimento cadastro=$idCad chave=$idBaia|$idRacao|$dataRef|$trato "
        "realizado=$deltaSessao mapa=${_toDouble(r["total_mapa"])}",
      );

      final payloadFixed = _fixBodyDecimals(payload) as Map<String, dynamic>;

      final ok = await api.postFornecimento(payloadFixed, log: log);
      if (ok) {
        await _marcarFornecimentoSyncOk(db, idCad);
        syncedCount++;
      } else {
        log(
          "Falha Fornecimento cadastro=$idCad chave=$idBaia|$idRacao|$dataRef|$trato",
        );
      }
    }

    if (syncedCount > 0) {
      log("$syncedCount registro(s) de fornecimento marcado(s) FLAG_SYNC=1");
    }
  }

  /// Fieldpec: fornecimento sobe independente de fabricação vinculada no tablet.
  Future<void> _syncFornecimentoFieldpec(void Function(String) log) async {
    final db = await AppDb.instance.db;

    final diag = await db.rawQuery("""
      SELECT COUNT(*) AS qtd
      FROM CADASTRO_FORNECIMENTO
      WHERE IFNULL(REALIZADO,0) > 0 AND IFNULL(FLAG_SYNC,0) = 0
    """);
    final qtdPend =
        diag.isNotEmpty ? int.tryParse("${diag.first["qtd"]}") ?? 0 : 0;
    log("Fieldpec: CADASTRO_FORNECIMENTO pendentes = $qtdPend");

    final rows = await db.rawQuery('''
      SELECT
        cf.ID                                                       AS id_cadastro,
        cf.ID_FORNECIMENTO                                          AS id_fornecimento,
        cf.ID_BAIA                                                  AS id_baia,
        cf.DATA                                                     AS data_forn,
        cf.HORA_INICIO                                              AS hora_inicio,
        cf.HORA_FIM                                                 AS hora_fim,
        cf.TRATO                                                    AS trato,
        cf.ID_FABRICACAO                                            AS id_fabricacao,
        cf.ID_USUARIO                                               AS id_usuario_lancamento,
        COALESCE(cf.ID_DIETA, cfr.ID_DIETA)                         AS id_dieta_realizada,
        COALESCE(cf.ID_DIETA, cfr.ID_DIETA)                         AS id_racao,
        COALESCE(cf.REALIZADO, 0)                                   AS delta_sessao,
        COALESCE(p.REALIZADO_KG, 0)                                 AS total_mapa,
        $_sqlMsFornecResolved                                        AS ms_dieta_realizada
      FROM CADASTRO_FORNECIMENTO cf
      LEFT JOIN CADASTRO_FABRICA_RACAO cfr ON cfr.ID = cf.ID_FABRICACAO
      LEFT JOIN DIETA d ON TRIM(d.ID) = TRIM(COALESCE(cf.ID_DIETA, cfr.ID_DIETA))
      LEFT JOIN PREVISAO p
        ON TRIM(p.ID_FORNECIMENTO) = TRIM(cf.ID_FORNECIMENTO)
       AND TRIM(p.ID_BAIA) = TRIM(cf.ID_BAIA)
       AND substr(p.DATA, 1, 10) = substr(cf.DATA, 1, 10)
       AND p.TRATO = cf.TRATO
      WHERE COALESCE(cf.REALIZADO, 0) > 0
        AND IFNULL(cf.FLAG_SYNC, 0) = 0
        AND TRIM(COALESCE(cf.ID_FORNECIMENTO, '')) <> ''
      ORDER BY cf.HORA_INICIO ASC, cf.ID ASC
    ''');

    if (rows.isEmpty) {
      log("Fieldpec: nenhum fornecimento pendente para enviar.");
      return;
    }

    var syncedCount = 0;
    for (final r in rows) {
      final idPrev = _s(r["id_fornecimento"]);
      final idCad = _s(r["id_cadastro"]);
      final idBaia = _s(r["id_baia"]);
      final idRacao = _s(r["id_racao"]);
      final trato = int.tryParse(_s(r["trato"])) ?? 0;
      final dataRef = _toBrDate(r["data_forn"]);
      final deltaSessao = _toDouble(r["delta_sessao"]);
      if (idPrev.isEmpty || idCad.isEmpty || deltaSessao <= 0) continue;
      if (idBaia.isEmpty || idRacao.isEmpty || trato <= 0 || dataRef.isEmpty) {
        log(
          "Fieldpec fornecimento chave incompleta: cadastro=$idCad "
          "baia=$idBaia racao=$idRacao trato=$trato data=$dataRef",
        );
        continue;
      }

      final msResolved = _toDouble(r["ms_dieta_realizada"]);
      if (!MsPercent.isValid(msResolved)) {
        log(
          "Fieldpec fornecimento cadastro=$idCad racao=$idRacao: MS invalida "
          "(fab/dieta; deve ser > 0 e <= 100). Pulando.",
        );
        continue;
      }

      final payload = <String, dynamic>{
        "id": idPrev,
        "id_cadastro": idCad,
        "id_fornecimento": idPrev,
        "id_fabricacao": _s(r["id_fabricacao"]),
        "id_usuario_lancamento": _s(r["id_usuario_lancamento"]),
        "id_tratador": _s(r["id_usuario_lancamento"]),
        "id_dieta_realizada": _s(r["id_dieta_realizada"]),
        "id_baia": idBaia,
        "id_racao": idRacao,
        "trato": trato.toString(),
        "data": dataRef,
        "realizado": _br3(deltaSessao),
        "ms_dieta_realizada": _br3(msResolved),
      };
      _putHorasFornecimento(
        payload,
        horaInicio: _toHora(r["hora_inicio"]),
        horaFim: _toHora(r["hora_fim"]),
      );

      final payloadFixed = _fixBodyDecimals(payload) as Map<String, dynamic>;
      final ok = await api.postFornecimento(payloadFixed, log: log);
      if (ok) {
        await _marcarFornecimentoSyncOk(db, idCad);
        syncedCount++;
      } else {
        log(
          "Fieldpec falha fornecimento cadastro=$idCad "
          "chave=$idBaia|$idRacao|$dataRef|$trato",
        );
      }
    }

    if (syncedCount > 0) {
      log("Fieldpec: $syncedCount fornecimento(s) sincronizado(s).");
    } else if (rows.isNotEmpty) {
      log(
        "Fieldpec: ${rows.length} pendente(s), nenhum enviado "
        "(verifique MS da dieta ou chave baia/racao/trato/data).",
      );
    }
  }

  /// TGC: sem vinculo sobe livre; com vinculo exige fabricacao FLAG_SYNC=1.
  /// Cada CADASTRO_FORNECIMENTO = 1 POST (trato 1 e 2 do mesmo carregamento
  /// sobem separados — nunca agrupar).
  Future<void> _syncFornecimentoTgc(
    void Function(String) log, {
    String? onlyFabricacaoId,
    bool throwOnFailure = true,
  }) async {
    final db = await AppDb.instance.db;
    final fabFilter = (onlyFabricacaoId ?? "").trim();
    final fabWhere = fabFilter.isEmpty
        ? ""
        : " AND TRIM(COALESCE(cf.ID_FABRICACAO,'')) = TRIM(?)";
    final fabArgs = fabFilter.isEmpty ? <Object?>[] : <Object?>[fabFilter];

    final diag = await db.rawQuery("""
      SELECT COUNT(*) AS qtd
      FROM CADASTRO_FORNECIMENTO cf
      WHERE IFNULL(REALIZADO,0) > 0 AND IFNULL(FLAG_SYNC,0) = 0$fabWhere
    """, fabArgs);
    final qtdPend =
        diag.isNotEmpty ? int.tryParse("${diag.first["qtd"]}") ?? 0 : 0;
    log("TGC: CADASTRO_FORNECIMENTO pendentes = $qtdPend");

    final blockedRows = await db.rawQuery("""
      SELECT
        cf.ID AS id_cadastro,
        cf.ID_FABRICACAO AS id_fabricacao,
        cfr.HANDOFF_ID AS handoff_id
      FROM CADASTRO_FORNECIMENTO cf
      LEFT JOIN CADASTRO_FABRICA_RACAO cfr ON cfr.ID = cf.ID_FABRICACAO
      WHERE COALESCE(cf.REALIZADO, 0) > 0
        AND IFNULL(cf.FLAG_SYNC, 0) = 0
        AND TRIM(COALESCE(cf.ID_FORNECIMENTO, '')) <> ''
        AND TRIM(COALESCE(cf.ID_FABRICACAO, '')) <> ''
        AND NOT $_sqlFornecFabSyncGate$fabWhere
      ORDER BY cf.HORA_INICIO ASC, cf.ID ASC
    """, fabArgs);
    if (blockedRows.isNotEmpty) {
      log(
        "TGC: ${blockedRows.length} fornecimento(s) vinculado(s) aguardando "
        "fabricacao no servidor:",
      );
      for (final b in blockedRows) {
        final idCad = _s(b["id_cadastro"]);
        final idFab = _s(b["id_fabricacao"]);
        final lote = _tgcLoteFabricacao(_s(b["handoff_id"]));
        log(
          "  - cadastro=$idCad fab=$idFab "
          "lote=${lote.isEmpty ? '(sem handoff)' : lote}",
        );
      }
    }

    final rows = await db.rawQuery('''
      SELECT
        cf.ID                                                       AS id_cadastro,
        cf.ID_FORNECIMENTO                                          AS id_fornecimento,
        cf.ID_BAIA                                                  AS id_baia,
        cf.DATA                                                     AS data_forn,
        cf.HORA_INICIO                                              AS hora_inicio,
        cf.HORA_FIM                                                 AS hora_fim,
        cf.TRATO                                                    AS trato,
        cf.ID_FABRICACAO                                            AS id_fabricacao,
        cfr.HANDOFF_ID                                              AS handoff_id_fab,
        cf.ID_USUARIO                                               AS id_usuario_lancamento,
        COALESCE(cf.ID_DIETA, cfr.ID_DIETA)                         AS id_dieta_realizada,
        COALESCE(cf.ID_DIETA, cfr.ID_DIETA)                         AS id_racao,
        COALESCE(cf.REALIZADO, 0)                                   AS delta_sessao,
        COALESCE(p.REALIZADO_KG, 0)                                 AS total_mapa,
        $_sqlMsFornecResolved                                        AS ms_dieta_realizada
      FROM CADASTRO_FORNECIMENTO cf
      LEFT JOIN CADASTRO_FABRICA_RACAO cfr ON cfr.ID = cf.ID_FABRICACAO
      LEFT JOIN DIETA d ON TRIM(d.ID) = TRIM(COALESCE(cf.ID_DIETA, cfr.ID_DIETA))
      LEFT JOIN PREVISAO p
        ON TRIM(p.ID_FORNECIMENTO) = TRIM(cf.ID_FORNECIMENTO)
       AND TRIM(p.ID_BAIA) = TRIM(cf.ID_BAIA)
       AND substr(p.DATA, 1, 10) = substr(cf.DATA, 1, 10)
       AND p.TRATO = cf.TRATO
      WHERE COALESCE(cf.REALIZADO, 0) > 0
        AND IFNULL(cf.FLAG_SYNC, 0) = 0
        AND TRIM(COALESCE(cf.ID_FORNECIMENTO, '')) <> ''
        AND $_sqlFornecFabSyncGate$fabWhere
      ORDER BY cf.HORA_INICIO ASC, cf.ID ASC
    ''', fabArgs);

    if (rows.isEmpty) {
      if (blockedRows.isNotEmpty) {
        log(
          "TGC: nenhum fornecimento elegivel — vinculados aguardam fabricacao.",
        );
      } else if (fabFilter.isNotEmpty) {
        log("TGC: nenhum fornecimento pendente para fab=$fabFilter.");
      } else {
        log("TGC: nenhum fornecimento pendente para enviar.");
      }
      return;
    }

    var syncedCount = 0;
    var failedCount = 0;
    log(
      "TGC: enviando ${rows.length} fornecimento(s) "
      "(1 POST por cadastro/trato; mesmo carregamento NAO agrupa).",
    );
    for (final r in rows) {
      final idPrev = _s(r["id_fornecimento"]);
      final idCad = _s(r["id_cadastro"]);
      final idBaia = _s(r["id_baia"]);
      final idRacao = _s(r["id_racao"]);
      final idFab = _s(r["id_fabricacao"]);
      final trato = _toInt(r["trato"]);
      final dataRef = _toBrDate(r["data_forn"]);
      final deltaSessao = _toDouble(r["delta_sessao"]);
      if (idPrev.isEmpty || idCad.isEmpty || deltaSessao <= 0) {
        failedCount++;
        log(
          "TGC fornecimento IGNORADO (chave/realizado invalido): "
          "cadastro=$idCad idFornecimento=$idPrev realizado=$deltaSessao",
        );
        continue;
      }
      if (idBaia.isEmpty || idRacao.isEmpty || trato <= 0 || dataRef.isEmpty) {
        failedCount++;
        log(
          "TGC fornecimento chave incompleta: cadastro=$idCad "
          "baia=$idBaia racao=$idRacao trato=$trato data=$dataRef",
        );
        continue;
      }

      final msResolved = _toDouble(r["ms_dieta_realizada"]);
      if (!MsPercent.isValid(msResolved)) {
        failedCount++;
        log(
          "TGC fornecimento cadastro=$idCad: MS invalida "
          "(fab/dieta; deve ser > 0 e <= 100). Pulando.",
        );
        continue;
      }

      final payload = <String, dynamic>{
        "id": idPrev,
        "id_cadastro": idCad,
        "id_fornecimento": idPrev,
        "CFORN_CODIGO": idPrev,
        "id_usuario_lancamento": _s(r["id_usuario_lancamento"]),
        "id_tratador": _s(r["id_usuario_lancamento"]),
        "id_dieta_realizada": _s(r["id_dieta_realizada"]),
        "id_baia": idBaia,
        "id_racao": idRacao,
        "trato": trato.toString(),
        "TRATO": trato.toString(),
        "CFORN_TRATO": trato.toString(),
        "data": dataRef,
        "realizado": _br3(deltaSessao),
        "ms_dieta_realizada": _br3(msResolved),
      };

      if (idFab.isNotEmpty) {
        final handoffFab = _s(r["handoff_id_fab"]);
        final lote = _tgcLoteFabricacao(handoffFab);
        payload["id_fabricacao"] = idFab;
        payload["handoff_id_fabricacao"] = handoffFab;
        if (lote.isNotEmpty) {
          payload["lote_fabricacao"] = lote;
          payload["CFORN_LOTE_FABRICACAO"] = lote;
        }
        log(
          "TGC fornecimento cadastro=$idCad VINCULADO fab=$idFab lote=$lote "
          "trato=$trato idFornecimento=$idPrev realizado=$deltaSessao",
        );
      } else {
        log(
          "TGC fornecimento cadastro=$idCad SEM vinculo de fabricacao "
          "trato=$trato idFornecimento=$idPrev realizado=$deltaSessao",
        );
      }

      _putHorasFornecimento(
        payload,
        horaInicio: _toHora(r["hora_inicio"]),
        horaFim: _toHora(r["hora_fim"]),
      );

      var nomeMotorista = _motoristaNomeLogin();
      if (nomeMotorista.isEmpty) {
        nomeMotorista =
            await _fetchUsuarioNome(_s(r["id_usuario_lancamento"]));
      }
      if (nomeMotorista.isNotEmpty) {
        payload["nome_motorista"] = nomeMotorista;
        payload["CFORN_MOTORISTA"] = nomeMotorista;
      } else {
        log(
          "TGC fornecimento cadastro=$idCad: nome motorista vazio "
          "(sessao/login).",
        );
      }

      final payloadFixed = _fixBodyDecimals(payload) as Map<String, dynamic>;
      final ok = await api.postFornecimento(payloadFixed, log: log);
      if (ok) {
        await _marcarFornecimentoSyncOk(db, idCad);
        syncedCount++;
      } else {
        failedCount++;
        log(
          "TGC FALHA fornecimento cadastro=$idCad "
          "chave=$idBaia|$idRacao|$dataRef|trato=$trato "
          "idFornecimento=$idPrev — NAO marcado FLAG_SYNC",
        );
      }
    }

    if (syncedCount > 0) {
      log("TGC: $syncedCount fornecimento(s) sincronizado(s).");
    }
    if (failedCount > 0) {
      final msg =
          "TGC: $failedCount fornecimento(s) NAO subiram (de ${rows.length} "
          "elegiveis). Verifique o log — nenhum pode ficar para tras.";
      log(msg);
      if (throwOnFailure) throw Exception(msg);
    }
    if (syncedCount == 0 && rows.isNotEmpty) {
      final msg =
          "TGC: ${rows.length} fornecimento(s) pendente(s) nao enviados "
          "(verifique MS ou resposta da API).";
      log(msg);
      if (throwOnFailure) throw Exception(msg);
    }
  }
}
