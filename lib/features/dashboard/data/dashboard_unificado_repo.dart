import "package:sqflite/sqflite.dart";

import "../../../db/app_db.dart";

class DashboardUnificadoRepo {
  Future<Database> get _db async => AppDb.instance.db;

  Future<Map<String, num>> fabricacaoTotaisDoDia(
    String dataIso, {
    int? trato,
    String? idDieta,
  }) async {
    final db = await _db;
    final args = <Object?>[dataIso];
    final filtroTrato = trato == null ? "" : " AND COALESCE(TRATO,0) = ? ";
    if (filtroTrato.isNotEmpty) args.add(trato);
    final filtroDieta = (idDieta ?? "").trim().isEmpty
        ? ""
        : " AND TRIM(CAST(ID_DIETA AS TEXT)) = TRIM(CAST(? AS TEXT)) ";
    if (filtroDieta.isNotEmpty) args.add(idDieta);
    final rows = await db.rawQuery("""
      SELECT
        COALESCE(SUM(COALESCE(QTD_PREVISTA,0)),0) AS previsto,
        COALESCE(SUM(COALESCE(QTD_REALIZADA,0)),0) AS realizado,
        COALESCE(COUNT(*),0) AS qtd,
        COALESCE(AVG(
          CASE
            WHEN TRIM(COALESCE(HORA_INICIO,'')) <> ''
             AND TRIM(COALESCE(HORA_FIM,'')) <> ''
             AND (
               (julianday('2000-01-01 ' || substr(HORA_FIM,1,8)) -
                julianday('2000-01-01 ' || substr(HORA_INICIO,1,8))) * 86400
             ) >= 0
            THEN (
              (julianday('2000-01-01 ' || substr(HORA_FIM,1,8)) -
               julianday('2000-01-01 ' || substr(HORA_INICIO,1,8))) * 86400
            )
            ELSE NULL
          END
        ),0) AS tempo_medio_seg
      FROM CADASTRO_FABRICA_RACAO
      WHERE DATE(DATA_FABRICACAO) = DATE(?)
        AND COALESCE(STATUS,1) = 1
        $filtroTrato
        $filtroDieta
    """, args);

    final r = rows.first;
    return {
      "previsto": (r["previsto"] as num?) ?? 0,
      "realizado": (r["realizado"] as num?) ?? 0,
      "qtd": (r["qtd"] as num?) ?? 0,
      "tempo_medio_seg": (r["tempo_medio_seg"] as num?) ?? 0,
    };
  }

  Future<Map<String, num>> fornecimentoTotaisDoDia(
    String dataIso, {
    int? trato,
    String? idDieta,
  }) async {
    final db = await _db;
    final args = <Object?>[dataIso];
    final filtroTrato = trato == null ? "" : " AND COALESCE(TRATO,0) = ? ";
    if (filtroTrato.isNotEmpty) args.add(trato);
    final filtroDieta = (idDieta ?? "").trim().isEmpty
        ? ""
        : " AND TRIM(CAST(ID_DIETA AS TEXT)) = TRIM(CAST(? AS TEXT)) ";
    if (filtroDieta.isNotEmpty) args.add(idDieta);
    final rows = await db.rawQuery("""
      SELECT
        COALESCE(SUM(COALESCE(PREVISTO,0)),0) AS previsto,
        COALESCE(SUM(COALESCE(REALIZADO,0)),0) AS realizado,
        COALESCE(COUNT(*),0) AS qtd,
        COALESCE(COUNT(DISTINCT ID_BAIA),0) AS currais
      FROM CADASTRO_FORNECIMENTO
      WHERE DATE(DATA) = DATE(?)
        $filtroTrato
        $filtroDieta
    """, args);

    final r = rows.first;
    return {
      "previsto": (r["previsto"] as num?) ?? 0,
      "realizado": (r["realizado"] as num?) ?? 0,
      "qtd": (r["qtd"] as num?) ?? 0,
      "currais": (r["currais"] as num?) ?? 0,
    };
  }

