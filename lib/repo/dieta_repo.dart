import "../db/app_db.dart";

class DietaRepo {
  Future<List<Map<String, Object?>>> listAll({String? idFazenda}) async {
    final db = await AppDb.instance.db;

    if (idFazenda != null && idFazenda.trim().isNotEmpty) {
      return db.query(
        "DIETA",
        columns: ["ID", "NOME", "TIPO", "MS", "ID_FAZENDA"],
        where: "TRIM(COALESCE(ID_FAZENDA, '')) = TRIM(?)",
        whereArgs: [idFazenda.trim()],
        orderBy: "NOME COLLATE NOCASE",
      );
    }

    return db.query(
      "DIETA",
      columns: ["ID", "NOME", "TIPO", "MS", "ID_FAZENDA"],
      orderBy: "NOME COLLATE NOCASE",
    );
  }

  Future<Map<String, Object?>?> findById(String id) async {
    final db = await AppDb.instance.db;
    final rows = await db.query(
      "DIETA",
      where: "ID = ?",
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }
}


