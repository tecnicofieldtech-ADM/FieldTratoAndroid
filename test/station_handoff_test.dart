import "package:flutter_test/flutter_test.dart";
import "package:sqflite_common_ffi/sqflite_ffi.dart";

import "package:field_trato/features/estacionario/data/carregamento_bridge_repo.dart";
import "package:field_trato/features/estacionario/data/carregamento_claim_store.dart";
import "package:field_trato/features/estacionario/domain/station_handoff_mode.dart";
import "package:field_trato/features/fabricacao/domain/fabricacao_flow.dart";

const truckA = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const truckB = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";

Future<Database> _openDb() async {
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
      FAB_STATUS INTEGER NOT NULL DEFAULT 0,
      HANDOFF_ID TEXT,
      CLAIM_DEVICE_ID TEXT,
      CLAIM_AT TEXT,
      CLAIM_EXPIRES_AT TEXT
    )
  """);
  await db.execute("""
    CREATE TABLE DIETA (
      ID TEXT PRIMARY KEY NOT NULL,
      NOME TEXT
    )
  """);
  await db.insert("DIETA", {"ID": "d1", "NOME": "TERMINAÇÃO"});
  return db;
}

Future<void> _ins(
  Database db, {
  required String id,
  required String handoff,
  required int fabStatus,
  required int finalizada,
  int carregada = 0,
  int status = 1,
  double kg = 1000,
}) async {
  await db.insert("CADASTRO_FABRICA_RACAO", {
    "ID": id,
    "HANDOFF_ID": handoff,
    "FAB_STATUS": fabStatus,
    "FINALIZADA": finalizada,
    "CARREGADA": carregada,
    "STATUS": status,
    "ID_DIETA": "d1",
    "QTD_PREVISTA": kg,
    "QTD_REALIZADA": kg,
    "DATA_FABRICACAO": "2026-01-01",
    "TRATO": 1,
    "ID_OPERADOR": "op",
    "ID_USUARIO": "u",
    "ID_FAZENDA": "f1",
  });
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group("handoffMode", () {
    test("PENDENTE → CONTINUE_FABRICATION", () {
      expect(
        resolveStationHandoffMode(fabStatus: 1, finalizada: 0),
        StationHandoffMode.continueFabrication,
      );
    });

    test("FINALIZADA → FABRICATION_COMPLETE", () {
      expect(
        resolveStationHandoffMode(fabStatus: 2, finalizada: 1),
        StationHandoffMode.fabricationComplete,
      );
    });

    test("estado ambíguo não adivinha", () {
      expect(
        resolveStationHandoffMode(fabStatus: 1, finalizada: 1),
        isNull,
      );
      expect(
        resolveStationHandoffMode(fabStatus: 2, finalizada: 0),
        isNull,
      );
      expect(
        resolveStationHandoffMode(fabStatus: 0, finalizada: 0),
        isNull,
      );
    });
  });

  group("filtro listDisponiveis (Etapa E)", () {
    test("1. PENDENTE + CARREGADA=0 → aparece", () async {
      final db = await _openDb();
      await _ins(
        db,
        id: "p1",
        handoff: "ho-p1",
        fabStatus: fabricacaoStatusPendenteCaminhao,
        finalizada: 0,
      );
      final list = await CarregamentoBridgeRepo(db: db).listDisponiveis();
      expect(list.length, 1);
      expect(list.first["handoff_mode"], "CONTINUE_FABRICATION");
      await db.close();
    });

    test("2. FINALIZADA + CARREGADA=0 → aparece", () async {
      final db = await _openDb();
      await _ins(
        db,
        id: "f1",
        handoff: "ho-f1",
        fabStatus: fabricacaoStatusFinalizada,
        finalizada: 1,
        kg: 8500,
      );
      final list = await CarregamentoBridgeRepo(db: db).listDisponiveis();
      expect(list.length, 1);
      expect(list.first["handoff_mode"], "FABRICATION_COMPLETE");
      await db.close();
    });

    test("3. PENDENTE + CARREGADA=1 → não aparece", () async {
      final db = await _openDb();
      await _ins(
        db,
        id: "p1",
        handoff: "ho-p1",
        fabStatus: fabricacaoStatusPendenteCaminhao,
        finalizada: 0,
        carregada: 1,
      );
      final list = await CarregamentoBridgeRepo(db: db).listDisponiveis();
      expect(list, isEmpty);
      await db.close();
    });

    test("4. FINALIZADA + CARREGADA=1 → não aparece", () async {
      final db = await _openDb();
      await _ins(
        db,
        id: "f1",
        handoff: "ho-f1",
        fabStatus: fabricacaoStatusFinalizada,
        finalizada: 1,
        carregada: 1,
      );
      final list = await CarregamentoBridgeRepo(db: db).listDisponiveis();
      expect(list, isEmpty);
      await db.close();
    });

    test("5. cancelada (STATUS!=1) → não aparece", () async {
      final db = await _openDb();
      await _ins(
        db,
        id: "c1",
        handoff: "ho-c1",
        fabStatus: fabricacaoStatusFinalizada,
        finalizada: 1,
        status: 0,
      );
      final list = await CarregamentoBridgeRepo(db: db).listDisponiveis();
      expect(list, isEmpty);
      await db.close();
    });

    test("6. status inválido / inconsistente → não aparece", () async {
      final db = await _openDb();
      await _ins(
        db,
        id: "i1",
        handoff: "ho-i1",
        fabStatus: fabricacaoStatusPendenteCaminhao,
        finalizada: 1, // inconsistente
      );
      await _ins(
        db,
        id: "i2",
        handoff: "ho-i2",
        fabStatus: fabricacaoStatusEmAndamento,
        finalizada: 0,
      );
      final list = await CarregamentoBridgeRepo(db: db).listDisponiveis();
      expect(list, isEmpty);
      await db.close();
    });

    test("parcial + finalizada ambas aparecem com modes distintos", () async {
      final db = await _openDb();
      await _ins(
        db,
        id: "p1",
        handoff: "ho-p",
        fabStatus: fabricacaoStatusPendenteCaminhao,
        finalizada: 0,
      );
      await _ins(
        db,
        id: "f1",
        handoff: "ho-f",
        fabStatus: fabricacaoStatusFinalizada,
        finalizada: 1,
      );
      final list = await CarregamentoBridgeRepo(db: db).listDisponiveis();
      expect(list.length, 2);
      final modes = list.map((e) => e["handoff_mode"]).toSet();
      expect(modes, {
        "CONTINUE_FABRICATION",
        "FABRICATION_COMPLETE",
      });
      await db.close();
    });
  });

  group("claim também na finalizada", () {
    test("24. A e B na FINALIZADA → um vence", () async {
      final db = await _openDb();
      await _ins(
        db,
        id: "fx",
        handoff: "ho-fx",
        fabStatus: fabricacaoStatusFinalizada,
        finalizada: 1,
      );
      final store = CarregamentoClaimStore(db);
      final results = await Future.wait([
        store.claim(idOrHandoff: "ho-fx", truckDeviceId: truckA),
        store.claim(idOrHandoff: "ho-fx", truckDeviceId: truckB),
      ]);
      expect(results.where((r) => r.ok).length, 1);
      expect(results.where((r) => !r.ok).length, 1);

      final ack = await store.ack(
        idOrHandoff: "ho-fx",
        truckDeviceId: results.firstWhere((r) => r.ok).claimedBy,
      );
      expect(ack.ok, isTrue);

      // retry ACK perdido
      final again = await store.ack(
        idOrHandoff: "ho-fx",
        truckDeviceId: results.firstWhere((r) => r.ok).claimedBy,
      );
      expect(again.ok, isTrue);
      expect(again.alreadyAcked, isTrue);

      final list = await CarregamentoBridgeRepo(db: db).listDisponiveis();
      expect(list, isEmpty);
      await db.close();
    });
  });
}
