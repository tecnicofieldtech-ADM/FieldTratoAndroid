// lib/features/espelho/data/mirror_targets_repo.dart
import "package:sqflite/sqflite.dart";

import "../../../db/app_db.dart";
import "../domain/mirror_target.dart";

class MirrorTargetsRepo {
  Future<Database> get _db async => AppDb.instance.db;

  String _norm(String v) => v.trim();

  // =========================
  // LISTAGEM
  // =========================
  Future<List<MirrorTarget>> listAll() async {
    final db = await _db;
    final rows = await db.rawQuery("""
      SELECT id, nome, host, porta, ativo
      FROM mirror_targets
      ORDER BY ativo DESC, nome ASC
    """);
    return rows.map((r) => MirrorTarget.fromMap(r)).toList();
  }

  Future<MirrorTarget?> getById(int id) async {
    final db = await _db;
    final rows = await db.rawQuery("""
      SELECT id, nome, host, porta, ativo
      FROM mirror_targets
      WHERE id = ?
      LIMIT 1
    """, [id]);
    if (rows.isEmpty) return null;
    return MirrorTarget.fromMap(rows.first);
  }

  Future<MirrorTarget?> getActive() async {
    final db = await _db;
    final rows = await db.rawQuery("""
      SELECT id, nome, host, porta, ativo
      FROM mirror_targets
      WHERE ativo = 1
      ORDER BY id DESC
      LIMIT 1
    """);
    if (rows.isEmpty) return null;
    return MirrorTarget.fromMap(rows.first);
  }

  // =========================
  // INSERT / UPDATE / DELETE
  // =========================
  Future<int> insert({
    required String nome,
    required String host,
    required int porta,
    int ativo = 0,
  }) async {
    final db = await _db;

    final n = _norm(nome);
    final h = _norm(host);
    final p = porta <= 0 ? 9000 : porta;

    if (n.isEmpty) throw Exception("Nome inválido");
    if (h.isEmpty) throw Exception("Host/IP inválido");

    final now = DateTime.now().toIso8601String();

    return db.rawInsert("""
      INSERT INTO mirror_targets (nome, host, porta, ativo, datareg, dataalteracao)
      VALUES (?, ?, ?, ?, ?, ?)
    """, [n, h, p, ativo, now, null]);
  }

  Future<int> update({
    required int id,
    required String nome,
    required String host,
    required int porta,
  }) async {
    final db = await _db;

    final n = _norm(nome);
    final h = _norm(host);
    final p = porta <= 0 ? 9000 : porta;

    if (id <= 0) throw Exception("ID inválido");
    if (n.isEmpty) throw Exception("Nome inválido");
    if (h.isEmpty) throw Exception("Host/IP inválido");

    final now = DateTime.now().toIso8601String();

    return db.rawUpdate("""
      UPDATE mirror_targets
      SET nome = ?, host = ?, porta = ?, dataalteracao = ?
      WHERE id = ?
    """, [n, h, p, now, id]);
  }

  Future<int> remove(int id) async {
    final db = await _db;
    if (id <= 0) return 0;
    return db.rawDelete("DELETE FROM mirror_targets WHERE id = ?", [id]);
  }

  // =========================
  // ATIVO (selecionado)
  // =========================
  Future<void> setActive(int id) async {
    final db = await _db;
    if (id <= 0) return;

    final now = DateTime.now().toIso8601String();

    await db.transaction((txn) async {
      // desativa todos
      await txn.rawUpdate("""
        UPDATE mirror_targets
        SET ativo = 0, dataalteracao = ?
        WHERE ativo <> 0
      """, [now]);

      // ativa o escolhido
      await txn.rawUpdate("""
        UPDATE mirror_targets
        SET ativo = 1, dataalteracao = ?
        WHERE id = ?
      """, [now, id]);
    });
  }
}
