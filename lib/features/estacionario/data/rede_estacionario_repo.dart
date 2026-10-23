import "package:sqflite/sqflite.dart";
import "package:uuid/uuid.dart";

import "../../../db/app_db.dart";
import "../domain/rede_estacionario.dart";
import "../domain/station_discovery.dart";

class RedeEstacionarioRepo {
  Future<Database> get _db async => AppDb.instance.db;
  static const _table = "ESTACIONARIO_REDE";
  final _uuid = const Uuid();

  Future<void> _ensureStationIdCol(Database db) async {
    try {
      final cols = await db.rawQuery("PRAGMA table_info($_table)");
      final names = cols
          .map((c) => (c["name"] ?? "").toString().toLowerCase())
          .toSet();
      if (!names.contains("station_id")) {
        await db.execute("ALTER TABLE $_table ADD COLUMN STATION_ID TEXT");
      }
    } catch (_) {}
  }

  Future<List<RedeEstacionario>> listAll() async {
    final db = await _db;
    await _ensureStationIdCol(db);
    final rows = await db.query(
      _table,
      orderBy: "COALESCE(UPDATED_AT, CREATED_AT) DESC",
    );
    return rows.map((e) => RedeEstacionario.fromMap(e)).toList();
  }

  Future<List<RedeEstacionario>> listRecentes({int limit = 8}) async {
    final all = await listAll();
    if (all.length <= limit) return all;
    return all.take(limit).toList();
  }

  Future<RedeEstacionario?> getById(String id) async {
    final db = await _db;
    await _ensureStationIdCol(db);
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
    String stationId = "",
    int ativo = 1,
  }) async {
    final db = await _db;
    await _ensureStationIdCol(db);
    final rid = (id ?? "").trim().isEmpty ? _uuid.v4() : id!.trim();

    final row = <String, Object?>{
      "ID": rid,
      "NOME": nome.trim(),
      "SSID": ssid.trim(),
      "SENHA": senha,
      "HOST_ESTACIONARIO": host.trim(),
      "PORTA_ESTACIONARIO": porta <= 0 ? 8080 : porta,
      "STATION_ID": stationId.trim(),
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

  /// Cache de recente a partir de discovery/seleção (não é fonte da verdade).
  Future<void> touchRecent(DiscoveredStation s) async {
    final db = await _db;
    await _ensureStationIdCol(db);
    final sid = s.stationId.trim();
    if (sid.isEmpty) return;

    final existing = await db.query(
      _table,
      where: "TRIM(COALESCE(STATION_ID,'')) = TRIM(?)",
      whereArgs: [sid],
      limit: 1,
    );

    final id = existing.isEmpty
        ? _uuid.v4()
        : (existing.first["ID"] ?? _uuid.v4()).toString();

    await upsert(
      id: id,
      nome: s.displayName,
      ssid: existing.isEmpty
          ? ""
          : (existing.first["SSID"] ?? "").toString(),
      senha: existing.isEmpty
          ? ""
          : (existing.first["SENHA"] ?? "").toString(),
      host: s.host,
      porta: s.port,
      stationId: sid,
      ativo: 1,
    );
  }

  Future<void> delete(String id) async {
    final db = await _db;
    await db.delete(_table, where: "ID = ?", whereArgs: [id]);
  }
}
