// lib/db/app_db.dart
import "dart:async";
import "package:path/path.dart" as p;
import "package:sqflite/sqflite.dart";

class AppDb {
  AppDb._();
  static final AppDb instance = AppDb._();

  Database? _db;

  Future<Database> get db async {
    final d = _db;
    if (d != null) return d;
    _db = await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final base = await getDatabasesPath();
    final path = p.join(base, "rfeed_pa.db");

    return openDatabase(
      path,
      version: 1,
      onCreate: (db, v) async {
        await db.execute("""
        CREATE TABLE mirror_targets(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          nome TEXT NOT NULL,
          host TEXT NOT NULL,
          porta INTEGER NOT NULL,
          ativo INTEGER NOT NULL DEFAULT 0,
          datareg TEXT NOT NULL,
          dataalteracao TEXT
        );
        """);

        await db.execute(
          "CREATE INDEX idx_targets_ativo ON mirror_targets(ativo);",
        );
      },
      onDowngrade: (db, oldV, newV) async {
        // Keep local data on downgrade in dev builds.
      },
    );
  }

  Future<void> close() async {
    final d = _db;
    _db = null;
    if (d != null) await d.close();
  }
}
