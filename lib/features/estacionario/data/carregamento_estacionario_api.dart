import "package:dio/dio.dart";
import "package:flutter/foundation.dart";

import "../domain/carregamento_payload.dart";

class CarregamentoEstacionarioApi {
  CarregamentoEstacionarioApi({required this.host, required this.port})
      : _dio = Dio(
          BaseOptions(
            baseUrl: "http://$host:$port",
            connectTimeout: const Duration(milliseconds: 2500),
            receiveTimeout: const Duration(milliseconds: 5000),
            sendTimeout: const Duration(milliseconds: 5000),
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

  String _clip(Object? data, {int max = 300}) {
    final s = (data ?? "").toString();
    if (s.length <= max) return s;
    return "${s.substring(0, max)}...";
  }

  Future<bool> health() async {
    try {
      debugPrint("[EST_API] GET $_base/health");
      final r = await _dio.get("/health");
      debugPrint("[EST_API] /health status=${r.statusCode} body=${_clip(r.data)}");
      return r.statusCode == 200;
    } catch (e) {
      debugPrint("[EST_API] /health erro=$e");
      return false;
    }
  }

  Future<List<CarregamentoResumoDto>> listCarregamentos() async {
    debugPrint("[EST_API] GET $_base/carregamentos");
    final r = await _dio.get("/carregamentos");
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

  Future<void> ack(
      {required String id,
      required String device,
      required String appVersion}) async {
    try {
      await _dio.post(
        "/carregamentos/$id/ack",
        data: {
          "device": device,
          "recebido_em": DateTime.now().toIso8601String(),
          "app_version": appVersion,
        },
      );
    } catch (e) {
      debugPrint("[ESTACIONARIO_API] ack falhou id=$id erro=$e");
    }
  }
}
