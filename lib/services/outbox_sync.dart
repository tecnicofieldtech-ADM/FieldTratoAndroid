import "../db/app_db.dart";
import "../services/api_service.dart";

class OutboxSync {
  final ApiService api;

  OutboxSync({required this.api});

  // -------------------------
  // Helpers de formatação
  // -------------------------

  String _s(dynamic v) => (v ?? "").toString().trim();

  /// converte qualquer coisa para double de forma segura
  double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    final t = v.toString().trim();
    if (t.isEmpty || t.toLowerCase() == "null") return 0;
    // aceita "99,00" ou "99.00"
    final norm = t.replaceAll(",", ".");
    return double.tryParse(norm) ?? 0;
  }

  /// Inteiro como string (Delphi mandava string)
  String _toBrIntStr(dynamic v) {
    final d = _toDouble(v);
    return d.round().toString(); // "77"
  }

  /// Decimal como string com vírgula, e se for 0 manda "0" (evita "0.00" / BCD)
  String _toBrDecStr(dynamic v, {int decimals = 2}) {
    final d = _toDouble(v);
    if (d == 0) return "0";
    final fixed = d.toStringAsFixed(decimals); // "99.00"
    return fixed.replaceAll(".", ","); // "99,00"
  }

  /// Converte "yyyy-mm-dd" (ou "yyyy-mm-ddTHH...") para "dd/mm/yyyy"
  String _toBrDate(dynamic v) {
    final t = _s(v);
    if (t.isEmpty) return "";
    final base = t.length >= 10 ? t.substring(0, 10) : t;

    // já está dd/mm/yyyy
    if (base.length == 10 && base[2] == "/" && base[5] == "/") return base;

    // yyyy-mm-dd
    if (base.length == 10 && base[4] == "-" && base[7] == "-") {
      final y = base.substring(0, 4);
      final m = base.substring(5, 7);
      final d = base.substring(8, 10);
      return "$d/$m/$y";
    }

    // fallback
    return t;
  }

  // -------------------------
  // 1) Sync GravaTag
  // -------------------------
  Future<void> syncGravaTag(void Function(String) log) async {
    final db = await AppDb.instance.db;
    final rows = await db.query("GRAVA_TAG", where: "SYNC = 0");

    for (final r in rows) {
      final idRow = _s(r["ID"]);
      final idCurral = _s(r["ID_PASTO_CURRAL"]);
      final tag = _s(r["TAG"]);

      if (idCurral.isEmpty || tag.isEmpty) {
        log("⚠️ GravaTag inválida (ID=$idRow) curral/tag vazio");
        continue;
      }

      final ok = await api.postGravaTag({
        "ID_PASTO_CURRAL": idCurral,
        "TAG": tag,
      });

      if (ok && idRow.isNotEmpty) {
        await db.update(
          "GRAVA_TAG",
          {"SYNC": 1},
          where: "ID = ?",
          whereArgs: [idRow],
        );
        log("✅ GravaTag SYNC=1 ID=$idRow");
      } else {
        log("⚠️ Falha GravaTag ID=$idRow");
      }
    }
  }

  // -------------------------
  // 2) Sync Fabricação + Itens
  // -------------------------
  Future<void> syncFabricacao(void Function(String) log, String idVagaoCfg) async {
    final db = await AppDb.instance.db;

    final fab = await db.query(
      "CADASTRO_FABRICA_RACAO",
      where: "STATUS=1 AND IFNULL(QTD_REALIZADA,0)>0 AND IFNULL(FLAG_SYNC,0)=0",
    );

    for (final f in fab) {
      final idFabricacao = _s(f["ID"]);
      final idFazenda = _s(f["ID_FAZENDA"]);

      if (idFabricacao.isEmpty) {
        log("⏭️ Pulando fabricação sem ID");
        continue;
      }

      // não envia se realizado <= 0
      final kgReal = _toDouble(f["QTD_REALIZADA"]);
      if (kgReal <= 0) {
        log("⏭️ Pulando fab $idFabricacao: qtde_realizada=0");
        continue;
      }

      // ✅ Payload igual ao Delphi: tudo string
      final payloadFab = <String, dynamic>{
        "id": idFabricacao,
        "id_fazenda": idFazenda,
        "id_dieta": _s(f["ID_DIETA"]),
        "data": _toBrDate(f["DATA_FABRICACAO"]), // dd/mm/yyyy
        "id_usuario": _s(f["ID_USUARIO"]),
        "id_operador": _s(f["ID_OPERADOR"]),
        "id_vagao": idVagaoCfg,

        // inteiros como string
        "qtde_prevista": _toBrIntStr(f["QTD_PREVISTA"]),
        "qtde_realizada": _toBrIntStr(f["QTD_REALIZADA"]),

        // decimais como string com vírgula (ou "0")
        "ms_prevista": _toBrDecStr(f["MS_PREVISTA"], decimals: 2),
        "ms_realizada": _toBrDecStr(f["MS_REALIZADA"], decimals: 2),
      };

      log("📤 /Post/Fabricacao id=$idFabricacao payload=$payloadFab");

      final okFab = await api.postFabricacao(payloadFab, log: log);
      if (!okFab) {
        log("⚠️ Falha Fabricacao id=$idFabricacao");
        continue;
      }

      // Itens
      final insumos = await db.query(
        "DETALHES_FABRICA_RACAO",
        where: "STATUS=1 AND ID_FABRICACAO=? AND IFNULL(FLAG_SYNC,0)=0",
        whereArgs: [idFabricacao],
      );

      if (insumos.isNotEmpty) {
        final itens = <Map<String, dynamic>>[];

        for (final i in insumos) {
          // ✅ não envia previsto=0 (evita divisão por zero no backend)
          final prev = _toDouble(i["QTD_PREVISTA"]);
          if (prev <= 0) {
            log("⏭️ Pulando insumo ${_s(i["ID"])} da fab $idFabricacao: qtde_prevista=0");
            continue;
          }

          itens.add({
            "id": _s(i["ID"]),
            "id_fazenda": idFazenda,
            "id_fabricacao": idFabricacao,
            "id_insumo": _s(i["ID_INSUMO"]),

            // backend espera esses nomes:
            "qtd_realizada": _toBrDecStr(i["QTD_REALIZADA"], decimals: 3).replaceAll(",", "."), // manda com ponto aqui p/ StrToFloatDef
            "qtde_prevista": _toBrDecStr(i["QTD_PREVISTA"], decimals: 3).replaceAll(",", "."),

            "id_operador": _s(i["ID_OPERADOR"]),
            "id_usuario": _s(i["ID_USUARIO"]),

            "ms_insumo": _toBrDecStr(i["MS_INSUMO"], decimals: 3).replaceAll(",", "."),
          });
        }

        if (itens.isNotEmpty) {
          log("📤 /Post/Fabricacao_Insumo id=$idFabricacao itens=${itens.length}");
          final okItens = await api.postFabricacaoInsumo({"itens": itens}, log: log);
          if (!okItens) {
            log("⚠️ Falha Fabricacao_Insumo id=$idFabricacao");
            continue;
          }
        } else {
          log("ℹ️ Nenhum insumo válido para enviar na fab $idFabricacao");
        }
      }

      // marcou sincronizado
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

      log("✅ FLAG_SYNC=1 fab $idFabricacao");
    }
  }

  // -------------------------
  // 3) Sync Fornecimento (agrupado)
  // -------------------------
  Future<void> syncFornecimento(void Function(String) log) async {
    final db = await AppDb.instance.db;

    final rows = await db.rawQuery('''
      SELECT
        cf.ID_FORNECIMENTO,
        MAX(cfr.ID_FAZENDA) AS id_fazenda,
        MAX(cf.ID_FABRICACAO) AS id_fabricacao,
        MAX(cf.ID_USUARIO) AS id_usuario_lancamento,
        MAX(cf.ID_USUARIO) AS id_tratador,
        MAX(cfr.ID_DIETA) AS id_dieta_realizada,
        SUM(cf.REALIZADO) AS realizado,
        AVG(cfr.MS_REALIZADA) AS ms_dieta_realizada
      FROM CADASTRO_FORNECIMENTO cf
      JOIN CADASTRO_FABRICA_RACAO cfr ON cfr.ID = cf.ID_FABRICACAO
      WHERE cf.REALIZADO > 0 AND IFNULL(cf.FLAG_SYNC,0) = 0
      GROUP BY cf.ID_FORNECIMENTO
    ''');

    final syncedIds = <String>{};

    for (final r in rows) {
      final idPrev = _s(r["ID_FORNECIMENTO"]);
      if (idPrev.isEmpty) {
        log("⚠️ Fornecimento sem ID_FORNECIMENTO (pular)");
        continue;
      }

      final payload = <String, dynamic>{
        "id": idPrev,
        "id_fabricacao": _s(r["id_fabricacao"]),
        "id_usuario_lancamento": _s(r["id_usuario_lancamento"]),
        "id_tratador": _s(r["id_tratador"]),
        "id_dieta_realizada": _s(r["id_dieta_realizada"]),

        // strings
        "realizado": _toBrDecStr(r["realizado"], decimals: 3).replaceAll(",", "."),
        "ms_dieta_realizada": _toBrDecStr(r["ms_dieta_realizada"], decimals: 3).replaceAll(",", "."),
      };

      final ok = await api.postFornecimento(payload);
      if (ok) {
        syncedIds.add(idPrev);
      } else {
        log("⚠️ Falha Fornecimento id=$idPrev payload=$payload");
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
  }
}
