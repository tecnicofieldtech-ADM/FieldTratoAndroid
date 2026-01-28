import "../db/app_db.dart";
import "../services/api_service.dart";

class OutboxSync {
  final ApiService api;

  OutboxSync({required this.api});

  Future<void> syncGravaTag(void Function(String) log) async {
    final db = await AppDb.instance.db;
    final rows = await db.query("GRAVA_TAG", where: "SYNC = 0");
    for (final r in rows) {
      final idRow = (r["ID"] ?? "").toString().trim();
      final idCurral = (r["ID_PASTO_CURRAL"] ?? "").toString().trim();
      final tag = (r["TAG"] ?? "").toString().trim();

      final ok = await api.postGravaTag({
        "ID_PASTO_CURRAL": idCurral,
        "TAG": tag,
      });

      if (ok && idRow.isNotEmpty) {
        await db.update("GRAVA_TAG", {"SYNC": 1}, where: "ID = ?", whereArgs: [idRow]);
      } else {
        log("⚠️ Falha GravaTag ID=$idRow");
      }
    }
  }

  Future<void> syncFabricacao(void Function(String) log, String idVagaoCfg) async {
    final db = await AppDb.instance.db;

    final fab = await db.query(
      "CADASTRO_FABRICA_RACAO",
      where: "STATUS=1 AND QTD_REALIZADA>0 AND FLAG_SYNC=0",
    );

    for (final f in fab) {
      final idFabricacao = (f["ID"] ?? "").toString();
      final idFazenda = (f["ID_FAZENDA"] ?? "").toString();

      final okFab = await api.postFabricacao({
        "id": idFabricacao,
        "id_fazenda": idFazenda,
        "id_dieta": (f["ID_DIETA"] ?? "").toString(),
        "data": (f["DATA_FABRICACAO"] ?? "").toString(),
        "id_usuario": (f["ID_USUARIO"] ?? "").toString(),
        "id_operador": (f["ID_OPERADOR"] ?? "").toString(),
        "id_vagao": idVagaoCfg,
        "qtde_prevista": (f["QTD_PREVISTA"] ?? 0).toString(),
        "qtde_realizada": (f["QTD_REALIZADA"] ?? 0).toString(),
        "ms_prevista": (f["MS_PREVISTA"] ?? 0).toString(),
        "ms_realizada": (f["MS_REALIZADA"] ?? 0).toString(),
      });

      if (!okFab) {
        log("⚠️ Falha Fabricacao id=$idFabricacao");
        continue;
      }

      final insumos = await db.query(
        "DETALHES_FABRICA_RACAO",
        where: "STATUS=1 AND ID_FABRICACAO=? AND FLAG_SYNC=0",
        whereArgs: [idFabricacao],
      );

      if (insumos.isNotEmpty) {
        final itens = insumos.map((i) {
          return {
            "id": (i["ID"] ?? "").toString(),
            "id_fazenda": idFazenda,
            "id_fabricacao": idFabricacao,
            "id_insumo": (i["ID_INSUMO"] ?? "").toString(),
            "qtd_realizada": (i["QTD_REALIZADA"] ?? 0).toString(),
            "qtde_prevista": (i["QTD_PREVISTA"] ?? 0).toString(),
            "id_operador": (i["ID_OPERADOR"] ?? "").toString(),
            "id_usuario": (i["ID_USUARIO"] ?? "").toString(),
            "ms_insumo": (i["MS_INSUMO"] ?? 0).toString(),
          };
        }).toList();

        final okItens = await api.postFabricacaoInsumo({"itens": itens});
        if (!okItens) {
          log("⚠️ Falha Fabricacao_Insumo id=$idFabricacao");
          continue;
        }
      }

      await db.update("CADASTRO_FABRICA_RACAO", {"FLAG_SYNC": 1}, where: "ID=?", whereArgs: [idFabricacao]);
      await db.update("DETALHES_FABRICA_RACAO", {"FLAG_SYNC": 1}, where: "ID_FABRICACAO=?", whereArgs: [idFabricacao]);
    }
  }

