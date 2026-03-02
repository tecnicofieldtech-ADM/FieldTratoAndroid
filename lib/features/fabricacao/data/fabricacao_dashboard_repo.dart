import "package:sqflite/sqflite.dart";
import "../../../db/app_db.dart";

class FabricacaoDashboardRepo {
  Future<Database> get _db async => AppDb.instance.db;

  static const head = "CADASTRO_FABRICA_RACAO";
  static const det = "DETALHES_FABRICA_RACAO";

  /// dataIso: "YYYY-MM-DD"
  Future<Map<String, num>> totalsDoDia(String dataIso, {String? idDieta}) async {
    final db = await _db;
    final args = <Object?>[dataIso];
    final filtroDieta = (idDieta ?? "").trim().isEmpty
        ? ""
        : " AND TRIM(CAST(ID_DIETA AS TEXT)) = TRIM(CAST(? AS TEXT)) ";
    if (filtroDieta.isNotEmpty) args.add(idDieta);
    final rows = await db.rawQuery("""
      SELECT
        COALESCE(SUM(COALESCE(QTD_PREVISTA,0)),0) AS previsto,
        COALESCE(SUM(COALESCE(QTD_REALIZADA,0)),0) AS realizado,
        COALESCE(COUNT(*),0) AS qtd
      FROM $head
      WHERE DATE(DATA_FABRICACAO) = DATE(?)
        AND COALESCE(STATUS,1) = 1
        $filtroDieta
    """, args);

    final r = rows.first;
    return {
      "previsto": (r["previsto"] as num?) ?? 0,
      "realizado": (r["realizado"] as num?) ?? 0,
      "qtd": (r["qtd"] as num?) ?? 0,
    };
  }

  Future<int> pendentesSyncDoDia(String dataIso, {String? idDieta}) async {
    final db = await _db;
    final args = <Object?>[dataIso];
    final filtroDieta = (idDieta ?? "").trim().isEmpty
        ? ""
        : " AND TRIM(CAST(ID_DIETA AS TEXT)) = TRIM(CAST(? AS TEXT)) ";
    if (filtroDieta.isNotEmpty) args.add(idDieta);
    final rows = await db.rawQuery("""
      SELECT COALESCE(COUNT(*),0) AS c
      FROM $head
      WHERE DATE(DATA_FABRICACAO) = DATE(?)
        AND COALESCE(STATUS,1) = 1
        AND COALESCE(FLAG_SYNC,0) = 0
        $filtroDieta
    """, args);
    return ((rows.first["c"] as num?) ?? 0).toInt();
  }

  /// Irregulares: finalizada e tem ingrediente com previsto>0 e realizado=0
  Future<int> irregularesCount(String dataIso, {String? idDieta}) async {
    final db = await _db;
    final args = <Object?>[dataIso];
    final filtroDieta = (idDieta ?? "").trim().isEmpty
        ? ""
        : " AND TRIM(CAST(h.ID_DIETA AS TEXT)) = TRIM(CAST(? AS TEXT)) ";
    if (filtroDieta.isNotEmpty) args.add(idDieta);
    final rows = await db.rawQuery("""
      SELECT COALESCE(COUNT(*),0) AS c
      FROM $head h
      WHERE DATE(h.DATA_FABRICACAO) = DATE(?)
        AND COALESCE(h.STATUS,1) = 1
        AND COALESCE(h.FINALIZADA,0) = 1
        $filtroDieta
        AND EXISTS (
          SELECT 1
          FROM $det d
          WHERE d.ID_FABRICACAO = h.ID
            AND COALESCE(d.QTD_PREVISTA,0) > 0
            AND COALESCE(d.QTD_REALIZADA,0) = 0
        )
    """, args);
    return ((rows.first["c"] as num?) ?? 0).toInt();
  }

  Future<List<Map<String, Object?>>> porRacao(String dataIso, {String? idDieta}) async {
    final db = await _db;
    final args = <Object?>[dataIso];
    final filtroDieta = (idDieta ?? "").trim().isEmpty
        ? ""
        : " AND TRIM(CAST(h.ID_DIETA AS TEXT)) = TRIM(CAST(? AS TEXT)) ";
    if (filtroDieta.isNotEmpty) args.add(idDieta);
    return db.rawQuery("""
      SELECT
        h.ID_DIETA AS idDieta,
        COALESCE(d.NOME, h.ID_DIETA) AS dieta,
        COALESCE(SUM(COALESCE(h.QTD_PREVISTA,0)),0) AS previsto,
        COALESCE(SUM(COALESCE(h.QTD_REALIZADA,0)),0) AS realizado,
        COALESCE(COUNT(*),0) AS qtd
      FROM $head h
      LEFT JOIN DIETA d ON d.ID = h.ID_DIETA
      WHERE DATE(h.DATA_FABRICACAO) = DATE(?)
        AND COALESCE(h.STATUS,1) = 1
        $filtroDieta
      GROUP BY h.ID_DIETA, COALESCE(d.NOME, h.ID_DIETA)
      ORDER BY realizado DESC
    """, args);
  }

