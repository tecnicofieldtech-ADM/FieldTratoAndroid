import "package:flutter_test/flutter_test.dart";
import "package:sqflite_common_ffi/sqflite_ffi.dart";
import "package:field_trato/constants/config_options.dart";
import "package:field_trato/services/planilha_importacao.dart";

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test("migration v16 adiciona IMPORTACAO_ID em fab e forn", () async {
    final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await db.execute(
      "CREATE TABLE CADASTRO_FABRICA_RACAO (ID TEXT PRIMARY KEY NOT NULL)",
    );
    await db.execute(
      "CREATE TABLE CADASTRO_FORNECIMENTO (ID TEXT PRIMARY KEY NOT NULL)",
    );
    await db.execute(
      "ALTER TABLE CADASTRO_FABRICA_RACAO ADD COLUMN IMPORTACAO_ID TEXT",
    );
    await db.execute(
      "ALTER TABLE CADASTRO_FORNECIMENTO ADD COLUMN IMPORTACAO_ID TEXT",
    );

    const cargaA = "imp-a";
    await db.insert("CADASTRO_FABRICA_RACAO", {
      "ID": "fab-1",
      "IMPORTACAO_ID": cargaA,
    });
    await db.insert("CADASTRO_FORNECIMENTO", {
      "ID": "forn-1",
      "IMPORTACAO_ID": cargaA,
    });

    final fab = await db.query("CADASTRO_FABRICA_RACAO", where: "ID=?", whereArgs: ["fab-1"]);
    final forn = await db.query("CADASTRO_FORNECIMENTO", where: "ID=?", whereArgs: ["forn-1"]);
    expect(fab.first["IMPORTACAO_ID"], cargaA);
    expect(forn.first["IMPORTACAO_ID"], cargaA);
    await db.close();
  });

  test("criação local + outbox após troca de carga permanece A", () async {
    final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await db.execute("""
      CREATE TABLE CONFIG (BACKEND INTEGER, IMPORTACAO_ID TEXT)
    """);
    await db.execute("""
      CREATE TABLE CADASTRO_FABRICA_RACAO (
        ID TEXT PRIMARY KEY NOT NULL,
        IMPORTACAO_ID TEXT
      )
    """);
    await db.execute("""
      CREATE TABLE CADASTRO_FORNECIMENTO (
        ID TEXT PRIMARY KEY NOT NULL,
        IMPORTACAO_ID TEXT
      )
    """);

    const cargaA = "carga-a";
    const cargaB = "carga-b";
    await db.insert("CONFIG", {"BACKEND": 3, "IMPORTACAO_ID": cargaA});

    final cfgA = (await db.query("CONFIG")).first;
    final stampA = PlanilhaImportacao.freezeFromConfig(
      backend: int.tryParse("${cfgA["BACKEND"]}"),
      configImportacaoId: cfgA["IMPORTACAO_ID"]?.toString(),
    );
    await db.insert("CADASTRO_FABRICA_RACAO", {
      "ID": "fab-a",
      "IMPORTACAO_ID": stampA,
    });
    await db.insert("CADASTRO_FORNECIMENTO", {
      "ID": "forn-a",
      "IMPORTACAO_ID": stampA,
    });

    await db.update("CONFIG", {"IMPORTACAO_ID": cargaB});

    final fab = (await db.query("CADASTRO_FABRICA_RACAO")).first;
    final forn = (await db.query("CADASTRO_FORNECIMENTO")).first;
    final postFab = PlanilhaImportacao.forOutbox(
      backend: ConfigOptions.backendPlanilha,
      registroImportacaoId: fab["IMPORTACAO_ID"]?.toString(),
    );
    final postForn = PlanilhaImportacao.forOutbox(
      backend: ConfigOptions.backendPlanilha,
      registroImportacaoId: forn["IMPORTACAO_ID"]?.toString(),
    );
    expect(postFab, cargaA);
    expect(postForn, cargaA);
    expect(postFab, isNot(cargaB));
    await db.close();
  });
}
