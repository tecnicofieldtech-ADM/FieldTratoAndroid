/// Normaliza URL do bridge HTTP no tablet estacionário (porta padrão 8080).
String normalizeStationBridgeUrl(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return "";
  if (!s.contains("://")) s = "http://$s";
  final uri = Uri.tryParse(s);
  if (uri == null || uri.host.trim().isEmpty) return raw.trim();
  var port = uri.hasPort
      ? uri.port
      : (uri.scheme.toLowerCase() == "https" ? 443 : 8080);
  if (port == 80 || (port < 1024 && uri.scheme.toLowerCase() == "http")) {
    port = 8080;
  }
  return "${uri.scheme}://${uri.host}:$port";
}

/// Host + porta do bridge estacionário.
({String host, int port})? parseStationBridgeHostPort(String raw) {
  final normalized = normalizeStationBridgeUrl(raw);
  if (normalized.isEmpty) return null;
  final uri = Uri.tryParse(normalized);
  if (uri == null || uri.host.trim().isEmpty || !uri.hasPort) return null;
  return (host: uri.host.trim(), port: uri.port);
}