  Future<List<Map<String, Object?>>> porTrato(String dataIso, {String? idDieta}) async {
    final db = await _db;
    final args = <Object?>[dataIso];
    final filtroDieta = (idDieta ?? "").trim().isEmpty
        ? ""
        : " AND TRIM(CAST(h.ID_DIETA AS TEXT)) = TRIM(CAST(? AS TEXT)) ";
    if (filtroDieta.isNotEmpty) args.add(idDieta);
    return db.rawQuery("""
      SELECT
        COALESCE(h.TRATO,0) AS trato,
        COALESCE(SUM(COALESCE(h.QTD_PREVISTA,0)),0) AS previsto,
        COALESCE(SUM(COALESCE(h.QTD_REALIZADA,0)),0) AS realizado,
        COALESCE(COUNT(*),0) AS qtd
      FROM $head h
      WHERE DATE(h.DATA_FABRICACAO) = DATE(?)
        AND COALESCE(h.STATUS,1) = 1
        $filtroDieta
      GROUP BY COALESCE(h.TRATO,0)
      ORDER BY trato ASC
    """, args);
  }

  Future<List<Map<String, Object?>>> topInsumosDif(
    String dataIso, {
    int limit = 10,
    String? idDieta,
  }) async {
    final db = await _db;
    final args = <Object?>[dataIso];
    final filtroDieta = (idDieta ?? "").trim().isEmpty
        ? ""
        : " AND TRIM(CAST(h.ID_DIETA AS TEXT)) = TRIM(CAST(? AS TEXT)) ";
    if (filtroDieta.isNotEmpty) args.add(idDieta);
    return db.rawQuery("""
      SELECT
        COALESCE(d.INSUMO_NOME, d.ID_INSUMO) AS insumo,
        COALESCE(SUM(COALESCE(d.QTD_PREVISTA,0)),0) AS previsto,
        COALESCE(SUM(COALESCE(d.QTD_REALIZADA,0)),0) AS realizado,
        (COALESCE(SUM(COALESCE(d.QTD_REALIZADA,0)),0) - COALESCE(SUM(COALESCE(d.QTD_PREVISTA,0)),0)) AS dif
      FROM $det d
      JOIN $head h ON h.ID = d.ID_FABRICACAO
      WHERE DATE(h.DATA_FABRICACAO) = DATE(?)
        AND COALESCE(h.STATUS,1) = 1
        $filtroDieta
      GROUP BY COALESCE(d.INSUMO_NOME, d.ID_INSUMO)
      ORDER BY ABS(dif) DESC
      LIMIT $limit
    """, args);
  }

  Future<List<Map<String, Object?>>> irregularesList(
    String dataIso, {
    int limit = 50,
    String? idDieta,
  }) async {
    final db = await _db;
    final args = <Object?>[dataIso];
    final filtroDieta = (idDieta ?? "").trim().isEmpty
        ? ""
        : " AND TRIM(CAST(h.ID_DIETA AS TEXT)) = TRIM(CAST(? AS TEXT)) ";
    if (filtroDieta.isNotEmpty) args.add(idDieta);
    return db.rawQuery("""
      SELECT
        h.ID as id,
        COALESCE(d.NOME, h.ID_DIETA) AS dieta,
        COALESCE(h.TRATO,0) AS trato,
        COALESCE(h.QTD_PREVISTA,0) AS previsto,
        COALESCE(h.QTD_REALIZADA,0) AS realizado,
        COALESCE(h.FLAG_SYNC,0) AS flag_sync
      FROM $head h
      LEFT JOIN DIETA d ON d.ID = h.ID_DIETA
      WHERE DATE(h.DATA_FABRICACAO) = DATE(?)
        AND COALESCE(h.STATUS,1) = 1
        AND COALESCE(h.FINALIZADA,0) = 1
        $filtroDieta
        AND EXISTS (
          SELECT 1
          FROM $det x
          WHERE x.ID_FABRICACAO = h.ID
            AND COALESCE(x.QTD_PREVISTA,0) > 0
            AND COALESCE(x.QTD_REALIZADA,0) = 0
        )
      ORDER BY dieta
      LIMIT $limit
    """, args);
  }

