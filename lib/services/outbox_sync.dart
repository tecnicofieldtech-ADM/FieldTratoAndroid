import "../db/app_db.dart";
import "../features/fabricacao/domain/fabricacao_flow.dart";
import "../services/api_service.dart";

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
        "ms_realizada": _br2(f["MS_REALIZADA"]),
      };

      final payloadFabFixed =
          _fixBodyDecimals(payloadFab) as Map<String, dynamic>;

      final okFab = await api.postFabricacao(payloadFabFixed, log: log);
      if (!okFab) {
        log("Falha Fabricacao id=$idFabricacao");
        continue;
      }

      final insumos = await db.query(
        "DETALHES_FABRICA_RACAO",
        where: "STATUS=1 AND ID_FABRICACAO=? AND IFNULL(FLAG_SYNC,0)=0",
        whereArgs: [idFabricacao],
      );

      log("insumos encontrados=${insumos.length} fab=$idFabricacao");

      if (insumos.isNotEmpty) {
        final itens = <Map<String, dynamic>>[];

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

        if (itens.isNotEmpty) {
          final bodyItensFixed = _fixBodyDecimals({"itens": itens})
              as Map<String, dynamic>;

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
    final db = await AppDb.instance.db;

    final diag = await db.rawQuery("""
      SELECT COUNT(*) AS qtd
      FROM CADASTRO_FORNECIMENTO
      WHERE IFNULL(REALIZADO,0) > 0 AND IFNULL(FLAG_SYNC,0) = 0
    """);
    final qtdPend =
        diag.isNotEmpty ? int.tryParse("${diag.first["qtd"]}") ?? 0 : 0;
    log("CADASTRO_FORNECIMENTO pendentes = $qtdPend");

    final rows = await db.rawQuery('''
      SELECT
        cf.ID_FORNECIMENTO                                          AS id_fornecimento,

        MAX(cfr.ID_FAZENDA)                                         AS id_fazenda,
        MAX(cf.ID_FABRICACAO)                                       AS id_fabricacao,
        MAX(cf.ID_USUARIO)                                          AS id_usuario_lancamento,
        MAX(cf.ID_USUARIO)                                          AS id_tratador,

        MAX(COALESCE(cfr.ID_DIETA, cf.ID_DIETA))                    AS id_dieta_realizada,

        SUM(COALESCE(cf.REALIZADO,0))                               AS realizado,
        AVG(COALESCE(cfr.MS_REALIZADA, 0))                          AS ms_dieta_realizada
      FROM CADASTRO_FORNECIMENTO cf
      LEFT JOIN CADASTRO_FABRICA_RACAO cfr ON cfr.ID = cf.ID_FABRICACAO
      WHERE COALESCE(cf.REALIZADO,0) > 0
        AND IFNULL(cf.FLAG_SYNC,0) = 0
        AND TRIM(COALESCE(cf.ID_FORNECIMENTO,'')) <> ''
      GROUP BY cf.ID_FORNECIMENTO
    ''');

    if (rows.isEmpty) {
      log("Nenhum fornecimento pendente para enviar.");
      return;
    }

    final syncedIds = <String>{};

    for (final r in rows) {
      final idPrev = _s(r["id_fornecimento"]);
      if (idPrev.isEmpty) {
        log("Fornecimento sem ID_FORNECIMENTO");
        continue;
      }

      final payload = <String, dynamic>{
        "id": idPrev,
        "id_fabricacao": _s(r["id_fabricacao"]),
        "id_usuario_lancamento": _s(r["id_usuario_lancamento"]),
        "id_tratador": _s(r["id_tratador"]),
        "id_dieta_realizada": _s(r["id_dieta_realizada"]),
        "realizado": _br3(r["realizado"]),
        "ms_dieta_realizada": _br3(r["ms_dieta_realizada"]),
      };

      final payloadFixed = _fixBodyDecimals(payload) as Map<String, dynamic>;

      final ok = await api.postFornecimento(payloadFixed, log: log);
      if (ok) {
        syncedIds.add(idPrev);
      } else {
        log("Falha Fornecimento id=$idPrev");
      }
    }

    if (syncedIds.isNotEmpty) {
      final inArgs = syncedIds.map((_) => "?").join(",");
      await db.rawUpdate(
        "UPDATE CADASTRO_FORNECIMENTO SET FLAG_SYNC=1 WHERE ID_FORNECIMENTO IN ($inArgs)",
        syncedIds.toList(),
      );
      log("${syncedIds.length} fornecimento(s) marcado(s) FLAG_SYNC=1");
    }
  }
}
