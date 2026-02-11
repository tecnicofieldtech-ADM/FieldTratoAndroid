// lib/services/carregamento_bridge.dart
import "dart:convert";
import "dart:io";

import "package:flutter/foundation.dart";

import "../features/fornecimento/data/carregamento_dao.dart";

class CarregamentoBridgeServer {
  CarregamentoBridgeServer._();

  static final CarregamentoBridgeServer instance = CarregamentoBridgeServer._();

  HttpServer? _server;

  bool get running => _server != null;

  final ValueNotifier<String> statusText = ValueNotifier<String>("OFF");

  Future<void> start({int port = 8080}) async {
    if (_server != null) return;
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    statusText.value = "ON :$port";
    _server!.listen(_handle, onError: (_) {});
  }

  Future<void> stop() async {
    final s = _server;
    _server = null;
    if (s != null) {
      await s.close(force: true);
    }
    statusText.value = "OFF";
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      _touch("REQ ${req.method} ${req.uri.path}");
      final path = req.uri.path;
      if (req.method == "GET" && path == "/carregamento/aberto") {
        final dataStr = req.uri.queryParameters["data"];
        DateTime? data;
        if (dataStr != null && dataStr.length >= 10) {
          data = DateTime.tryParse(dataStr.substring(0, 10));
        }

        final dao = CarregamentoDao();
        final car = await dao.getAbertoHoje(data: data ?? DateTime.now());
        if (car == null) {
        _touch("SEM ABERTO");
        return _json(req, 200, {"ok": false, "message": "sem_aberto"});
        }

        _touch("ABERTO OK");
        return _json(req, 200, {
          "ok": true,
          "carregamento": _mapCarregamento(car),
        });
      }

      if (req.method == "POST" && path == "/carregamento/consumido") {
        final body = await utf8.decoder.bind(req).join();
        final data = (body.trim().isEmpty) ? {} : jsonDecode(body);

        final id = (data["id"] ?? data["ID"] ?? "").toString().trim();
        if (id.isEmpty) {
          return _json(req, 400, {"ok": false, "message": "id_vazio"});
        }

        final dao = CarregamentoDao();
        await dao.marcarConsumido(id);
        _touch("CONSUMIDO $id");
        return _json(req, 200, {"ok": true});
      }

      _touch("404 ${req.method} ${req.uri.path}");
      return _json(req, 404, {"ok": false, "message": "not_found"});
    } catch (_) {
      _touch("ERRO");
      return _json(req, 500, {"ok": false, "message": "erro_interno"});
    }
  }

  Map<String, Object?> _mapCarregamento(Map<String, Object?> m) {
    Object? pick(List<String> keys) {
      for (final k in keys) {
        if (m.containsKey(k)) return m[k];
      }
      return null;
    }

    return {
      "id": (pick(["ID", "id"]) ?? "").toString(),
      "dataRegistro": (pick(["DATA_REGISTRO", "data_registro"]) ?? "").toString(),
      "status": pick(["STATUS", "status"]),
      "idFabricacao": (pick(["ID_FABRICACAO", "id_fabricacao"]) ?? "").toString(),
      "idDieta": (pick(["ID_DIETA", "id_dieta"]) ?? "").toString(),
      "pesoFabricado": pick(["PESO_FABRICADO", "peso_fabricado"]),
      "pesoCarregado": pick(["PESO_CARREGADO", "peso_carregado"]),
      "idVagao": (pick(["ID_VAGAO", "id_vagao"]) ?? "").toString(),
    };
  }

  void _json(HttpRequest req, int status, Object body) {
    req.response.statusCode = status;
    req.response.headers.contentType = ContentType.json;
    req.response.write(jsonEncode(body));
    req.response.close();
  }

  void _touch(String msg) {
    if (_server == null) return;
    final t = DateTime.now();
    statusText.value = "${t.hour.toString().padLeft(2, "0")}:${t.minute.toString().padLeft(2, "0")}:${t.second.toString().padLeft(2, "0")}  $msg";
  }
}
