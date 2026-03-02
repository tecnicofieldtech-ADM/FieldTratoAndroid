import "package:sqflite/sqflite.dart";

import "../db/app_db.dart";

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
    final db = await _db;

    final faz = _s(idFazenda);
    final where = <String>["TRIM(COALESCE(LINHA, '')) <> ''"];
    final args = <Object?>[];

    if (faz.isNotEmpty) {
      where.add("TRIM(COALESCE(ID_FAZENDA, '')) = TRIM(?)");
      args.add(faz);
    }

    final rows = await db.query(
      "DETALHES_BAIAS",
      columns: ["LINHA"],
      where: where.join(" AND "),
      whereArgs: args,
      distinct: true,
      orderBy: "LINHA ASC",
    );

    return rows
        .map((r) => _s(r["LINHA"]))
        .where((v) => v.isNotEmpty)
        .toList();
  }

  Future<List<GravaTagCurral>> listCurrais({
    String? idFazenda,
    String? linha,
    String? nomeCurral,
  }) async {
    final db = await _db;

    final where = <String>["1=1"];
    final args = <Object?>[];

    final faz = _s(idFazenda);
    if (faz.isNotEmpty) {
      where.add("TRIM(COALESCE(ID_FAZENDA, '')) = TRIM(?)");
      args.add(faz);
    }

    final lin = _s(linha);
    if (lin.isNotEmpty) {
      where.add("TRIM(COALESCE(LINHA, '')) = TRIM(?)");
      args.add(lin);
    }

    final nome = _s(nomeCurral);
    if (nome.isNotEmpty) {
      where.add("UPPER(COALESCE(NOME_LOCAL, '')) LIKE UPPER(?)");
      args.add("%$nome%");
    }

    final rows = await db.query(
      "DETALHES_BAIAS",
      columns: ["ID", "NOME_LOCAL", "LINHA", "RFID", "ID_FAZENDA"],
      where: where.join(" AND "),
      whereArgs: args,
      orderBy: "COALESCE(LINHA, '') ASC, COALESCE(NOME_LOCAL, '') ASC",
    );

    return rows
        .map(
          (r) => GravaTagCurral(
            id: _s(r["ID"]),
            nomeLocal: _s(r["NOME_LOCAL"]),
            linha: _s(r["LINHA"]),
            rfid: _s(r["RFID"]).isEmpty ? null : _s(r["RFID"]),
            idFazenda: _s(r["ID_FAZENDA"]).isEmpty ? null : _s(r["ID_FAZENDA"]),
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

    final faz = _s(idFazenda);
    final where = <String>["UPPER(TRIM(COALESCE(RFID, ''))) = UPPER(TRIM(?))"];
    final args = <Object?>[tag];

    if (faz.isNotEmpty) {
      where.add("TRIM(COALESCE(ID_FAZENDA, '')) = TRIM(?)");
      args.add(faz);
    }

    final rows = await db.query(
      "DETALHES_BAIAS",
      columns: ["ID", "NOME_LOCAL", "LINHA", "RFID", "ID_FAZENDA"],
      where: where.join(" AND "),
      whereArgs: args,
      limit: 1,
    );

    if (rows.isEmpty) return null;
    final r = rows.first;

    return GravaTagCurral(
      id: _s(r["ID"]),
      nomeLocal: _s(r["NOME_LOCAL"]),
      linha: _s(r["LINHA"]),
      rfid: _s(r["RFID"]).isEmpty ? null : _s(r["RFID"]),
      idFazenda: _s(r["ID_FAZENDA"]).isEmpty ? null : _s(r["ID_FAZENDA"]),
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

      await txn.update(
        "DETALHES_BAIAS",
        {"RFID": ""},
        where: "UPPER(TRIM(COALESCE(RFID, ''))) = UPPER(TRIM(?))",
        whereArgs: [tag],
      );

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
}
