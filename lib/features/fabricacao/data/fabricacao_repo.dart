// lib/features/fabricacao/data/fabricacao_repo.dart
import "package:sqflite/sqflite.dart";
import "../../../db/app_db.dart";
import "../domain/models.dart";

class FabricacaoRepo {
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
  // COMPAT
  // =========================================================
  // =========================================================
// FAB EM ABERTO (HOJE)  ✅ COM JOIN NA DIETA
// =========================================================
  // =========================================================
// COMPAT (mantém chamadas antigas da UI)
// =========================================================
Future<FabricacaoHeader?> getFabricacaoEmAberto([String? idFazenda]) {
  return getFabricacaoEmAbertoHoje(idFazenda);
}
  
  Future<FabricacaoHeader?> getFabricacaoEmAbertoHoje(
      [String? idFazenda]) async {
    const t = "CADASTRO_FABRICA_RACAO";
    if (!await _hasTable(t)) return null;

    final idCol = await _pickCol(t, ["ID"]) ?? "ID";

    final statusCol = await _pickCol(t, ["STATUS"]);
    final finalizadaCol = await _pickCol(t, ["FINALIZADA"]);
    final carregadaCol = await _pickCol(t, ["CARREGADA"]);

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

    // ✅ JOIN DIETA (igual listagem)
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
    final carregadaCol = await _pickCol(t, ["CARREGADA"]);
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

    // tenta joinar com DIETA se existir tabela e se existir idDietaCol
    final hasDieta = await _hasTable("DIETA");
    final canJoin = hasDieta && idDietaCol != null;

    final join = canJoin ? "LEFT JOIN DIETA di ON di.ID = f.$idDietaCol" : "";

    final dietaNomeExpr =
        canJoin ? "COALESCE(NULLIF(TRIM(di.NOME),''),'')" : "''";

    final select = """
    SELECT
      f.$idCol AS id,
      ${sel("id_dieta", idDietaCol != null ? "f.$idDietaCol" : null, "''")},
      $dietaNomeExpr AS dieta_nome,
      ${sel("trato", tratoCol != null ? "f.$tratoCol" : null, "0")},
      ${sel("qtd_prevista", prevCol != null ? "f.$prevCol" : null, "0")},
      ${sel("qtd_realizada", realCol != null ? "f.$realCol" : null, "0")},
      ${sel("finalizada", finalizadaCol != null ? "f.$finalizadaCol" : null, "0")},
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

  // =========================================================
  // INGREDIENTES
  // =========================================================
  Future<List<FabIngrediente>> listIngredientesModal(String fabId) async {
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
    final prevCol = await _pickCol(t, ["QTD_PREVISTA", "PREVKG", "PREV_KG"]);
    final realCol =
        await _pickCol(t, ["QTD_REALIZADA", "REALIZADOKG", "REALIZADO_KG"]);
    final ordemCol = await _pickCol(t, ["ORDEM", "ORDEM_INSUMO", "SEQ"]);
    final prePesadoCol = await _pickCol(t, ["PRE_PESADO", "PREPESADO"]);

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
        ${sel("pre_pesado", prePesadoCol, "0")}
      FROM $t
      WHERE $idFabCol = ?
      ${statusCol != null ? "AND $statusCol = 1" : ""}
      ORDER BY ${ordemCol != null ? "COALESCE($ordemCol,0)" : "1"} ASC
    """;

    final db = await _db;
    final rows = await db.rawQuery(sql, [fabId]);

    return rows
        .map((m) =>
            FabIngrediente.fromMap(_lowerKeys(Map<String, Object?>.from(m))))
        .toList();
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
        ${sel("pre_pesado", prePesadoCol, "0")}
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

    final syncCol = await _pickCol(t, ["SYNCAWS", "SYNC_AWS", "SYNC"]);
    if (syncCol != null) {
      final db = await _db;
      final r = await db.rawQuery(
        "SELECT COALESCE($syncCol,0) AS v FROM $t WHERE ID = ? LIMIT 1",
        [idFab],
      );
      if (r.isNotEmpty) {
        final v = (r.first["v"] as num?)?.toInt() ?? 0;
        if (v != 0) return false;
      }
    }

    final realHeaderCol = await _pickCol(
        t, ["QTD_REALIZADA", "REALIZADOKG", "REALIZADO_KG", "REALIZADO"]);
    if (realHeaderCol != null) {
      final db = await _db;
      final r = await db.rawQuery(
        "SELECT COALESCE($realHeaderCol,0) AS v FROM $t WHERE ID = ? LIMIT 1",
        [idFab],
      );
      final v =
          (r.isNotEmpty ? (r.first["v"] as num?)?.toDouble() : 0.0) ?? 0.0;
      if (v > 0) return false;
    }

    const d = "DETALHES_FABRICA_RACAO";
    if (await _hasTable(d)) {
      final idFabCol = await _pickCol(d,
              ["ID_FABRICACAO", "IDFABRICACAO", "ID_CABECALHO", "ID_HEADER"]) ??
          "ID_FABRICACAO";
      final realDetCol =
          await _pickCol(d, ["QTD_REALIZADA", "REALIZADOKG", "REALIZADO_KG"]);
      if (realDetCol != null) {
        final db = await _db;
        final r = await db.rawQuery(
          "SELECT COALESCE(SUM(COALESCE($realDetCol,0)),0) AS s FROM $d WHERE $idFabCol = ?",
          [idFab],
        );
        final s =
            (r.isNotEmpty ? (r.first["s"] as num?)?.toDouble() : 0.0) ?? 0.0;
        if (s > 0) return false;
      }
    }

    return true;
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

  // =========================================================
  // ✅ MÉTODOS PARA O CONTROLLER (Delphi compat)
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

  /// Atualiza QTD_REALIZADA + horas (se existirem colunas)
  Future<void> updateIngredienteFabricacao({
    required String idDet,
    required double qtdRealizada,
    required String horaInicio,
    required String horaFim,
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

    final values = <String, Object?>{
      realCol: qtdRealizada,
    };
    if (horaIniCol != null) values[horaIniCol] = horaInicio;
    if (horaFimCol != null) values[horaFimCol] = horaFim;

    final db = await _db;
    await db.update(
      t,
      values,
      where: "ID = ?",
      whereArgs: [idDet],
    );
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
// ✅ FINALIZA FABRICAÇÃO (igual Delphi FinalizaFabricacao)
// - garante MS_REALIZADA calculada (reaproveita seu updateFabricacaoParcial)
// =========================================================
  Future<void> finalizaFabricacao({
    required String idFabricacao,
    required double qtdRealizada,
    required String horaFim,
    required int finalizada,
  }) async {
    const h = "CADASTRO_FABRICA_RACAO";
    if (!await _hasTable(h)) return;

    // garante MS_REALIZADA e QTD_REALIZADA consistentes
    await updateFabricacaoParcial(idFabricacao);

    final realCol = await _pickCol(
            h, ["QTD_REALIZADA", "REALIZADOKG", "REALIZADO_KG", "REALIZADO"]) ??
        "QTD_REALIZADA";
    final fimCol = await _pickCol(h, ["HORA_FIM", "HORAFIM", "HORA_FIM_FAB"]);
    final finCol = await _pickCol(h, ["FINALIZADA"]);

    final values = <String, Object?>{
      realCol: qtdRealizada,
    };

    if (fimCol != null) values[fimCol] = horaFim;
    if (finCol != null) values[finCol] = finalizada;

    final db = await _db;
    await db.update(
      h,
      values,
      where: "ID = ?",
      whereArgs: [idFabricacao],
    );
  }

// =========================================================
// ✅ INSERE CARREGAMENTO (se existir tabela/colunas)
// =========================================================
  Future<void> insereCarregamentoSePossivel({
    required String idFabricacao,
    required String idDieta,
    required double pesoFabricado,
    required double pesoCarregado,
    required String idVagao,
  }) async {
    const t = "CARREGAMENTO";
    if (!await _hasTable(t)) return;

    final idCol = await _pickCol(t, ["ID"]) ?? "ID";
    final idFabCol =
        await _pickCol(t, ["ID_FABRICACAO", "IDFABRICACAO"]) ?? "ID_FABRICACAO";
    final idDietaCol = await _pickCol(t, ["ID_DIETA", "IDDIETA"]) ?? "ID_DIETA";
    final pesoFabCol = await _pickCol(t, ["PESO_FABRICADO", "PESOFABRICADO"]) ??
        "PESO_FABRICADO";
    final pesoCarCol = await _pickCol(t, ["PESO_CARREGADO", "PESOCARREGADO"]) ??
        "PESO_CARREGADO";
    final idVagCol = await _pickCol(t, ["ID_VAGAO", "IDVAGAO"]) ?? "ID_VAGAO";

    // uid simples (se você já tiver um helper de GUID, pode trocar)
    final uid = DateTime.now().microsecondsSinceEpoch.toString();

    final db = await _db;
    await db.insert(t, {
      idCol: uid,
      idFabCol: idFabricacao,
      idDietaCol: idDieta,
      pesoFabCol: pesoFabricado,
      pesoCarCol: pesoCarregado,
      idVagCol: idVagao,
    });
  }

  /// Atualiza QTD_REALIZADA (header) e MS_REALIZADA (se existir)
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

    final msRealizada =
        (totalRealizado > 0) ? (totalMS / totalRealizado) * 100.0 : 0.0;

    final headRealCol = await _pickCol(
            h, ["QTD_REALIZADA", "REALIZADOKG", "REALIZADO_KG", "REALIZADO"]) ??
        "QTD_REALIZADA";
    final headMsCol =
        await _pickCol(h, ["MS_REALIZADA", "MSREALIZADA", "MS_REAL"]);

    final values = <String, Object?>{headRealCol: totalRealizado};
    if (headMsCol != null) values[headMsCol] = msRealizada;

    await db.update(
      h,
      values,
      where: "ID = ?",
      whereArgs: [idFabricacao],
    );
  }
}
