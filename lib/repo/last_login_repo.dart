import "package:sqflite/sqflite.dart";

import "../db/app_db.dart";
import "../features/fornecimento/data/fornecimento_tables.dart";
import "session_repo.dart";

/// Persiste o último usuário que fez login (tabela ULTIMO_LOGIN).
class LastLoginRepo {
  final SessionRepo _sessionRepo = SessionRepo();

  Future<Database> get _db async => AppDb.instance.db;

  Future<String?> getLastUserId() async {
    final db = await _db;
    final rows = await db.rawQuery(
      "SELECT ID FROM ${FornTables.ultimoLogin} LIMIT 1",
    );
    if (rows.isNotEmpty) {
      final id = (rows.first["ID"] ?? "").toString().trim();
      if (id.isNotEmpty) return id;
    }

    return _sessionRepo.getLastUserId();
  }

  Future<void> save({
    required String userId,
    required String nome,
    required String login,
    String? cargo,
  }) async {
    final db = await _db;

    await db.delete(FornTables.ultimoLogin);

    await db.insert(
      FornTables.ultimoLogin,
      {
        "ID": userId,
        "NOME": nome,
        "LOGIN": login,
        "SENHA": "",
        "CARGO": cargo ?? "",
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
