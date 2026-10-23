import "package:sqflite/sqflite.dart";

import "package:flutter/foundation.dart";

import "../../../db/app_db.dart";
import "../../fabricacao/domain/fabricacao_flow.dart";
import "../domain/station_claim.dart";
import "../domain/station_handoff_mode.dart";
import "carregamento_claim_store.dart";

class CarregamentoBridgeRepo {
  CarregamentoBridgeRepo({Database? db}) : _injected = db;

  final Database? _injected;

  Future<Database> get _db async {
    final injected = _injected;
    if (injected != null) return injected;
    return AppDb.instance.db;
  }

  Future<CarregamentoClaimStore> _claimStore() async {
    final db = await _db;
    final store = CarregamentoClaimStore(db);
    await store.ensureColumns();
    return store;
  }

  Future<List<Map<String, Object?>>> listDisponiveis({
    String? truckDeviceId,
  }) async {
    final db = await _db;
    await (await _claimStore()).ensureColumns();
    final now = DateTime.now();
    // Etapa E: PENDENTE_CAMINHAO OU FINALIZADA (consistente), ainda não CARREGADA.
    final rows = await db.rawQuery("""
      SELECT
        f.ID AS id_local,
        COALESCE(f.HANDOFF_ID,'') AS handoff_id,
        substr(COALESCE(f.DATA_FABRICACAO,''),1,10) AS data,
        COALESCE(f.HORA_FIM, f.HORA_INICIO, '') AS hora,
        COALESCE(d.NOME,'') AS nome_racao,
        COALESCE(f.QTD_REALIZADA, 0) AS total_fabricado_kg,
        COALESCE(f.FAB_STATUS,0) AS fab_status,
        COALESCE(f.FINALIZADA,0) AS finalizada,
        COALESCE(f.CLAIM_DEVICE_ID,'') AS claim_device_id,
        COALESCE(f.CLAIM_EXPIRES_AT,'') AS claim_expires_at
      FROM CADASTRO_FABRICA_RACAO f
      LEFT JOIN DIETA d ON d.ID = f.ID_DIETA
      WHERE COALESCE(f.STATUS,1) = 1
        AND COALESCE(f.CARREGADA,0) = 0
        AND (
          (
            COALESCE(f.FAB_STATUS,0) = $fabricacaoStatusPendenteCaminhao
            AND COALESCE(f.FINALIZADA,0) = 0
          )
          OR
          (
            COALESCE(f.FAB_STATUS,0) = $fabricacaoStatusFinalizada
            AND COALESCE(f.FINALIZADA,0) = 1
          )
        )
      ORDER BY COALESCE(f.DATA_FABRICACAO,'') DESC, COALESCE(f.HORA_FIM, f.HORA_INICIO, '') DESC
    """);

    final viewer = (truckDeviceId ?? "").trim();
    final out = <Map<String, Object?>>[];
    for (final m in rows) {
      final mode = resolveStationHandoffMode(
        fabStatus: m["fab_status"],
        finalizada: m["finalizada"],
      );
      if (mode == null) {
        debugPrint(
          "[BRIDGE_LIST] skip inconsistente id=${m["id_local"]} "
          "fab=${m["fab_status"]} fin=${m["finalizada"]}",
        );
        continue;
      }

      final row = Map<String, Object?>.from(m);
      final status = StationClaim.listStatus(
        claimDeviceId: (m["claim_device_id"] ?? "").toString(),
        claimExpiresAt: (m["claim_expires_at"] ?? "").toString(),
        now: now,
        viewerTruckDeviceId: viewer.isEmpty ? null : viewer,
      );
      row["claim_status"] = status;
      final exp = (m["claim_expires_at"] ?? "").toString();
      row["claim_expires_at"] =
          status == StationClaim.statusAvailable ? "" : exp;
      row["handoff_mode"] = mode.apiValue;
      // Não expor CLAIM_DEVICE_ID do outro device.
      row.remove("claim_device_id");
      out.add(row);
    }
    return out;
  }

  Future<ClaimResult> claim({
    required String idOrHandoff,
    required String truckDeviceId,
    DateTime? now,
  }) async {
    final store = await _claimStore();
    return store.claim(
      idOrHandoff: idOrHandoff,
      truckDeviceId: truckDeviceId,
      now: now,
    );
  }

  Future<ReleaseResult> release({
    required String idOrHandoff,
    required String truckDeviceId,
    DateTime? now,
  }) async {
    final store = await _claimStore();
    return store.release(
      idOrHandoff: idOrHandoff,
      truckDeviceId: truckDeviceId,
      now: now,
    );
  }

  Future<AckResult> ack({
    required String idOrHandoff,
    String? truckDeviceId,
    bool requireClaim = true,
    DateTime? now,
  }) async {
    final store = await _claimStore();
    return store.ack(
      idOrHandoff: idOrHandoff,
      truckDeviceId: truckDeviceId,
      requireClaim: requireClaim,
      now: now,
    );
  }

  /// Legado: marca recebido sem claim (Bridge antigo / clients sem truckDeviceId).
  Future<bool> marcarRecebido(String idLocal) async {
    final r = await ack(
      idOrHandoff: idLocal,
      requireClaim: false,
    );
    return r.ok;
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
         OR TRIM(COALESCE(f.HANDOFF_ID,'')) = TRIM(?)
      LIMIT 1
      """,
      [idLocal, idLocal],
    );
    if (rows.isEmpty) return null;
    return rows.first;
  }

  Future<List<Map<String, Object?>>> listInsumosFabricacao(
    String idFabricacao,
  ) async {
    final db = await _db;
    // Se veio handoff, resolve ID local.
    final fab = await getByFabricacaoId(idFabricacao);
    final id = (fab?["id_local"] ?? idFabricacao).toString();
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
      [id],
    );
  }
}
