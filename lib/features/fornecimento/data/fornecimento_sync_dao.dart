// lib/features/fornecimento/data/fornecimento_sync_dao.dart
import "package:sqflite/sqflite.dart"; // DatabaseExecutor, ConflictAlgorithm

class FornecimentoSyncDao {
  FornecimentoSyncDao(this.db);

  // ✅ DatabaseExecutor aceita Database OU Transaction
  final DatabaseExecutor db;

  // =========================
  // CREATE TABLES (se precisar)
  // =========================
  static Future<void> ensureTables(DatabaseExecutor db) async {
    await db.execute("""
CREATE TABLE IF NOT EXISTS PREVISAO (
  ID_FORNECIMENTO TEXT,
  DATA TEXT,
  ID_BAIA TEXT,
  TRATO INTEGER,
  PREVISTO_KG REAL,
  REALIZADO_KG REAL,
  ID_RACAO TEXT
);
""");

    await db.execute("""
CREATE TABLE IF NOT EXISTS DETALHES_DIETAS (
  ID TEXT PRIMARY KEY,
  ID_DIETA TEXT,
  ID_INSUMO TEXT,
  INSUMO TEXT,
  MS_INSUMO REAL,
  MS_INCLUSAO REAL,
  MN_PERCENT REAL,
  ORDEM INTEGER,
  PRE_PESADO INTEGER
);
""");

    // (opcional, mas recomendado) índices pra acelerar filtros
    await db.execute("""
CREATE INDEX IF NOT EXISTS IDX_PREVISAO_DATA_TRATO
ON PREVISAO (DATA, TRATO);
""");
    await db.execute("""
CREATE INDEX IF NOT EXISTS IDX_PREVISAO_BAIA
ON PREVISAO (ID_BAIA);
""");
    await db.execute("""
CREATE INDEX IF NOT EXISTS IDX_DET_DIETAS_DIETA
ON DETALHES_DIETAS (ID_DIETA);
""");
  }

  // =========================
  // CLEAR
  // =========================
  Future<void> clearPrevisao() async {
    await db.delete("PREVISAO");
  }

  Future<void> clearDietasDetalhes() async {
    await db.delete("DETALHES_DIETAS");
  }

  // =========================
  // INSERT PREVISAO
  // =========================
  Future<void> insertPrevisao({
    required String idFornecimento,
    required String dataIso, // yyyy-mm-dd
    required String idBaia,
    required int trato,
    required double previstoKg,
    required double realizadoKg,
    required String idRacao,
  }) async {
    await db.insert(
      "PREVISAO",
      {
        "ID_FORNECIMENTO": idFornecimento,
        "DATA": dataIso,
        "ID_BAIA": idBaia,
        "TRATO": trato,
        "PREVISTO_KG": previstoKg,
        "REALIZADO_KG": realizadoKg,
        "ID_RACAO": idRacao,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // =========================
  // UPSERT DETALHES_DIETAS
  // =========================
  Future<void> upsertDietaDetalhe({
    required String id,
    required String idDieta,
    required String idInsumo,
    required String insumo,
    required double msInsumo,
    required double msInclusao,
    required double mnPercent,
    required int ordem,
    required int prePesado, // 0/1
  }) async {
    await db.insert(
      "DETALHES_DIETAS",
      {
        "ID": id,
        "ID_DIETA": idDieta,
        "ID_INSUMO": idInsumo,
        "INSUMO": insumo,
        "MS_INSUMO": msInsumo,
        "MS_INCLUSAO": msInclusao,
        "MN_PERCENT": mnPercent,
        "ORDEM": ordem,
        "PRE_PESADO": prePesado,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}


