import "package:sqflite/sqflite.dart";
import "package:uuid/uuid.dart";

import "../../../db/app_db.dart";
import "../domain/rede_estacionario.dart";

class RedeEstacionarioRepo {
  Future<Database> get _db async => AppDb.instance.db;
  static const _table = "ESTACIONARIO_REDE";
  final _uuid = const Uuid();

  Future<List<RedeEstacionario>> listAll() async {
    final db = await _db;
    final rows = await db.query(_table, orderBy: "COALESCE(NOME,SSID) ASC");
    return rows.map((e) => RedeEstacionario.fromMap(e)).toList();
  }

  Future<RedeEstacionario?> getById(String id) async {
    final db = await _db;
    final rows =
        await db.query(_table, where: "ID = ?", whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return RedeEstacionario.fromMap(rows.first);
  }

  Future<String> upsert({
    String? id,
    required String nome,
    required String ssid,
    required String senha,
    required String host,
    required int porta,
    int ativo = 1,
  }) async {
    final db = await _db;
    final rid = (id ?? "").trim().isEmpty ? _uuid.v4() : id!.trim();

    final row = <String, Object?>{
      "ID": rid,
      "NOME": nome.trim(),
      "SSID": ssid.trim(),
      "SENHA": senha,
      "HOST_ESTACIONARIO": host.trim(),
      "PORTA_ESTACIONARIO": porta <= 0 ? 8080 : porta,
      "ATIVO": ativo == 0 ? 0 : 1,
      "UPDATED_AT": DateTime.now().toIso8601String(),
    };

    await db.insert(
      _table,
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    return rid;
  }

  Future<void> delete(String id) async {
    final db = await _db;
    await db.delete(_table, where: "ID = ?", whereArgs: [id]);
  }
}
