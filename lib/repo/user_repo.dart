import "../db/app_db.dart";

class UserRepo {
  Future<bool> hasAnyUser() async {
    final db = await AppDb.instance.db;
    final rows = await db.rawQuery("SELECT 1 FROM CADASTRO_USUARIO LIMIT 1");
    return rows.isNotEmpty;
  }

  Future<List<Map<String, Object?>>> listAll() async {
    final db = await AppDb.instance.db;
    return db.query(
      "CADASTRO_USUARIO",
      columns: ["ID", "NOME", "LOGIN", "SENHA", "CARGO", "ID_FAZENDA"],
      orderBy: "NOME COLLATE NOCASE",
    );
  }

  Future<Map<String, Object?>?> findById(String id) async {
    final db = await AppDb.instance.db;
    final rows = await db.query(
      "CADASTRO_USUARIO",
      where: "ID = ?",
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<Map<String, Object?>?> findByLoginSenha(String login, String senha) async {
    final db = await AppDb.instance.db;
    final rows = await db.query(
      "CADASTRO_USUARIO",
      where: "LOGIN = ? AND SENHA = ?",
      whereArgs: [login, senha],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }
}


