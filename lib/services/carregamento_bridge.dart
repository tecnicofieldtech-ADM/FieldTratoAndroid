import "dart:convert";
import "dart:io";

import "package:flutter/foundation.dart";

import "../features/estacionario/data/carregamento_bridge_repo.dart";
import "../features/fabricacao/domain/fabricacao_flow.dart";

class CarregamentoBridgeServer {
  CarregamentoBridgeServer._();

  static final CarregamentoBridgeServer instance = CarregamentoBridgeServer._();

  HttpServer? _server;
  final _repo = CarregamentoBridgeRepo();

  bool get running => _server != null;

  final ValueNotifier<String> statusText = ValueNotifier<String>("OFF");

  Future<void> start({int port = 8080}) async {
    if (_server != null) {
      debugPrint("[BRIDGE] start ignorado: servidor ja ativo.");
      return;
    }

    debugPrint("[BRIDGE] iniciando em 0.0.0.0:$port ...");
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
      statusText.value = "ON :$port";
      debugPrint("[BRIDGE] ON em 0.0.0.0:$port");
      _server!.listen(
        _handle,
        onError: (e, st) {
          debugPrint("[BRIDGE] erro no listen: $e");
          debugPrint("$st");
        },
      );
      _touch("bridge on");
    } catch (e, st) {
      _server = null;
      statusText.value = "OFF (erro em :$port)";
      debugPrint("[BRIDGE] falha ao iniciar em :$port -> $e");
      debugPrint("$st");
      rethrow;
    }
  }

  Future<void> stop() async {
    final s = _server;
    _server = null;
    if (s != null) {
      await s.close(force: true);
      debugPrint("[BRIDGE] OFF (stop)");
    }
    statusText.value = "OFF";
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      final path = req.uri.path;
      _touch("REQ ${req.method} $path");

      if (req.method == "GET" && path == "/health") {
        return _json(req, 200, {"ok": true});
      }

      if (req.method == "GET" && path == "/carregamentos") {
        return _listCarregamentos(req);
      }

      if (req.method == "GET" && path.startsWith("/carregamentos/")) {
        final id = _extractId(path);
        if (id == null || id.isEmpty) {
          return _json(req, 400, {"erro": "id_invalido"});
        }
        return _getCarregamentoDetalhe(req, id);
      }

      return _json(req, 404, {"ok": false, "message": "not_found"});
    } catch (e) {
      _touch("ERRO $e");
      return _json(req, 500, {
        "ok": false,
        "message": "erro_interno",
        "erro": e.toString(),
      });
    }
  }

  Future<void> _listCarregamentos(HttpRequest req) async {
    final rows = await _repo.listDisponiveis();
    final items = rows
        .map(
          (m) => {
            "idLocal": (m["id_local"] ?? "").toString(),
            "handoffId": (m["handoff_id"] ?? "").toString(),
            "data": (m["data"] ?? "").toString(),
            "hora": (m["hora"] ?? "").toString(),
            "nome_racao": (m["nome_racao"] ?? "").toString(),
            "total_fabricado_kg": _toNum(m["total_fabricado_kg"]),
            "status": fabricacaoStatusToApi(
              fabricacaoStatusFromDb(m["fab_status"]),
            ),
          },
        )
        .toList();

    _touch("LISTA ${items.length}");
    return _json(req, 200, items);
  }

  Future<void> _getCarregamentoDetalhe(HttpRequest req, String idLocal) async {
    final c = await _repo.getByFabricacaoId(idLocal);
    if (c == null) {
      return _json(req, 404, {"erro": "fabricacao_nao_encontrada"});
    }

    final insumos = await _repo.listInsumosFabricacao(idLocal);

    final status = fabricacaoStatusFromDb(c["fab_status"]);

    final payload = {
      "fabricacao": {
        "id_local": idLocal,
        "id_origem": idLocal,
        "handoff_id": (c["handoff_id"] ?? "").toString(),
        "status": fabricacaoStatusToApi(status),
        "data": _coalesceStr(c["data_fabricacao"]),
        "hora_inicio": _coalesceStr(c["hora_inicio"]),
        "hora_fim": _coalesceStr(c["hora_fim"]),
        "id_racao": _coalesceStr(c["id_dieta"]),
        "nome_racao": _coalesceStr(c["nome_racao"]),
        "total_previsto_kg": _toNum(c["qtd_prevista"]),
        "total_realizado_kg": _toNum(c["qtd_realizada"]),
        "observacao": "",
        "finalizada": status == FabricacaoStatus.finalizada,
        "exportado_em": _coalesceStr(c["exportado_em"]),
        "origin_device": _coalesceStr(c["origin_device"], fallback: "ESTACIONARIO"),
      },
      "insumos": insumos,
      "meta": {
        "origem": "ESTACIONARIO",
        "versao": 1,
      }
    };

    _touch("DETALHE $idLocal");
    return _json(req, 200, payload);
  }

  String? _extractId(String path) {
    final seg = path.split("/").where((e) => e.trim().isNotEmpty).toList();
    if (seg.length < 2) return null;
    return seg[1];
  }

  String _coalesceStr(Object? v, {String fallback = ""}) {
    final s = (v ?? "").toString().trim();
    return s.isEmpty ? fallback : s;
  }

  double _toNum(Object? v, {double fallback = 0}) {
    if (v == null) return fallback;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().replaceAll(",", ".")) ?? fallback;
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
    statusText.value =
        "${t.hour.toString().padLeft(2, "0")}:${t.minute.toString().padLeft(2, "0")}:${t.second.toString().padLeft(2, "0")}  $msg";
  }
}
