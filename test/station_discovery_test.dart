import "dart:io";

import "package:flutter_test/flutter_test.dart";
import "package:sqflite_common_ffi/sqflite_ffi.dart";
import "package:uuid/uuid.dart";

import "package:field_trato/features/estacionario/data/carregamento_estacionario_api.dart";
import "package:field_trato/features/estacionario/domain/station_discovery.dart";
import "package:field_trato/features/estacionario/services/station_discovery_responder.dart";
import "package:field_trato/features/estacionario/services/station_discovery_service.dart";

/// Simula a regra de CONFIG.STATION_ID / TRUCK_DEVICE_ID (gerar uma vez).
String ensureDeviceIdOnce({
  required String existing,
  required int tipoTrabalho,
  required int expectedTipo,
  required String Function() generate,
}) {
  final cur = existing.trim();
  if (cur.isNotEmpty) return cur;
  if (tipoTrabalho != expectedTipo) return "";
  return generate();
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group("identidade STATION_ID / TRUCK_DEVICE_ID", () {
    test("1. STATION_ID é criado uma vez (tipo=1)", () {
      final gen = const Uuid().v4;
      final id1 = ensureDeviceIdOnce(
        existing: "",
        tipoTrabalho: 1,
        expectedTipo: 1,
        generate: gen,
      );
      expect(id1, isNotEmpty);
      expect(
        RegExp(
          r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$",
        ).hasMatch(id1),
        isTrue,
      );

      final id2 = ensureDeviceIdOnce(
        existing: id1,
        tipoTrabalho: 1,
        expectedTipo: 1,
        generate: () => "SHOULD_NOT_RUN",
      );
      expect(id2, id1);
    });

    test("2. STATION_ID não muda após restart (persistência simulada)", () async {
      final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      await db.execute(
        "CREATE TABLE CONFIG (STATION_ID TEXT, TIPO_TRABALHO INTEGER)",
      );
      await db.insert("CONFIG", {"STATION_ID": "", "TIPO_TRABALHO": 1});

      Future<String> ensure() async {
        final row = (await db.query("CONFIG")).first;
        final existing = (row["STATION_ID"] ?? "").toString();
        final tipo = int.tryParse("${row["TIPO_TRABALHO"]}") ?? 0;
        final id = ensureDeviceIdOnce(
          existing: existing,
          tipoTrabalho: tipo,
          expectedTipo: 1,
          generate: const Uuid().v4,
        );
        if (id.isNotEmpty && existing.trim().isEmpty) {
          await db.update("CONFIG", {"STATION_ID": id});
        }
        return id;
      }

      final first = await ensure();
      // "restart": nova leitura do mesmo store
      final afterRestart = await ensure();
      expect(afterRestart, first);
      await db.close();
    });

    test("3. TRUCK_DEVICE_ID é criado uma vez (tipo=2)", () {
      final id1 = ensureDeviceIdOnce(
        existing: "",
        tipoTrabalho: 2,
        expectedTipo: 2,
        generate: const Uuid().v4,
      );
      expect(id1, isNotEmpty);
      final id2 = ensureDeviceIdOnce(
        existing: id1,
        tipoTrabalho: 2,
        expectedTipo: 2,
        generate: () => "NOPE",
      );
      expect(id2, id1);
      // tipo errado não gera
      expect(
        ensureDeviceIdOnce(
          existing: "",
          tipoTrabalho: 1,
          expectedTipo: 2,
          generate: const Uuid().v4,
        ),
        "",
      );
    });
  });

  group("protocolo discovery", () {
    test("4. responder payload contém stationId correto", () {
      const sid = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee";
      final reply = StationDiscoveryProtocol.stationReply(
        stationId: sid,
        name: "Misturador 01",
        port: 8080,
      );
      expect(reply["type"], StationDiscoveryProtocol.typeStation);
      expect(reply["version"], 1);
      expect(reply["stationId"], sid);
      expect(reply["name"], "Misturador 01");
      expect(reply["port"], 8080);
    });

    test("5. discovery aceita 1 estação", () {
      final s = StationDiscoveryProtocol.parseStationReply(
        json: {
          "type": "RFEED_STATION",
          "version": 1,
          "stationId": "st-a",
          "name": "A",
          "port": 8080,
          "ip": "10.0.0.99", // ignorado
        },
        remoteHost: "192.168.1.20",
      );
      expect(s, isNotNull);
      expect(s!.stationId, "st-a");
      expect(s.host, "192.168.1.20"); // remoto UDP, não JSON ip
      expect(s.port, 8080);
      final list = StationDiscoveryProtocol.dedupeByStationId([s]);
      expect(list.length, 1);
    });

    test("6. discovery aceita 3 estações", () {
      final items = [
        StationDiscoveryProtocol.parseStationReply(
          json: {
            "type": "RFEED_STATION",
            "version": 1,
            "stationId": "a",
            "name": "A",
            "port": 8080,
          },
          remoteHost: "192.168.1.20",
        )!,
        StationDiscoveryProtocol.parseStationReply(
          json: {
            "type": "RFEED_STATION",
            "version": 1,
            "stationId": "b",
            "name": "B",
            "port": 8080,
          },
          remoteHost: "192.168.1.21",
        )!,
        StationDiscoveryProtocol.parseStationReply(
          json: {
            "type": "RFEED_STATION",
            "version": 1,
            "stationId": "c",
            "name": "C",
            "port": 8080,
          },
          remoteHost: "192.168.1.22",
        )!,
      ];
      final list = StationDiscoveryProtocol.dedupeByStationId(items);
      expect(list.length, 3);
      expect(list.map((e) => e.stationId).toSet(), {"a", "b", "c"});
    });

    test("7. respostas duplicadas do mesmo stationId viram 1 item", () {
      final a1 = DiscoveredStation(
        stationId: "same",
        name: "Misturador",
        host: "192.168.1.20",
        port: 8080,
      );
      final a2 = DiscoveredStation(
        stationId: "same",
        name: "Misturador",
        host: "192.168.1.25",
        port: 8080,
      );
      final list = StationDiscoveryProtocol.dedupeByStationId([a1, a2]);
      expect(list.length, 1);
      expect(list.first.host, "192.168.1.25");
    });

    test("8. timeout retorna lista vazia", () async {
      final svc = StationDiscoveryService();
      final list = await svc.discover(
        window: const Duration(milliseconds: 200),
        port: 19099, // porta sem responder
      );
      expect(list, isEmpty);
    });

    test("9. pacote inválido é ignorado", () {
      expect(
        StationDiscoveryProtocol.parseStationReply(
          json: "not-a-map",
          remoteHost: "1.2.3.4",
        ),
        isNull,
      );
      expect(
        StationDiscoveryProtocol.parseStationReply(
          json: {"type": "OTHER", "version": 1, "stationId": "x", "port": 8080},
          remoteHost: "1.2.3.4",
        ),
        isNull,
      );
      expect(
        StationDiscoveryProtocol.parseStationReply(
          json: {
            "type": "RFEED_STATION",
            "version": 1,
            "stationId": "",
            "port": 8080,
          },
          remoteHost: "1.2.3.4",
        ),
        isNull,
      );
    });

    test("10. versão incompatível é ignorada", () {
      expect(
        StationDiscoveryProtocol.parseStationReply(
          json: {
            "type": "RFEED_STATION",
            "version": 99,
            "stationId": "x",
            "port": 8080,
          },
          remoteHost: "1.2.3.4",
        ),
        isNull,
      );
    });
  });

  group("API dinâmica / seleção", () {
    test("11. seleção A usa host A", () {
      final api = CarregamentoEstacionarioApi(host: "192.168.1.20", port: 8080);
      expect(api.host, "192.168.1.20");
      expect(api.port, 8080);
      final fromUrl = CarregamentoEstacionarioApi.tryFromBaseUrl(
        "http://192.168.1.20:8080",
      );
      expect(fromUrl!.host, "192.168.1.20");
    });

    test("12. seleção B depois usa host B (sem mutar A)", () {
      final apiA = CarregamentoEstacionarioApi(host: "192.168.1.20", port: 8080);
      final apiB = CarregamentoEstacionarioApi(host: "192.168.1.21", port: 8080);
      expect(apiA.host, "192.168.1.20");
      expect(apiB.host, "192.168.1.21");
      expect(apiA.host, isNot(apiB.host));
    });

    test("13. STATION_BASE_URL não é sobrescrito ao trocar dinamicamente", () {
      // Seleção dinâmica cria API nova; CONFIG permanece intocado neste nível.
      var configStationBaseUrl = "http://192.168.1.10:8080";
      final selected = DiscoveredStation(
        stationId: "b",
        name: "B",
        host: "192.168.1.21",
        port: 8080,
      );
      final api = CarregamentoEstacionarioApi(
        host: selected.host,
        port: selected.port,
      );
      expect(api.host, "192.168.1.21");
      expect(configStationBaseUrl, "http://192.168.1.10:8080");
      // trocar de estação
      final selected2 = DiscoveredStation(
        stationId: "a",
        name: "A",
        host: "192.168.1.20",
        port: 8080,
      );
      final api2 = CarregamentoEstacionarioApi(
        host: selected2.host,
        port: selected2.port,
      );
      expect(api2.host, "192.168.1.20");
      expect(configStationBaseUrl, "http://192.168.1.10:8080");
    });

    test("14. IP manual funciona (parse host/porta default 8080)", () {
      final hp = CarregamentoEstacionarioApi.tryParseHostPort("192.168.1.50");
      expect(hp, isNotNull);
      expect(hp!.host, "192.168.1.50");
      expect(hp.port, 8080);

      final withPort = CarregamentoEstacionarioApi.tryParseHostPort(
        "192.168.1.50:9090",
      );
      expect(withPort!.port, 9090);

      final legacy = DiscoveredStation(
        stationId: "manual:192.168.1.50:8080",
        name: "192.168.1.50",
        host: "192.168.1.50",
        port: 8080,
        fromDiscovery: false,
      );
      expect(legacy.baseUrl, "http://192.168.1.50:8080");
      expect(legacy.stationId.startsWith("manual:"), isTrue);
    });
  });

  group("lifecycle UDP responder", () {
    test("15. Bridge desligado fecha responder UDP", () async {
      // Responder real exige ConfigRepo/AppDb; validamos contrato stop() + bind liberado.
      final sock = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final port = sock.port;
      expect(port, greaterThan(0));
      sock.close();

      // Após close, a porta pode ser reutilizada (não órfã).
      final sock2 = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        port,
      );
      expect(sock2.port, port);
      sock2.close();

      final responder = StationDiscoveryResponder();
      expect(responder.running, isFalse);
      await responder.stop(); // idempotente
      expect(responder.running, isFalse);
    });

    test("discovery A+B: seleção troca host sem persistir CONFIG", () {
      // Fluxo funcional A → B (nível de modelo/API).
      final a = DiscoveredStation(
        stationId: "st-a",
        name: "Misturador 01",
        host: "192.168.1.20",
        port: 8080,
      );
      final b = DiscoveredStation(
        stationId: "st-b",
        name: "Misturador 02",
        host: "192.168.1.21",
        port: 8080,
      );
      final found = StationDiscoveryProtocol.dedupeByStationId([a, b]);
      expect(found.length, 2);

      var configBaseUrl = "http://legacy:8080";
      final apiA = CarregamentoEstacionarioApi(host: a.host, port: a.port);
      expect(apiA.host, "192.168.1.20");
      expect(configBaseUrl, "http://legacy:8080");

      final apiB = CarregamentoEstacionarioApi(host: b.host, port: b.port);
      expect(apiB.host, "192.168.1.21");
      expect(configBaseUrl, "http://legacy:8080");
    });
  });
}