  Future<List<Map<String, Object?>>> fabricacaoVsFornecidoDoDia(
    String dataIso, {
    int? trato,
    String? idDieta,
  }
  ) async {
    final db = await _db;
    final args = <Object?>[dataIso];
    final filtroCfTrato = trato == null ? "" : " AND COALESCE(TRATO,0) = ? ";
    if (filtroCfTrato.isNotEmpty) args.add(trato);
    final filtroCfDieta = (idDieta ?? "").trim().isEmpty
        ? ""
        : " AND TRIM(CAST(ID_DIETA AS TEXT)) = TRIM(CAST(? AS TEXT)) ";
    if (filtroCfDieta.isNotEmpty) args.add(idDieta);
    args.add(dataIso);
    final filtroFabTrato = trato == null ? "" : " AND COALESCE(h.TRATO,0) = ? ";
    if (filtroFabTrato.isNotEmpty) args.add(trato);
    final filtroFabDieta = (idDieta ?? "").trim().isEmpty
        ? ""
        : " AND TRIM(CAST(h.ID_DIETA AS TEXT)) = TRIM(CAST(? AS TEXT)) ";
    if (filtroFabDieta.isNotEmpty) args.add(idDieta);

    return db.rawQuery("""
      SELECT
        h.ID AS id_fabricacao,
        TRIM(CAST(h.ID_DIETA AS TEXT)) AS id_dieta,
        COALESCE(di.NOME, h.ID_DIETA, '(Sem dieta)') AS dieta,
        COALESCE(h.TRATO,0) AS trato,
        COALESCE(h.QTD_REALIZADA,0) AS fabricado_kg,
        COALESCE(cf.total_fornecido,0) AS fornecido_kg,
        (COALESCE(h.QTD_REALIZADA,0) - COALESCE(cf.total_fornecido,0)) AS diferenca_kg
      FROM CADASTRO_FABRICA_RACAO h
      LEFT JOIN DIETA di
        ON TRIM(CAST(di.ID AS TEXT)) = TRIM(CAST(h.ID_DIETA AS TEXT))
      LEFT JOIN (
        SELECT
          ID_FABRICACAO,
          SUM(COALESCE(REALIZADO,0)) AS total_fornecido
        FROM CADASTRO_FORNECIMENTO
        WHERE DATE(DATA) = DATE(?)
          $filtroCfTrato
          $filtroCfDieta
        GROUP BY ID_FABRICACAO
      ) cf
        ON TRIM(CAST(cf.ID_FABRICACAO AS TEXT)) = TRIM(CAST(h.ID AS TEXT))
      WHERE DATE(h.DATA_FABRICACAO) = DATE(?)
        AND COALESCE(h.STATUS,1) = 1
        $filtroFabTrato
        $filtroFabDieta
      ORDER BY ABS(diferenca_kg) DESC, COALESCE(h.TRATO,0) ASC
    """, args);
  }

  Future<List<Map<String, Object?>>> curraisDaFabricacao(
    String idFabricacao, {
    String? dataIso,
    int? trato,
    String? idDieta,
  }) async {
    final db = await _db;
    final args = <Object?>[idFabricacao];
    final whereData = (dataIso ?? "").trim().isEmpty ? "" : "AND DATE(cf.DATA) = DATE(?)";
    if (whereData.isNotEmpty) args.add(dataIso);
    final whereTrato = trato == null ? "" : "AND COALESCE(cf.TRATO,0) = ?";
    if (whereTrato.isNotEmpty) args.add(trato);
    final whereDieta = (idDieta ?? "").trim().isEmpty
        ? ""
        : "AND TRIM(CAST(cf.ID_DIETA AS TEXT)) = TRIM(CAST(? AS TEXT))";
    if (whereDieta.isNotEmpty) args.add(idDieta);

    return db.rawQuery("""
      SELECT
        COALESCE(cf.ID_BAIA,'') AS id_baia,
        COALESCE(db.NOME_LOCAL, cf.ID_BAIA, '(Sem curral)') AS curral,
        COALESCE(MAX(cf.TRATO),0) AS trato,
        COALESCE(SUM(COALESCE(cf.REALIZADO,0)),0) AS fornecido_kg
      FROM CADASTRO_FORNECIMENTO cf
      LEFT JOIN DETALHES_BAIAS db
        ON TRIM(CAST(db.ID AS TEXT)) = TRIM(CAST(cf.ID_BAIA AS TEXT))
      WHERE TRIM(COALESCE(cf.ID_FABRICACAO,'')) = TRIM(?)
        $whereData
        $whereTrato
        $whereDieta
      GROUP BY COALESCE(cf.ID_BAIA,''), COALESCE(db.NOME_LOCAL, cf.ID_BAIA, '(Sem curral)')
      ORDER BY fornecido_kg DESC, curral ASC
    """, args);
  }

