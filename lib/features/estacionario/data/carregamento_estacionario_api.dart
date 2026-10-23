import "package:dio/dio.dart";
import "package:flutter/foundation.dart";

import "../../../utils/station_bridge_url.dart";
import "../domain/carregamento_payload.dart";
import "../domain/station_claim.dart";

/// Host + porta usados para chamar o **bridge HTTP** no tablet estacion?rio.
typedef EstacionarioHostPort = ({String host, int port});

class CarregamentoEstacionarioApi {
  CarregamentoEstacionarioApi({required this.host, required this.port})
      : _dio = Dio(
          BaseOptions(
            baseUrl: "http://$host:$port",
            connectTimeout: const Duration(milliseconds: 8000),
            receiveTimeout: const Duration(milliseconds: 8000),
            sendTimeout: const Duration(milliseconds: 8000),
            headers: const {
              "Accept": "application/json",
              "Content-Type": "application/json",
            },
          ),
        );

  final String host;
  final int port;
  final Dio _dio;
  String get _base => "http://$host:$port";

  /// Aceita `http://192.168.1.5:8080`, `192.168.1.5:8080` ou s? host com porta.
  ///
  /// Se n?o houver porta na URL, usa **8080** para `http` (padr?o do bridge no app)
  /// ??? antes ca?a em 80 e o teste falhava mesmo com rede OK.
  static EstacionarioHostPort? tryParseHostPort(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return null;
    if (!s.contains("://")) {
      s = "http://$s";
    }
    final uri = Uri.tryParse(s);
    if (uri == null || uri.host.trim().isEmpty) return null;
    final host = uri.host.trim();
    final int port;
    if (uri.hasPort) {
      port = uri.port;
    } else {
      port = uri.scheme.toLowerCase() == "https" ? 443 : 8080;
    }
    if (port <= 0 || port > 65535) return null;
    return (host: host, port: port);
  }

  static CarregamentoEstacionarioApi? tryFromBaseUrl(String raw) {
    final hp = parseStationBridgeHostPort(raw);
    if (hp == null) return null;
    return CarregamentoEstacionarioApi(host: hp.host, port: hp.port);
  }

  /// Garante `http://host:8080` (corrige legado `:80` ou URL sem porta).
  static String normalizeBaseUrl(String raw) => normalizeStationBridgeUrl(raw);

  static String mensagemErroDio(Object e) {
    if (e is DioException) {
      final t = e.type;
      if (t == DioExceptionType.connectionTimeout ||
          t == DioExceptionType.sendTimeout ||
          t == DioExceptionType.receiveTimeout) {
        return "Tempo esgotado ao conectar. Confira IP, porta e Wi???Fi.";
      }
      if (t == DioExceptionType.connectionError) {
        final msg = (e.message ?? "").toLowerCase();
        if (msg.contains("refused") || msg.contains("connection refused")) {
          return "Conex?o recusada. Use a porta do bridge (ex.: :8080), "
              "igual ? ?Porta estacion?rio? no tablet misturador, e confira se o Bridge est? ON.";
        }
        return "Sem rota ao servidor (${e.message ?? "erro de rede"}). "
            "Confira o IP do tablet estacion?rio na mesma rede.";
      }
      if (t == DioExceptionType.badCertificate) {
        return "Certificado HTTPS inv?lido. Use http:// e porta do bridge.";
      }
      return e.message ?? e.toString();
    }
    return e.toString();
  }

  String _clip(Object? data, {int max = 300}) {
    final s = (data ?? "").toString();
    if (s.length <= max) return s;
    return "${s.substring(0, max)}...";
  }

  Future<bool> health() async {
    final r = await tryHealth();
    return r.ok;
  }

  /// Para toasts: devolve mensagem detalhada quando falha.
  Future<({bool ok, String message, String? stationId, String? name})>
      tryHealth() async {
    try {
      debugPrint("[EST_API] GET $_base/health");
      final r = await _dio.get("/health");
      debugPrint(
          "[EST_API] /health status=${r.statusCode} body=${_clip(r.data)}");
      if (r.statusCode == 200) {
        String? stationId;
        String? name;
        final data = r.data;
        if (data is Map) {
          final sid = (data["stationId"] ?? "").toString().trim();
          stationId = sid.isEmpty ? null : sid;
          final n = (data["name"] ?? "").toString().trim();
          name = n.isEmpty ? null : n;
        }
        return (
          ok: true,
          message: "Conexão OK ($_base/health).",
          stationId: stationId,
          name: name,
        );
      }
      return (
        ok: false,
        message: "HTTP ${r.statusCode} (esperado 200).",
        stationId: null,
        name: null,
      );
    } catch (e) {
      debugPrint("[EST_API] /health erro=$e");
      return (
        ok: false,
        message: mensagemErroDio(e),
        stationId: null,
        name: null,
      );
    }
  }

