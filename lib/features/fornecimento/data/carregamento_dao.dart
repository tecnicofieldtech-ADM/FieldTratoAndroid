// lib/features/fornecimento/data/carregamento_dao.dart
import "dart:math";
import "package:sqflite/sqflite.dart";
import "../../../db/app_db.dart";

class CarregamentoDao {
  Future<Database> get _db async => AppDb.instance.db;

  // ✅ nome real da tabela no SQLite
  static const _table = "CARREGAMENTO";

  // ✅ status conforme seu schema (0 = ABERTO)
  static const int statusAberto = 0;
  static const int statusFinalizado = 2; // ✅ consumido/carregado

  String _ymd(DateTime d) {
    final yyyy = d.year.toString().padLeft(4, "0");
    final mm = d.month.toString().padLeft(2, "0");
    final dd = d.day.toString().padLeft(2, "0");
    return "$yyyy-$mm-$dd";
  }

  /// Finaliza todos os carregamentos abertos do dia (opcionalmente do vagão).
  Future<int> finalizarAbertos({
    DateTime? data,
    String? idVagao,
    String? excetoId,
  }) async {
    final db = await _db;
    final dateStr = _ymd(data ?? DateTime.now());
    final vag = (idVagao ?? "").trim();
    final exc = (excetoId ?? "").trim();

    final where = <String>[
      "COALESCE(CAST(STATUS AS INTEGER),0) = ?",
      "substr(COALESCE(DATA_REGISTRO,''), 1, 10) = ?",
    ];
    final args = <Object?>[statusAberto, dateStr];

    if (vag.isNotEmpty) {
      where.add("TRIM(COALESCE(CAST(ID_VAGAO AS TEXT),'')) = TRIM(?)");
      args.add(vag);
    }
    if (exc.isNotEmpty) {
      where.add("TRIM(ID) <> TRIM(?)");
      args.add(exc);
    }

    return db.update(
      _table,
      {"STATUS": statusFinalizado},
      where: where.join(" AND "),
      whereArgs: args,
    );
  }