  Future<List<Map<String, Object?>>> fornecimentoDesviosPorCurralTrato(
    String dataIso, {
    int limit = 12,
    int? trato,
    String? idDieta,
  }) async {
    final db = await _db;
    final args = <Object?>[dataIso];
    final filtroTrato = trato == null ? "" : " AND COALESCE(p.TRATO,0) = ? ";
    if (filtroTrato.isNotEmpty) args.add(trato);
    final filtroDieta = (idDieta ?? "").trim().isEmpty
        ? ""
        : " AND TRIM(CAST(p.ID_RACAO AS TEXT)) = TRIM(CAST(? AS TEXT)) ";
    if (filtroDieta.isNotEmpty) args.add(idDieta);
    args.add(limit);
    return db.rawQuery("""
      SELECT
        COALESCE(db.NOME_LOCAL, p.ID_BAIA, '(Sem curral)') AS curral,
        COALESCE(p.TRATO,0) AS trato,
        COALESCE(SUM(COALESCE(p.PREVISTO_KG,0)),0) AS previsto,
        COALESCE(SUM(COALESCE(p.REALIZADO_KG,0)),0) AS realizado,
        (COALESCE(SUM(COALESCE(p.REALIZADO_KG,0)),0) - COALESCE(SUM(COALESCE(p.PREVISTO_KG,0)),0)) AS dif
      FROM PREVISAO p
      LEFT JOIN DETALHES_BAIAS db
        ON TRIM(CAST(db.ID AS TEXT)) = TRIM(CAST(p.ID_BAIA AS TEXT))
      WHERE DATE(p.DATA) = DATE(?)
        $filtroTrato
        $filtroDieta
      GROUP BY COALESCE(db.NOME_LOCAL, p.ID_BAIA, '(Sem curral)'), COALESCE(p.TRATO,0)
      ORDER BY ABS(dif) DESC, curral ASC
      LIMIT ?
    """, args);
  }

  Future<List<Map<String, Object?>>> fabricacaoDesvioPorRacao(
    String dataIso, {
    int limit = 12,
    int? trato,
    String? idDieta,
  }) async {
    final db = await _db;
    final args = <Object?>[dataIso];
    final filtroTrato = trato == null ? "" : " AND COALESCE(h.TRATO,0) = ? ";
    if (filtroTrato.isNotEmpty) args.add(trato);
    final filtroDieta = (idDieta ?? "").trim().isEmpty
        ? ""
        : " AND TRIM(CAST(h.ID_DIETA AS TEXT)) = TRIM(CAST(? AS TEXT)) ";
    if (filtroDieta.isNotEmpty) args.add(idDieta);
    args.add(limit);
    return db.rawQuery("""
      SELECT
        COALESCE(di.NOME, h.ID_DIETA, '(Sem dieta)') AS racao,
        COALESCE(SUM(COALESCE(h.QTD_PREVISTA,0)),0) AS previsto,
        COALESCE(SUM(COALESCE(h.QTD_REALIZADA,0)),0) AS realizado,
        (COALESCE(SUM(COALESCE(h.QTD_REALIZADA,0)),0) - COALESCE(SUM(COALESCE(h.QTD_PREVISTA,0)),0)) AS dif
      FROM CADASTRO_FABRICA_RACAO h
      LEFT JOIN DIETA di
        ON TRIM(CAST(di.ID AS TEXT)) = TRIM(CAST(h.ID_DIETA AS TEXT))
      WHERE DATE(h.DATA_FABRICACAO) = DATE(?)
        AND COALESCE(h.STATUS,1) = 1
        $filtroTrato
        $filtroDieta
      GROUP BY COALESCE(di.NOME, h.ID_DIETA, '(Sem dieta)')
      ORDER BY ABS(dif) DESC, racao ASC
      LIMIT ?
    """, args);
  }

