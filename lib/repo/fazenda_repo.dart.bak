import "package:sqflite/sqflite.dart";
import "../db/app_db.dart";

class FazendaRepo {
  Future<List<Map<String, Object?>>> listAll() async {
    final db = await AppDb.instance.db;
    return db.query("CADASTRO_FAZENDAS", orderBy: "NOME");
  }

  Future<void> replaceAll(List<Map<String, Object?>> items) async {
    final db = await AppDb.instance.db;
    await db.transaction((txn) async {
      await txn.delete("CADASTRO_FAZENDAS");
      for (final it in items) {
        await txn.insert(
          "CADASTRO_FAZENDAS",
          it,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }
}
