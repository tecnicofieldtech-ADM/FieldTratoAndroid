import "package:sqflite/sqflite.dart";

import "../../../db/app_db.dart";
import "../../fabricacao/domain/fabricacao_flow.dart";

class CarregamentoBridgeRepo {
  Future<Database> get _db async => AppDb.instance.db;

  Future<List<Map<String, Object?>>> listDisponiveis() async {
    final db = await _db;
    return db.rawQuery("""
      SELECT
        f.ID AS id_local,
        COALESCE(f.HANDOFF_ID,'') AS handoff_id,
        substr(COALESCE(f.DATA_FABRICACAO,''),1,10) AS data,
        COALESCE(f.HORA_FIM, f.HORA_INICIO, '') AS hora,
        COALESCE(d.NOME,'') AS nome_racao,
        COALESCE(f.QTD_REALIZADA, 0) AS total_fabricado_kg,
        COALESCE(f.FAB_STATUS,0) AS fab_status
      FROM CADASTRO_FABRICA_RACAO f
      LEFT JOIN DIETA d ON d.ID = f.ID_DIETA
      WHERE COALESCE(f.STATUS,1) = 1
        AND COALESCE(f.FAB_STATUS,0) IN ($fabricacaoStatusPendenteCaminhao, $fabricacaoStatusFinalizada)
      ORDER BY COALESCE(f.DATA_FABRICACAO,'') DESC, COALESCE(f.HORA_FIM, f.HORA_INICIO, '') DESC
    """);
  }

  Future<Map<String, Object?>?> getByFabricacaoId(String idLocal) async {
    final db = await _db;
    final rows = await db.rawQuery(
      """
      SELECT
        f.ID AS id_local,
        f.HANDOFF_ID AS handoff_id,
        f.FAB_STATUS AS fab_status,
        f.DATA_FABRICACAO AS data_fabricacao,
        f.HORA_INICIO AS hora_inicio,
        f.HORA_FIM AS hora_fim,
        f.ID_DIETA AS id_dieta,
        COALESCE(d.NOME,'') AS nome_racao,
        COALESCE(f.QTD_PREVISTA,0) AS qtd_prevista,
        COALESCE(f.QTD_REALIZADA,0) AS qtd_realizada,
        COALESCE(f.FINALIZADA,0) AS finalizada,
        COALESCE(f.EXPORTADO_EM,'') AS exportado_em,
        COALESCE(f.ORIGIN_DEVICE,'ESTACIONARIO') AS origin_device
      FROM CADASTRO_FABRICA_RACAO f
      LEFT JOIN DIETA d ON d.ID = f.ID_DIETA
      WHERE TRIM(COALESCE(f.ID,'')) = TRIM(?)
      LIMIT 1
      """,
      [idLocal],
    );
    if (rows.isEmpty) return null;
    return rows.first;
  }

  Future<List<Map<String, Object?>>> listInsumosFabricacao(String idFabricacao) async {
    final db = await _db;
    return db.rawQuery(
      """
      SELECT
        COALESCE(ID_INSUMO,'') AS id_insumo,
        COALESCE(INSUMO_NOME,'') AS nome_insumo,
        COALESCE(QTD_PREVISTA,0) AS previsto_kg,
        COALESCE(QTD_REALIZADA,0) AS realizado_kg,
        COALESCE(ORDEM,0) AS ordem
      FROM DETALHES_FABRICA_RACAO
      WHERE TRIM(COALESCE(ID_FABRICACAO,'')) = TRIM(?)
      ORDER BY COALESCE(ORDEM,0) ASC
      """,
      [idFabricacao],
    );
  }
}
