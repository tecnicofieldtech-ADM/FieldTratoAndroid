import "package:sqflite/sqflite.dart";

import "../domain/station_claim.dart";

/// Persistência atômica de claim/lease/ack na estação (SQLite).
///
/// Aceita [Database] injetado para testes (sem AppDb singleton).
class CarregamentoClaimStore {
  CarregamentoClaimStore(this.db);

  final Database db;

  Future<void> ensureColumns() async {
    await _addCol("CLAIM_DEVICE_ID TEXT");
    await _addCol("CLAIM_AT TEXT");
    await _addCol("CLAIM_EXPIRES_AT TEXT");
  }

  Future<void> _addCol(String ddl) async {
    try {
      await db.execute("ALTER TABLE CADASTRO_FABRICA_RACAO ADD COLUMN $ddl");
    } catch (_) {}
  }

  /// Resolve por ID local ou HANDOFF_ID.
  Future<Map<String, Object?>?> findByIdOrHandoff(String idOrHandoff) async {
    final key = idOrHandoff.trim();
    if (key.isEmpty) return null;
    final rows = await db.rawQuery(
      """
      SELECT
        ID AS id_local,
        COALESCE(HANDOFF_ID,'') AS handoff_id,
        COALESCE(CARREGADA,0) AS carregada,
        COALESCE(CLAIM_DEVICE_ID,'') AS claim_device_id,
        COALESCE(CLAIM_AT,'') AS claim_at,
        COALESCE(CLAIM_EXPIRES_AT,'') AS claim_expires_at
      FROM CADASTRO_FABRICA_RACAO
      WHERE TRIM(COALESCE(ID,'')) = TRIM(?)
         OR TRIM(COALESCE(HANDOFF_ID,'')) = TRIM(?)
      LIMIT 1
      """,
      [key, key],
    );
    if (rows.isEmpty) return null;
    return Map<String, Object?>.from(rows.first);
  }

  Future<ClaimResult> claim({
    required String idOrHandoff,
    required String truckDeviceId,
    DateTime? now,
  }) async {
    final truck = truckDeviceId.trim();
    if (!StationClaim.isValidTruckDeviceId(truck)) {
      return const ClaimResult(
        outcome: ClaimOutcome.invalid,
        message: "truckDeviceId_invalido",
      );
    }
    final key = idOrHandoff.trim();
    if (key.isEmpty) {
      return const ClaimResult(
        outcome: ClaimOutcome.invalid,
        message: "id_invalido",
      );
    }

    final clock = now ?? DateTime.now();
    final nowIso = StationClaim.nowIso(clock);
    final expIso = StationClaim.expiresIso(clock);

    return db.transaction((txn) async {
      final rows = await txn.rawQuery(
        """
        SELECT
          ID AS id_local,
          COALESCE(HANDOFF_ID,'') AS handoff_id,
          COALESCE(CARREGADA,0) AS carregada,
          COALESCE(CLAIM_DEVICE_ID,'') AS claim_device_id,
          COALESCE(CLAIM_EXPIRES_AT,'') AS claim_expires_at
        FROM CADASTRO_FABRICA_RACAO
        WHERE TRIM(COALESCE(ID,'')) = TRIM(?)
           OR TRIM(COALESCE(HANDOFF_ID,'')) = TRIM(?)
        LIMIT 1
        """,
        [key, key],
      );
      if (rows.isEmpty) {
        return const ClaimResult(
          outcome: ClaimOutcome.notFound,
          message: "fabricacao_nao_encontrada",
        );
      }

      final row = rows.first;
      final idLocal = (row["id_local"] ?? "").toString();
      final handoff = (row["handoff_id"] ?? "").toString();
      final carregada = _toInt(row["carregada"]) ?? 0;
      if (carregada == 1) {
        return ClaimResult(
          outcome: ClaimOutcome.alreadyLoaded,
          handoffId: handoff,
          message: StationClaim.codeAlreadyLoaded,
        );
      }

      final prevClaim = (row["claim_device_id"] ?? "").toString().trim();
      final prevExp = (row["claim_expires_at"] ?? "").toString();
      final expired = StationClaim.isExpired(prevExp, clock);
      final alreadyOwned =
          prevClaim.isNotEmpty && prevClaim == truck && !expired;

      if (prevClaim.isNotEmpty && prevClaim != truck && !expired) {
        return ClaimResult(
          outcome: ClaimOutcome.conflict,
          handoffId: handoff,
          claimExpiresAt: prevExp,
          message: StationClaim.codeAlreadyClaimed,
        );
      }

      // UPDATE condicional atômico (proteção contra corrida).
      final n = await txn.rawUpdate(
        """
        UPDATE CADASTRO_FABRICA_RACAO
        SET
          CLAIM_DEVICE_ID = ?,
          CLAIM_AT = ?,
          CLAIM_EXPIRES_AT = ?
        WHERE TRIM(COALESCE(ID,'')) = TRIM(?)
          AND COALESCE(CARREGADA,0) = 0
          AND (
            TRIM(COALESCE(CLAIM_DEVICE_ID,'')) = ''
            OR COALESCE(CLAIM_EXPIRES_AT,'') = ''
            OR CLAIM_EXPIRES_AT <= ?
            OR TRIM(COALESCE(CLAIM_DEVICE_ID,'')) = TRIM(?)
          )
        """,
        [truck, nowIso, expIso, idLocal, nowIso, truck],
      );

      if (n != 1) {
        // Corrida: outro device ganhou entre SELECT e UPDATE.
        final again = await txn.rawQuery(
          """
          SELECT COALESCE(CLAIM_DEVICE_ID,'') AS claim_device_id,
                 COALESCE(CLAIM_EXPIRES_AT,'') AS claim_expires_at,
                 COALESCE(CARREGADA,0) AS carregada,
                 COALESCE(HANDOFF_ID,'') AS handoff_id
          FROM CADASTRO_FABRICA_RACAO
          WHERE TRIM(COALESCE(ID,'')) = TRIM(?)
          LIMIT 1
          """,
          [idLocal],
        );
        if (again.isEmpty) {
          return const ClaimResult(
            outcome: ClaimOutcome.notFound,
            message: "fabricacao_nao_encontrada",
          );
        }
        final a = again.first;
        if ((_toInt(a["carregada"]) ?? 0) == 1) {
          return ClaimResult(
            outcome: ClaimOutcome.alreadyLoaded,
            handoffId: (a["handoff_id"] ?? "").toString(),
            message: StationClaim.codeAlreadyLoaded,
          );
        }
        return ClaimResult(
          outcome: ClaimOutcome.conflict,
          handoffId: (a["handoff_id"] ?? "").toString(),
          claimExpiresAt: (a["claim_expires_at"] ?? "").toString(),
          message: StationClaim.codeAlreadyClaimed,
        );
      }

      return ClaimResult(
        outcome:
            alreadyOwned ? ClaimOutcome.alreadyOwned : ClaimOutcome.ok,
        handoffId: handoff,
        claimedBy: truck,
        claimExpiresAt: expIso,
        alreadyOwned: alreadyOwned,
      );
    });
  }

