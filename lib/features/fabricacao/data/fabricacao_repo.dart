// lib/features/fabricacao/data/fabricacao_repo.dart
import "dart:math";
import "package:flutter/foundation.dart";
import "package:sqflite/sqflite.dart";
import "../../../db/app_db.dart";
import "../../../utils/ms_percent.dart";
import "../../fornecimento/data/carregamento_dao.dart";
import "../../fornecimento/data/fornecimento_tables.dart";
import "../domain/models.dart";
import "../domain/fabricacao_flow.dart";

class FabricacaoRepo {
  FabricacaoRepo({CarregamentoDao? carregamentoDao})
      : _carregDao = carregamentoDao ?? CarregamentoDao();

  final CarregamentoDao _carregDao;

  Future<Database> get _db async => AppDb.instance.db;

  // cache de colunas por tabela (evita PRAGMA toda hora)
  final Map<String, Set<String>> _colsCache = {};

  Future<Set<String>> _cols(String table) async {
    final key = table.toLowerCase();
    if (_colsCache.containsKey(key)) return _colsCache[key]!;
    final db = await _db;

    final rows = await db.rawQuery("PRAGMA table_info($table)");
    final cols = <String>{};
    for (final r in rows) {
      final name = (r["name"] ?? "").toString().toLowerCase().trim();
      if (name.isNotEmpty) cols.add(name);
    }
    _colsCache[key] = cols;
    return cols;
  }

