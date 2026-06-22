// lib/features/fornecimento/data/carregamento_dao.dart
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


