import "package:sqflite/sqflite.dart";
import "../db/app_db.dart";

class VagaoRepo {
  Future<List<Map<String, Object?>>> listAll() async {
    final db = await AppDb.instance.db;
    return db.query("vagao", orderBy: "NOME");
  }

  Future<void> replaceAll(List<Map<String, Object?>> items) async {
    final db = await AppDb.instance.db;
    await db.transaction((txn) async {
      await txn.delete("vagao");
      for (final it in items) {
        await txn.insert(
          "vagao",
          it,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }
}