  Future<bool> _hasTable(String table) async {
    final db = await _db;
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND lower(name)=lower(?) LIMIT 1",
      [table],
    );
    return rows.isNotEmpty;
  }

  Future<bool> _hasCol(String table, String col) async {
    final cols = await _cols(table);
    return cols.contains(col.toLowerCase());
  }

  /// retorna o 1º nome de coluna existente (mantém o case que você passar)
  Future<String?> _pickCol(String table, List<String> candidates) async {
    for (final c in candidates) {
      if (await _hasCol(table, c)) return c;
    }
    return null;
  }

  Map<String, Object?> _lowerKeys(Map<String, Object?> m) {
    final out = <String, Object?>{};
    for (final e in m.entries) {
      out[e.key.toString().toLowerCase()] = e.value;
    }
    return out;
  }

  // =========================================================
  // RESUMO POR DIETA/DATA/TRATO (PREVISAO)
  // =========================================================
  static String _normalizeDietaId(String? raw) {
    return (raw ?? "").replaceAll(RegExp(r"\s+"), "").trim().toUpperCase();
  }

  List<String> _dietaIdCandidates(String idDieta) {
    final raw = idDieta.trim();
    final out = <String>[];
    void add(String s) {
      final n = _normalizeDietaId(s);
      if (n.isNotEmpty && !out.contains(n)) out.add(n);
    }

    add(raw);
    final asInt = int.tryParse(raw);
    if (asInt != null) add(asInt.toString());
    return out;
  }

  Future<List<Map<String, Object?>>> _queryResumoPorDietaDataTrato({
    required String dietaNorm,
    required String ymd,
    int? trato,
    String? idFazenda,
  }) async {
    final where = <String>[];
    final args = <Object?>[];

    where.add(
      "REPLACE(UPPER(TRIM(COALESCE(p.${FornTables.pvIdRacao},''))), ' ', '') = ?",
    );
    args.add(dietaNorm);

    if (trato != null && trato > 0) {
      where.add("COALESCE(p.${FornTables.pvTrato},0) = ?");
      args.add(trato);
    }

    where.add("substr(COALESCE(p.${FornTables.pvData},''),1,10) = ?");
    args.add(ymd);

    final faz = (idFazenda ?? "").trim();
    if (faz.isNotEmpty && await _hasTable(FornTables.detalhesBaias)) {
      where.add("""
        EXISTS (
          SELECT 1
          FROM ${FornTables.detalhesBaias} db
          WHERE TRIM(CAST(db.${FornTables.dbId} AS TEXT)) =
                TRIM(CAST(p.${FornTables.pvIdBaia} AS TEXT))
            AND TRIM(db.${FornTables.dbIdFazenda}) = TRIM(?)
        )
      """);
      args.add(faz);
    }

    final sql = """
      SELECT
        COALESCE(p.${FornTables.pvIdRacao},'') AS id_dieta,
        substr(COALESCE(p.${FornTables.pvData},''),1,10) AS data_ymd,
        COALESCE(p.${FornTables.pvTrato},0) AS trato,
        SUM(COALESCE(p.${FornTables.pvPrevistoKg},0)) AS previsto,
        SUM(${FornTables.sqlRealizadoKgLocal("p")}) AS realizado
      FROM ${FornTables.previsao} p
      WHERE ${where.join(" AND ")}
      GROUP BY id_dieta, data_ymd, trato
      ORDER BY data_ymd DESC, trato ASC
    """;

    final db = await _db;
    final rows = await db.rawQuery(sql, args);
    return rows.map((e) => _lowerKeys(Map<String, Object?>.from(e))).toList();
  }

  Future<List<Map<String, Object?>>> listResumoPorDietaDataTrato({
    required String idDieta,
    int? trato,
    DateTime? data,
    String? idFazenda,
  }) async {
    if (!await _hasTable(FornTables.previsao)) return [];

    final d = data ?? DateTime.now();
    final y = d.year.toString().padLeft(4, "0");
    final m = d.month.toString().padLeft(2, "0");
    final dd = d.day.toString().padLeft(2, "0");
    final ymd = "$y-$m-$dd";

    final faz = (idFazenda ?? "").trim();
    final candidates = _dietaIdCandidates(idDieta);

    for (final dietaNorm in candidates) {
      if (faz.isNotEmpty) {
        final comFazenda = await _queryResumoPorDietaDataTrato(
          dietaNorm: dietaNorm,
          ymd: ymd,
          trato: trato,
          idFazenda: faz,
        );
        if (comFazenda.isNotEmpty) return comFazenda;
      }

      final semFazenda = await _queryResumoPorDietaDataTrato(
        dietaNorm: dietaNorm,
        ymd: ymd,
        trato: trato,
        idFazenda: null,
      );
      if (semFazenda.isNotEmpty) return semFazenda;
    }

    if (kDebugMode) {
      debugPrint(
        "[FAB_RESUMO] vazio dieta='$idDieta' data=$ymd trato=$trato fazenda='$faz'",
      );
    }
    return [];
  }

  // =========================================================
  // COMPAT
  // =========================================================

  // ✅ compat (mantém chamadas antigas da UI)
  Future<FabricacaoHeader?> getFabricacaoEmAberto([String? idFazenda]) {
    return getFabricacaoEmAbertoHoje(idFazenda);
  }

  // =========================================================
  // FAB EM ABERTO (HOJE) ✅ COM JOIN NA DIETA
  // =========================================================
  Future<FabricacaoHeader?> getFabricacaoEmAbertoHoje(
      [String? idFazenda]) async {
    const t = "CADASTRO_FABRICA_RACAO";
    if (!await _hasTable(t)) return null;

    final idCol = await _pickCol(t, ["ID"]) ?? "ID";

    final statusCol = await _pickCol(t, ["STATUS"]);
    final finalizadaCol = await _pickCol(t, ["FINALIZADA"]);
    final fabStatusCol = await _pickCol(t, ["FAB_STATUS"]);
    final carregadaCol = await _pickCol(t, ["CARREGADA"]);
    final handoffCol = await _pickCol(t, ["HANDOFF_ID"]);
    final exportadoEmCol = await _pickCol(t, ["EXPORTADO_EM"]);
    final originDeviceCol = await _pickCol(t, ["ORIGIN_DEVICE"]);

    final tratoCol = await _pickCol(t, ["TRATO"]);
    final idFazCol = await _pickCol(t, ["ID_FAZENDA", "IDFAZENDA"]);

    final dataFabCol = await _pickCol(
      t,
      ["DATA_FABRICACAO", "DATA_FAB", "DATA", "DATAREG", "DATA_REG"],
    );
    final horaIniCol =
        await _pickCol(t, ["HORA_INICIO", "HORAINI", "HORA_INI", "HORA"]);

    final prevCol = await _pickCol(
      t,
      ["QTD_PREVISTA", "PREVKG", "PREV_KG", "PREVISTOKG", "PREV_KG_TOTAL"],
    );
    final realCol = await _pickCol(t, [
      "QTD_REALIZADA",
      "REALIZADOKG",
      "REALIZADO_KG",
      "REALIZADO",
      "REALIZADO_KG_TOTAL"
    ]);

    // ✅ no seu schema é isso mesmo
    const idDietaCol = "ID_DIETA";

    String sel(String alias, String? col, String fallback) {
      if (col == null) return "$fallback AS $alias";
      return "COALESCE($col, $fallback) AS $alias";
    }

    // ✅ JOIN DIETA
    final hasDieta = await _hasTable("DIETA");
    final join = hasDieta ? "LEFT JOIN DIETA di ON di.ID = f.$idDietaCol" : "";
    final dietaNomeExpr =
        hasDieta ? "COALESCE(NULLIF(TRIM(di.NOME),''),'')" : "''";

    final select = """
    SELECT
      f.$idCol AS id,
      COALESCE(f.$idDietaCol,'') AS id_dieta,
      $dietaNomeExpr AS dieta_nome,
      ${sel("trato", tratoCol != null ? "f.$tratoCol" : null, "0")},
      ${sel("qtd_prevista", prevCol != null ? "f.$prevCol" : null, "0")},
      ${sel("qtd_realizada", realCol != null ? "f.$realCol" : null, "0")},
      ${sel("finalizada", finalizadaCol != null ? "f.$finalizadaCol" : null, "0")},
      ${sel("fab_status", fabStatusCol != null ? "f.$fabStatusCol" : null, "0")},
      ${sel("handoff_id", handoffCol != null ? "f.$handoffCol" : null, "''")},
      ${sel("exportado_em", exportadoEmCol != null ? "f.$exportadoEmCol" : null, "''")},
      ${sel("origin_device", originDeviceCol != null ? "f.$originDeviceCol" : null, "''")},
      ${sel("carregada", carregadaCol != null ? "f.$carregadaCol" : null, "0")},
      ${sel("data_fabricacao", dataFabCol != null ? "f.$dataFabCol" : null, "''")},
      ${sel("hora_inicio", horaIniCol != null ? "f.$horaIniCol" : null, "''")}
    FROM $t f
    $join
  """;

    final where = <String>[];
    final args = <Object?>[];

    if (statusCol != null) where.add("f.$statusCol = 1");
    if (finalizadaCol != null) where.add("COALESCE(f.$finalizadaCol,0) = 0");
    if (fabStatusCol != null) {
      where.add("COALESCE(f.$fabStatusCol,0) = $fabricacaoStatusEmAndamento");
    }

    if (idFazCol != null && idFazenda != null && idFazenda.trim().isNotEmpty) {
      where.add("f.$idFazCol = ?");
      args.add(idFazenda.trim());
    }

    if (dataFabCol != null) {
      where.add("date(f.$dataFabCol) = date('now','localtime')");
    }

    final order = (horaIniCol != null)
        ? "ORDER BY COALESCE(f.$horaIniCol,'') DESC"
        : (dataFabCol != null)
            ? "ORDER BY COALESCE(f.$dataFabCol,'') DESC"
            : "";

    final sql = """
    $select
    ${where.isEmpty ? "" : "WHERE ${where.join(" AND ")}"}
    $order
    LIMIT 1
  """;

    final db = await _db;
    final rows = await db.rawQuery(sql, args);
    if (rows.isEmpty) return null;

    return FabricacaoHeader.fromMap(
      _lowerKeys(Map<String, Object?>.from(rows.first)),
    );
  }

  // =========================================================
  // LISTA FABRICAÇÕES (COM JOIN EM DIETA)
  // =========================================================
  Future<List<FabricacaoHeader>> listFabricacoes() async {
    const t = "CADASTRO_FABRICA_RACAO";
    if (!await _hasTable(t)) return [];

    final idCol = await _pickCol(t, ["ID"]) ?? "ID";
    final statusCol = await _pickCol(t, ["STATUS"]);
    final finalizadaCol = await _pickCol(t, ["FINALIZADA"]);
    final fabStatusCol = await _pickCol(t, ["FAB_STATUS"]);
    final carregadaCol = await _pickCol(t, ["CARREGADA"]);
    final handoffCol = await _pickCol(t, ["HANDOFF_ID"]);
    final exportadoEmCol = await _pickCol(t, ["EXPORTADO_EM"]);
    final originDeviceCol = await _pickCol(t, ["ORIGIN_DEVICE"]);
    final tratoCol = await _pickCol(t, ["TRATO"]);

    final dataFabCol = await _pickCol(
      t,
      ["DATA_FABRICACAO", "DATA_FAB", "DATA", "DATAREG", "DATA_REG"],
    );
    final horaIniCol =
        await _pickCol(t, ["HORA_INICIO", "HORAINI", "HORA_INI", "HORA"]);

    final prevCol =
        await _pickCol(t, ["QTD_PREVISTA", "PREVKG", "PREV_KG", "PREVISTOKG"]);
    final realCol = await _pickCol(
        t, ["QTD_REALIZADA", "REALIZADOKG", "REALIZADO_KG", "REALIZADO"]);

    const idDietaCol = "ID_DIETA";

    String sel(String alias, String? col, String fallback) {
      if (col == null) return "$fallback AS $alias";
      return "COALESCE($col, $fallback) AS $alias";
    }

    final hasDieta = await _hasTable("DIETA");
    final join = hasDieta ? "LEFT JOIN DIETA di ON di.ID = f.$idDietaCol" : "";
    final dietaNomeExpr =
        hasDieta ? "COALESCE(NULLIF(TRIM(di.NOME),''),'')" : "''";

    final select = """
    SELECT
      f.$idCol AS id,
      ${sel("id_dieta", "f.$idDietaCol", "''")},
      $dietaNomeExpr AS dieta_nome,
      ${sel("trato", tratoCol != null ? "f.$tratoCol" : null, "0")},
      ${sel("qtd_prevista", prevCol != null ? "f.$prevCol" : null, "0")},
      ${sel("qtd_realizada", realCol != null ? "f.$realCol" : null, "0")},
      ${sel("finalizada", finalizadaCol != null ? "f.$finalizadaCol" : null, "0")},
      ${sel("fab_status", fabStatusCol != null ? "f.$fabStatusCol" : null, "0")},
      ${sel("handoff_id", handoffCol != null ? "f.$handoffCol" : null, "''")},
      ${sel("exportado_em", exportadoEmCol != null ? "f.$exportadoEmCol" : null, "''")},
      ${sel("origin_device", originDeviceCol != null ? "f.$originDeviceCol" : null, "''")},
      ${sel("carregada", carregadaCol != null ? "f.$carregadaCol" : null, "0")},
      ${sel("data_fabricacao", dataFabCol != null ? "f.$dataFabCol" : null, "''")},
      ${sel("hora_inicio", horaIniCol != null ? "f.$horaIniCol" : null, "''")}
    FROM $t f
    $join
  """;

    final where = <String>[];
    if (statusCol != null) where.add("f.$statusCol = 1");

    final order = (dataFabCol != null)
        ? "ORDER BY COALESCE(f.$dataFabCol,'') DESC, COALESCE(f.${horaIniCol ?? "''"},'') DESC"
        : (horaIniCol != null)
            ? "ORDER BY COALESCE(f.$horaIniCol,'') DESC"
            : "";

    final sql = """
    $select
    ${where.isEmpty ? "" : "WHERE ${where.join(" AND ")}"}
    $order
  """;

    final db = await _db;
    final rows = await db.rawQuery(sql);

    return rows
        .map((e) =>
            FabricacaoHeader.fromMap(_lowerKeys(Map<String, Object?>.from(e))))
        .toList();
  }

  Future<FabricacaoHeader?> getFabricacaoById(String idFab) async {
    final id = idFab.trim();
    if (id.isEmpty) return null;
    final list = await listFabricacoes();
    for (final h in list) {
      if (h.id == id) return h;
    }
    return null;
  }

  // =========================================================
  // INGREDIENTES
  // =========================================================
  Future<List<FabIngrediente>> listIngredientesModal(String fabId) async {
    return listIngredientesDaFabricacao(fabId);
  }

  Future<List<FabIngrediente>> listIngredientesDaFabricacao(
      String idFab) async {
    const t = "DETALHES_FABRICA_RACAO";
    if (!await _hasTable(t)) return [];

    final idCol = await _pickCol(t, ["ID"]) ?? "ID";
    final idFabCol = await _pickCol(t,
            ["ID_FABRICACAO", "IDFABRICACAO", "ID_CABECALHO", "ID_HEADER"]) ??
        "ID_FABRICACAO";
    final statusCol = await _pickCol(t, ["STATUS"]);

    final idInsumoCol = await _pickCol(t, ["ID_INSUMO", "IDINSUMO"]);
    final insumoNomeCol =
        await _pickCol(t, ["INSUMO_NOME", "NOME_INSUMO", "INSUMO"]);
    final ordemCol = await _pickCol(t, ["ORDEM", "ORDEM_INSUMO", "SEQ"]);

    final prevCol = await _pickCol(t, ["QTD_PREVISTA", "PREVKG", "PREV_KG"]);
    final realCol =
        await _pickCol(t, ["QTD_REALIZADA", "REALIZADOKG", "REALIZADO_KG"]);
    final prePesadoCol = await _pickCol(
        t, ["PRE_PESADO", "PREPESADO", "PRE_PESADO_FLAG", "PREPESADO_FLAG"]);
    final horaIniCol = await _pickCol(t, ["HORA_INICIO", "HORAINI", "HORA_INI"]);
    final horaFimCol =
        await _pickCol(t, ["HORA_FIM", "HORAFIM", "HORA_FIM_INSUMO"]);
    final pesoIniCol =
        await _pickCol(t, ["PESO_INICIO", "PESOINICIO", "PESO_INI"]);
    final pesoFimCol =
        await _pickCol(t, ["PESO_FIM", "PESOFIM", "PESO_FIM_INSUMO"]);

    String sel(String alias, String? col, String fallback) {
      if (col == null) return "$fallback AS $alias";
      return "COALESCE($col, $fallback) AS $alias";
    }

    final sql = """
      SELECT
        $idCol AS id,
        ${sel("id_insumo", idInsumoCol, "''")},
        ${sel("insumo_nome", insumoNomeCol, "''")},
        ${sel("ordem", ordemCol, "0")},
        ${sel("qtd_prevista", prevCol, "0")},
        ${sel("qtd_realizada", realCol, "0")},
        ${sel("pre_pesado", prePesadoCol, "0")},
        ${sel("hora_inicio", horaIniCol, "''")},
        ${sel("hora_fim", horaFimCol, "''")},
        ${sel("peso_inicio", pesoIniCol, "0")},
        ${sel("peso_fim", pesoFimCol, "0")}
      FROM $t
      WHERE $idFabCol = ?
      ${statusCol != null ? "AND $statusCol = 1" : ""}
      ORDER BY ${ordemCol != null ? "COALESCE($ordemCol,0)" : "1"} ASC
    """;

    final db = await _db;
    final rows = await db.rawQuery(sql, [idFab]);

    return rows
        .map((m) =>
            FabIngrediente.fromMap(_lowerKeys(Map<String, Object?>.from(m))))
        .toList();
  }

  Future<List<FabIngrediente>> listIngredientesFabricacao(String idFab) async {
    return listIngredientesDaFabricacao(idFab);
  }

  // =========================================================
  // DELETE
  // =========================================================
  Future<bool> canDeleteFabricacao(String idFab) async {
    const t = "CADASTRO_FABRICA_RACAO";
    if (!await _hasTable(t)) return false;

    // Regra: pode excluir qualquer fabricação ainda não sincronizada.
    final syncCol =
        await _pickCol(t, ["FLAG_SYNC", "SYNCAWS", "SYNC_AWS", "SYNC"]);
    if (syncCol == null) return false;

    final db = await _db;
    final r = await db.rawQuery(
      "SELECT COALESCE($syncCol,0) AS v FROM $t WHERE ID = ? LIMIT 1",
      [idFab],
    );
    if (r.isEmpty) return false;

    final v = (r.first["v"] as num?)?.toInt() ?? 0;
    return v == 0;
  }

  Future<void> deleteFabricacao(String idFab) async {
    const h = "CADASTRO_FABRICA_RACAO";
    const d = "DETALHES_FABRICA_RACAO";
    final db = await _db;

    final hasD = await _hasTable(d);
    final hasH = await _hasTable(h);

    String idFabCol = "ID_FABRICACAO";
    if (hasD) {
      idFabCol = await _pickCol(d,
              ["ID_FABRICACAO", "IDFABRICACAO", "ID_CABECALHO", "ID_HEADER"]) ??
          "ID_FABRICACAO";
    }

    await db.transaction((txn) async {
      if (hasD) {
        await txn.delete(d, where: "$idFabCol = ?", whereArgs: [idFab]);
      }
      if (hasH) {
        await txn.delete(h, where: "ID = ?", whereArgs: [idFab]);
      }
    });
  }

  Future<int> reabilitarSyncFiltrados({
    required List<FabricacaoHeader> itens,
  }) async {
    return _setSyncFiltrados(itens: itens, syncValue: 0);
  }

  Future<int> marcarSyncOkFiltrados({
    required List<FabricacaoHeader> itens,
  }) async {
    return _setSyncFiltrados(itens: itens, syncValue: 1);
  }

  Future<int> _setSyncFiltrados({
    required List<FabricacaoHeader> itens,
    required int syncValue,
  }) async {
    const h = "CADASTRO_FABRICA_RACAO";
    const d = "DETALHES_FABRICA_RACAO";
    if (!await _hasTable(h)) return 0;

    final ids = itens
        .map((e) => e.id.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    if (ids.isEmpty) return 0;

    final syncHeaderCol =
        await _pickCol(h, ["FLAG_SYNC", "SYNCAWS", "SYNC_AWS", "SYNC"]);
    if (syncHeaderCol == null) return 0;

    final hasDetalhes = await _hasTable(d);
    final syncDetCol = hasDetalhes
        ? await _pickCol(d, ["FLAG_SYNC", "SYNCAWS", "SYNC_AWS", "SYNC"])
        : null;
    final idFabDetCol = hasDetalhes
        ? await _pickCol(
                d, ["ID_FABRICACAO", "IDFABRICACAO", "ID_CABECALHO", "ID_HEADER"]) ??
            "ID_FABRICACAO"
        : "ID_FABRICACAO";

    final db = await _db;
    var total = 0;

    await db.transaction((txn) async {
      for (final idFab in ids) {
        total += await txn.update(
          h,
          {syncHeaderCol: syncValue},
          where: "ID = ?",
          whereArgs: [idFab],
        );

        if (syncDetCol != null) {
          await txn.update(
            d,
            {syncDetCol: syncValue},
            where: "$idFabDetCol = ?",
            whereArgs: [idFab],
          );
        }
      }
    });

    return total;
  }

  // =========================================================
  // ✅ MÉTODOS PARA O CONTROLLER
  // =========================================================
  Future<String> getHoraInicioByDetId(String idDet) async {
    const t = "DETALHES_FABRICA_RACAO";
    if (!await _hasTable(t)) return "";

    final horaIniCol =
        await _pickCol(t, ["HORA_INICIO", "HORAINI", "HORA_INI"]);
    if (horaIniCol == null) return "";

    final db = await _db;
    final rows = await db.rawQuery(
      "SELECT COALESCE($horaIniCol,'') AS v FROM $t WHERE ID = ? LIMIT 1",
      [idDet],
    );
    return rows.isEmpty ? "" : (rows.first["v"] ?? "").toString();
  }

  Future<String> getHoraFimByDetId(String idDet) async {
    const t = "DETALHES_FABRICA_RACAO";
    if (!await _hasTable(t)) return "";

    final horaFimCol =
        await _pickCol(t, ["HORA_FIM", "HORAFIM", "HORA_FIM_INSUMO"]);
    if (horaFimCol == null) return "";

    final db = await _db;
    final rows = await db.rawQuery(
      "SELECT COALESCE($horaFimCol,'') AS v FROM $t WHERE ID = ? LIMIT 1",
      [idDet],
    );
    return rows.isEmpty ? "" : (rows.first["v"] ?? "").toString();
  }

  Future<int> getPesoInicioByDetId(String idDet) async {
    const t = "DETALHES_FABRICA_RACAO";
    if (!await _hasTable(t)) return 0;

    final col = await _pickCol(t, ["PESO_INICIO", "PESOINICIO", "PESO_INI"]);
    if (col == null) return 0;

    final db = await _db;
    final rows = await db.rawQuery(
      "SELECT COALESCE($col,0) AS v FROM $t WHERE ID = ? LIMIT 1",
      [idDet],
    );
    return rows.isEmpty ? 0 : (rows.first["v"] as num?)?.toInt() ?? 0;
  }

  Future<int> getPesoFimByDetId(String idDet) async {
    const t = "DETALHES_FABRICA_RACAO";
    if (!await _hasTable(t)) return 0;

    final col = await _pickCol(t, ["PESO_FIM", "PESOFIM", "PESO_FIM_INSUMO"]);
    if (col == null) return 0;

    final db = await _db;
    final rows = await db.rawQuery(
      "SELECT COALESCE($col,0) AS v FROM $t WHERE ID = ? LIMIT 1",
      [idDet],
    );
    return rows.isEmpty ? 0 : (rows.first["v"] as num?)?.toInt() ?? 0;
  }

  Future<void> updateIngredienteFabricacao({
    required String idDet,
    required double qtdRealizada,
    required String horaInicio,
    required String horaFim,
    int? pesoInicio,
    int? pesoFim,
  }) async {
    const t = "DETALHES_FABRICA_RACAO";
    if (!await _hasTable(t)) return;

    final realCol =
        await _pickCol(t, ["QTD_REALIZADA", "REALIZADOKG", "REALIZADO_KG"]) ??
            "QTD_REALIZADA";
    final horaIniCol =
        await _pickCol(t, ["HORA_INICIO", "HORAINI", "HORA_INI"]);
    final horaFimCol =
        await _pickCol(t, ["HORA_FIM", "HORAFIM", "HORA_FIM_INSUMO"]);
    final pesoIniCol =
        await _pickCol(t, ["PESO_INICIO", "PESOINICIO", "PESO_INI"]);
    final pesoFimCol =
        await _pickCol(t, ["PESO_FIM", "PESOFIM", "PESO_FIM_INSUMO"]);

    final values = <String, Object?>{
      realCol: qtdRealizada,
    };
    if (horaIniCol != null) values[horaIniCol] = horaInicio;
    if (horaFimCol != null) values[horaFimCol] = horaFim;
    if (pesoIniCol != null && pesoInicio != null) values[pesoIniCol] = pesoInicio;
    if (pesoFimCol != null && pesoFim != null) values[pesoFimCol] = pesoFim;

    final db = await _db;
    await db.update(
      t,
      values,
      where: "ID = ?",
      whereArgs: [idDet],
    );
  }

  Future<int> updateIngredienteFabricacaoRobusto({
    required String idDet,
    required String idFabricacao,
    required String idInsumo,
    required int ordem,
    required double qtdRealizada,
    required String horaInicio,
    required String horaFim,
    int? pesoInicio,
    int? pesoFim,
  }) async {
    const t = "DETALHES_FABRICA_RACAO";
    if (!await _hasTable(t)) return 0;

    final realCol =
        await _pickCol(t, ["QTD_REALIZADA", "REALIZADOKG", "REALIZADO_KG"]) ??
            "QTD_REALIZADA";
    final horaIniCol =
        await _pickCol(t, ["HORA_INICIO", "HORAINI", "HORA_INI"]);
    final horaFimCol =
        await _pickCol(t, ["HORA_FIM", "HORAFIM", "HORA_FIM_INSUMO"]);
    final pesoIniCol =
        await _pickCol(t, ["PESO_INICIO", "PESOINICIO", "PESO_INI"]);
    final pesoFimCol =
        await _pickCol(t, ["PESO_FIM", "PESOFIM", "PESO_FIM_INSUMO"]);

    final values = <String, Object?>{
      realCol: qtdRealizada,
    };
    if (horaIniCol != null) values[horaIniCol] = horaInicio;
    if (horaFimCol != null) values[horaFimCol] = horaFim;
    if (pesoIniCol != null && pesoInicio != null) values[pesoIniCol] = pesoInicio;
    if (pesoFimCol != null && pesoFim != null) values[pesoFimCol] = pesoFim;

    final db = await _db;
    final det = idDet.trim();
    if (det.isEmpty) return 0;

    final updated = await db.update(
      t,
      values,
      where: "TRIM(COALESCE(ID,'')) = TRIM(?)",
      whereArgs: [det],
    );

    if (updated <= 0 && kDebugMode) {
      debugPrint(
        "[FAB] persist falhou por ID det='$idDet' fab='$idFabricacao' insumo='$idInsumo' ordem=$ordem",
      );
    }

    return updated;
  }

  // =========================================================
  // ✅ TOTAL REALIZADO DO HEADER
  // =========================================================
  Future<double> getTotalRealizadoFabricacao(String idFabricacao) async {
    const h = "CADASTRO_FABRICA_RACAO";
    if (!await _hasTable(h)) return 0.0;

    final realCol = await _pickCol(
            h, ["QTD_REALIZADA", "REALIZADOKG", "REALIZADO_KG", "REALIZADO"]) ??
        "QTD_REALIZADA";

    final db = await _db;
    final rows = await db.rawQuery(
      "SELECT COALESCE($realCol,0) AS v FROM $h WHERE ID = ? LIMIT 1",
      [idFabricacao],
    );
    if (rows.isEmpty) return 0.0;
    return (rows.first["v"] as num?)?.toDouble() ?? 0.0;
  }

  // =========================================================
  // ✅ FINALIZA FABRICAÇÃO
  // =========================================================
  Future<void> finalizaFabricacao({
    required String idFabricacao,
    required double qtdRealizada,
    required String horaFim,
    required int finalizada,
  }) async {
    const h = "CADASTRO_FABRICA_RACAO";
    if (!await _hasTable(h)) return;

    await updateFabricacaoParcial(idFabricacao);

    final realCol = await _pickCol(
            h, ["QTD_REALIZADA", "REALIZADOKG", "REALIZADO_KG", "REALIZADO"]) ??
        "QTD_REALIZADA";
    final fimCol = await _pickCol(h, ["HORA_FIM", "HORAFIM", "HORA_FIM_FAB"]);
    final finCol = await _pickCol(h, ["FINALIZADA"]);
    final fabStatusCol = await _pickCol(h, ["FAB_STATUS"]);

    final values = <String, Object?>{
      realCol: qtdRealizada,
    };

    if (fimCol != null) values[fimCol] = horaFim;
    if (finCol != null) values[finCol] = finalizada;
    if (fabStatusCol != null && finalizada == 1) {
      values[fabStatusCol] = fabricacaoStatusFinalizada;
    }

    final db = await _db;
    await db.update(
      h,
      values,
      where: "ID = ?",
      whereArgs: [idFabricacao],
    );
  }

  // =========================================================
  // ✅ INSERE / GARANTE CARREGAMENTO ABERTO (STATUS=0)
  // - idempotente: se já existe aberto, não cria outro
  // =========================================================
  Future<String?> ensureCarregamentoAberto({
    required String idFabricacao,
    required String idDieta,
    required double pesoFabricado,
    required double pesoCarregado,
    required String idVagao,
  }) async {
    const t = "CARREGAMENTO";
    if (!await _hasTable(t)) return null;

    final db = await _db;

    final idCol = await _pickCol(t, ["ID"]) ?? "ID";
    final idFabCol =
        await _pickCol(t, ["ID_FABRICACAO", "IDFABRICACAO"]) ?? "ID_FABRICACAO";
    final idDietaCol = await _pickCol(t, ["ID_DIETA", "IDDIETA"]) ?? "ID_DIETA";

    final statusCol = await _pickCol(t, ["STATUS"]);
    final dataRegCol =
        await _pickCol(t, ["DATA_REGISTRO", "DATAREG", "DATA_REG"]);

    final pesoFabCol = await _pickCol(t, ["PESO_FABRICADO", "PESOFABRICADO"]) ??
        "PESO_FABRICADO";
    final pesoCarCol = await _pickCol(t, ["PESO_CARREGADO", "PESOCARREGADO"]) ??
        "PESO_CARREGADO";
    final idVagCol = await _pickCol(t, ["ID_VAGAO", "IDVAGAO"]) ?? "ID_VAGAO";

    // ✅ valida vagão (não pode criar carregamento sem vagão)
    final vag = idVagao.trim();
    if (vag.isEmpty) {
      throw Exception(
          "Vagão não informado. Selecione um vagão nas configurações.");
    }

    // 1) se existe carregamento ABERTO pra essa fabricação, reutiliza
    if (statusCol != null) {
      final existing = await db.rawQuery(
        "SELECT $idCol AS id FROM $t WHERE $idFabCol = ? AND COALESCE($statusCol,0) = 0 LIMIT 1",
        [idFabricacao],
      );
      if (existing.isNotEmpty) {
        return (existing.first["id"] ?? "").toString();
      }
    }

    await _carregDao.finalizarAbertos(idVagao: vag);

    // 2) cria novo
    final uid = _genUuid();
    final row = <String, Object?>{
      idCol: uid,
      idFabCol: idFabricacao,
      idDietaCol: idDieta,
      pesoFabCol: pesoFabricado,
      pesoCarCol: pesoCarregado,
      idVagCol: vag, // ✅ TEXT (UUID)
    };

    // STATUS=0 se existir coluna
    if (statusCol != null) row[statusCol] = 0;

    // DATA_REGISTRO se existir coluna
    if (dataRegCol != null) {
      row[dataRegCol] = DateTime.now().toIso8601String();
    }

    await db.insert(t, row);
    return uid;
  }

  // =========================================================
// ✅ STATUS DO CARREGAMENTO POR FABRICAÇÃO
// =========================================================
  Future<Map<String, Object?>?> getCarregamentoStatusByFabricacao(
      String idFabricacao) async {
    const t = "CARREGAMENTO";
    if (!await _hasTable(t)) return null;

    final db = await _db;

    final idCol = await _pickCol(t, ["ID"]) ?? "ID";
    final idFabCol =
        await _pickCol(t, ["ID_FABRICACAO", "IDFABRICACAO"]) ?? "ID_FABRICACAO";
    final statusCol = await _pickCol(t, ["STATUS"]) ?? "STATUS";
    final dataRegCol =
        await _pickCol(t, ["DATA_REGISTRO", "DATAREG", "DATA_REG"]);
    final pesoFabCol = await _pickCol(t, ["PESO_FABRICADO", "PESOFABRICADO"]);
    final pesoCarCol = await _pickCol(t, ["PESO_CARREGADO", "PESOCARREGADO"]);
    final idVagCol = await _pickCol(t, ["ID_VAGAO", "IDVAGAO"]);

    // pega o mais recente dessa fabricação
    final rows = await db.rawQuery("""
    SELECT
      $idCol AS id,
      COALESCE($statusCol,0) AS status
      ${dataRegCol != null ? ", $dataRegCol AS data_registro" : ""}
      ${pesoFabCol != null ? ", COALESCE($pesoFabCol,0) AS peso_fabricado" : ""}
      ${pesoCarCol != null ? ", COALESCE($pesoCarCol,0) AS peso_carregado" : ""}
      ${idVagCol != null ? ", COALESCE($idVagCol,'') AS id_vagao" : ""}
    FROM $t
    WHERE $idFabCol = ?
    ORDER BY COALESCE($statusCol,0) ASC, ${dataRegCol ?? "rowid"} DESC
    LIMIT 1
  """, [idFabricacao]);

    if (rows.isEmpty) return null;

    final m = Map<String, Object?>.from(rows.first);
    final st = (m["status"] as num?)?.toInt() ?? 0;

    // statusText:
    // - não existe linha => null (tratado fora)
    // - 0 => ABERTO
    // - !=0 => FECHADO
    m["status_text"] = (st == 0) ? "ABERTO" : "FECHADO";

    return m;
  }

  /// (mantém o método antigo, mas agora grava STATUS=0 se tiver coluna)
  Future<void> insereCarregamentoSePossivel({
    required String idFabricacao,
    required String idDieta,
    required double pesoFabricado,
    required double pesoCarregado,
    required String idVagao,
  }) async {
    await ensureCarregamentoAberto(
      idFabricacao: idFabricacao,
      idDieta: idDieta,
      pesoFabricado: pesoFabricado,
      pesoCarregado: pesoCarregado,
      idVagao: idVagao, // ✅ UUID
    );
  }

  // =========================================================
  // Atualiza QTD_REALIZADA (header) e MS_REALIZADA (se existir)
  // =========================================================
  Future<void> updateFabricacaoParcial(String idFabricacao) async {
    const h = "CADASTRO_FABRICA_RACAO";
    const d = "DETALHES_FABRICA_RACAO";
    if (!await _hasTable(h) || !await _hasTable(d)) return;

    final idFabCol = await _pickCol(d,
            ["ID_FABRICACAO", "IDFABRICACAO", "ID_CABECALHO", "ID_HEADER"]) ??
        "ID_FABRICACAO";

    final detRealCol =
        await _pickCol(d, ["QTD_REALIZADA", "REALIZADOKG", "REALIZADO_KG"]) ??
            "QTD_REALIZADA";
    final detMsCol =
        await _pickCol(d, ["MS_INSUMO", "MS", "PERC_MS", "MS_PERC"]);

    final db = await _db;

    double totalRealizado = 0.0;
    double totalMS = 0.0;

    final rows = await db.rawQuery(
      """
      SELECT
        COALESCE($detRealCol,0) AS qtd
        ${detMsCol != null ? ", COALESCE($detMsCol,0) AS ms" : ""}
      FROM $d
      WHERE $idFabCol = ?
      """,
      [idFabricacao],
    );

    for (final r in rows) {
      final qtd = (r["qtd"] as num?)?.toDouble() ?? 0.0;
      totalRealizado += qtd;

      if (detMsCol != null) {
        final ms = (r["ms"] as num?)?.toDouble() ?? 0.0; // percentual
        totalMS += (qtd * (ms / 100.0));
      }
    }

    var msRealizada =
        (totalRealizado > 0) ? (totalMS / totalRealizado) * 100.0 : 0.0;

    if (!MsPercent.isValid(msRealizada)) {
      final headDietaCol =
          await _pickCol(h, ["ID_DIETA", "IDDIETA", "ID_RACAO"]) ?? "ID_DIETA";
      final headRow = await db.query(
        h,
        columns: [headDietaCol],
        where: "ID = ?",
        whereArgs: [idFabricacao],
        limit: 1,
      );
      final idDieta = headRow.isNotEmpty
          ? (headRow.first[headDietaCol] ?? "").toString().trim()
          : "";
      if (idDieta.isNotEmpty) {
        final dietaRows = await db.rawQuery(
          "SELECT COALESCE(MS, 0) AS ms FROM DIETA WHERE TRIM(ID) = TRIM(?) LIMIT 1",
          [idDieta],
        );
        if (dietaRows.isNotEmpty) {
          msRealizada = MsPercent.resolve(
            msFabricacao: 0,
            msDieta: (dietaRows.first["ms"] as num?)?.toDouble(),
          );
        }
      }
    }

    final headRealCol = await _pickCol(
            h, ["QTD_REALIZADA", "REALIZADOKG", "REALIZADO_KG", "REALIZADO"]) ??
        "QTD_REALIZADA";
    final headMsCol =
        await _pickCol(h, ["MS_REALIZADA", "MSREALIZADA", "MS_REAL"]);

    final values = <String, Object?>{headRealCol: totalRealizado};
    if (headMsCol != null && MsPercent.isValid(msRealizada)) {
      values[headMsCol] = msRealizada;
    }

    await db.update(
      h,
      values,
      where: "ID = ?",
      whereArgs: [idFabricacao],
    );
  }

  Future<String> ensureHandoffId(String idFabricacao) async {
    const h = "CADASTRO_FABRICA_RACAO";
    if (!await _hasTable(h)) return "";

    final handoffCol = await _pickCol(h, ["HANDOFF_ID"]);
    if (handoffCol == null) return "";

    final db = await _db;
    final rows = await db.rawQuery(
      "SELECT COALESCE($handoffCol,'') AS v FROM $h WHERE ID = ? LIMIT 1",
      [idFabricacao],
    );
    final atual = rows.isEmpty ? "" : (rows.first["v"] ?? "").toString().trim();
    if (atual.isNotEmpty) return atual;

    final novo = _genUuid();
    await db.update(
      h,
      {handoffCol: novo},
      where: "ID = ?",
      whereArgs: [idFabricacao],
    );
    return novo;
  }

  Future<void> marcarPendenteCaminhao(String idFabricacao) async {
    const h = "CADASTRO_FABRICA_RACAO";
    if (!await _hasTable(h)) return;

    final fabStatusCol = await _pickCol(h, ["FAB_STATUS"]);
    final exportadoEmCol = await _pickCol(h, ["EXPORTADO_EM"]);
    final finalizadaCol = await _pickCol(h, ["FINALIZADA"]);
    final originDeviceCol = await _pickCol(h, ["ORIGIN_DEVICE"]);

    final handoffId = await ensureHandoffId(idFabricacao);

    final values = <String, Object?>{};
    if (fabStatusCol != null) {
      values[fabStatusCol] = fabricacaoStatusPendenteCaminhao;
    }
    if (exportadoEmCol != null) {
      values[exportadoEmCol] = DateTime.now().toIso8601String();
    }
    if (finalizadaCol != null) {
      values[finalizadaCol] = 0;
    }
    if (originDeviceCol != null) {
      values[originDeviceCol] = "ESTACIONARIO";
    }
    if (values.isNotEmpty) {
      final db = await _db;
      await db.update(
        h,
        values,
        where: "ID = ?",
        whereArgs: [idFabricacao],
      );
    }

    if (kDebugMode) {
      debugPrint("[FAB] parcial->pendente fab=$idFabricacao handoff=$handoffId");
    }
  }

  Future<void> marcarFinalizadaComOrigem(
      String idFabricacao, String originDevice) async {
    const h = "CADASTRO_FABRICA_RACAO";
    if (!await _hasTable(h)) return;
    final fabStatusCol = await _pickCol(h, ["FAB_STATUS"]);
    final originDeviceCol = await _pickCol(h, ["ORIGIN_DEVICE"]);
    final values = <String, Object?>{};
    if (fabStatusCol != null) values[fabStatusCol] = fabricacaoStatusFinalizada;
    if (originDeviceCol != null) values[originDeviceCol] = originDevice;
    if (values.isEmpty) return;
    final db = await _db;
    await db.update(h, values, where: "ID = ?", whereArgs: [idFabricacao]);
  }

  /// Distribuidor: grava peso lido na balança do vagão em [CARREGAMENTO].
  Future<void> registrarCarregamentoDistribuidorVagao({
    required String idFabricacao,
    required double pesoCarregadoKg,
    required String idVagao,
    required bool concluirFabricacaoNoVagao,
  }) async {
    final vag = idVagao.trim();
    if (vag.isEmpty) {
      throw Exception(
        "Vagão não configurado. Selecione um vagão nas configurações.",
      );
    }
    if (pesoCarregadoKg <= 0) {
      throw Exception("Informe um peso carregado maior que zero.");
    }

    final dao = CarregamentoDao();
    final n = await dao.updatePesoCarregadoAbertoPorFabricacao(
      idFabricacao: idFabricacao,
      pesoCarregado: pesoCarregadoKg,
      idVagao: vag,
    );
    if (n <= 0) {
      throw Exception(
        "Não há carregamento aberto para esta fabricação. "
        "Receba o lote do estacionário em Carregamento primeiro.",
      );
    }

    await _marcarHeaderIntColumn(idFabricacao, "CARREGADA", 1);

    if (concluirFabricacaoNoVagao) {
      await marcarFinalizadaComOrigem(idFabricacao, "CAMINHAO");
      await _marcarHeaderIntColumn(idFabricacao, "FINALIZADA", 1);
    }
  }

  Future<void> _marcarHeaderIntColumn(
    String idFab,
    String colName,
    int value,
  ) async {
    const h = "CADASTRO_FABRICA_RACAO";
    if (!await _hasTable(h)) return;
    final col = await _pickCol(h, [colName]);
    if (col == null) return;
    final db = await _db;
    await db.update(
      h,
      {col: value},
      where: "ID = ?",
      whereArgs: [idFab],
    );
  }

  Future<bool> isPendenteCaminhao(String idFabricacao) async {
    const h = "CADASTRO_FABRICA_RACAO";
    if (!await _hasTable(h)) return false;
    final fabStatusCol = await _pickCol(h, ["FAB_STATUS"]);
    if (fabStatusCol == null) return false;
    final db = await _db;
    final rows = await db.rawQuery(
      "SELECT COALESCE($fabStatusCol,0) AS st FROM $h WHERE ID = ? LIMIT 1",
      [idFabricacao],
    );
    if (rows.isEmpty) return false;
    final st = (rows.first["st"] as num?)?.toInt() ?? 0;
    return st == fabricacaoStatusPendenteCaminhao;
  }

  // =========================================================
  // UUID helper
  // =========================================================
  String _genUuid() {
    final r = Random.secure();
    String h(int v) => v.toRadixString(16).padLeft(2, "0");
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final s = b.map(h).join();
    return "${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}";
  }

  // =========================================================
  // ✅ CRIA / REUTILIZA CARREGAMENTO PARA UMA FABRICAÇÃO
  // =========================================================
  Future<String?> criarCarregamentoParaFabricacao({
    required String idFabricacao,
    String? idVagaoOverride,
    int tipoTrabalho = 0,
  }) async {
    final id = idFabricacao.trim();
    if (id.isEmpty) {
      throw Exception("ID da fabricação inválido.");
    }

    final h = await getFabricacaoById(id);
    if (h == null) {
      throw Exception("Fabricação não encontrada.");
    }

    var idVagao = (idVagaoOverride ?? "").trim();
    if (idVagao.isEmpty) {
      idVagao = await getIdVagaoByFabricacaoId(id);
    }
    if (idVagao.isEmpty) {
      throw Exception(
        "Vagão não informado. Selecione um vagão nas configurações ou na fabricação.",
      );
    }

    var totalReal = h.qtdRealizada;
    if (totalReal <= 0) {
      totalReal = await getTotalRealizadoFabricacao(id);
    }
    if (totalReal <= 0) {
      throw Exception(
        "Fabricação sem peso realizado. Não é possível gerar carregamento.",
      );
    }

    final pesoCarregado = (tipoTrabalho == 0) ? totalReal : 0.0;

    return ensureCarregamentoAberto(
      idFabricacao: id,
      idDieta: h.idDieta,
      pesoFabricado: totalReal,
      pesoCarregado: pesoCarregado,
      idVagao: idVagao,
    );
  }

  /// Finaliza o carregamento aberto desta fabricação (STATUS=2).
  Future<void> finalizarCarregamentoDaFabricacao(String idFabricacao) async {
    final id = idFabricacao.trim();
    if (id.isEmpty) throw Exception("ID da fabricação inválido.");

    final aberto = await _carregDao.getAbertoByFabricacao(id);
    if (aberto == null) {
      throw Exception("Não há carregamento aberto para esta fabricação.");
    }
    final idCar = (aberto["ID"] ?? aberto["id"] ?? "").toString().trim();
    if (idCar.isEmpty) {
      throw Exception("Carregamento aberto sem ID.");
    }
    final n = await _carregDao.finalizar(idCar);
    if (n <= 0) {
      throw Exception("Falha ao finalizar o carregamento.");
    }
  }

  /// Reabre o último carregamento fechado da fabricação, se não houver nenhum aberto.
  Future<void> reabrirCarregamentoDaFabricacao(String idFabricacao) async {
    final id = idFabricacao.trim();
    if (id.isEmpty) throw Exception("ID da fabricação inválido.");

    if (await _carregDao.existeAlgumAberto()) {
      throw Exception(
        "Já existe um carregamento aberto. Finalize-o antes de reabrir outro.",
      );
    }

    final ultimo = await _carregDao.getUltimoPorFabricacao(id);
    if (ultimo == null) {
      throw Exception("Esta fabricação não possui carregamento para reabrir.");
    }

    final st = int.tryParse((ultimo["STATUS"] ?? "0").toString().trim()) ?? 0;
    if (st == CarregamentoDao.statusAberto) {
      throw Exception("O carregamento desta fabricação já está aberto.");
    }

    final idCar = (ultimo["ID"] ?? ultimo["id"] ?? "").toString().trim();
    if (idCar.isEmpty) {
      throw Exception("Carregamento sem ID.");
    }

    final n = await _carregDao.reabrir(idCar);
    if (n <= 0) {
      throw Exception("Falha ao reabrir o carregamento.");
    }
  }

  // =========================================================
  // ✅ BUSCA ID_VAGAO GRAVADO NA FABRICAÇÃO (HEADER)
  // =========================================================
  Future<String> getIdVagaoByFabricacaoId(String idFabricacao) async {
    const h = "CADASTRO_FABRICA_RACAO";
    if (!await _hasTable(h)) return "";

    final idVagCol = await _pickCol(h, ["ID_VAGAO", "IDVAGAO"]);
    if (idVagCol == null) return "";

    final db = await _db;
    final rows = await db.rawQuery(
      "SELECT COALESCE($idVagCol,'') AS v FROM $h WHERE ID = ? LIMIT 1",
      [idFabricacao],
    );

    if (rows.isEmpty) return "";
    return (rows.first["v"] ?? "").toString().trim();
  }

  /// Exportação completa para auditoria (POST /Post/FabricacaoAudit).
  Future<List<Map<String, Object?>>> listAllForAudit() async {
    const h = "CADASTRO_FABRICA_RACAO";
    final db = await _db;

    final hasDieta = await _hasTable("DIETA");
    if (hasDieta) {
      return db.rawQuery("""
        SELECT
          f.ID AS id,
          f.ID_DIETA AS id_dieta,
          COALESCE(d.NOME, f.ID_DIETA, '') AS racao_nome,
          f.DATA_FABRICACAO AS data_fabricacao,
          f.HORA_INICIO AS hora_inicio,
          f.HORA_FIM AS hora_fim,
          f.TRATO AS trato,
          COALESCE(f.QTD_PREVISTA, 0) AS qtd_prevista,
          COALESCE(f.QTD_REALIZADA, 0) AS qtd_realizada,
          COALESCE(f.FINALIZADA, 0) AS finalizada,
          COALESCE(f.FLAG_SYNC, 0) AS flag_sync,
          COALESCE(f.FAB_STATUS, 0) AS fab_status,
          COALESCE(f.HANDOFF_ID, '') AS handoff_id,
          COALESCE(f.ORIGIN_DEVICE, '') AS origin_device,
          COALESCE(f.ID_FAZENDA, '') AS id_fazenda,
          COALESCE(f.ID_USUARIO, '') AS id_usuario,
          COALESCE(f.ID_OPERADOR, '') AS id_operador,
          COALESCE(f.MS_PREVISTA, 0) AS ms_prevista,
          COALESCE(f.MS_REALIZADA, 0) AS ms_realizada,
          COALESCE(f.CARREGADA, 0) AS carregada,
          COALESCE(f.EXPORTADO_EM, '') AS exportado_em
        FROM $h f
        LEFT JOIN DIETA d ON TRIM(CAST(d.ID AS TEXT)) = TRIM(CAST(f.ID_DIETA AS TEXT))
        ORDER BY f.DATA_FABRICACAO DESC, f.HORA_INICIO DESC, f.ID DESC
      """);
    }

    return db.rawQuery("""
      SELECT
        f.ID AS id,
        f.ID_DIETA AS id_dieta,
        f.ID_DIETA AS racao_nome,
        f.DATA_FABRICACAO AS data_fabricacao,
        f.HORA_INICIO AS hora_inicio,
        f.HORA_FIM AS hora_fim,
        f.TRATO AS trato,
        COALESCE(f.QTD_PREVISTA, 0) AS qtd_prevista,
        COALESCE(f.QTD_REALIZADA, 0) AS qtd_realizada,
        COALESCE(f.FINALIZADA, 0) AS finalizada,
        COALESCE(f.FLAG_SYNC, 0) AS flag_sync,
        COALESCE(f.FAB_STATUS, 0) AS fab_status,
        COALESCE(f.HANDOFF_ID, '') AS handoff_id,
        COALESCE(f.ORIGIN_DEVICE, '') AS origin_device,
        COALESCE(f.ID_FAZENDA, '') AS id_fazenda,
        COALESCE(f.ID_USUARIO, '') AS id_usuario,
        COALESCE(f.ID_OPERADOR, '') AS id_operador,
        COALESCE(f.MS_PREVISTA, 0) AS ms_prevista,
        COALESCE(f.MS_REALIZADA, 0) AS ms_realizada,
        COALESCE(f.CARREGADA, 0) AS carregada,
        COALESCE(f.EXPORTADO_EM, '') AS exportado_em
      FROM $h f
      ORDER BY f.DATA_FABRICACAO DESC, f.HORA_INICIO DESC, f.ID DESC
    """);
  }
}
