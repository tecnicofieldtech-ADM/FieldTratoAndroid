// lib/features/fornecimento/data/fornecimento_dao.dart
import "dart:math";
import "package:flutter/foundation.dart";
import "package:sqflite/sqflite.dart";

import "../../../db/app_db.dart";
import "../../../services/rfid_tag_resolver.dart";
import "fornecimento_tables.dart";
import "../domain/fornecimento_models.dart";

class FornecimentoDao {
  FornecimentoDao({RfidTagResolver? rfidResolver})
      : _rfidResolver = rfidResolver ?? RfidTagResolver();

  final RfidTagResolver _rfidResolver;

  Future<Database> get _db async => AppDb.instance.db;

  // ✅ executa SQL "cru"
  Future<List<Map<String, Object?>>> rawQuery(
    String sql,
    List<Object?> args,
  ) async {
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

  DateTime? _parseYmd(String ymd) {
    final t = ymd.trim();
    if (t.length < 10) return null;
    final y = int.tryParse(t.substring(0, 4));
    final m = int.tryParse(t.substring(5, 7));
    final d = int.tryParse(t.substring(8, 10));
    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }

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
  // 🧪 DEBUG: dump rápido do CADASTRO_FORNECIMENTO
  // =========================================================
  // =========================================================
  // 🧪 DEBUG: dump rápido do CADASTRO_FORNECIMENTO
  // =========================================================
  Future<void> debugDumpCadastroFornecimento({int limit = 20}) async {
    final db = await _db;

    final r1 = await db
        .rawQuery("SELECT COUNT(*) c FROM ${FornTables.cadastroFornecimento}");
    final total = (r1.first["c"] as int?) ?? 0;

    final r2 = await db.rawQuery("""
      SELECT COUNT(*) c
      FROM ${FornTables.cadastroFornecimento}
      WHERE COALESCE(${FornTables.cfFlagSync},0)=0
    """);
    final pend = (r2.first["c"] as int?) ?? 0;

    final rows = await db.rawQuery("""
      SELECT
        ${FornTables.cfId} AS id,
        ${FornTables.cfData} AS data,
        ${FornTables.cfTrato} AS trato,
        ${FornTables.cfIdBaia} AS id_baia,
        ${FornTables.cfIdFornecimento} AS id_fornecimento,
        ${FornTables.cfRealizado} AS realizado,
        ${FornTables.cfHoraFim} AS hora_fim,
        ${FornTables.cfFlagSync} AS flag_sync
      FROM ${FornTables.cadastroFornecimento}
      ORDER BY ROWID DESC
      LIMIT ?
    """, [limit]);

    if (kDebugMode) {
      debugPrint("🧪 CADASTRO_FORNECIMENTO total=$total pendentes=$pend");
      for (final r in rows) {
        debugPrint(" → $r");
      }
    }
  }

  // =========================================================
  // ✅ LOGIN / USUÁRIO (ULTIMO_LOGIN)
  // =========================================================
  Future<String?> getUsuarioAtualId() async {
    final db = await _db;

    // 1) descobre quais colunas existem na ULTIMO_LOGIN
    final cols =
        await db.rawQuery("PRAGMA table_info(${FornTables.ultimoLogin})");
    final names = cols
        .map((m) => (m["name"] ?? "").toString().trim().toUpperCase())
        .where((s) => s.isNotEmpty)
        .toList();

    if (names.isEmpty) return null;

    // 2) tenta achar a coluna do ID do usuário (ordem de preferência)
    String? pick(String n) => names.contains(n) ? n : null;

    final col = pick("ID_USUARIO") ??
        pick("IDUSER") ??
        pick("USUARIO_ID") ??
        pick("ID") ??
        pick("USER_ID");

    if (col == null) return null;

    // 3) busca o valor
    final rows = await db.rawQuery(
      "SELECT $col AS ID FROM ${FornTables.ultimoLogin} LIMIT 1",
    );
    if (rows.isEmpty) return null;

    final id = (rows.first["ID"] ?? "").toString().trim();
    return id.isEmpty ? null : id;
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

  Future<Map<String, Object?>?> getFabricacaoResumo(String idFabricacao) async {
    final db = await _db;
    final id = idFabricacao.trim();
    if (id.isEmpty) return null;

    final rows = await db.rawQuery("""
      SELECT
        f.ID AS id,
        f.ID_DIETA AS id_dieta,
        f.DATA_FABRICACAO AS data_fabricacao,
        f.HORA_INICIO AS hora_inicio,
        f.HORA_FIM AS hora_fim,
        COALESCE(f.QTD_PREVISTA, 0) AS qtd_prevista,
        COALESCE(f.QTD_REALIZADA, 0) AS qtd_realizada,
        COALESCE(f.FINALIZADA, 0) AS finalizada,
        COALESCE(f.FLAG_SYNC, 0) AS flag_sync,
        COALESCE(f.FAB_STATUS, 0) AS fab_status,
        COALESCE(f.HANDOFF_ID, '') AS handoff_id,
        COALESCE(f.ORIGIN_DEVICE, '') AS origin_device,
        COALESCE(d.NOME, f.ID_DIETA, '') AS racao_nome
      FROM ${FornTables.cadastroFabrica} f
      LEFT JOIN DIETA d
        ON TRIM(CAST(d.ID AS TEXT)) = TRIM(CAST(f.ID_DIETA AS TEXT))
      WHERE TRIM(f.ID) = TRIM(?)
      LIMIT 1
    """, [id]);

    if (rows.isEmpty) return null;
    return rows.first;
  }

  // =========================================================
  // LISTA CURRAIS (PREVISAO + DETALHES_BAIAS)
  // =========================================================
  Future<List<Map<String, Object?>>> listCurraisPrevistos({
    required String dataYmd,
    required int trato,
    String? idFazenda,
    String? idRacao,
  }) async {
    final db = await _db;

    final where = <String>[
      "substr(a.${FornTables.pvData},1,10) = ?",
      "a.${FornTables.pvTrato} = ?",
    ];
    final args = <Object?>[dataYmd, trato];

    final racao = (idRacao ?? "").trim();
    if (racao.isNotEmpty) {
      where.add("TRIM(a.${FornTables.pvIdRacao}) = TRIM(?)");
      args.add(racao);
    }

    final sql = """
    SELECT
      a.${FornTables.pvIdFornecimento} AS id_fornecimento,
      a.${FornTables.pvData}           AS data,
      a.${FornTables.pvTrato}          AS trato,
      a.${FornTables.pvIdBaia}         AS id_baia,
      a.${FornTables.pvPrevistoKg}     AS previsto,
      ${FornTables.sqlRealizadoKgLocal("a")} AS realizado,
      a.${FornTables.pvIdRacao}        AS id_racao,

      db.${FornTables.dbNomeLocal}     AS nome_local,

      COALESCE(CAST(db.${FornTables.dbLinha} AS TEXT), '')     AS linha,

      COALESCE(db.${FornTables.dbOrderTrato}, 0)  AS order_trato,
      COALESCE(db.${FornTables.dbRfid}, '')       AS rfid,
      db.${FornTables.dbIdLote}        AS id_lote
    FROM ${FornTables.previsao} a
    JOIN ${FornTables.detalhesBaias} db
      ON TRIM(CAST(db.${FornTables.dbId} AS TEXT)) =
         TRIM(CAST(a.${FornTables.pvIdBaia} AS TEXT))
    WHERE ${where.join(" AND ")}
    ORDER BY
      COALESCE(CAST(db.${FornTables.dbLinha} AS TEXT), '') ASC,
      COALESCE(db.${FornTables.dbOrderTrato}, 0) ASC,
      db.${FornTables.dbNomeLocal} ASC
  """;

    return db.rawQuery(sql, args);
  }

  // =========================================================
  // RFID -> ID_FORNECIMENTO  (PREVISAO + DETALHES_BAIAS)
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

    final rfidMatch = await _rfidResolver.sqlRfidEquals(
      "db.${FornTables.dbRfid}",
      tag,
    );

    final where = <String>[
      rfidMatch.clause,
      "substr(a.${FornTables.pvData},1,10) = ?",
      "a.${FornTables.pvTrato} = ?",
    ];
    final args = <Object?>[...rfidMatch.args, dataYmd, trato];

    final racao = (idRacao ?? "").trim();
    if (racao.isNotEmpty) {
      where.add("TRIM(a.${FornTables.pvIdRacao}) = TRIM(?)");
      args.add(racao);
    }

    final rows = await db.rawQuery("""
    SELECT a.${FornTables.pvIdFornecimento} AS id_fornecimento
    FROM ${FornTables.detalhesBaias} db
    JOIN ${FornTables.previsao} a
      ON TRIM(CAST(a.${FornTables.pvIdBaia} AS TEXT)) =
         TRIM(CAST(db.${FornTables.dbId} AS TEXT))
    WHERE ${where.join(" AND ")}
    LIMIT 1
  """, args);

    if (rows.isEmpty) return null;
    final id = _toStr(rows.first["id_fornecimento"]).trim();
    return id.isEmpty ? null : id;
  }

  // =========================================================
  // SNAPSHOT (PREVISAO)
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
      a.${FornTables.pvIdFornecimento} AS id_fornecimento,
      a.${FornTables.pvIdBaia}         AS id_baia,
      a.${FornTables.pvPrevistoKg}     AS previsto,
      ${FornTables.sqlRealizadoKgLocal("a")} AS realizado,
      a.${FornTables.pvIdRacao}        AS id_racao
    FROM ${FornTables.previsao} a
    WHERE
      TRIM(a.${FornTables.pvIdFornecimento}) = TRIM(?)
      AND substr(a.${FornTables.pvData},1,10) = ?
      AND a.${FornTables.pvTrato} = ?
    LIMIT 1
  """, [idF, dataYmd, trato]);

    if (rows.isEmpty) return null;
    final m = rows.first;

    return CurralSnapshot(
      idBaia: _toStr(m["id_baia"]).trim(),
      dataIso: dataYmd,
      trato: trato,
      idDieta: _toStr(m["id_racao"]).trim(),
      idFornecimento: _toStr(m["id_fornecimento"]).trim(),
      previstoKg: _toDouble(m["previsto"]),
      realizadoKg: _toDouble(m["realizado"]),
    );
  }

  // =========================================================
  // FORNECIMENTO ABERTO (Mini)
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
      columns: [
        FornTables.cfId,
        FornTables.cfIdFornecimento,
        FornTables.cfIdBaia,
        FornTables.cfPesoInicio,
      ],
      where: """
        ${FornTables.cfData} = ?
        AND ${FornTables.cfTrato} = ?
        AND TRIM(${FornTables.cfIdFornecimento}) = TRIM(?)
        AND TRIM(${FornTables.cfIdBaia}) = TRIM(?)
        AND (${FornTables.cfHoraFim} IS NULL OR ${FornTables.cfHoraFim} = '')
      """,
      whereArgs: [d, trato, idFornecimento, idBaia],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    final m = rows.first;

    final idCadastro = _toStr(m[FornTables.cfId]).trim();
    final idFornec = _toStr(m[FornTables.cfIdFornecimento]).trim();
    final idBaiaDb = _toStr(m[FornTables.cfIdBaia]).trim();

    return FornecimentoAbertoMini(
      idCadastro: idCadastro,
      idFornecimento: idFornec.isEmpty ? idFornecimento : idFornec,
      idBaia: idBaiaDb.isEmpty ? idBaia : idBaiaDb,
      pesoInicio: _toDouble(m[FornTables.cfPesoInicio]),
    );
  }

  Future<void> atualizarPesoInicioAberto({
    required String idCadastro,
    required double pesoInicio,
  }) async {
    final db = await _db;
    await db.update(
      FornTables.cadastroFornecimento,
      {
        FornTables.cfPesoInicio: pesoInicio,
        FornTables.cfPesoFim: pesoInicio,
      },
      where: "${FornTables.cfId} = ?",
      whereArgs: [idCadastro.trim()],
    );
  }

  // =========================================================
  // ABRIR (insert)  ✅ CORRIGIDO: replace + log
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
        FornTables.cfId: id,
        FornTables.cfIdFornecimento: idFornecimento,
        FornTables.cfIdFabricacao: idFabricacao,
        FornTables.cfIdBaia: idBaia,
        FornTables.cfData: d,
        FornTables.cfHoraInicio: hora,
        FornTables.cfPesoInicio: pesoInicio,
        FornTables.cfHoraFim: null,
        FornTables.cfPesoFim: pesoInicio,
        FornTables.cfPrevisto: previsto,
        FornTables.cfRealizado: null,
        FornTables.cfFlagSync: 0,
        FornTables.cfTrato: trato,
        FornTables.cfIdUsuario: idUsuario,
        FornTables.cfIdDieta: idDieta,
      },
      // ✅ evita “sumir” por PK abort (e te ajuda a testar rápido)
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    if (kDebugMode) {
      debugPrint(
        "✅ CADASTRO_FORNECIMENTO.abrir OK id=$id idFornecimento=$idFornecimento idBaia=$idBaia trato=$trato data=$d",
      );
    }
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
        FornTables.cfHoraFim: hora,
        FornTables.cfPesoFim: pesoFim,
        FornTables.cfRealizado: realizado,
        FornTables.cfFlagSync: 0,
      },
      where: "${FornTables.cfId} = ?",
      whereArgs: [id],
    );
  }

  // =========================================================
  // SALVAR FINALIZADO (insert direto, novo fluxo)
  // =========================================================
  Future<void> salvarFinalizado({
    required String id,
    required String idFornecimento,
    required String idFabricacao,
    required String idBaia,
    required DateTime data,
    required int trato,
    required String idUsuario,
    String? idDieta,
    required double pesoFim,
    required double realizado,
    required double previsto,
    int mapa = 0,
    String? horaInicio,
  }) async {
    final db = await _db;
    final d = toSqlDate(data);
    final horaFim = nowTime();
    final horaIni = (horaInicio != null && horaInicio.trim().isNotEmpty)
        ? horaInicio.trim()
        : horaFim;

    await db.insert(
      FornTables.cadastroFornecimento,
      {
        FornTables.cfId: id,
        FornTables.cfIdFornecimento: idFornecimento,
        FornTables.cfIdFabricacao: idFabricacao,
        FornTables.cfIdBaia: idBaia,
        FornTables.cfData: d,
        FornTables.cfHoraInicio: horaIni,
        FornTables.cfHoraFim: horaFim,
        FornTables.cfPesoInicio: pesoFim,
        FornTables.cfPesoFim: pesoFim,
        FornTables.cfPrevisto: previsto,
        FornTables.cfRealizado: realizado,
        FornTables.cfFlagSync: 0,
        FornTables.cfTrato: trato,
        FornTables.cfIdUsuario: idUsuario,
        FornTables.cfIdDieta: idDieta,
        FornTables.cfMapa: mapa,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Não espelha o cadastro local por cima do realizado da API/TGC.
  /// O mapa soma PREVISAO (TGC) + sessões com FLAG_SYNC=0.
  Future<void> aplicarRealizadoLocalPrevisao({
    required String idFornecimento,
    required String idBaia,
    required int trato,
    required String dataYmd,
    required double deltaRealizado,
  }) async {
    if (deltaRealizado <= 0) return;
    if (kDebugMode) {
      debugPrint(
        "[FORN] PREVISAO.REALIZADO_KG preservado (API/TGC). "
        "Delta local=$deltaRealizado idForn=$idFornecimento "
        "baia=$idBaia trato=$trato data=$dataYmd",
      );
    }
  }

  // =========================================================
  // CANCELAR ABERTO
  // =========================================================
  Future<void> cancelarCadastroAberto(String idCadastro) async {
    final db = await _db;
    await db.update(
      FornTables.cadastroFornecimento,
      {
        FornTables.cfHoraFim: nowTime(),
        FornTables.cfRealizado: 0,
        FornTables.cfFlagSync: 0,
      },
      where: "${FornTables.cfId} = ?",
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
        FornTables.cfHoraFim: hora,
        FornTables.cfPesoInicio: pesoInicio,
        FornTables.cfPesoFim: pesoFim,
        FornTables.cfRealizado: realizado,
        FornTables.cfFlagSync: 0,
      },
      where: "${FornTables.cfId} = ?",
      whereArgs: [id],
    );
  }

  // =========================================================
  // REALIZADO ACUMULADO (PREVISAO)
  // =========================================================
  Future<double> getRealizadoAcumulado({
    required String idFornecimento,
    required String idBaia,
    required DateTime data,
    required int trato,
  }) async {
    final db = await _db;
    final d = toSqlDate(data);

    final idF = idFornecimento.trim();
    final idB = idBaia.trim();

    final rows = await db.rawQuery("""
    SELECT ${FornTables.sqlRealizadoKgLocal("a")} AS realizado
    FROM ${FornTables.previsao} a
    WHERE
      TRIM(a.${FornTables.pvIdFornecimento}) = TRIM(?)
      AND TRIM(a.${FornTables.pvIdBaia}) = TRIM(?)
      AND substr(a.${FornTables.pvData},1,10) = ?
      AND a.${FornTables.pvTrato} = ?
    LIMIT 1
    """, [idF, idB, d, trato]);

    if (rows.isEmpty) return 0.0;
    return _toDouble(rows.first["realizado"]);
  }

  Future<double> _maxRealizadoPrevisaoBaiaTrato({
    required String idBaia,
    required String d,
    required int trato,
  }) async {
    final db = await _db;
    final idB = idBaia.trim();

    final rows = await db.query(
      FornTables.previsao,
      columns: [FornTables.pvRealizadoKg],
      where: """
      TRIM(${FornTables.pvIdBaia}) = TRIM(?)
      AND substr(${FornTables.pvData},1,10) = ?
      AND ${FornTables.pvTrato} = ?
    """,
      whereArgs: [idB, d, trato],
    );

    var maxV = 0.0;
    for (final r in rows) {
      final v = _toDouble(r[FornTables.pvRealizadoKg]);
      if (v > maxV) maxV = v;
    }
    return maxV;
  }

  Future<double> getRealizadoAcumuladoWithFallback({
    required String idFornecimento,
    required String idBaia,
    required DateTime data,
    required int trato,
  }) async {
    final v = await getRealizadoAcumulado(
      idFornecimento: idFornecimento,
      idBaia: idBaia,
      data: data,
      trato: trato,
    );
    if (v > 0) return v;

    final d = toSqlDate(data);
    final fallback = await _maxRealizadoPrevisaoBaiaTrato(
      idBaia: idBaia,
      d: d,
      trato: trato,
    );
    return fallback;
  }

  // =========================================================
  // ATUALIZAR REALIZADO NA PREVISAO
  // =========================================================
  Future<void> setPrevRealizado({
    required DateTime data,
    required int trato,
    required String idBaia,
    required double realizadoKg,
    String? idFornecimento,
  }) async {
    final db = await _db;
    final d = toSqlDate(data);

    final idF = (idFornecimento ?? "").trim();

    final idB = idBaia.trim();

    if (idF.isNotEmpty) {
      await db.update(
        FornTables.previsao,
        {FornTables.pvRealizadoKg: realizadoKg},
        where: """
        substr(${FornTables.pvData},1,10) = ?
        AND ${FornTables.pvTrato} = ?
        AND TRIM(${FornTables.pvIdBaia}) = TRIM(?)
        AND TRIM(${FornTables.pvIdFornecimento}) = TRIM(?)
      """,
        whereArgs: [d, trato, idB, idF],
      );
      return;
    }

    await db.update(
      FornTables.previsao,
      {FornTables.pvRealizadoKg: realizadoKg},
      where: """
      substr(${FornTables.pvData},1,10) = ?
      AND ${FornTables.pvTrato} = ?
      AND TRIM(${FornTables.pvIdBaia}) = TRIM(?)
    """,
      whereArgs: [d, trato, idB],
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
        F.${FornTables.cfId}              AS id,
        F.${FornTables.cfIdFornecimento}  AS id_fornecimento,
        F.${FornTables.cfIdFabricacao}    AS id_fabricacao,
        F.${FornTables.cfIdBaia}          AS id_baia,
        F.${FornTables.cfData}            AS data,
        F.${FornTables.cfHoraInicio}      AS hora_inicio,
        F.${FornTables.cfHoraFim}         AS hora_fim,
        F.${FornTables.cfPesoInicio}      AS peso_inicio,
        F.${FornTables.cfPesoFim}         AS peso_fim,
        F.${FornTables.cfPrevisto}        AS previsto,
        F.${FornTables.cfRealizado}       AS realizado,
        F.${FornTables.cfFlagSync}        AS flag_sync,
        F.${FornTables.cfTrato}           AS trato,
        F.${FornTables.cfIdUsuario}       AS id_usuario,
        F.${FornTables.cfIdDieta}         AS id_dieta,

        B.${FornTables.dbNomeLocal}       AS nome_local,

        COALESCE(CAST(B.${FornTables.dbLinha} AS TEXT), '') AS linha,

        B.${FornTables.dbIdLote}          AS id_lote,
        B.${FornTables.dbRfid}            AS rfid
      FROM ${FornTables.cadastroFornecimento} F
      LEFT JOIN ${FornTables.detalhesBaias} B
        ON TRIM(CAST(B.${FornTables.dbId} AS TEXT)) = TRIM(CAST(F.${FornTables.cfIdBaia} AS TEXT))
      WHERE
        F.${FornTables.cfData} = ?
        AND F.${FornTables.cfTrato} = ?
      ORDER BY
        COALESCE(CAST(B.${FornTables.dbLinha} AS TEXT), '') ASC,
        COALESCE(B.${FornTables.dbOrderTrato}, 0) ASC,
        B.${FornTables.dbNomeLocal} ASC,
        F.${FornTables.cfHoraInicio} ASC
    """, [dataSql, trato]);
  }

  /// Linhas de CADASTRO_FORNECIMENTO para baia+trato+data+dieta (detalhe na lista).
  Future<List<Map<String, Object?>>> listSessoesPorChave({
    required String dataYmd,
    required int trato,
    required String idBaia,
    required String idRacao,
    String? idFornecimento,
  }) async {
    final db = await _db;
    final baia = idBaia.trim();
    final racao = idRacao.trim();
    final idPrev = (idFornecimento ?? "").trim();

    return db.rawQuery("""
      SELECT
        ${FornTables.cfId}              AS id,
        ${FornTables.cfHoraInicio}      AS hora_inicio,
        ${FornTables.cfHoraFim}         AS hora_fim,
        ${FornTables.cfPesoInicio}      AS peso_inicio,
        ${FornTables.cfPesoFim}         AS peso_fim,
        ${FornTables.cfRealizado}       AS realizado,
        ${FornTables.cfPrevisto}        AS previsto,
        ${FornTables.cfFlagSync}        AS flag_sync,
        ${FornTables.cfIdDieta}         AS id_dieta,
        ${FornTables.cfIdFornecimento}  AS id_fornecimento,
        ${FornTables.cfIdFabricacao}    AS id_fabricacao
      FROM ${FornTables.cadastroFornecimento}
      WHERE substr(COALESCE(${FornTables.cfData}, ''), 1, 10) = ?
        AND ${FornTables.cfTrato} = ?
        AND TRIM(COALESCE(${FornTables.cfIdBaia}, '')) = TRIM(?)
        AND COALESCE(${FornTables.cfRealizado}, 0) > 0
        AND (
          TRIM(COALESCE(${FornTables.cfIdDieta}, '')) = TRIM(?)
          OR (
            TRIM(COALESCE(${FornTables.cfIdDieta}, '')) = ''
            AND TRIM(COALESCE(${FornTables.cfIdFornecimento}, '')) = TRIM(?)
          )
        )
      ORDER BY
        COALESCE(${FornTables.cfHoraInicio}, '') ASC,
        ${FornTables.cfId} ASC
    """, [dataYmd, trato, baia, racao, idPrev]);
  }

  /// Exportacao completa para auditoria (POST /Post/FornecimentoAudit).
  Future<List<Map<String, Object?>>> listAllCadastroForAudit() async {
    final db = await _db;

    const sqlWithMapa = """
      SELECT
        F.${FornTables.cfId}              AS id,
        F.${FornTables.cfIdFornecimento}  AS id_fornecimento,
        F.${FornTables.cfIdFabricacao}    AS id_fabricacao,
        F.${FornTables.cfIdBaia}          AS id_baia,
        F.${FornTables.cfData}            AS data,
        F.${FornTables.cfHoraInicio}      AS hora_inicio,
        F.${FornTables.cfHoraFim}         AS hora_fim,
        F.${FornTables.cfPesoInicio}      AS peso_inicio,
        F.${FornTables.cfPesoFim}         AS peso_fim,
        F.${FornTables.cfPrevisto}        AS previsto,
        F.${FornTables.cfRealizado}       AS realizado,
        F.${FornTables.cfFlagSync}        AS flag_sync,
        F.${FornTables.cfTrato}           AS trato,
        F.${FornTables.cfIdUsuario}       AS id_usuario,
        F.${FornTables.cfIdDieta}         AS id_dieta,
        F.${FornTables.cfMapa}            AS mapa,
        COALESCE(B.${FornTables.dbNomeLocal}, '') AS nome_baia,
        COALESCE(CAST(B.${FornTables.dbLinha} AS TEXT), '') AS linha
      FROM ${FornTables.cadastroFornecimento} F
      LEFT JOIN ${FornTables.detalhesBaias} B
        ON TRIM(CAST(B.${FornTables.dbId} AS TEXT)) = TRIM(CAST(F.${FornTables.cfIdBaia} AS TEXT))
      ORDER BY
        substr(F.${FornTables.cfData}, 1, 10) DESC,
        F.${FornTables.cfTrato} ASC,
        F.${FornTables.cfHoraInicio} ASC,
        F.${FornTables.cfId} ASC
    """;

    const sqlWithoutMapa = """
      SELECT
        F.${FornTables.cfId}              AS id,
        F.${FornTables.cfIdFornecimento}  AS id_fornecimento,
        F.${FornTables.cfIdFabricacao}    AS id_fabricacao,
        F.${FornTables.cfIdBaia}          AS id_baia,
        F.${FornTables.cfData}            AS data,
        F.${FornTables.cfHoraInicio}      AS hora_inicio,
        F.${FornTables.cfHoraFim}         AS hora_fim,
        F.${FornTables.cfPesoInicio}      AS peso_inicio,
        F.${FornTables.cfPesoFim}         AS peso_fim,
        F.${FornTables.cfPrevisto}        AS previsto,
        F.${FornTables.cfRealizado}       AS realizado,
        F.${FornTables.cfFlagSync}        AS flag_sync,
        F.${FornTables.cfTrato}           AS trato,
        F.${FornTables.cfIdUsuario}       AS id_usuario,
        F.${FornTables.cfIdDieta}         AS id_dieta,
        0                                 AS mapa,
        COALESCE(B.${FornTables.dbNomeLocal}, '') AS nome_baia,
        COALESCE(CAST(B.${FornTables.dbLinha} AS TEXT), '') AS linha
      FROM ${FornTables.cadastroFornecimento} F
      LEFT JOIN ${FornTables.detalhesBaias} B
        ON TRIM(CAST(B.${FornTables.dbId} AS TEXT)) = TRIM(CAST(F.${FornTables.cfIdBaia} AS TEXT))
      ORDER BY
        substr(F.${FornTables.cfData}, 1, 10) DESC,
        F.${FornTables.cfTrato} ASC,
        F.${FornTables.cfHoraInicio} ASC,
        F.${FornTables.cfId} ASC
    """;

    try {
      return db.rawQuery(sqlWithMapa);
    } catch (_) {
      return db.rawQuery(sqlWithoutMapa);
    }
  }

  Future<List<FornecimentoRow>> listPendentesSync({int limit = 200}) async {
    final db = await _db;

    final rows = await db.query(
      FornTables.cadastroFornecimento,
      where: "COALESCE(${FornTables.cfFlagSync},0) = 0",
      limit: limit,
      orderBy: "${FornTables.cfData} DESC, ${FornTables.cfHoraInicio} DESC",
    );

    return rows.map((m) {
      return FornecimentoRow.fromMap({
        "id": m[FornTables.cfId],
        "idFornecimento": m[FornTables.cfIdFornecimento],
        "idBaia": m[FornTables.cfIdBaia],
        "idDieta": m[FornTables.cfIdDieta],
        "dataIso": m[FornTables.cfData],
        "trato": m[FornTables.cfTrato],
        "previstoKg": m[FornTables.cfPrevisto],
        "realizadoKg": m[FornTables.cfRealizado],
      });
    }).toList();
  }

  Future<void> marcarSyncOk(String id) async {
    final db = await _db;
    await db.update(
      FornTables.cadastroFornecimento,
      {FornTables.cfFlagSync: 1},
      where: "${FornTables.cfId} = ?",
      whereArgs: [id],
    );
  }

  Future<int> marcarSyncPendentePorChave({
    required DateTime data,
    required int trato,
    required String idFornecimento,
    required String idBaia,
  }) async {
    final db = await _db;
    final dataSql = toSqlDate(data);

    return db.update(
      FornTables.cadastroFornecimento,
      {FornTables.cfFlagSync: 0},
      where: """
        substr(${FornTables.cfData},1,10) = ?
        AND ${FornTables.cfTrato} = ?
        AND TRIM(${FornTables.cfIdFornecimento}) = TRIM(?)
        AND TRIM(${FornTables.cfIdBaia}) = TRIM(?)
      """,
      whereArgs: [dataSql, trato, idFornecimento, idBaia],
    );
  }

  /// Reabilita TODOS os cadastros do dia com realizado > 0 (todos os tratos).
  Future<int> marcarSyncPendenteDoDia({required DateTime data}) async {
    final db = await _db;
    final dataSql = toSqlDate(data);
    return db.update(
      FornTables.cadastroFornecimento,
      {FornTables.cfFlagSync: 0},
      where: """
        substr(${FornTables.cfData},1,10) = ?
        AND COALESCE(${FornTables.cfRealizado}, 0) > 0
      """,
      whereArgs: [dataSql],
    );
  }

  Future<int> marcarSyncOkPorChave({
    required DateTime data,
    required int trato,
    required String idFornecimento,
    required String idBaia,
  }) async {
    final db = await _db;
    final dataSql = toSqlDate(data);

    return db.update(
      FornTables.cadastroFornecimento,
      {FornTables.cfFlagSync: 1},
      where: """
        substr(${FornTables.cfData},1,10) = ?
        AND ${FornTables.cfTrato} = ?
        AND TRIM(${FornTables.cfIdFornecimento}) = TRIM(?)
        AND TRIM(${FornTables.cfIdBaia}) = TRIM(?)
      """,
      whereArgs: [dataSql, trato, idFornecimento, idBaia],
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

    final rfidMatch = await _rfidResolver.sqlRfidEquals(
      FornTables.dbRfid,
      tag,
    );

    final rows = await db.rawQuery(
      """
      SELECT *
      FROM ${FornTables.detalhesBaias}
      WHERE ${rfidMatch.clause}
      LIMIT 1
      """,
      rfidMatch.args,
    );

    if (rows.isEmpty) return null;
    return BaiaRow.fromMap(rows.first);
  }

  // =========================================================
  // PREVISAO - replicar dia anterior
  // =========================================================
  Future<int> countPrevisaoByData({
    required String dataYmd,
    String? idFazenda,
  }) async {
    final db = await _db;
    final rows = await db.rawQuery(
      """
      SELECT COUNT(*) AS c
      FROM ${FornTables.previsao}
      WHERE substr(${FornTables.pvData},1,10) = ?
      """,
      [dataYmd],
    );
    return (rows.first["c"] as int?) ?? 0;
  }

  Future<int> replicarPrevisaoEntreDatas({
    required String dataOrigemYmd,
    required String dataDestinoYmd,
    String? idFazenda,
  }) async {
    final db = await _db;

    await db.rawInsert(
      """
      INSERT INTO ${FornTables.previsao} (
        ${FornTables.pvIdFornecimento},
        ${FornTables.pvData},
        ${FornTables.pvIdBaia},
        ${FornTables.pvTrato},
        ${FornTables.pvPrevistoKg},
        ${FornTables.pvRealizadoKg},
        ${FornTables.pvIdRacao}
      )
      SELECT
        p.${FornTables.pvIdFornecimento},
        ?,
        p.${FornTables.pvIdBaia},
        p.${FornTables.pvTrato},
        p.${FornTables.pvPrevistoKg},
        0,
        p.${FornTables.pvIdRacao}
      FROM ${FornTables.previsao} p
      WHERE substr(p.${FornTables.pvData},1,10) = ?
      """,
      [dataDestinoYmd, dataOrigemYmd],
    );

    final changed = await db.rawQuery("SELECT changes() AS c");
    return (changed.first["c"] as int?) ?? 0;
  }
}


