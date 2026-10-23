/// Protocolo UDP de descoberta de estacionárias (v1).
class StationDiscoveryProtocol {
  static const int udpPort = 19091;
  static const int version = 1;
  static const String typeDiscover = "RFEED_DISCOVER_STATION";
  static const String typeStation = "RFEED_STATION";
  static const Duration listenWindow = Duration(seconds: 2);

  static Map<String, Object?> discoverRequest() => {
        "type": typeDiscover,
        "version": version,
      };

  static Map<String, Object?> stationReply({
    required String stationId,
    required String name,
    required int port,
    String? ip,
  }) =>
      {
        "type": typeStation,
        "version": version,
        "stationId": stationId,
        "name": name,
        "port": port,
        if (ip != null && ip.trim().isNotEmpty) "ip": ip.trim(),
      };

  /// Parse + validação de resposta discovery (host efetivo = [remoteHost] do UDP).
  static DiscoveredStation? parseStationReply({
    required Object? json,
    required String remoteHost,
  }) {
    if (json is! Map) return null;
    final m = Map<String, dynamic>.from(json);

    final type = (m["type"] ?? "").toString().trim().toUpperCase();
    if (type != typeStation) return null;

    final ver = _toInt(m["version"]);
    if (ver != version) return null;

    final id = (m["stationId"] ?? "").toString().trim();
    if (id.isEmpty) return null;

    final port = _toInt(m["port"], def: 8080);
    if (port <= 0 || port > 65535) return null;

    final host = remoteHost.trim();
    if (host.isEmpty) return null;

    final name = (m["name"] ?? "").toString().trim();
    return DiscoveredStation(
      stationId: id,
      name: name.isEmpty ? host : name,
      host: host,
      port: port,
      version: ver,
      lastSeen: DateTime.now(),
      fromDiscovery: true,
      online: true,
    );
  }

  /// Deduplica por stationId (última ocorrência vence).
  static List<DiscoveredStation> dedupeByStationId(
    Iterable<DiscoveredStation> items,
  ) {
    final byId = <String, DiscoveredStation>{};
    for (final s in items) {
      final id = s.stationId.trim();
      if (id.isEmpty) continue;
      byId[id] = s;
    }
    final list = byId.values.toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
    return list;
  }

  static int _toInt(Object? v, {int def = 0}) {
    if (v == null) return def;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? def;
  }
}

/// Estação encontrada na rede (ou IP manual / recente).
class DiscoveredStation {
  const DiscoveredStation({
    required this.stationId,
    required this.name,
    required this.host,
    required this.port,
    this.version = StationDiscoveryProtocol.version,
    this.lastSeen,
    this.fromDiscovery = true,
    this.online = true,
  });

  final String stationId;
  final String name;
  final String host;
  final int port;
  final int version;
  final DateTime? lastSeen;
  final bool fromDiscovery;
  final bool online;

  String get baseUrl => "http://$host:$port";

  String get displayName {
    final n = name.trim();
    if (n.isNotEmpty) return n;
    return host;
  }

  DiscoveredStation copyWith({
    String? host,
    int? port,
    String? name,
    DateTime? lastSeen,
    bool? fromDiscovery,
    bool? online,
  }) {
    return DiscoveredStation(
      stationId: stationId,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      version: version,
      lastSeen: lastSeen ?? this.lastSeen,
      fromDiscovery: fromDiscovery ?? this.fromDiscovery,
      online: online ?? this.online,
    );
  }
}
