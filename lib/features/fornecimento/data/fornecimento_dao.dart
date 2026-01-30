// lib/features/fornecimento/data/fornecimento_dao.dart
import "dart:math";
import "package:sqflite/sqflite.dart";

import "../../../db/app_db.dart";
import "fornecimento_tables.dart";
import "../domain/fornecimento_models.dart";

class FornecimentoDao {
  Future<Database> get _db async => AppDb.instance.db;

  // (warning: unused_field — ok, depois a gente remove se não usar)
  
  // ✅ executa SQL "cru"
  Future<List<Map<String, Object?>>> rawQuery(String sql, List<Object?> args) async {
    final db = await _db;
    final rows = await db.rawQuery(sql, args);
    return rows.cast<Map<String, Object?>>();
  }

  // -------------------------
  // helpers
  // -------------------------
  String _pad2(int n) => n.toString().padLeft(2, "0");

  String toSqlDate(DateTime d) =>
      "${d.year.toString().padLeft(4, '0')}-${_pad2(d.month)}-${_pad2(d.day)}";

  String nowTime() {
    final d = DateTime.now();
    return "${_pad2(d.hour)}:${_pad2(d.minute)}:${_pad2(d.second)}";
  }

  // UUID simples (40 chars) sem depender de package
  String newId40() {
    final r = Random.secure();
    final ts = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    final a = List.generate(16, (_) => r.nextInt(256));
    final b = a.map((e) => e.toRadixString(16).padLeft(2, "0")).join();
    final s = (ts + b);
    return s.length <= 40 ? s.padRight(40, "0") : s.substring(0, 40);
  }