  Future<void> syncFornecimento(void Function(String) log) async {
    final db = await AppDb.instance.db;

    // mesmo agrupamento do Delphi
    final rows = await db.rawQuery('''
      SELECT
        cf.ID_FORNECIMENTO,
        MAX(cfr.ID_FAZENDA) AS id_fazenda,
        MAX(cf.ID_FABRICACAO) AS id_fabricacao,
        MAX(cf.ID_USUARIO) AS id_usuario_lancamento,
        MAX(cf.ID_USUARIO) AS id_tratador,
        MAX(cfr.ID_DIETA) AS id_dieta_realizada,
        SUM(cf.REALIZADO) AS realizado,
        AVG(cfr.MS_REALIZADA) AS ms_dieta_realizada,
        MAX(cf.DATA) as data_fornec,
        MAX(cf.ID_BAIA) as id_baia,
        MAX(cf.TRATO) as trato
      FROM CADASTRO_FORNECIMENTO cf
      JOIN CADASTRO_FABRICA_RACAO cfr ON cfr.ID = cf.ID_FABRICACAO
      WHERE cf.REALIZADO > 0 AND cf.FLAG_SYNC = 0
      GROUP BY cf.ID_FORNECIMENTO
    ''');

    final syncedIds = <String>{};

    for (final r in rows) {
      final idPrev = (r["ID_FORNECIMENTO"] ?? "").toString().trim();
      if (idPrev.isEmpty) {
        log("⚠️ Fornecimento sem ID_FORNECIMENTO (pular por enquanto)");
        continue;
      }

      final ok = await api.postFornecimento({
        "id": idPrev,
        "id_fabricacao": (r["id_fabricacao"] ?? "").toString(),
        "id_usuario_lancamento": (r["id_usuario_lancamento"] ?? "").toString(),
        "id_tratador": (r["id_tratador"] ?? "").toString(),
        "id_dieta_realizada": (r["id_dieta_realizada"] ?? "").toString(),
        "realizado": (r["realizado"] ?? 0).toString(),
        "ms_dieta_realizada": (r["ms_dieta_realizada"] ?? 0).toString(),
      });

      if (ok) {
        syncedIds.add(idPrev);
      } else {
        log("⚠️ Falha Fornecimento id=$idPrev");
      }
    }

    if (syncedIds.isNotEmpty) {
      final inArgs = syncedIds.map((_) => "?").join(",");
      await db.rawUpdate(
        "UPDATE CADASTRO_FORNECIMENTO SET FLAG_SYNC=1 WHERE ID_FORNECIMENTO IN ($inArgs)",
        syncedIds.toList(),
      );
      log("✅ ${syncedIds.length} fornecimento(s) marcado(s) FLAG_SYNC=1");
    }

    Future<void> syncGravaTag(void Function(String) log) async {
  final db = await AppDb.instance.db;
  final rows = await db.query("GRAVA_TAG", where: "SYNC = 0");

  for (final r in rows) {
    final id = (r["ID"] as int?) ?? 0;
    final idCurral = (r["ID_PASTO_CURRAL"] ?? "").toString().trim();
    final tag = (r["TAG"] ?? "").toString().trim();

    if (idCurral.isEmpty || tag.isEmpty) {
      log("⚠️ GravaTag inválida (id=$id)");
      continue;
    }

    final ok = await api.postGravaTag({
      "ID_PASTO_CURRAL": idCurral,
      "TAG": tag,
    });

    if (ok && id > 0) {
      await db.update("GRAVA_TAG", {"SYNC": 1}, where: "ID = ?", whereArgs: [id]);
    } else {
      log("⚠️ Falha GravaTag (id=$id)");
    }
  }
}

  }
}
