import "package:flutter_test/flutter_test.dart";
import "package:sqflite_common_ffi/sqflite_ffi.dart";
import "package:uuid/uuid.dart";

import "package:field_trato/features/estacionario/data/carregamento_claim_store.dart";
import "package:field_trato/features/estacionario/domain/station_claim.dart";

const truckA = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const truckB = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";

Future<Database> _openFabDb() async {
  final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
  await db.execute("""
    CREATE TABLE CADASTRO_FABRICA_RACAO (
      ID TEXT PRIMARY KEY NOT NULL,
      ID_DIETA TEXT NOT NULL DEFAULT 'd1',
      QTD_PREVISTA NUMERIC NOT NULL DEFAULT 0,
      QTD_REALIZADA NUMERIC DEFAULT 0,
      DATA_FABRICACAO TEXT NOT NULL DEFAULT '2026-01-01',
      HORA_INICIO TEXT,
      HORA_FIM TEXT,
      TRATO INTEGER NOT NULL DEFAULT 1,
      FINALIZADA INTEGER NOT NULL DEFAULT 0,
      CARREGADA INTEGER NOT NULL DEFAULT 0,
      ID_OPERADOR TEXT NOT NULL DEFAULT 'op',
      ID_USUARIO TEXT NOT NULL DEFAULT 'u',
      STATUS INTEGER NOT NULL DEFAULT 1,
      FLAG_SYNC INTEGER NOT NULL DEFAULT 0,
      ID_FAZENDA TEXT NOT NULL DEFAULT 'f1',
      FAB_STATUS INTEGER NOT NULL DEFAULT 1,
      HANDOFF_ID TEXT,
      CLAIM_DEVICE_ID TEXT,
      CLAIM_AT TEXT,
      CLAIM_EXPIRES_AT TEXT
    )
  """);
  return db;
}

