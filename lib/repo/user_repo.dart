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

  /// TGC: só quem o SQL de CAD_FUNCIONARIO marcou OPERADOR='1'
  /// (cargos OPERADOR DE PA / OPERADOR / PASEIRO / OPERADOR PÁ).
  /// Aceita também o texto do cargo, caso a sync antiga tenha gravado o nome.
  Future<List<Map<String, Object?>>> listOperadoresPa() async {
    final all = await listAll();
    return all.where((u) => isOperadorPa(u["CARGO"])).toList();
  }

  static bool isOperadorPa(Object? cargo) {
    final raw = (cargo ?? "").toString().trim();
    if (raw == "1") return true;
    switch (raw.toUpperCase()) {
      case "OPERADOR":
      case "OPERADOR DE PA":
      case "OPERADOR DE PÁ":
      case "OPERADOR PA":
      case "OPERADOR PÁ":
      case "PASEIRO":
        return true;
      default:
        return false;
    }
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


