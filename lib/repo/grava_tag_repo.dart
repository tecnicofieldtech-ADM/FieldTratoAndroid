import "package:sqflite/sqflite.dart";

import "../db/app_db.dart";
import "../services/rfid_tag_resolver.dart";

class GravaTagCurral {
  GravaTagCurral({
    required this.id,
    required this.nomeLocal,
    required this.linha,
    this.rfid,
    this.idFazenda,
  });

  final String id;
  final String nomeLocal;
  final String linha;
  final String? rfid;
  final String? idFazenda;
}

class GravaTagRepo {
  GravaTagRepo({RfidTagResolver? rfidResolver})
      : _rfidResolver = rfidResolver ?? RfidTagResolver();

  final RfidTagResolver _rfidResolver;

  Future<Database> get _db async => AppDb.instance.db;

  String _s(dynamic v) => (v ?? "").toString().trim();

  Future<void> _ensureGravaTagTable(DatabaseExecutor db) async {
    await db.execute("""
      CREATE TABLE IF NOT EXISTS GRAVA_TAG (
        ID INTEGER PRIMARY KEY AUTOINCREMENT,
        TAG TEXT NOT NULL,
        ID_PASTO_CURRAL TEXT NOT NULL,
        SYNC INTEGER DEFAULT 0
      );
    """);

    await db.execute("""
      CREATE INDEX IF NOT EXISTS IDX_GRAVA_TAG_SYNC
      ON GRAVA_TAG (SYNC);
    """);
  }

  Future<List<String>> listLinhas({String? idFazenda}) async {
    return const [];
  }

  Future<List<GravaTagCurral>> listCurrais({
    String? idFazenda,
    String? linha,
    String? nomeCurral,
  }) async {
    final db = await _db;

    final where = <String>["1=1"];
    final args = <Object?>[];

    final nome = _s(nomeCurral);
    if (nome.isNotEmpty) {
      where.add("UPPER(COALESCE(NOME, '')) LIKE UPPER(?)");
      args.add("%$nome%");
    }

    final rows = await db.query(
      "CADASTRO_CURRAL",
      columns: ["ID", "NOME", "TAG"],
      where: where.join(" AND "),
      whereArgs: args,
      orderBy: "COALESCE(NOME, '') ASC",
    );

    return rows
        .map(
          (r) => GravaTagCurral(
            id: _s(r["ID"]),
            nomeLocal: _s(r["NOME"]),
            linha: "",
            rfid: _s(r["TAG"]).isEmpty ? null : _s(r["TAG"]),
          ),
        )
        .where((e) => e.id.isNotEmpty)
        .toList();
  }

  Future<GravaTagCurral?> findCurralByEpc(
    String epc, {
    String? idFazenda,
  }) async {
    final db = await _db;

    final tag = _s(epc);
    if (tag.isEmpty) return null;

    final rfidMatch = await _rfidResolver.sqlRfidEquals(
      "COALESCE(TAG, '')",
      tag,
    );

    final rows = await db.query(
      "CADASTRO_CURRAL",
      columns: ["ID", "NOME", "TAG"],
      where: rfidMatch.clause,
      whereArgs: rfidMatch.args,
      limit: 1,
    );

    if (rows.isEmpty) return null;
    final r = rows.first;

    return GravaTagCurral(
      id: _s(r["ID"]),
      nomeLocal: _s(r["NOME"]),
      linha: "",
      rfid: _s(r["TAG"]).isEmpty ? null : _s(r["TAG"]),
    );
  }

  Future<void> salvarVinculo({
    required String idCurral,
    required String epc,
  }) async {
    final db = await _db;

    final curral = _s(idCurral);
    final tag = _s(epc);
    if (curral.isEmpty || tag.isEmpty) {
      throw Exception("ID do curral e EPC sao obrigatorios.");
    }

    await db.transaction((txn) async {
      await _ensureGravaTagTable(txn);

      final rfidMatch = await _rfidResolver.sqlRfidEquals(
        "COALESCE(TAG, '')",
        tag,
      );
      final rfidBaia = await _rfidResolver.sqlRfidEquals(
        "COALESCE(RFID, '')",
        tag,
      );

      await txn.update(
        "CADASTRO_CURRAL",
        {"TAG": ""},
        where: rfidMatch.clause,
        whereArgs: rfidMatch.args,
      );
      await txn.update(
        "DETALHES_BAIAS",
        {"RFID": ""},
        where: rfidBaia.clause,
        whereArgs: rfidBaia.args,
      );

      final updated = await txn.update(
        "CADASTRO_CURRAL",
        {"TAG": tag},
        where: "TRIM(ID) = TRIM(?)",
        whereArgs: [curral],
      );
      if (updated == 0) {
        throw Exception("Curral nao encontrado.");
      }
      await txn.update(
        "DETALHES_BAIAS",
        {"RFID": tag},
        where: "TRIM(ID) = TRIM(?)",
        whereArgs: [curral],
      );

      await txn.insert("GRAVA_TAG", {
        "ID_PASTO_CURRAL": curral,
        "TAG": tag,
        "SYNC": 0,
      });
    });
  }

  /// Remove o vínculo RFID do curral (local) para permitir gravar uma nova tag.
  Future<String?> limparVinculo({required String idCurral}) async {
    final db = await _db;
    final curral = _s(idCurral);
    if (curral.isEmpty) {
      throw Exception("ID do curral e obrigatorio.");
    }

    String? tagRemovida;

    await db.transaction((txn) async {
      final rows = await txn.query(
        "CADASTRO_CURRAL",
        columns: ["TAG"],
        where: "TRIM(ID) = TRIM(?)",
        whereArgs: [curral],
        limit: 1,
      );

      if (rows.isEmpty) {
        throw Exception("Curral nao encontrado.");
      }

      final atual = _s(rows.first["TAG"]);
      if (atual.isEmpty) return;
      tagRemovida = atual;

      await txn.update(
        "CADASTRO_CURRAL",
        {"TAG": ""},
        where: "TRIM(ID) = TRIM(?)",
        whereArgs: [curral],
      );
      await txn.update(
        "DETALHES_BAIAS",
        {"RFID": ""},
        where: "TRIM(ID) = TRIM(?)",
        whereArgs: [curral],
      );
    });

    return tagRemovida?.trim().isEmpty == true ? null : tagRemovida?.trim();
  }
}
