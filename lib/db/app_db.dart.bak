import "package:sqflite/sqflite.dart";
import "package:path/path.dart" as p;

class AppDb {
  static final AppDb instance = AppDb._();
  AppDb._();

  Database? _db;

  Future<Database> get db async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, "rfeed_app.db");

    return openDatabase(
      path,
      version: 4,
      onConfigure: (db) async {
        // importante se você usar FK no futuro
        await db.execute("PRAGMA foreign_keys = ON;");
      },
      onCreate: (db, v) async {
        await _createAll(db);
        await _ensureConfigRow(db); // garante 1 linha
      },
      onUpgrade: (db, oldV, newV) async {
        await _onUpgrade(db, oldV, newV);
        await _ensureConfigRow(db); // se atualizou, garante 1 linha também
      },
    );
  }

  // =========================
  // CREATE ALL TABLES
  // =========================
  Future<void> _createAll(Database db) async {
    // CONFIG (1 linha)
    await db.execute("""
    CREATE TABLE IF NOT EXISTS CONFIG (
      HOST            TEXT,
      PORTA           INTEGER,
      ID_FAZENDA      TEXT,
      TIPO_TRABALHO   INTEGER,
      HOST_BALANCA    TEXT,
      MODELO_BALANCA  INTEGER,
      HOST_RFID       TEXT,
      PORTA_BALANCA   INTEGER,
      PORTA_RFID      INTEGER,
      MODELO_RFID     INTEGER,
      BACKEND         INTEGER,
      ID_VAGAO        TEXT,
      NOME_VAGAO      TEXT,
      IP_ESPELHO      TEXT,

      PULO_AUTOMATICO INTEGER DEFAULT 1,
      TEMPO_EM_SEGUNDOS_PULO INTEGER DEFAULT 10,
      INCREMENTO_PESO INTEGER DEFAULT 1,
      TEMPO_MISTURA INTEGER,
      TOLERANCIA_CARREGAMENTO NUMERIC DEFAULT 0
    );
    """);

    // USUÁRIOS
    await db.execute("""
    CREATE TABLE IF NOT EXISTS CADASTRO_USUARIO (
      ID         TEXT PRIMARY KEY NOT NULL,
      NOME       TEXT,
      LOGIN      TEXT,
      SENHA      TEXT,
      CARGO      TEXT,
      ID_FAZENDA TEXT NOT NULL
    );
    """);

    await db.execute("""
    CREATE INDEX IF NOT EXISTS IDX_USUARIO_FAZENDA
    ON CADASTRO_USUARIO (ID_FAZENDA);
    """);

    // VAGÃO
    await db.execute("""
    CREATE TABLE IF NOT EXISTS VAGAO (
      ID   TEXT PRIMARY KEY NOT NULL,
      NOME TEXT
    );
    """);

    // FAZENDAS
    await db.execute("""
    CREATE TABLE IF NOT EXISTS CADASTRO_FAZENDAS (
      ID   TEXT PRIMARY KEY NOT NULL,
      NOME TEXT NOT NULL
    );
    """);

    // GRAVA TAG (RFID)
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

    // Tabelas da Fabricação/Fornecimento
    await _createFabricaTables(db);
  }

  Future<void> _createFabricaTables(Database db) async {
    await db.execute("""
    CREATE TABLE IF NOT EXISTS CADASTRO_FABRICA_RACAO (
      ID TEXT PRIMARY KEY NOT NULL,
      ID_DIETA TEXT NOT NULL,
      QTD_PREVISTA NUMERIC NOT NULL,
      QTD_REALIZADA NUMERIC DEFAULT 0,
      DATA_FABRICACAO TEXT NOT NULL,  -- 'YYYY-MM-DD'
      HORA_INICIO TEXT,
      HORA_FIM TEXT,
      TRATO INTEGER NOT NULL,
      FINALIZADA INTEGER NOT NULL DEFAULT 0,
      CARREGADA INTEGER NOT NULL DEFAULT 0,
      ID_OPERADOR TEXT NOT NULL,
      ID_USUARIO TEXT NOT NULL,
      STATUS INTEGER NOT NULL DEFAULT 1,
      FLAG_SYNC INTEGER NOT NULL DEFAULT 0,
      ID_FAZENDA TEXT NOT NULL,
      MS_PREVISTA NUMERIC DEFAULT 0,
      MS_REALIZADA NUMERIC DEFAULT 0
    );
    """);

    await db.execute("""
    CREATE INDEX IF NOT EXISTS IDX_FAB_SYNC
    ON CADASTRO_FABRICA_RACAO (FLAG_SYNC);
    """);
    await db.execute("""
    CREATE INDEX IF NOT EXISTS IDX_FAB_DATA_TRATO
    ON CADASTRO_FABRICA_RACAO (DATA_FABRICACAO, TRATO);
    """);
    await db.execute("""
    CREATE INDEX IF NOT EXISTS IDX_FAB_FAZENDA
    ON CADASTRO_FABRICA_RACAO (ID_FAZENDA);
    """);

    await db.execute("""
    CREATE TABLE IF NOT EXISTS CADASTRO_FORNECIMENTO (
      ID TEXT PRIMARY KEY NOT NULL,
      ID_FORNECIMENTO TEXT NOT NULL,
      ID_FABRICACAO TEXT NOT NULL,
      ID_BAIA TEXT NOT NULL,
      DATA TEXT NOT NULL,               -- 'YYYY-MM-DD'
      HORA_INICIO TEXT,
      PESO_INICIO NUMERIC NOT NULL,
      HORA_FIM TEXT,
      PESO_FIM NUMERIC NOT NULL,
      PREVISTO NUMERIC NOT NULL,
      REALIZADO NUMERIC,                -- pode ser NULL
      FLAG_SYNC INTEGER NOT NULL DEFAULT 0,
      TRATO INTEGER NOT NULL,
      ID_USUARIO TEXT NOT NULL,
      ID_DIETA TEXT
    );
    """);

    await db.execute("""
    CREATE INDEX IF NOT EXISTS IDX_FORN_SYNC
    ON CADASTRO_FORNECIMENTO (FLAG_SYNC);
    """);
    await db.execute("""
    CREATE INDEX IF NOT EXISTS IDX_FORN_DATA
    ON CADASTRO_FORNECIMENTO (DATA);
    """);
    await db.execute("""
    CREATE INDEX IF NOT EXISTS IDX_FORN_BAIA_DATA
    ON CADASTRO_FORNECIMENTO (ID_BAIA, DATA);
    """);

    await db.execute("""
    CREATE TABLE IF NOT EXISTS CARREGAMENTO (
      ID TEXT PRIMARY KEY NOT NULL,
      DATA_REGISTRO TEXT DEFAULT (datetime('now', 'localtime')),
      STATUS INTEGER DEFAULT 0,
      ID_FABRICACAO TEXT,
      ID_DIETA TEXT,
      PESO_FABRICADO NUMERIC,
      PESO_CARREGADO NUMERIC,
      ID_VAGAO TEXT NOT NULL
    );
    """);

    await db.execute("""
    CREATE INDEX IF NOT EXISTS IDX_CARR_STATUS
    ON CARREGAMENTO (STATUS);
    """);
    await db.execute("""
    CREATE INDEX IF NOT EXISTS IDX_CARR_DATA
    ON CARREGAMENTO (DATA_REGISTRO);
    """);
    await db.execute("""
    CREATE INDEX IF NOT EXISTS IDX_CARR_FAB
    ON CARREGAMENTO (ID_FABRICACAO);
    """);

    await db.execute("""
    CREATE TABLE IF NOT EXISTS DETALHES_BAIAS (
      ID TEXT PRIMARY KEY NOT NULL,
      ID_LOTE TEXT NOT NULL,
      NOME_LOCAL TEXT NOT NULL,
      LINHA TEXT NOT NULL,
      ORDER_TRATO INTEGER,
      ID_FAZENDA TEXT NOT NULL,
      RFID TEXT
    );
    """);

    await db.execute("""
    CREATE INDEX IF NOT EXISTS IDX_BAIAS_FAZENDA
    ON DETALHES_BAIAS (ID_FAZENDA);
    """);
    await db.execute("""
    CREATE INDEX IF NOT EXISTS IDX_BAIAS_LOTE
    ON DETALHES_BAIAS (ID_LOTE);
    """);
    await db.execute("""
    CREATE INDEX IF NOT EXISTS IDX_BAIAS_RFID
    ON DETALHES_BAIAS (RFID);
    """);

    await db.execute("""
    CREATE TABLE IF NOT EXISTS DETALHES_DIETAS (
      ID TEXT PRIMARY KEY NOT NULL,
      ID_DIETA TEXT NOT NULL,
      ID_INSUMO TEXT NOT NULL,
      INSUMO TEXT NOT NULL,
      MN_PERCENT NUMERIC NOT NULL,
      ORDEM INTEGER,
      MS_INSUMO NUMERIC,
      MS_INCLUSAO NUMERIC,
      MN_PERC NUMERIC,
      PRE_PESADO INTEGER DEFAULT 0
    );
    """);

    await db.execute("""
    CREATE INDEX IF NOT EXISTS IDX_DET_DIETAS_DIETA
    ON DETALHES_DIETAS (ID_DIETA);
    """);

    await db.execute("""
    CREATE TABLE IF NOT EXISTS DETALHES_FABRICA_RACAO (
      ID TEXT PRIMARY KEY NOT NULL,
      ID_FABRICACAO TEXT NOT NULL,
      ID_INSUMO TEXT NOT NULL,
      QTD_PREVISTA NUMERIC NOT NULL,
      QTD_REALIZADA NUMERIC DEFAULT 0,
      DATA_FABRICACAO TEXT NOT NULL,
      ORDEM INTEGER,
      HORA_INICIO TEXT,
      HORA_FIM TEXT,
      ID_OPERADOR TEXT NOT NULL,
      ID_USUARIO TEXT NOT NULL,
      STATUS INTEGER NOT NULL DEFAULT 1,
      FLAG_SYNC INTEGER NOT NULL DEFAULT 0,
      ID_FAZENDA TEXT NOT NULL,
      INSUMO_NOME TEXT,
      MS_INSUMO NUMERIC,
      MS_INCLUSAO NUMERIC,
      MN_PERC NUMERIC,
      PRE_PESADO INTEGER DEFAULT 0
    );
    """);

    await db.execute("""
    CREATE INDEX IF NOT EXISTS IDX_DET_FAB_FAB
    ON DETALHES_FABRICA_RACAO (ID_FABRICACAO);
    """);
    await db.execute("""
    CREATE INDEX IF NOT EXISTS IDX_DET_FAB_SYNC
    ON DETALHES_FABRICA_RACAO (FLAG_SYNC);
    """);

    await db.execute("""
    CREATE TABLE IF NOT EXISTS DIETA (
      ID TEXT PRIMARY KEY NOT NULL,
      NOME TEXT,
      TIPO TEXT,
      MS NUMERIC,
      ID_FAZENDA TEXT NOT NULL
    );
    """);

    await db.execute("""
    CREATE INDEX IF NOT EXISTS IDX_DIETA_FAZENDA
    ON DIETA (ID_FAZENDA);
    """);

    await db.execute("""
    CREATE TABLE IF NOT EXISTS PREVISAO (
      ID_FORNECIMENTO TEXT PRIMARY KEY NOT NULL,
      DATA TEXT NOT NULL,
      ID_BAIA TEXT NOT NULL,
      TRATO INTEGER NOT NULL,
      PREVISTO_KG NUMERIC NOT NULL,
      REALIZADO_KG NUMERIC DEFAULT 0,
      ID_RACAO TEXT
    );
    """);

    await db.execute("""
    CREATE INDEX IF NOT EXISTS IDX_PREV_DATA_TRATO
    ON PREVISAO (DATA, TRATO);
    """);
    await db.execute("""
    CREATE INDEX IF NOT EXISTS IDX_PREV_BAIA
    ON PREVISAO (ID_BAIA);
    """);

    await db.execute("""
    CREATE TABLE IF NOT EXISTS ULTIMO_LOGIN (
      ID TEXT PRIMARY KEY NOT NULL,
      NOME TEXT NOT NULL,
      LOGIN TEXT,
      SENHA TEXT,
      CARGO TEXT
    );
    """);
  }

  // =========================
  // garante CONFIG com 1 linha
  // =========================
  Future<void> _ensureConfigRow(Database db) async {
    final r = await db.rawQuery("SELECT COUNT(*) c FROM CONFIG");
    final c = (r.first["c"] as int?) ?? 0;
    if (c == 0) {
      await db.insert("CONFIG", {
        "HOST": null,
        "PORTA": null,
        "ID_FAZENDA": null,
        "TIPO_TRABALHO": null,
        "HOST_BALANCA": null,
        "MODELO_BALANCA": null,
        "HOST_RFID": null,
        "PORTA_BALANCA": null,
        "PORTA_RFID": null,
        "MODELO_RFID": null,
        "BACKEND": null,
        "ID_VAGAO": null,
        "NOME_VAGAO": null,
        "IP_ESPELHO": null,
        "PULO_AUTOMATICO": 1,
        "TEMPO_EM_SEGUNDOS_PULO": 10,
        "INCREMENTO_PESO": 1,
        "TEMPO_MISTURA": null,
        "TOLERANCIA_CARREGAMENTO": 0,
      });
    }
  }

  // =========================
  // helpers upgrade
  // =========================
  Future<void> _addColumnIgnore(Database db, String table, String ddl) async {
    try {
      await db.execute("ALTER TABLE $table ADD COLUMN $ddl");
    } catch (_) {
      // ignora
    }
  }

  // =========================
  // UPGRADE CONTROLADO
  // =========================
  Future<void> _onUpgrade(Database db, int oldV, int newV) async {
    // v2: GRAVA_TAG
    if (oldV < 2) {
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

    // v3: tabelas fabricação
    if (oldV < 3) {
      await _createFabricaTables(db);
    }

    // v4: novas colunas de config
    if (oldV < 4) {
      await _addColumnIgnore(db, "CONFIG", "PULO_AUTOMATICO INTEGER DEFAULT 1");
      await _addColumnIgnore(
          db, "CONFIG", "TEMPO_EM_SEGUNDOS_PULO INTEGER DEFAULT 10");
      await _addColumnIgnore(db, "CONFIG", "INCREMENTO_PESO INTEGER DEFAULT 1");
      await _addColumnIgnore(db, "CONFIG", "TEMPO_MISTURA INTEGER");
      await _addColumnIgnore(
          db, "CONFIG", "TOLERANCIA_CARREGAMENTO NUMERIC DEFAULT 0");
    }
  }
}