  /// Carregamento aberto ativo (status=0) do dia, opcionalmente filtrado por vagão.
  Future<Map<String, Object?>?> getAbertoAtivo({
    DateTime? data,
    String? idVagao,
  }) async {
    final db = await _db;
    final dateStr = _ymd(data ?? DateTime.now());
    final vag = (idVagao ?? "").trim();

    final where = <String>[
      "COALESCE(CAST(STATUS AS INTEGER),0) = ?",
      "substr(COALESCE(DATA_REGISTRO,''), 1, 10) = ?",
    ];
    final args = <Object?>[statusAberto, dateStr];

    if (vag.isNotEmpty) {
      where.add("TRIM(COALESCE(CAST(ID_VAGAO AS TEXT),'')) = TRIM(?)");
      args.add(vag);
    }

    final rows = await db.query(
      _table,
      where: where.join(" AND "),
      whereArgs: args,
      orderBy: "DATA_REGISTRO DESC",
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return rows.first;
  }

  /// Pega o carregamento aberto mais recente (status=0) no dia informado.
  /// 🔥 FIX: usa substr(DATA_REGISTRO,1,10)=YYYY-MM-DD (mais estável que date()).
  Future<Map<String, Object?>?> getAbertoHoje({DateTime? data}) async {
    final db = await _db;

    final dateStr = _ymd(data ?? DateTime.now());

    final rows = await db.query(
      _table,
      where: """
        COALESCE(CAST(STATUS AS INTEGER),0) = ?
        AND substr(COALESCE(DATA_REGISTRO,''), 1, 10) = ?
      """,
      whereArgs: [statusAberto, dateStr],
      orderBy: "DATA_REGISTRO DESC",
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return rows.first;
  }

  /// Pega o carregamento aberto do vagão (status=0)
  /// ✅ TRIM no ID_VAGAO pra evitar mismatch por espaços
  Future<Map<String, Object?>?> getAbertoByVagao(String idVagao) async {
    final db = await _db;

    final vagao = idVagao.trim();
    if (vagao.isEmpty) return null;

    final rows = await db.query(
      _table,
      where: """
        TRIM(COALESCE(CAST(ID_VAGAO AS TEXT),'')) = TRIM(?)
        AND COALESCE(CAST(STATUS AS INTEGER),0) = ?
      """,
      whereArgs: [vagao, statusAberto],
      orderBy: "DATA_REGISTRO DESC",
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return rows.first;
  }

  /// Pega o carregamento aberto de uma fabricação (status=0)
  /// ✅ TRIM no ID_FABRICACAO pra evitar mismatch por espaços
  Future<Map<String, Object?>?> getAbertoByFabricacao(String idFabricacao) async {
    final db = await _db;

    final fab = idFabricacao.trim();
    if (fab.isEmpty) return null;

    final rows = await db.query(
      _table,
      where: """
        TRIM(COALESCE(CAST(ID_FABRICACAO AS TEXT),'')) = TRIM(?)
        AND COALESCE(CAST(STATUS AS INTEGER),0) = ?
      """,
      whereArgs: [fab, statusAberto],
      orderBy: "DATA_REGISTRO DESC",
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return rows.first;
  }

  String _newId() {
    final r = Random();
    final s = List.generate(32, (_) => r.nextInt(16).toRadixString(16)).join();
    return "${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-"
        "${s.substring(16, 20)}-${s.substring(20)}";
  }

  Future<Map<String, Object?>?> getById(String id) async {
    final db = await _db;
    final key = id.trim();
    if (key.isEmpty) return null;

    final rows = await db.query(
      _table,
      where: "TRIM(ID) = TRIM(?)",
      whereArgs: [key],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return rows.first;
  }

  /// Carregamento aberto sem fabricação (ração pronta no vagão).
  Future<Map<String, Object?>?> getAbertoSemFabricacao({
    String? idVagao,
    DateTime? data,
  }) async {
    final db = await _db;
    final dateStr = _ymd(data ?? DateTime.now());
    final vag = (idVagao ?? "").trim();

    final where = <String>[
      "COALESCE(CAST(STATUS AS INTEGER),0) = ?",
      "substr(COALESCE(DATA_REGISTRO,''), 1, 10) = ?",
      "TRIM(COALESCE(CAST(ID_FABRICACAO AS TEXT),'')) = ''",
    ];
    final args = <Object?>[statusAberto, dateStr];

    if (vag.isNotEmpty) {
      where.add("TRIM(COALESCE(CAST(ID_VAGAO AS TEXT),'')) = TRIM(?)");
      args.add(vag);
    }

    final rows = await db.query(
      _table,
      where: where.join(" AND "),
      whereArgs: args,
      orderBy: "DATA_REGISTRO DESC",
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return rows.first;
  }

  Future<String> criarAbertoSemFabricacao({
    required String idDieta,
    required String idVagao,
    required double pesoCarregado,
    DateTime? data,
  }) async {
    final db = await _db;
    final dieta = idDieta.trim();
    final vag = idVagao.trim();
    if (dieta.isEmpty) {
      throw Exception("Dieta obrigatoria para carregamento sem fabricacao.");
    }
    if (vag.isEmpty) {
      throw Exception("Vagao nao configurado.");
    }
    if (pesoCarregado <= 0) {
      throw Exception("Peso carregado deve ser maior que zero.");
    }

    await finalizarAbertos(data: data, idVagao: vag);

    final id = _newId();
    await db.insert(_table, {
      "ID": id,
      "DATA_REGISTRO": (data ?? DateTime.now()).toIso8601String(),
      "STATUS": statusAberto,
      "ID_FABRICACAO": "",
      "ID_DIETA": dieta,
      "PESO_FABRICADO": pesoCarregado,
      "PESO_CARREGADO": pesoCarregado,
      "ID_VAGAO": vag,
    });
    return id;
  }

  Future<int> updatePesoCarregadoAberto({
    required String idCarregamento,
    required double pesoCarregado,
  }) async {
    final db = await _db;
    final id = idCarregamento.trim();
    if (id.isEmpty) return 0;

    return db.update(
      _table,
      {
        "PESO_CARREGADO": pesoCarregado,
        "PESO_FABRICADO": pesoCarregado,
      },
      where: "TRIM(ID) = TRIM(?) AND COALESCE(CAST(STATUS AS INTEGER),0) = ?",
      whereArgs: [id, statusAberto],
    );
  }

  /// ✅ Finaliza um carregamento (status=1)
  Future<int> finalizar(String idCarregamento) async {
    final db = await _db;

    final id = idCarregamento.trim();
    if (id.isEmpty) return 0;

    return db.update(
      _table,
      {"STATUS": statusFinalizado},
      where: "TRIM(ID) = TRIM(?)",
      whereArgs: [id],
    );
  }

  Future<int> marcarConsumido(String idCarregamento) =>
      finalizar(idCarregamento);

  Future<int> updatePesoCarregadoAbertoPorFabricacao({
    required String idFabricacao,
    required double pesoCarregado,
    required String idVagao,
  }) async {
    final db = await _db;
    final fab = idFabricacao.trim();
    if (fab.isEmpty) return 0;

    final row = await getAbertoByFabricacao(fab);
    if (row == null) return 0;

    final idCar = (row["ID"] ?? row["id"] ?? "").toString().trim();
    if (idCar.isEmpty) return 0;

    return db.update(
      _table,
      {
        "PESO_CARREGADO": pesoCarregado,
        "ID_VAGAO": idVagao.trim(),
      },
      where: "TRIM(ID) = TRIM(?) AND COALESCE(CAST(STATUS AS INTEGER),0) = ?",
      whereArgs: [idCar, statusAberto],
    );
  }

  Future<void> upsertFromRemote(Map<String, Object?> m) async {
    final db = await _db;

    String s(dynamic v) => (v ?? "").toString().trim();
    double toD(dynamic v) {
      if (v == null) return 0.0;
      if (v is num) return v.toDouble();
      final t = v.toString().replaceAll(",", ".").trim();
      return double.tryParse(t) ?? 0.0;
    }

    final row = {
      "ID": s(m["id"] ?? m["ID"]),
      "DATA_REGISTRO": s(m["dataRegistro"] ?? m["DATA_REGISTRO"]),
      "STATUS": statusAberto,
      "ID_FABRICACAO": s(m["idFabricacao"] ?? m["ID_FABRICACAO"]),
      "ID_DIETA": s(m["idDieta"] ?? m["ID_DIETA"]),
      "PESO_FABRICADO": toD(m["pesoFabricado"] ?? m["PESO_FABRICADO"]),
      "PESO_CARREGADO": toD(m["pesoCarregado"] ?? m["PESO_CARREGADO"]),
      "ID_VAGAO": s(m["idVagao"] ?? m["ID_VAGAO"]),
    };

    if ((row["ID"] ?? "").toString().trim().isEmpty) return;

    await db.insert(
      _table,
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}