Future<void> _insertLoad(
  Database db, {
  required String id,
  required String handoff,
  int carregada = 0,
  String? claimDevice,
  String? claimExpires,
}) async {
  await db.insert("CADASTRO_FABRICA_RACAO", {
    "ID": id,
    "HANDOFF_ID": handoff,
    "CARREGADA": carregada,
    "CLAIM_DEVICE_ID": claimDevice,
    "CLAIM_EXPIRES_AT": claimExpires,
    "ID_DIETA": "d1",
    "QTD_PREVISTA": 100,
    "DATA_FABRICACAO": "2026-01-01",
    "TRATO": 1,
    "ID_OPERADOR": "op",
    "ID_USUARIO": "u",
    "ID_FAZENDA": "f1",
    "STATUS": 1,
    "FAB_STATUS": 1,
  });
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group("claim atômico (repo)", () {
    test("1. carga livre → truck A recebe claim", () async {
      final db = await _openFabDb();
      await _insertLoad(db, id: "fab-1", handoff: "ho-1");
      final store = CarregamentoClaimStore(db);
      final r = await store.claim(idOrHandoff: "ho-1", truckDeviceId: truckA);
      expect(r.ok, isTrue);
      expect(r.alreadyOwned, isFalse);
      expect(r.claimedBy, truckA);
      expect(r.handoffId, "ho-1");
      expect(r.claimExpiresAt, isNotEmpty);
      await db.close();
    });

    test("2. truck A repete → 200 idempotente (alreadyOwned)", () async {
      final db = await _openFabDb();
      await _insertLoad(db, id: "fab-1", handoff: "ho-1");
      final store = CarregamentoClaimStore(db);
      final r1 = await store.claim(idOrHandoff: "fab-1", truckDeviceId: truckA);
      final r2 = await store.claim(idOrHandoff: "fab-1", truckDeviceId: truckA);
      expect(r1.ok, isTrue);
      expect(r2.ok, isTrue);
      expect(r2.alreadyOwned, isTrue);
      expect(r2.outcome, ClaimOutcome.alreadyOwned);
      await db.close();
    });

    test("3. truck B tenta → conflito", () async {
      final db = await _openFabDb();
      await _insertLoad(db, id: "fab-1", handoff: "ho-1");
      final store = CarregamentoClaimStore(db);
      await store.claim(idOrHandoff: "ho-1", truckDeviceId: truckA);
      final r = await store.claim(idOrHandoff: "ho-1", truckDeviceId: truckB);
      expect(r.outcome, ClaimOutcome.conflict);
      expect(r.message, StationClaim.codeAlreadyClaimed);
      await db.close();
    });

    test("4. lease expira → B consegue", () async {
      final db = await _openFabDb();
      final past = DateTime.now().subtract(const Duration(minutes: 5));
      await _insertLoad(
        db,
        id: "fab-1",
        handoff: "ho-1",
        claimDevice: truckA,
        claimExpires: past.toIso8601String(),
      );
      final store = CarregamentoClaimStore(db);
      final r = await store.claim(idOrHandoff: "ho-1", truckDeviceId: truckB);
      expect(r.ok, isTrue);
      expect(r.claimedBy, truckB);
      await db.close();
    });

    test("5. A renova antes da expiração", () async {
      final db = await _openFabDb();
      await _insertLoad(db, id: "fab-1", handoff: "ho-1");
      final store = CarregamentoClaimStore(db);
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);
      final r1 = await store.claim(
        idOrHandoff: "ho-1",
        truckDeviceId: truckA,
        now: t0,
      );
      final t1 = t0.add(const Duration(minutes: 1));
      final r2 = await store.claim(
        idOrHandoff: "ho-1",
        truckDeviceId: truckA,
        now: t1,
      );
      expect(r1.ok, isTrue);
      expect(r2.ok, isTrue);
      expect(r2.alreadyOwned, isTrue);
      expect(
        DateTime.parse(r2.claimExpiresAt).isAfter(DateTime.parse(r1.claimExpiresAt)),
        isTrue,
      );
      await db.close();
    });

    test("6. B não consegue release de A", () async {
      final db = await _openFabDb();
      await _insertLoad(db, id: "fab-1", handoff: "ho-1");
      final store = CarregamentoClaimStore(db);
      await store.claim(idOrHandoff: "ho-1", truckDeviceId: truckA);
      final r = await store.release(idOrHandoff: "ho-1", truckDeviceId: truckB);
      expect(r.outcome, ClaimOutcome.forbidden);
      await db.close();
    });

    test("7. A consegue release", () async {
      final db = await _openFabDb();
      await _insertLoad(db, id: "fab-1", handoff: "ho-1");
      final store = CarregamentoClaimStore(db);
      await store.claim(idOrHandoff: "ho-1", truckDeviceId: truckA);
      final r = await store.release(idOrHandoff: "ho-1", truckDeviceId: truckA);
      expect(r.ok, isTrue);
      final again =
          await store.claim(idOrHandoff: "ho-1", truckDeviceId: truckB);
      expect(again.ok, isTrue);
      await db.close();
    });

    test("8. carga CARREGADA não pode receber novo claim", () async {
      final db = await _openFabDb();
      await _insertLoad(db, id: "fab-1", handoff: "ho-1", carregada: 1);
      final store = CarregamentoClaimStore(db);
      final r = await store.claim(idOrHandoff: "ho-1", truckDeviceId: truckA);
      expect(r.outcome, ClaimOutcome.alreadyLoaded);
      await db.close();
    });
  });

  group("corrida real A/B", () {
    test("23. exatamente um obtém o claim (concorrente)", () async {
      final db = await _openFabDb();
      await _insertLoad(db, id: "fab-x", handoff: "ho-x");
      final store = CarregamentoClaimStore(db);

      final results = await Future.wait([
        store.claim(idOrHandoff: "ho-x", truckDeviceId: truckA),
        store.claim(idOrHandoff: "ho-x", truckDeviceId: truckB),
      ]);

      final winners = results.where((r) => r.ok).toList();
      final losers = results.where((r) => !r.ok).toList();
      expect(winners.length, 1, reason: "exatamente um claim OK");
      expect(losers.length, 1);
      expect(losers.first.outcome, ClaimOutcome.conflict);

      final row = (await db.query("CADASTRO_FABRICA_RACAO")).first;
      final owner = (row["CLAIM_DEVICE_ID"] ?? "").toString();
      expect(owner == truckA || owner == truckB, isTrue);
      expect(winners.first.claimedBy, owner);
      await db.close();
    });

    test("23b. stress 20 claims paralelos → 1 vencedor", () async {
      final db = await _openFabDb();
      await _insertLoad(db, id: "fab-s", handoff: "ho-s");
      final store = CarregamentoClaimStore(db);
      final trucks = List.generate(20, (_) => const Uuid().v4());

      final results = await Future.wait(
        trucks.map((t) => store.claim(idOrHandoff: "ho-s", truckDeviceId: t)),
      );

      expect(results.where((r) => r.ok).length, 1);
      expect(results.where((r) => r.outcome == ClaimOutcome.conflict).length, 19);
      await db.close();
    });
  });

  group("ack / release / HTTP semantics", () {
    test("ack exige claim do mesmo truck", () async {
      final db = await _openFabDb();
      await _insertLoad(db, id: "fab-1", handoff: "ho-1");
      final store = CarregamentoClaimStore(db);
      await store.claim(idOrHandoff: "ho-1", truckDeviceId: truckA);

      final bad = await store.ack(
        idOrHandoff: "ho-1",
        truckDeviceId: truckB,
        requireClaim: true,
      );
      expect(bad.outcome, ClaimOutcome.conflict);

      final good = await store.ack(
        idOrHandoff: "ho-1",
        truckDeviceId: truckA,
        requireClaim: true,
      );
      expect(good.ok, isTrue);

      final row = (await db.query("CADASTRO_FABRICA_RACAO")).first;
      expect(row["CARREGADA"], 1);
      expect((row["CLAIM_DEVICE_ID"] ?? "").toString(), "");
      await db.close();
    });

    test("27. ACK perdido → retry idempotente", () async {
      final db = await _openFabDb();
      await _insertLoad(db, id: "fab-1", handoff: "ho-1");
      final store = CarregamentoClaimStore(db);
      await store.claim(idOrHandoff: "ho-1", truckDeviceId: truckA);
      final r1 = await store.ack(
        idOrHandoff: "ho-1",
        truckDeviceId: truckA,
      );
      expect(r1.ok, isTrue);
      expect(r1.alreadyAcked, isFalse);

      // Simula perda de resposta: cliente retenta.
      final r2 = await store.ack(
        idOrHandoff: "ho-1",
        truckDeviceId: truckA,
      );
      expect(r2.ok, isTrue);
      expect(r2.alreadyAcked, isTrue);
      await db.close();
    });

    test("26. falha local → release; sem ack", () async {
      final db = await _openFabDb();
      await _insertLoad(db, id: "fab-1", handoff: "ho-1");
      final store = CarregamentoClaimStore(db);
      await store.claim(idOrHandoff: "ho-1", truckDeviceId: truckA);
      // Simula falha de import: release
      final rel = await store.release(
        idOrHandoff: "ho-1",
        truckDeviceId: truckA,
      );
      expect(rel.ok, isTrue);
      final row = (await db.query("CADASTRO_FABRICA_RACAO")).first;
      expect(row["CARREGADA"], 0);
      expect((row["CLAIM_DEVICE_ID"] ?? "").toString(), isEmpty);

      final b = await store.claim(idOrHandoff: "ho-1", truckDeviceId: truckB);
      expect(b.ok, isTrue);
      await db.close();
    });

    test("listStatus deriva available/claimedByMe/claimed", () {
      final now = DateTime(2026, 1, 1, 12);
      expect(
        StationClaim.listStatus(
          claimDeviceId: null,
          claimExpiresAt: null,
          now: now,
          viewerTruckDeviceId: truckA,
        ),
        StationClaim.statusAvailable,
      );
      expect(
        StationClaim.listStatus(
          claimDeviceId: truckA,
          claimExpiresAt: now.add(const Duration(minutes: 2)).toIso8601String(),
          now: now,
          viewerTruckDeviceId: truckA,
        ),
        StationClaim.statusClaimedByMe,
      );
      expect(
        StationClaim.listStatus(
          claimDeviceId: truckB,
          claimExpiresAt: now.add(const Duration(minutes: 2)).toIso8601String(),
          now: now,
          viewerTruckDeviceId: truckA,
        ),
        StationClaim.statusClaimed,
      );
      expect(
        StationClaim.listStatus(
          claimDeviceId: truckB,
          claimExpiresAt: now.subtract(const Duration(minutes: 1)).toIso8601String(),
          now: now,
          viewerTruckDeviceId: truckA,
        ),
        StationClaim.statusAvailable,
      );
    });

    test("lease duration centralizada = 3 min", () {
      expect(StationClaim.claimLeaseDuration, const Duration(minutes: 3));
    });

    test("truckDeviceId inválido → invalid", () async {
      final db = await _openFabDb();
      await _insertLoad(db, id: "fab-1", handoff: "ho-1");
      final store = CarregamentoClaimStore(db);
      final r = await store.claim(idOrHandoff: "ho-1", truckDeviceId: "CAMINHAO");
      expect(r.outcome, ClaimOutcome.invalid);
      await db.close();
    });

    test("fluxo vagão: A claim+ack; B 409; lista some", () async {
      final db = await _openFabDb();
      await _insertLoad(db, id: "fab-x", handoff: "ho-x");
      final store = CarregamentoClaimStore(db);

      final c1 = await store.claim(idOrHandoff: "ho-x", truckDeviceId: truckA);
      expect(c1.ok, isTrue);
      final c2 = await store.claim(idOrHandoff: "ho-x", truckDeviceId: truckB);
      expect(c2.outcome, ClaimOutcome.conflict);

      final ack = await store.ack(
        idOrHandoff: "ho-x",
        truckDeviceId: truckA,
      );
      expect(ack.ok, isTrue);

      final open = await db.query(
        "CADASTRO_FABRICA_RACAO",
        where: "COALESCE(CARREGADA,0)=0",
      );
      expect(open, isEmpty);
      await db.close();
    });
  });
}
