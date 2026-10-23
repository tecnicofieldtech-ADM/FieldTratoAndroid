import "dart:async";
import "dart:convert";
import "dart:io";

import "package:flutter/foundation.dart";

import "../../../repo/config_repo.dart";
import "../domain/station_discovery.dart";

/// Responde broadcasts UDP enquanto o Bridge HTTP está ativo.
class StationDiscoveryResponder {
  StationDiscoveryResponder({ConfigRepo? configRepo})
      : _cfg = configRepo ?? ConfigRepo();

  final ConfigRepo _cfg;
  RawDatagramSocket? _sock;
  StreamSubscription<RawSocketEvent>? _sub;
  bool get running => _sock != null;

  Future<void> start({required int httpPort}) async {
    if (_sock != null) return;

    final stationId = await _cfg.ensureStationId();
    final name = await _cfg.getStationDisplayName();
    final port = httpPort <= 0 ? 8080 : httpPort;

    try {
      _sock = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        StationDiscoveryProtocol.udpPort,
        reuseAddress: true,
      );
      _sock!.broadcastEnabled = true;
      debugPrint(
        "[DISCOVERY_RESPONDER] ON :${StationDiscoveryProtocol.udpPort} "
        "stationId=$stationId name=$name httpPort=$port",
      );

      _sub = _sock!.listen((event) {
        if (event != RawSocketEvent.read) return;
        final dg = _sock?.receive();
        if (dg == null) return;
        unawaited(_onDatagram(dg, stationId: stationId, name: name, httpPort: port));
      });
    } catch (e) {
      debugPrint("[DISCOVERY_RESPONDER] falha bind: $e");
      await stop();
      rethrow;
    }
  }

  Future<void> _onDatagram(
    Datagram dg, {
    required String stationId,
    required String name,
    required int httpPort,
  }) async {
    try {
      final raw = utf8.decode(dg.data, allowMalformed: true).trim();
      if (raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final type = (decoded["type"] ?? "").toString().trim().toUpperCase();
      if (type != StationDiscoveryProtocol.typeDiscover) return;
      final ver = int.tryParse("${decoded["version"]}") ?? 0;
      if (ver != StationDiscoveryProtocol.version) return;

      final reply = utf8.encode(
        jsonEncode(
          StationDiscoveryProtocol.stationReply(
            stationId: stationId,
            name: name,
            port: httpPort,
          ),
        ),
      );
      _sock?.send(reply, dg.address, dg.port);
    } catch (e) {
      debugPrint("[DISCOVERY_RESPONDER] ignore packet: $e");
    }
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _sock?.close();
    _sock = null;
    debugPrint("[DISCOVERY_RESPONDER] OFF");
  }
}