  Future<List<Map<String, Object?>>> pendentesSyncList(
    String dataIso, {
    int limit = 50,
    String? idDieta,
  }) async {
    final db = await _db;
    final args = <Object?>[dataIso];
    final filtroDieta = (idDieta ?? "").trim().isEmpty
        ? ""
        : " AND TRIM(CAST(h.ID_DIETA AS TEXT)) = TRIM(CAST(? AS TEXT)) ";
    if (filtroDieta.isNotEmpty) args.add(idDieta);
    return db.rawQuery("""
      SELECT
        h.ID as id,
        COALESCE(d.NOME, h.ID_DIETA) AS dieta,
        COALESCE(h.TRATO,0) AS trato,
        COALESCE(h.QTD_PREVISTA,0) AS previsto,
        COALESCE(h.QTD_REALIZADA,0) AS realizado,
        COALESCE(h.FINALIZADA,0) AS finalizada
      FROM $head h
      LEFT JOIN DIETA d ON d.ID = h.ID_DIETA
      WHERE DATE(h.DATA_FABRICACAO) = DATE(?)
        AND COALESCE(h.STATUS,1) = 1
        AND COALESCE(h.FLAG_SYNC,0) = 0
        $filtroDieta
      ORDER BY h.FINALIZADA ASC, dieta ASC
      LIMIT $limit
    """, args);
  }

  // ✅ Ranking: melhores acertos do dia (por fabricação)
  Future<List<Map<String, Object?>>> topAcertosDoDia(
    String dataIso, {
    int limit = 10,
    String? idDieta,
  }) async {
    final db = await _db;
    final args = <Object?>[dataIso];
    final filtroDieta = (idDieta ?? "").trim().isEmpty
        ? ""
        : " AND TRIM(CAST(f.ID_DIETA AS TEXT)) = TRIM(CAST(? AS TEXT)) ";
    if (filtroDieta.isNotEmpty) args.add(idDieta);
    args.add(limit);

    // Observação:
    // - calcula "acerto_pct" = 100 - |prev-real|/prev*100 (clamp 0..100)
    // - se previsto=0 => acerto 0 (evita divisão por zero)
    //
    // Você disse que na lista mostra o nome correto via JOIN em DIETA,
    // então aqui também fazemos JOIN pra pegar di.NOME.

    final sql = """
    SELECT
      f.ID AS id,
      COALESCE(f.TRATO,0) AS trato,
      COALESCE(f.QTD_PREVISTA,0) AS previsto,
      COALESCE(f.QTD_REALIZADA,0) AS realizado,
      COALESCE(di.NOME,'') AS dieta,
      CASE
        WHEN COALESCE(f.QTD_PREVISTA,0) <= 0 THEN 0
        ELSE
          MAX(
            0,
            MIN(
              100,
              100.0 - (ABS(COALESCE(f.QTD_PREVISTA,0) - COALESCE(f.QTD_REALIZADA,0)) * 100.0 / COALESCE(f.QTD_PREVISTA,0))
            )
          )
      END AS acerto_pct
    FROM CADASTRO_FABRICA_RACAO f
    LEFT JOIN DIETA di ON di.ID = f.ID_DIETA
    WHERE date(f.DATA_FABRICACAO) = date(?)
      AND COALESCE(f.STATUS,1) = 1
      $filtroDieta
    ORDER BY acerto_pct DESC, ABS(COALESCE(f.QTD_PREVISTA,0) - COALESCE(f.QTD_REALIZADA,0)) ASC
    LIMIT ?
    """;

    return await db.rawQuery(sql, args);
  }

  Future<List<Map<String, Object?>>> racoesDoDia(String dataIso) async {
    final db = await _db;
    return db.rawQuery("""
      SELECT
        TRIM(COALESCE(CAST(h.ID_DIETA AS TEXT), '')) AS idDieta,
        TRIM(COALESCE(d.NOME, CAST(h.ID_DIETA AS TEXT), '')) AS dieta
      FROM $head h
      LEFT JOIN DIETA d ON TRIM(CAST(d.ID AS TEXT)) = TRIM(CAST(h.ID_DIETA AS TEXT))
      WHERE DATE(h.DATA_FABRICACAO) = DATE(?)
        AND COALESCE(h.STATUS,1) = 1
      GROUP BY TRIM(COALESCE(CAST(h.ID_DIETA AS TEXT), '')), TRIM(COALESCE(d.NOME, CAST(h.ID_DIETA AS TEXT), ''))
      ORDER BY dieta ASC
    """, [dataIso]);
  }
}


