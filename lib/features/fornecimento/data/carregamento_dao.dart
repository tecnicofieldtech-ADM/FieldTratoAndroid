// lib/features/fornecimento/data/carregamento_dao.dart
import "package:sqflite/sqflite.dart";
import "../../../db/app_db.dart";

class CarregamentoDao {
  Future<Database> get _db async => AppDb.instance.db;

  // ⚠️ ajuste pro nome real da sua tabela
  static const _table = "CADASTRO_CARREGAMENTO";

  String _pad2(int n) => n.toString().padLeft(2, "0");
  String _toSqlDate(DateTime d) =>
      "${d.year.toString().padLeft(4, '0')}-${_pad2(d.month)}-${_pad2(d.day)}";

  Future<Map<String, Object?>?> getAbertoHoje({DateTime? data}) async {
    final db = await _db;
    final d = _toSqlDate(data ?? DateTime.now());

    final rows = await db.query(
      _table,
      where: "DATA = ? AND COALESCE(STATUS,0) = 0",
      whereArgs: [d],
      limit: 1,
      orderBy: "ROWID DESC",
    );
    if (rows.isEmpty) return null;
    return rows.first;
  }

  Future<Map<String, Object?>?> getAbertoByVagao(String idVagao) async {
    final db = await _db;
    final rows = await db.query(
      _table,
      where: "ID_VAGAO = ? AND COALESCE(STATUS,0) = 0",
      whereArgs: [idVagao],
      limit: 1,
      orderBy: "ROWID DESC",
    );
    if (rows.isEmpty) return null;
    return rows.first;
  }

  Future<Map<String, Object?>?> getAbertoByFabricacao(String idFabricacao) async {
    final db = await _db;
    final rows = await db.query(
      _table,
      where: "ID_FABRICACAO = ? AND COALESCE(STATUS,0) = 0",
      whereArgs: [idFabricacao],
      limit: 1,
      orderBy: "ROWID DESC",
    );
    if (rows.isEmpty) return null;
    return rows.first;
  }
}