  double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    final s = v.toString().trim().replaceAll(",", ".");
    return double.tryParse(s) ?? 0.0;
  }

  String _toStr(dynamic v) => (v ?? "").toString();

  // =========================================================
  // ✅ LOGIN / USUÁRIO (ULTIMO_LOGIN)
  // =========================================================
  Future<String?> getUsuarioAtualId() async {
    final db = await _db;
    try {
      final rows = await db.rawQuery("SELECT ID FROM ${FornTables.ultimoLogin} LIMIT 1");
      if (rows.isEmpty) return null;
      final id = _toStr(rows.first["ID"]).trim();
      return id.isEmpty ? null : id;
    } catch (_) {
      return null;
    }
  }

  // =========================================================
  // ✅ FABRICAÇÃO EM ABERTO (CADASTRO_FABRICA_RACAO)
  // =========================================================
  Future<String?> getFabricacaoEmAbertoId({DateTime? data}) async {
    final db = await _db;
    final d = toSqlDate(data ?? DateTime.now());

    // em aberto hoje
    final rowsHoje = await db.rawQuery("""
      SELECT ID
      FROM ${FornTables.cadastroFabrica}
      WHERE DATA_FABRICACAO = ?
        AND COALESCE(FINALIZADA, 0) = 0
        AND COALESCE(STATUS, 1) = 1
      ORDER BY ROWID DESC
      LIMIT 1
    """, [d]);

    if (rowsHoje.isNotEmpty) {
        final id = _toStr(rowsHoje.first["ID"]).trim();
      if (id.isNotEmpty) return id;
    }

    // última em aberto
    final rows = await db.rawQuery("""
      SELECT ID
      FROM ${FornTables.cadastroFabrica}
      WHERE COALESCE(FINALIZADA, 0) = 0
        AND COALESCE(STATUS, 1) = 1
      ORDER BY ROWID DESC
      LIMIT 1
    """);

    if (rows.isEmpty) return null;
    final id = _toStr(rows.first["ID"]).trim();
    return id.isEmpty ? null : id;
  }

  // =========================================================
  // LISTA CURRAIS (PREVISAO + DETALHES_BAIAS)
  // ⚠️ Mantido como estava (runtime) — aqui o foco é zerar compile.
  // =========================================================
  Future<List<Map<String, Object?>>> listCurraisPrevistos({
    required String dataYmd,
    required int trato,
    String? idFazenda,
  }) async {
    final db = await _db;

    final where = <String>["P.DATA = ?", "P.TRATO = ?"];
    final args = <Object?>[dataYmd, trato];

    final faz = (idFazenda ?? "").trim();
    if (faz.isNotEmpty) {
      where.add("B.ID_FAZENDA = ?");
      args.add(faz);
    }

    final sql = """
      SELECT
        P.ID_FORNECIMENTO AS id_fornecimento,
        P.DATA            AS data,
        P.TRATO           AS trato,
        P.ID_BAIA         AS id_baia,
        P.PREVISTO_KG     AS previsto,
        P.REALIZADO_KG    AS realizado,
        P.ID_RACAO        AS id_racao,

        B.NOME_LOCAL      AS nome_local,
        B.LINHA           AS linha,
        B.ORDER_TRATO     AS order_trato,
        B.RFID            AS rfid,
        B.ID_LOTE         AS id_lote
      FROM PREVISAO P
      JOIN DETALHES_BAIAS B
        ON B.ID = P.ID_BAIA
      WHERE ${where.join(" AND ")}
      ORDER BY
        B.LINHA ASC,
        COALESCE(B.ORDER_TRATO, 0) ASC,
        B.NOME_LOCAL ASC
    """;

    return db.rawQuery(sql, args);
  }

  // =========================================================
  // RFID -> ID_FORNECIMENTO  (PREVISAO + DETALHES_BAIAS)
  // ⚠️ Mantido como estava (runtime) — aqui o foco é zerar compile.
  // =========================================================
  Future<String?> findIdFornecimentoByRfid({
    required String epc,
    required int trato,
    String? idRacao,
    required String dataYmd,
  }) async {
    final db = await _db;
    final tag = epc.trim();
    if (tag.isEmpty) return null;

    final where = <String>[
      "B.RFID = ?",
      "P.DATA = ?",
      "P.TRATO = ?",
    ];
    final args = <Object?>[tag, dataYmd, trato];

    final racao = (idRacao ?? "").trim();
    if (racao.isNotEmpty) {
      where.add("P.ID_RACAO = ?");
      args.add(racao);
    }

    final rows = await db.rawQuery("""
      SELECT P.ID_FORNECIMENTO AS id_fornecimento
      FROM DETALHES_BAIAS B
      JOIN PREVISAO P
        ON P.ID_BAIA = B.ID
      WHERE ${where.join(" AND ")}
      LIMIT 1
    """, args);

    if (rows.isEmpty) return null;
    final id = _toStr(rows.first["id_fornecimento"]).trim();
    return id.isEmpty ? null : id;
  }

  // =========================================================
  // SNAPSHOT (FORNECIMENTO_CONF + DETALHES_BAIAS) ✅ compile ok
  // =========================================================
  Future<CurralSnapshot?> loadCurralSnapshot({
    required String idFornecimento,
    required String dataYmd,
    required int trato,
  }) async {
    final db = await _db;
    final idF = idFornecimento.trim();
    if (idF.isEmpty) return null;

    final rows = await db.rawQuery("""
      SELECT
        P.${FornTables.pv_idFornecimento} AS id_fornecimento,
        P.${FornTables.pv_idBaia}         AS id_baia,
        P.${FornTables.pv_previstoKg}     AS previsto,
        P.${FornTables.pv_realizadoKg}    AS realizado,
        P.${FornTables.pv_idRacao}        AS id_racao,

        B.${FornTables.db_nomeLocal}      AS nome_local,
        B.${FornTables.db_linha}          AS linha,
        B.${FornTables.db_idLote}         AS id_lote,
        B.${FornTables.db_rfid}           AS rfid
      FROM ${FornTables.previsao} P
      JOIN ${FornTables.detalhesBaias} B
        ON B.${FornTables.db_id} = P.${FornTables.pv_idBaia}
      WHERE
        P.${FornTables.pv_idFornecimento} = ?
        AND P.${FornTables.pv_data} = ?
        AND P.${FornTables.pv_trato} = ?
      LIMIT 1
    """, [idF, dataYmd, trato]);

    if (rows.isEmpty) return null;
    final m = rows.first;

    return CurralSnapshot(
      idBaia: _toStr(m["id_baia"]),
      dataIso: dataYmd,
      trato: trato,
      idDieta: _toStr(m["id_racao"]), // ✅ dieta = ID_RACAO
      idFornecimento: _toStr(m["id_fornecimento"]),
      previstoKg: _toDouble(m["previsto"]),
      realizadoKg: _toDouble(m["realizado"]),
    );
  }

  // =========================================================
  // FORNECIMENTO ABERTO (versão “antiga” usada em alguns fluxos)
  // =========================================================
  Future<FornecimentoAberto?> getAberto({
    required DateTime data,
    required int trato,
    required String idBaia,
  }) async {
    final db = await _db;
    final d = toSqlDate(data);

    final rows = await db.query(
      FornTables.cadastroFornecimento,
      where: """
        ${FornTables.cf_data} = ?
        AND ${FornTables.cf_trato} = ?
        AND ${FornTables.cf_idBaia} = ?
        AND (${FornTables.cf_horaFim} IS NULL OR ${FornTables.cf_horaFim} = '')
      """,
      whereArgs: [d, trato, idBaia],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    final m = rows.first;

    final idFornec = _toStr(m[FornTables.cf_idFornecimento]).trim();
    final idDieta = _toStr(m[FornTables.cf_idDieta]).trim();
    if (idFornec.isEmpty || idDieta.isEmpty) {
      // evita passar String vazia para required String
      return null;
    }

    return FornecimentoAberto(
      idFornecimento: idFornec,
      idBaia: _toStr(m[FornTables.cf_idBaia]),
      idDieta: idDieta,
      dataIso: _toStr(_toStr(m[FornTables.cf_data]).isEmpty ? d : m[FornTables.cf_data]),
      trato: (m[FornTables.cf_trato] as num?)?.toInt() ?? trato,
      idUsuario: _toStr(m[FornTables.cf_idUsuario]).trim().isEmpty
          ? null
          : _toStr(m[FornTables.cf_idUsuario]),
      idFabricacao: _toStr(m[FornTables.cf_idFabricacao]).trim().isEmpty
          ? null
          : _toStr(m[FornTables.cf_idFabricacao]),
      pesoInicio: _toDouble(m[FornTables.cf_pesoInicio]),
      horaInicio: _toStr(m[FornTables.cf_horaInicio]),
      previstoKg: _toDouble(m[FornTables.cf_previsto]),
    );
  }

  // =========================================================
  // FORNECIMENTO ABERTO (Mini) ✅ (model tem só 2 campos)
  // =========================================================
  Future<FornecimentoAbertoMini?> getFornecimentoAberto({
    required String idFornecimento,
    required String idBaia,
    required DateTime data,
    required int trato,
  }) async {
    final db = await _db;
    final d = toSqlDate(data);

    final rows = await db.query(
      FornTables.cadastroFornecimento,
      where: """
        ${FornTables.cf_data} = ?
        AND ${FornTables.cf_trato} = ?
        AND ${FornTables.cf_idFornecimento} = ?
        AND ${FornTables.cf_idBaia} = ?
        AND (${FornTables.cf_horaFim} IS NULL OR ${FornTables.cf_horaFim} = '')
      """,
      whereArgs: [d, trato, idFornecimento, idBaia],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    final m = rows.first;

    final idFornec = _toStr(m[FornTables.cf_idFornecimento]).trim();
    final idBaiaDb = _toStr(m[FornTables.cf_idBaia]).trim();

    return FornecimentoAbertoMini(
      idFornecimento: idFornec.isEmpty ? idFornecimento : idFornec,
      idBaia: idBaiaDb.isEmpty ? idBaia : idBaiaDb,
    );
  }

  // =========================================================
  // ABRIR (insert)
  // =========================================================
  Future<void> abrir({
    required String id,
    required String idFornecimento,
    required String idFabricacao,
    required String idBaia,
    required DateTime data,
    required num pesoInicio,
    required num previsto,
    required int trato,
    required String idUsuario,
    String? idDieta,
  }) async {
    final db = await _db;
    final d = toSqlDate(data);
    final hora = nowTime();

    await db.insert(
      FornTables.cadastroFornecimento,
      {
        FornTables.cf_id: id,
        FornTables.cf_idFornecimento: idFornecimento,
        FornTables.cf_idFabricacao: idFabricacao,
        FornTables.cf_idBaia: idBaia,
        FornTables.cf_data: d,
        FornTables.cf_horaInicio: hora,
        FornTables.cf_pesoInicio: pesoInicio,
        FornTables.cf_horaFim: null,
        FornTables.cf_pesoFim: pesoInicio, // NOT NULL
        FornTables.cf_previsto: previsto,
        FornTables.cf_realizado: null,
        FornTables.cf_flagSync: 0,
        FornTables.cf_trato: trato,
        FornTables.cf_idUsuario: idUsuario,
        FornTables.cf_idDieta: idDieta,
      },
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  // =========================================================
  // FINALIZAR (update)
  // =========================================================
  Future<void> finalizar({
    required String id,
    required num pesoFim,
    required num previsto,
    required num? realizado,
  }) async {
    final db = await _db;
    final hora = nowTime();

    await db.update(
      FornTables.cadastroFornecimento,
      {
        FornTables.cf_horaFim: hora,
        FornTables.cf_pesoFim: pesoFim,
        FornTables.cf_previsto: previsto,
        FornTables.cf_realizado: realizado,
        FornTables.cf_flagSync: 0,
      },
      where: "${FornTables.cf_id} = ?",
      whereArgs: [id],
    );
  }

  // =========================================================
  // FINALIZAR CADASTRO_FORNECIMENTO (uso principal)
  // =========================================================
  Future<void> finalizarCadastro({
    required String id,
    required double pesoFim,
    required double realizado,
  }) async {
    final db = await _db;
    final hora = nowTime();

    await db.update(
      FornTables.cadastroFornecimento,
      {
        FornTables.cf_horaFim: hora,
        FornTables.cf_pesoFim: pesoFim,
        FornTables.cf_realizado: realizado,
        FornTables.cf_flagSync: 0,
      },
      where: "${FornTables.cf_id} = ?",
      whereArgs: [id],
    );
  }

  // =========================================================
  // CANCELAR ABERTO (quando realizado baixo)
  // =========================================================
  Future<void> cancelarCadastroAberto(String idCadastro) async {
    final db = await _db;
    await db.update(
      FornTables.cadastroFornecimento,
      {
        FornTables.cf_horaFim: nowTime(),
        FornTables.cf_realizado: 0,
        FornTables.cf_flagSync: 0,
      },
      where: "${FornTables.cf_id} = ?",
      whereArgs: [idCadastro],
    );
  }

  // =========================================================
  // SALVAR PARCIAL
  // =========================================================
  Future<void> salvarParcial({
    required String motivo,
    required String id,
    required double pesoInicio,
    required double pesoFim,
    required double realizado,
  }) async {
    final db = await _db;
    final hora = nowTime();

    await db.update(
      FornTables.cadastroFornecimento,
      {
        FornTables.cf_horaFim: hora,
        FornTables.cf_pesoInicio: pesoInicio,
        FornTables.cf_pesoFim: pesoFim,
        FornTables.cf_realizado: realizado,
        FornTables.cf_flagSync: 0,
      },
      where: "${FornTables.cf_id} = ?",
      whereArgs: [id],
    );
  }

  // =========================================================
  // REALIZADO ACUMULADO (FORNECIMENTO_CONF)
  // =========================================================
  Future<double> getRealizadoAcumulado({
    required String idFornecimento,
    required String idBaia,
    required DateTime data,
    required int trato,
  }) async {
    final db = await _db;
    final d = toSqlDate(data);

    final rows = await db.query(
      FornTables.previsao,
      columns: [FornTables.pv_realizadoKg],
      where: """
        ${FornTables.pv_idFornecimento} = ?
        AND ${FornTables.pv_idBaia} = ?
        AND ${FornTables.pv_data} = ?
        AND ${FornTables.pv_trato} = ?
      """,
      whereArgs: [idFornecimento, idBaia, d, trato],
      limit: 1,
    );

    if (rows.isEmpty) return 0.0;
    return _toDouble(rows.first[FornTables.pv_realizadoKg]);
  }

  // =========================================================
  // ATUALIZAR REALIZADO NA PREVISAO (FORNECIMENTO_CONF)
  // =========================================================
  Future<void> setPrevRealizado({
    required DateTime data,
    required int trato,
    required String idBaia,
    required double realizadoKg,
  }) async {
    final db = await _db;
    final d = toSqlDate(data);

    await db.update(
      FornTables.previsao,
      {FornTables.pv_realizadoKg: realizadoKg},
      where: """
        ${FornTables.pv_data} = ?
        AND ${FornTables.pv_trato} = ?
        AND ${FornTables.pv_idBaia} = ?
      """,
      whereArgs: [d, trato, idBaia],
    );
  }

  // =========================================================
  // LISTA PARA TELA (JOIN CADASTRO_FORNECIMENTO + BAIA)
  // =========================================================
  Future<List<Map<String, Object?>>> listByDateTratoJoinBaia({
    required String dataSql,
    required int trato,
  }) async {
    final db = await _db;

    return db.rawQuery("""
      SELECT
        F.${FornTables.cf_id}              AS id,
        F.${FornTables.cf_idFornecimento}  AS id_fornecimento,
        F.${FornTables.cf_idFabricacao}    AS id_fabricacao,
        F.${FornTables.cf_idBaia}          AS id_baia,
        F.${FornTables.cf_data}            AS data,
        F.${FornTables.cf_horaInicio}      AS hora_inicio,
        F.${FornTables.cf_horaFim}         AS hora_fim,
        F.${FornTables.cf_pesoInicio}      AS peso_inicio,
        F.${FornTables.cf_pesoFim}         AS peso_fim,
        F.${FornTables.cf_previsto}        AS previsto,
        F.${FornTables.cf_realizado}       AS realizado,
        F.${FornTables.cf_flagSync}        AS flag_sync,
        F.${FornTables.cf_trato}           AS trato,
        F.${FornTables.cf_idUsuario}       AS id_usuario,
        F.${FornTables.cf_idDieta}         AS id_dieta,

        B.${FornTables.db_nomeLocal}       AS nome_local,
        B.${FornTables.db_linha}           AS linha,
        B.${FornTables.db_idLote}          AS id_lote,
        B.${FornTables.db_rfid}            AS rfid
      FROM ${FornTables.cadastroFornecimento} F
      LEFT JOIN ${FornTables.detalhesBaias} B
        ON B.${FornTables.db_id} = F.${FornTables.cf_idBaia}
      WHERE
        F.${FornTables.cf_data} = ?
        AND F.${FornTables.cf_trato} = ?
      ORDER BY
        B.${FornTables.db_linha} ASC,
        COALESCE(B.${FornTables.db_orderTrato}, 0) ASC,
        B.${FornTables.db_nomeLocal} ASC,
        F.${FornTables.cf_horaInicio} ASC
    """, [dataSql, trato]);
  }

  // =========================================================
  // SYNC
  // =========================================================
  Future<List<FornecimentoRow>> listPendentesSync({int limit = 200}) async {
    final db = await _db;

    final rows = await db.query(
      FornTables.cadastroFornecimento,
      where: "${FornTables.cf_flagSync} = 0",
      limit: limit,
      orderBy: "${FornTables.cf_data} DESC, ${FornTables.cf_horaInicio} DESC",
    );

    return rows.map((m) => FornecimentoRow.fromMap(m)).toList();
  }

  Future<void> marcarSyncOk(String id) async {
    final db = await _db;
    await db.update(
      FornTables.cadastroFornecimento,
      {FornTables.cf_flagSync: 1},
      where: "${FornTables.cf_id} = ?",
      whereArgs: [id],
    );
  }

  Future<void> upsert(FornecimentoRow row) async {
    final db = await _db;
    await db.insert(
      FornTables.cadastroFornecimento,
      row.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // =========================================================
  // BAIAS
  // =========================================================
  Future<void> upsertBaia(BaiaRow b) async {
    final db = await _db;
    await db.insert(
      FornTables.detalhesBaias,
      b.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<BaiaRow?> getBaiaByRfid(String rfid) async {
    final db = await _db;
    final tag = rfid.trim();
    if (tag.isEmpty) return null;

    final rows = await db.query(
      FornTables.detalhesBaias,
      where: "${FornTables.db_rfid} = ?",
      whereArgs: [tag],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return BaiaRow.fromMap(rows.first);
  }
}