  Future<ReleaseResult> release({
    required String idOrHandoff,
    required String truckDeviceId,
    DateTime? now,
  }) async {
    final truck = truckDeviceId.trim();
    if (!StationClaim.isValidTruckDeviceId(truck)) {
      return const ReleaseResult(
        outcome: ClaimOutcome.invalid,
        message: "truckDeviceId_invalido",
      );
    }
    final key = idOrHandoff.trim();
    if (key.isEmpty) {
      return const ReleaseResult(
        outcome: ClaimOutcome.invalid,
        message: "id_invalido",
      );
    }

    final clock = now ?? DateTime.now();

    return db.transaction((txn) async {
      final rows = await txn.rawQuery(
        """
        SELECT
          ID AS id_local,
          COALESCE(CARREGADA,0) AS carregada,
          COALESCE(CLAIM_DEVICE_ID,'') AS claim_device_id,
          COALESCE(CLAIM_EXPIRES_AT,'') AS claim_expires_at
        FROM CADASTRO_FABRICA_RACAO
        WHERE TRIM(COALESCE(ID,'')) = TRIM(?)
           OR TRIM(COALESCE(HANDOFF_ID,'')) = TRIM(?)
        LIMIT 1
        """,
        [key, key],
      );
      if (rows.isEmpty) {
        return const ReleaseResult(
          outcome: ClaimOutcome.notFound,
          message: "fabricacao_nao_encontrada",
        );
      }

      final row = rows.first;
      final idLocal = (row["id_local"] ?? "").toString();
      final claim = (row["claim_device_id"] ?? "").toString().trim();
      final exp = (row["claim_expires_at"] ?? "").toString();

      // Já livre / expirado → idempotente.
      if (claim.isEmpty || StationClaim.isExpired(exp, clock)) {
        if (claim.isNotEmpty) {
          await txn.rawUpdate(
            """
            UPDATE CADASTRO_FABRICA_RACAO
            SET CLAIM_DEVICE_ID = NULL, CLAIM_AT = NULL, CLAIM_EXPIRES_AT = NULL
            WHERE TRIM(COALESCE(ID,'')) = TRIM(?)
            """,
            [idLocal],
          );
        }
        return const ReleaseResult(outcome: ClaimOutcome.ok);
      }

      if (claim != truck) {
        return const ReleaseResult(
          outcome: ClaimOutcome.forbidden,
          message: StationClaim.codeForbidden,
        );
      }

      await txn.rawUpdate(
        """
        UPDATE CADASTRO_FABRICA_RACAO
        SET CLAIM_DEVICE_ID = NULL, CLAIM_AT = NULL, CLAIM_EXPIRES_AT = NULL
        WHERE TRIM(COALESCE(ID,'')) = TRIM(?)
          AND TRIM(COALESCE(CLAIM_DEVICE_ID,'')) = TRIM(?)
        """,
        [idLocal, truck],
      );
      return const ReleaseResult(outcome: ClaimOutcome.ok);
    });
  }