  Future<List<CarregamentoResumoDto>> listCarregamentos({
    String? truckDeviceId,
  }) async {
    final q = (truckDeviceId ?? "").trim();
    final path = q.isEmpty
        ? "/carregamentos"
        : "/carregamentos?truckDeviceId=${Uri.encodeQueryComponent(q)}";
    debugPrint("[EST_API] GET $_base$path");
    final r = await _dio.get(path);
    debugPrint(
      "[EST_API] /carregamentos status=${r.statusCode} body=${_clip(r.data)}",
    );
    final data = r.data;
    final list = (data is List)
        ? data
        : (data is Map && data["items"] is List)
            ? (data["items"] as List)
            : const [];

    return list
        .whereType<Map>()
        .map(
            (e) => CarregamentoResumoDto.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<CarregamentoDetalheDto> getDetalhe(String id) async {
    debugPrint("[EST_API] GET $_base/carregamentos/$id");
    final r = await _dio.get("/carregamentos/$id");
    debugPrint(
      "[EST_API] /carregamentos/$id status=${r.statusCode} body=${_clip(r.data)}",
    );
    final data = (r.data is Map)
        ? Map<String, dynamic>.from(r.data as Map)
        : <String, dynamic>{};
    return CarregamentoDetalheDto.fromJson(data);
  }

  /// Resultado de claim/release/ack no cliente.
  static StationApiResult resultFromResponse(Response r) {
    final data = r.data is Map
        ? Map<String, dynamic>.from(r.data as Map)
        : <String, dynamic>{};
    final code = (data["code"] ?? "").toString();
    return StationApiResult(
      statusCode: r.statusCode ?? 0,
      ok: (r.statusCode ?? 0) >= 200 && (r.statusCode ?? 0) < 300,
      code: code,
      handoffId: (data["handoffId"] ?? "").toString(),
      claimExpiresAt: (data["claimExpiresAt"] ?? "").toString(),
      alreadyOwned: data["alreadyOwned"] == true,
      alreadyAcked: data["alreadyAcked"] == true,
      raw: data,
    );
  }

  Future<StationApiResult> claim({
    required String id,
    required String truckDeviceId,
  }) async {
    try {
      debugPrint("[EST_API] POST claim id=$id truck=$truckDeviceId");
      final r = await _dio.post(
        "/carregamentos/$id/claim",
        data: {"truckDeviceId": truckDeviceId},
        options: Options(
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      if (r.statusCode == 404) {
        final parsed = resultFromResponse(r);
        // Bridge novo: carga inexistente. Bridge antigo: rota /claim inexistente.
        if (parsed.code == StationClaim.codeNotFound) return parsed;
        debugPrint("[${StationClaim.codeClaimUnsupported}] /claim 404");
        return StationApiResult(
          statusCode: 404,
          ok: false,
          code: StationClaim.codeClaimUnsupported,
        );
      }
      return resultFromResponse(r);
    } on DioException catch (e) {
      final status = e.response?.statusCode ?? 0;
      if (status == 404) {
        final data = e.response?.data;
        final code = data is Map ? (data["code"] ?? "").toString() : "";
        if (code == StationClaim.codeNotFound) {
          return StationApiResult(
            statusCode: 404,
            ok: false,
            code: StationClaim.codeNotFound,
          );
        }
        debugPrint("[${StationClaim.codeClaimUnsupported}] /claim Dio 404");
        return StationApiResult(
          statusCode: 404,
          ok: false,
          code: StationClaim.codeClaimUnsupported,
        );
      }
      debugPrint("[EST_API] claim erro=$e");
      return StationApiResult(
        statusCode: status,
        ok: false,
        code: "NETWORK_ERROR",
        message: mensagemErroDio(e),
      );
    }
  }

  Future<StationApiResult> release({
    required String id,
    required String truckDeviceId,
  }) async {
    try {
      final r = await _dio.post(
        "/carregamentos/$id/release",
        data: {"truckDeviceId": truckDeviceId},
        options: Options(
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      return resultFromResponse(r);
    } on DioException catch (e) {
      debugPrint("[EST_API] release erro=$e");
      return StationApiResult(
        statusCode: e.response?.statusCode ?? 0,
        ok: false,
        code: "NETWORK_ERROR",
        message: mensagemErroDio(e),
      );
    }
  }

  /// Confirma importação. Preferir [truckDeviceId] (Bridge novo).
  Future<bool> ack({
    required String id,
    required String truckDeviceId,
    String? appVersion,
    String? deviceLegacy,
  }) async {
    try {
      final body = <String, Object?>{
        if (StationClaim.isValidTruckDeviceId(truckDeviceId))
          "truckDeviceId": truckDeviceId.trim(),
        if ((deviceLegacy ?? "").trim().isNotEmpty)
          "device": deviceLegacy!.trim(),
        "recebido_em": DateTime.now().toIso8601String(),
        if ((appVersion ?? "").trim().isNotEmpty) "app_version": appVersion,
      };
      final r = await _dio.post(
        "/carregamentos/$id/ack",
        data: body,
        options: Options(
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      final ok = r.statusCode == 200;
      if (!ok) {
        debugPrint(
          "[ESTACIONARIO_API] ack HTTP ${r.statusCode} id=$id body=${_clip(r.data)}",
        );
      }
      return ok;
    } catch (e) {
      debugPrint("[ESTACIONARIO_API] ack falhou id=$id erro=$e");
      return false;
    }
  }
}

class StationApiResult {
  StationApiResult({
    required this.statusCode,
    required this.ok,
    this.code = "",
    this.handoffId = "",
    this.claimExpiresAt = "",
    this.alreadyOwned = false,
    this.alreadyAcked = false,
    this.message = "",
    this.raw = const {},
  });

  final int statusCode;
  final bool ok;
  final String code;
  final String handoffId;
  final String claimExpiresAt;
  final bool alreadyOwned;
  final bool alreadyAcked;
  final String message;
  final Map<String, dynamic> raw;

  bool get isConflict => statusCode == 409;
  bool get isLegacyUnsupported =>
      code == StationClaim.codeClaimUnsupported || statusCode == 404;
}
