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
      version: 9, // flow estacionario/caminhao + handoff
      onConfigure: (db) async {
        await db.execute("PRAGMA foreign_keys = ON;");
      },
      onCreate: (db, v) async {
        await _createAll(db);
        await _ensureConfigRow(db);
        await _removeReviewerUser(db);
      },
      onUpgrade: (db, oldV, newV) async {
        await _onUpgrade(db, oldV, newV);
        await _ensureConfigRow(db);
        await _removeReviewerUser(db);
      },
      onDowngrade: (db, oldV, newV) async {
        // Avoid automatic data wipe on version downgrade during local builds.
        await _ensureConfigRow(db);
        await _removeReviewerUser(db);
      },
      onOpen: (db) async {
        await _ensureConfigRow(db);
        await _removeReviewerUser(db);
      },
    );
  }

  // =========================
  // CREATE ALL TABLES
  // =========================
  Future<void> _createAll(Database db) async {
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
      ID_VAGAO        TEXT,   -- ✅ UUID do vagão (vem da config)
      NOME_VAGAO      TEXT,
      IP_ESPELHO      TEXT,

      PULO_AUTOMATICO INTEGER DEFAULT 1,
      TEMPO_EM_SEGUNDOS_PULO INTEGER DEFAULT 10,
      INCREMENTO_PESO INTEGER DEFAULT 1,
      TEMPO_MISTURA INTEGER,
      TOLERANCIA_CARREGAMENTO NUMERIC DEFAULT 0,
      FLOW_MODE INTEGER DEFAULT 0,
      STATION_WIFI_SSID TEXT,
      STATION_WIFI_PASSWORD TEXT,
      STATION_BASE_URL TEXT,
      STATION_BASE_URL_LEGACY TEXT,

      -- ✅ NOVO: tolerância em KG (ConfigRepo já garante, mas aqui nasce certo)
      TOLERANCIA_CARREGAMENTO_KG NUMERIC DEFAULT 0
    );
    """);

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

    await db.execute("""
    CREATE TABLE IF NOT EXISTS VAGAO (
      ID   TEXT PRIMARY KEY NOT NULL,
      NOME TEXT
    );
    """);

    await db.execute("""
    CREATE TABLE IF NOT EXISTS ESTACIONARIO_REDE (
      ID TEXT PRIMARY KEY NOT NULL,
      NOME TEXT,
      SSID TEXT NOT NULL,
      SENHA TEXT,
      HOST_ESTACIONARIO TEXT NOT NULL,
      PORTA_ESTACIONARIO INTEGER NOT NULL DEFAULT 8080,
      ATIVO INTEGER NOT NULL DEFAULT 1,
      CREATED_AT TEXT DEFAULT (datetime('now', 'localtime')),
      UPDATED_AT TEXT
    );
    """);

    await db.execute("""
    CREATE INDEX IF NOT EXISTS IDX_EST_REDE_ATIVO
    ON ESTACIONARIO_REDE (ATIVO);
    """);

    await db.execute("""
    CREATE UNIQUE INDEX IF NOT EXISTS UQ_EST_REDE_SSID_HOST_PORTA
    ON ESTACIONARIO_REDE (SSID, HOST_ESTACIONARIO, PORTA_ESTACIONARIO);
    """);

    await db.execute("""
    CREATE TABLE IF NOT EXISTS CADASTRO_FAZENDAS (
      ID   TEXT PRIMARY KEY NOT NULL,
      NOME TEXT NOT NULL
    );
    """);

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

    await _createFabricaTables(db);
  }

  Future<void> _createFabricaTables(Database db) async {
    await db.execute("""
    CREATE TABLE IF NOT EXISTS CADASTRO_FABRICA_RACAO (
      ID TEXT PRIMARY KEY NOT NULL,
      ID_DIETA TEXT NOT NULL,
      QTD_PREVISTA NUMERIC NOT NULL,
      QTD_REALIZADA NUMERIC DEFAULT 0,
      DATA_FABRICACAO TEXT NOT NULL,
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
      ORIGEM TEXT,
      ID_ORIGEM_ESTACIONARIO TEXT,
      FAB_STATUS INTEGER NOT NULL DEFAULT 0,
      HANDOFF_ID TEXT,
      EXPORTADO_EM TEXT,
      ORIGIN_DEVICE TEXT,
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
    CREATE INDEX IF NOT EXISTS IDX_FAB_FLOW_STATUS
    ON CADASTRO_FABRICA_RACAO (FAB_STATUS);
    """);

    await db.execute("""
    CREATE UNIQUE INDEX IF NOT EXISTS UQ_FAB_HANDOFF_ID
    ON CADASTRO_FABRICA_RACAO (HANDOFF_ID)
    WHERE HANDOFF_ID IS NOT NULL AND TRIM(HANDOFF_ID) <> '';
    """);

    await db.execute("""
    CREATE TABLE IF NOT EXISTS CADASTRO_FORNECIMENTO (
      ID TEXT PRIMARY KEY NOT NULL,
      ID_FORNECIMENTO TEXT NOT NULL,
      ID_FABRICACAO TEXT NOT NULL,
      ID_BAIA TEXT NOT NULL,
      DATA TEXT NOT NULL,
      HORA_INICIO TEXT,
      PESO_INICIO NUMERIC NOT NULL,
      HORA_FIM TEXT,
      PESO_FIM NUMERIC NOT NULL,
      PREVISTO NUMERIC NOT NULL,
      REALIZADO NUMERIC,
      FLAG_SYNC INTEGER NOT NULL DEFAULT 0,
      TRATO INTEGER NOT NULL,
      ID_USUARIO TEXT NOT NULL,
      ID_DIETA TEXT,
      MAPA INTEGER DEFAULT 0
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
      ID_VAGAO TEXT
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

    // ✅ CORRIGIDO: PREVISAO com PK composta (ID_FORNECIMENTO + DATA + ID_BAIA + TRATO)
    await db.execute("""
    CREATE TABLE IF NOT EXISTS PREVISAO (
      ID_FORNECIMENTO TEXT NOT NULL,
      DATA TEXT NOT NULL,
      ID_BAIA TEXT NOT NULL,
      TRATO INTEGER NOT NULL,
      PREVISTO_KG NUMERIC NOT NULL,
      REALIZADO_KG NUMERIC DEFAULT 0,
      ID_RACAO TEXT,
      PRIMARY KEY (ID_FORNECIMENTO, DATA, ID_BAIA, TRATO)
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
    CREATE INDEX IF NOT EXISTS IDX_PREV_IDFORN
    ON PREVISAO (ID_FORNECIMENTO);
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

  Future<void> _ensureConfigRow(Database db) async {
    final r = await db.rawQuery("SELECT COUNT(*) c FROM CONFIG");
    final c = (r.first["c"] as int?) ?? 0;
    if (c == 0) {
      await db.insert("CONFIG", {
        "HOST": null,
        "PORTA": 9100,
        "ID_FAZENDA": null,
        "TIPO_TRABALHO": null,
        "HOST_BALANCA": "10.10.100.254",
        "MODELO_BALANCA": null,
        "HOST_RFID": "10.10.100.250",
        "PORTA_BALANCA": 8899,
        "PORTA_RFID": 5000,
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
        "TOLERANCIA_CARREGAMENTO_KG": 0,
        "FLOW_MODE": 0,
        "STATION_WIFI_SSID": null,
        "STATION_WIFI_PASSWORD": null,
        "STATION_BASE_URL": null,
      });
    }
  }

  Future<void> _removeReviewerUser(Database db) async {
    try {
      await db.delete(
        "CADASTRO_USUARIO",
        where: "ID = ? OR LOGIN = ?",
        whereArgs: ["PLAY_REVIEW_DEMO", "playreview"],
      );
    } catch (_) {}
  }

  Future<void> _addColumnIgnore(Database db, String table, String ddl) async {
    try {
      await db.execute("ALTER TABLE $table ADD COLUMN $ddl");
    } catch (_) {}
  }

  Future<void> _onUpgrade(Database db, int oldV, int newV) async {
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

    if (oldV < 3) {
      await _createFabricaTables(db);
    }

    if (oldV < 4) {
      await _addColumnIgnore(db, "CONFIG", "PULO_AUTOMATICO INTEGER DEFAULT 1");
      await _addColumnIgnore(
        db,
        "CONFIG",
        "TEMPO_EM_SEGUNDOS_PULO INTEGER DEFAULT 10",
      );
      await _addColumnIgnore(db, "CONFIG", "INCREMENTO_PESO INTEGER DEFAULT 1");
      await _addColumnIgnore(db, "CONFIG", "TEMPO_MISTURA INTEGER");
      await _addColumnIgnore(
        db,
        "CONFIG",
        "TOLERANCIA_CARREGAMENTO NUMERIC DEFAULT 0",
      );
    }

    if (oldV < 5) {
      try {
        await db.execute("ALTER TABLE CARREGAMENTO RENAME TO CARREGAMENTO_OLD");
        await db.execute("""
        CREATE TABLE CARREGAMENTO (
          ID TEXT PRIMARY KEY NOT NULL,
          DATA_REGISTRO TEXT DEFAULT (datetime('now', 'localtime')),
          STATUS INTEGER DEFAULT 1,
          ID_FABRICACAO TEXT,
          ID_DIETA TEXT,
          PESO_FABRICADO NUMERIC,
          PESO_CARREGADO NUMERIC,
          ID_VAGAO TEXT
        );
        """);
        await db.execute("""
        INSERT INTO CARREGAMENTO (
          ID, DATA_REGISTRO, STATUS, ID_FABRICACAO, ID_DIETA,
          PESO_FABRICADO, PESO_CARREGADO, ID_VAGAO
        )
        SELECT
          ID, DATA_REGISTRO, STATUS, ID_FABRICACAO, ID_DIETA,
          PESO_FABRICADO, PESO_CARREGADO, ID_VAGAO
        FROM CARREGAMENTO_OLD;
        """);
        await db.execute("DROP TABLE CARREGAMENTO_OLD");
      } catch (_) {}
    }

    // ✅ v6: Corrige PK da PREVISAO + adiciona TOLERANCIA_CARREGAMENTO_KG
    if (oldV < 6) {
      await _addColumnIgnore(
        db,
        "CONFIG",
        "TOLERANCIA_CARREGAMENTO_KG NUMERIC DEFAULT 0",
      );

      // Migração segura da PREVISAO para PK composta
      try {
        await db.execute("ALTER TABLE PREVISAO RENAME TO PREVISAO_OLD");

        await db.execute("""
        CREATE TABLE PREVISAO (
          ID_FORNECIMENTO TEXT NOT NULL,
          DATA TEXT NOT NULL,
          ID_BAIA TEXT NOT NULL,
          TRATO INTEGER NOT NULL,
          PREVISTO_KG NUMERIC NOT NULL,
          REALIZADO_KG NUMERIC DEFAULT 0,
          ID_RACAO TEXT,
          PRIMARY KEY (ID_FORNECIMENTO, DATA, ID_BAIA, TRATO)
        );
        """);

        // Copia o que der (se existirem duplicados, a PK antiga já teria impedido)
        await db.execute("""
        INSERT OR IGNORE INTO PREVISAO (
          ID_FORNECIMENTO, DATA, ID_BAIA, TRATO, PREVISTO_KG, REALIZADO_KG, ID_RACAO
        )
        SELECT
          ID_FORNECIMENTO, DATA, ID_BAIA, TRATO, PREVISTO_KG, REALIZADO_KG, ID_RACAO
        FROM PREVISAO_OLD;
        """);

        await db.execute("DROP TABLE PREVISAO_OLD");

        await db.execute("""
        CREATE INDEX IF NOT EXISTS IDX_PREV_DATA_TRATO
        ON PREVISAO (DATA, TRATO);
        """);

        await db.execute("""
        CREATE INDEX IF NOT EXISTS IDX_PREV_BAIA
        ON PREVISAO (ID_BAIA);
        """);

        await db.execute("""
        CREATE INDEX IF NOT EXISTS IDX_PREV_IDFORN
        ON PREVISAO (ID_FORNECIMENTO);
        """);
      } catch (_) {
        // se falhar, não derruba o app
      }
    }

    if (oldV < 7) {
      await _addColumnIgnore(
        db,
        "CADASTRO_FORNECIMENTO",
        "MAPA INTEGER DEFAULT 0",
      );
    }

    if (oldV < 8) {
      await _addColumnIgnore(db, "CADASTRO_FABRICA_RACAO", "ORIGEM TEXT");
      await _addColumnIgnore(
        db,
        "CADASTRO_FABRICA_RACAO",
        "ID_ORIGEM_ESTACIONARIO TEXT",
      );

      await db.execute("""
      CREATE TABLE IF NOT EXISTS ESTACIONARIO_REDE (
        ID TEXT PRIMARY KEY NOT NULL,
        NOME TEXT,
        SSID TEXT NOT NULL,
        SENHA TEXT,
        HOST_ESTACIONARIO TEXT NOT NULL,
        PORTA_ESTACIONARIO INTEGER NOT NULL DEFAULT 8080,
        ATIVO INTEGER NOT NULL DEFAULT 1,
        CREATED_AT TEXT DEFAULT (datetime('now', 'localtime')),
        UPDATED_AT TEXT
      );
      """);

      await db.execute("""
      CREATE INDEX IF NOT EXISTS IDX_EST_REDE_ATIVO
      ON ESTACIONARIO_REDE (ATIVO);
      """);

      await db.execute("""
      CREATE UNIQUE INDEX IF NOT EXISTS UQ_EST_REDE_SSID_HOST_PORTA
      ON ESTACIONARIO_REDE (SSID, HOST_ESTACIONARIO, PORTA_ESTACIONARIO);
      """);
    }

    if (oldV < 9) {
      await _addColumnIgnore(db, "CONFIG", "FLOW_MODE INTEGER DEFAULT 0");
      await _addColumnIgnore(db, "CONFIG", "STATION_WIFI_SSID TEXT");
      await _addColumnIgnore(db, "CONFIG", "STATION_WIFI_PASSWORD TEXT");
      await _addColumnIgnore(db, "CONFIG", "STATION_BASE_URL TEXT");
      await _addColumnIgnore(db, "CONFIG", "STATION_BASE_URL_LEGACY TEXT");

      await _addColumnIgnore(
        db,
        "CADASTRO_FABRICA_RACAO",
        "FAB_STATUS INTEGER NOT NULL DEFAULT 0",
      );
      await _addColumnIgnore(db, "CADASTRO_FABRICA_RACAO", "HANDOFF_ID TEXT");
      await _addColumnIgnore(db, "CADASTRO_FABRICA_RACAO", "EXPORTADO_EM TEXT");
      await _addColumnIgnore(db, "CADASTRO_FABRICA_RACAO", "ORIGIN_DEVICE TEXT");

      await db.execute("""
      CREATE INDEX IF NOT EXISTS IDX_FAB_FLOW_STATUS
      ON CADASTRO_FABRICA_RACAO (FAB_STATUS);
      """);

      await db.execute("""
      CREATE UNIQUE INDEX IF NOT EXISTS UQ_FAB_HANDOFF_ID
      ON CADASTRO_FABRICA_RACAO (HANDOFF_ID)
      WHERE HANDOFF_ID IS NOT NULL AND TRIM(HANDOFF_ID) <> '';
      """);
    }
  }
}