  /// ACK: CARREGADA=1 + limpa claim. Idempotente se já carregada.
  Future<AckResult> ack({
    required String idOrHandoff,
    String? truckDeviceId,
    bool requireClaim = true,
    DateTime? now,
  }) async {
    final key = idOrHandoff.trim();
    if (key.isEmpty) {
      return const AckResult(
        outcome: ClaimOutcome.invalid,
        message: "id_invalido",
      );
    }

    final truck = (truckDeviceId ?? "").trim();
    final clock = now ?? DateTime.now();

    if (requireClaim) {
      if (!StationClaim.isValidTruckDeviceId(truck)) {
        return const AckResult(
          outcome: ClaimOutcome.invalid,
          message: "truckDeviceId_invalido",
        );
      }
    }

    return db.transaction((txn) async {
      final rows = await txn.rawQuery(
        """
        SELECT
          ID AS id_local,
          COALESCE(HANDOFF_ID,'') AS handoff_id,
          COALESCE(CARREGADA,0) AS carregada,
          COALESCE(CLAIM_DEVICE_ID,'') AS claim_device_id,
          COALESCE(CLAIM_EXPIRES_AT,'') AS claim_expires_at
        FROM CADASTRO_FABRICA_RACAO
        WHERE TRIM(COALESCE(ID,'')) = TRIM(?)
           OR TRIM(COALESCE(HANDOFF_ID,'')) = TRIM(?)
        LIMIT 1
        """,
        [key, key],
      );
      if (rows.isEmpty) {
        return const AckResult(
          outcome: ClaimOutcome.notFound,
          message: "fabricacao_nao_encontrada",
        );
      }

      final row = rows.first;
      final idLocal = (row["id_local"] ?? "").toString();
      final carregada = _toInt(row["carregada"]) ?? 0;

      // ACK perdido: já CARREGADA → sucesso idempotente.
      if (carregada == 1) {
        return const AckResult(
          outcome: ClaimOutcome.ok,
          alreadyAcked: true,
        );
      }

      if (requireClaim) {
        final claim = (row["claim_device_id"] ?? "").toString().trim();
        final exp = (row["claim_expires_at"] ?? "").toString();
        final expired = StationClaim.isExpired(exp, clock);
        if (claim.isEmpty || expired) {
          // Sem claim válido: permitir renovar via claim antes — aqui nega.
          return const AckResult(
            outcome: ClaimOutcome.forbidden,
            message: "claim_obrigatorio",
          );
        }
        if (claim != truck) {
          return const AckResult(
            outcome: ClaimOutcome.conflict,
            message: StationClaim.codeAlreadyClaimed,
          );
        }
      }

      final n = await txn.rawUpdate(
        """
        UPDATE CADASTRO_FABRICA_RACAO
        SET
          CARREGADA = 1,
          CLAIM_DEVICE_ID = NULL,
          CLAIM_AT = NULL,
          CLAIM_EXPIRES_AT = NULL
        WHERE TRIM(COALESCE(ID,'')) = TRIM(?)
          AND COALESCE(CARREGADA,0) = 0
        """,
        [idLocal],
      );

      if (n != 1) {
        // Outro ACK concorrente — se agora está carregada, idempotente.
        final again = await txn.rawQuery(
          "SELECT COALESCE(CARREGADA,0) AS c FROM CADASTRO_FABRICA_RACAO "
          "WHERE TRIM(COALESCE(ID,'')) = TRIM(?) LIMIT 1",
          [idLocal],
        );
        if (again.isNotEmpty && (_toInt(again.first["c"]) ?? 0) == 1) {
          return const AckResult(
            outcome: ClaimOutcome.ok,
            alreadyAcked: true,
          );
        }
        return const AckResult(
          outcome: ClaimOutcome.notFound,
          message: "ack_falhou",
        );
      }

      return const AckResult(outcome: ClaimOutcome.ok);
    });
  }

  int? _toInt(Object? v) {
    if (v == null) return null;
    if (v is int) return v;
    return int.tryParse(v.toString());
  }
}
