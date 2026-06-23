import "../db/app_db.dart";
import "../features/fabricacao/domain/fabricacao_flow.dart";
import "../services/api_service.dart";
import "../utils/ms_percent.dart";

class OutboxSync {
  final ApiService api;

  OutboxSync({required this.api});

  String _s(dynamic v) => (v ?? "").toString().trim();

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

  Future<void> _marcarFornecimentoSyncOk(dynamic db, String idCadastro) async {
    final id = idCadastro.trim();
    if (id.isEmpty) return;
    await db.update(
      "CADASTRO_FORNECIMENTO",
      {"FLAG_SYNC": 1},
      where: "ID = ?",
      whereArgs: [id],
    );
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

  static const Set<String> _decimalKeys = {
    "qtde_prevista",
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

  dynamic _fixBodyDecimals(dynamic node) {
    if (node is List) {
      return node.map(_fixBodyDecimals).toList();
    }
    if (node is Map) {
      final out = <String, dynamic>{};
      node.forEach((k, v) {
        final key = k.toString();
        if (_decimalKeys.contains(key)) {
          final dec = (key == "ms_prevista" || key == "ms_realizada") ? 2 : 3;
          out[key] = _fixDecimalToBr(v, decimals: dec);
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

    for (final f in fab) {
      final idFabricacao = _s(f["ID"]);
      final idFazenda = _s(f["ID_FAZENDA"]);
      var handoffId = _s(f["HANDOFF_ID"]);

      if (idFabricacao.isEmpty) {
        log("Pulando fabricacao sem ID");
        continue;
      }

      if (handoffId.isEmpty) {
        handoffId = idFabricacao;
        await db.update(
          "CADASTRO_FABRICA_RACAO",
          {"HANDOFF_ID": handoffId},
          where: "ID=?",
          whereArgs: [idFabricacao],
        );
        log("handoff_id ausente em $idFabricacao: usando fallback pelo ID local.");
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

      final payloadFab = <String, dynamic>{
        "id": idFabricacao,
        "handoff_id": handoffId,
        "id_fazenda": idFazenda,
        "id_dieta": _s(f["ID_DIETA"]),
        "data": _toBrDate(f["DATA_FABRICACAO"]),
        "id_usuario": _s(f["ID_USUARIO"]),
        "id_operador": _s(f["ID_OPERADOR"]),
        "id_vagao": idVagaoCfg,
        "qtde_prevista": _toBrIntStr(f["QTD_PREVISTA"]),
        "qtde_realizada": _toBrIntStr(f["QTD_REALIZADA"]),
        "ms_prevista": _br2(f["MS_PREVISTA"]),
        "ms_realizada": _br2(msFabResolved),
      };

      final payloadFabFixed =
          _fixBodyDecimals(payloadFab) as Map<String, dynamic>;

      final insumos = await db.query(
        "DETALHES_FABRICA_RACAO",
        where: "STATUS=1 AND ID_FABRICACAO=? AND IFNULL(FLAG_SYNC,0)=0",
        whereArgs: [idFabricacao],
      );
      final itens = <Map<String, dynamic>>[];

      log("insumos encontrados=${insumos.length} fab=$idFabricacao");

      if (insumos.isNotEmpty) {
        for (final i in insumos) {
          final prevD = _toDouble(i["QTD_PREVISTA"]);
          if (prevD <= 0) {
            log("Pulando insumo ${_s(i["ID"])}: prev<=0");
            continue;
          }

          itens.add({
            "id": _s(i["ID"]),
            "id_fazenda": idFazenda,
            "id_fabricacao": idFabricacao,
            "id_insumo": _s(i["ID_INSUMO"]),
            "qtde_prevista": _br3(i["QTD_PREVISTA"]),
            "qtd_realizada": _br3(i["QTD_REALIZADA"]),
            "ms_insumo": _br3(i["MS_INSUMO"]),
            "id_operador": _s(i["ID_OPERADOR"]),
            "id_usuario": _s(i["ID_USUARIO"]),
          });
        }
      }

      final isFieldpec = api.isFieldpec;

      final fornecimentosVinculados = await db.rawQuery('''
        SELECT
          cf.ID_FORNECIMENTO                                          AS id_fornecimento,
          MAX(cf.ID_BAIA)                                             AS id_curral,
          MAX(COALESCE(cf.HORA_FIM, cf.HORA_INICIO, ''))             AS hora_forn,
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

        fornecimentos.add({
          "id": idPrev,
          "id_fabricacao": idFabricacao,
          "handoff_id_fabricacao": handoffId,
          "IDCURRAL": _s(r["id_curral"]),
          "id_baia": _s(r["id_curral"]),
          "id_racao": _s(r["id_racao"]),
          "HORA_FORN": _s(r["hora_forn"]),
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
      }

      log(
        "fornecimentos vinculados=${fornecimentos.length} fab=$idFabricacao",
      );

      if (isFieldpec) {
        final pacoteCompleto = <String, dynamic>{
          ...payloadFabFixed,
          "itens": itens,
          "fornecimentos": fornecimentos,
        };

        final pacoteCompletoFixed =
            _fixBodyDecimals(pacoteCompleto) as Map<String, dynamic>;

        final okPacote =
            await api.postFabricacao(pacoteCompletoFixed, log: log);

        if (!okPacote) {
          log("Falha Fabricacao (pacote completo Fieldpec) id=$idFabricacao");
          continue;
        }

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
          final syncedRowIds = pendingRows
              .map((e) => _s(e["ID"]))
              .where((e) => e.isNotEmpty)
              .toList();

          for (final idCad in syncedRowIds) {
            await _marcarFornecimentoSyncOk(db, idCad);
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
    }
  }

  Future<void> syncFornecimento(void Function(String) log) async {
    if (api.isFieldpec) {
      await _syncFornecimentoFieldpecSemFabricacao(log);
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

  /// Fieldpec: fornecimentos sem fabricação no tablet (carregamento sem vínculo).
  Future<void> _syncFornecimentoFieldpecSemFabricacao(
    void Function(String) log,
  ) async {
    final db = await AppDb.instance.db;

    final rows = await db.rawQuery('''
      SELECT
        cf.ID                                                       AS id_cadastro,
        cf.ID_FORNECIMENTO                                          AS id_fornecimento,
        cf.ID_BAIA                                                  AS id_baia,
        cf.DATA                                                     AS data_forn,
        cf.TRATO                                                    AS trato,
        cf.ID_FABRICACAO                                            AS id_fabricacao,
        cf.ID_USUARIO                                               AS id_usuario_lancamento,
        COALESCE(cf.ID_DIETA, '')                                   AS id_dieta_realizada,
        COALESCE(cf.ID_DIETA, '')                                   AS id_racao,
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
        AND TRIM(COALESCE(cf.ID_FABRICACAO, '')) = ''
      ORDER BY cf.HORA_INICIO ASC, cf.ID ASC
    ''');

    if (rows.isEmpty) {
      log("Fieldpec: nenhum fornecimento sem fabricacao pendente.");
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
        continue;
      }

      final msResolved = _toDouble(r["ms_dieta_realizada"]);
      if (!MsPercent.isValid(msResolved)) {
        log(
          "Fieldpec fornecimento cadastro=$idCad: MS invalida (dieta). Pulando.",
        );
        continue;
      }

      final payload = <String, dynamic>{
        "id": idPrev,
        "id_cadastro": idCad,
        "id_fornecimento": idPrev,
        "id_fabricacao": "",
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

      final payloadFixed = _fixBodyDecimals(payload) as Map<String, dynamic>;
      final ok = await api.postFornecimento(payloadFixed, log: log);
      if (ok) {
        await _marcarFornecimentoSyncOk(db, idCad);
        syncedCount++;
      }
    }

    if (syncedCount > 0) {
      log(
        "Fieldpec: $syncedCount fornecimento(s) sem fabricacao sincronizado(s).",
      );
    }
  }
}
