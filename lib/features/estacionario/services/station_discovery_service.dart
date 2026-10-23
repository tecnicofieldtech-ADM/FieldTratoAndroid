import "dart:async";
import "dart:convert";
import "dart:io";

import "package:flutter/foundation.dart";

import "../domain/station_discovery.dart";

/// Cliente UDP: broadcast + coleta de respostas por janela curta.
class StationDiscoveryService {
  Future<List<DiscoveredStation>> discover({
    Duration? window,
    int? port,
  }) async {
    final listenPort = port ?? StationDiscoveryProtocol.udpPort;
    final timeout = window ?? StationDiscoveryProtocol.listenWindow;
    final byId = <String, DiscoveredStation>{};

    debugPrint("[DISCOVERY_START] port=$listenPort window=${timeout.inMs}ms");

    RawDatagramSocket? sock;
    try {
      sock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      sock.broadcastEnabled = true;

      final req = utf8.encode(
        jsonEncode(StationDiscoveryProtocol.discoverRequest()),
      );

      final targets = await _broadcastTargets();
      for (final t in targets) {
        try {
          sock.send(req, t, listenPort);
        } catch (e) {
          debugPrint("[DISCOVERY_START] send fail ${t.address}: $e");
        }
      }

      final deadline = DateTime.now().add(timeout);
      while (DateTime.now().isBefore(deadline)) {
        final remaining = deadline.difference(DateTime.now());
        if (remaining.isNegative || remaining == Duration.zero) break;

        final dg = sock.receive();
        if (dg == null) {
          await Future<void>.delayed(const Duration(milliseconds: 40));
          continue;
        }

        final parsed = _parseReply(dg);
        if (parsed == null) continue;

        debugPrint(
          "[DISCOVERY_RESPONSE] id=${parsed.stationId} "
          "host=${parsed.host}:${parsed.port} name=${parsed.name}",
        );
        byId[parsed.stationId] = parsed;
      }
    } catch (e) {
      debugPrint("[DISCOVERY_TIMEOUT] erro=$e");
    } finally {
      sock?.close();
    }

    if (byId.isEmpty) {
      debugPrint("[DISCOVERY_TIMEOUT] nenhuma estação");
    }

    return StationDiscoveryProtocol.dedupeByStationId(byId.values);
  }

  Future<List<InternetAddress>> _broadcastTargets() async {
    final out = <InternetAddress>[
      InternetAddress("255.255.255.255"),
    ];
    try {
      for (final iface in await NetworkInterface.list(
        includeLinkLocal: false,
        type: InternetAddressType.IPv4,
      )) {
        for (final addr in iface.addresses) {
          if (addr.isLoopback) continue;
          final b = _subnetBroadcast(addr);
          if (b != null) out.add(b);
        }
      }
    } catch (_) {}
    return out;
  }

  InternetAddress? _subnetBroadcast(InternetAddress addr) {
    final parts = addr.address.split(".");
    if (parts.length != 4) return null;
    // Assumir /24 típico de Wi‑Fi de fazenda.
    return InternetAddress("${parts[0]}.${parts[1]}.${parts[2]}.255");
  }

  DiscoveredStation? _parseReply(Datagram dg) {
    try {
      final raw = utf8.decode(dg.data, allowMalformed: true).trim();
      if (raw.isEmpty) return null;
      final map = jsonDecode(raw);
      // Host efetivo = endereço remoto do pacote (não o IP do JSON).
      return StationDiscoveryProtocol.parseStationReply(
        json: map,
        remoteHost: dg.address.address,
      );
    } catch (_) {
      return null;
    }
  }
}

extension on Duration {
  int get inMs => inMilliseconds;
}