  Future<List<Map<String, Object?>>> fabricacaoDesvioPorInsumo(
    String dataIso, {
    int limit = 12,
    int? trato,
    String? idDieta,
  }) async {
    final db = await _db;
    final args = <Object?>[dataIso];
    final filtroTrato = trato == null ? "" : " AND COALESCE(h.TRATO,0) = ? ";
    if (filtroTrato.isNotEmpty) args.add(trato);
    final filtroDieta = (idDieta ?? "").trim().isEmpty
        ? ""
        : " AND TRIM(CAST(h.ID_DIETA AS TEXT)) = TRIM(CAST(? AS TEXT)) ";
    if (filtroDieta.isNotEmpty) args.add(idDieta);
    args.add(limit);
    return db.rawQuery("""
      SELECT
        COALESCE(d.INSUMO_NOME, d.ID_INSUMO, '(Sem insumo)') AS insumo,
        COALESCE(SUM(COALESCE(d.QTD_PREVISTA,0)),0) AS previsto,
        COALESCE(SUM(COALESCE(d.QTD_REALIZADA,0)),0) AS realizado,
        (COALESCE(SUM(COALESCE(d.QTD_REALIZADA,0)),0) - COALESCE(SUM(COALESCE(d.QTD_PREVISTA,0)),0)) AS dif
      FROM DETALHES_FABRICA_RACAO d
      JOIN CADASTRO_FABRICA_RACAO h
        ON TRIM(CAST(h.ID AS TEXT)) = TRIM(CAST(d.ID_FABRICACAO AS TEXT))
      WHERE DATE(h.DATA_FABRICACAO) = DATE(?)
        AND COALESCE(h.STATUS,1) = 1
        $filtroTrato
        $filtroDieta
      GROUP BY COALESCE(d.INSUMO_NOME, d.ID_INSUMO, '(Sem insumo)')
      ORDER BY ABS(dif) DESC, insumo ASC
      LIMIT ?
    """, args);
  }

  Future<Map<String, List<Map<String, Object?>>>> filtrosDoDia(String dataIso) async {
    final db = await _db;
    final tratos = await db.rawQuery("""
      SELECT DISTINCT COALESCE(TRATO,0) AS trato
      FROM CADASTRO_FABRICA_RACAO
      WHERE DATE(DATA_FABRICACAO) = DATE(?)
        AND COALESCE(STATUS,1) = 1
      ORDER BY trato ASC
    """, [dataIso]);
    final dietas = await db.rawQuery("""
      SELECT
        TRIM(CAST(h.ID_DIETA AS TEXT)) AS id_dieta,
        COALESCE(di.NOME, h.ID_DIETA, '(Sem dieta)') AS dieta
      FROM CADASTRO_FABRICA_RACAO h
      LEFT JOIN DIETA di
        ON TRIM(CAST(di.ID AS TEXT)) = TRIM(CAST(h.ID_DIETA AS TEXT))
      WHERE DATE(h.DATA_FABRICACAO) = DATE(?)
        AND COALESCE(h.STATUS,1) = 1
      GROUP BY TRIM(CAST(h.ID_DIETA AS TEXT)), COALESCE(di.NOME, h.ID_DIETA, '(Sem dieta)')
      ORDER BY dieta ASC
    """, [dataIso]);
    return {"tratos": tratos, "dietas": dietas};
  }
}
