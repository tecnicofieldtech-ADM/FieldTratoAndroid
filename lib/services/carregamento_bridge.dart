import "dart:convert";
import "dart:io";

import "package:flutter/foundation.dart";

import "../features/estacionario/data/carregamento_bridge_repo.dart";
import "../features/estacionario/domain/station_claim.dart";
import "../features/estacionario/domain/station_discovery.dart";
import "../features/estacionario/domain/station_handoff_mode.dart";
import "../features/estacionario/services/station_discovery_responder.dart";
import "../features/fabricacao/domain/fabricacao_flow.dart";
import "../repo/config_repo.dart";

class CarregamentoBridgeServer {
  CarregamentoBridgeServer._();

  static final CarregamentoBridgeServer instance = CarregamentoBridgeServer._();

  HttpServer? _server;
  final _repo = CarregamentoBridgeRepo();
  final _cfg = ConfigRepo();
  final _discovery = StationDiscoveryResponder();
  int _boundPort = 8080;

  bool get running => _server != null;

  final ValueNotifier<String> statusText = ValueNotifier<String>("OFF");

  Future<void> start({int port = 8080}) async {
    if (_server != null) {
      debugPrint("[BRIDGE] start ignorado: servidor ja ativo.");
      return;
    }

    await _cfg.ensureStationId();
    _boundPort = port <= 0 ? 8080 : port;

    debugPrint("[BRIDGE] iniciando em 0.0.0.0:$_boundPort ...");
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, _boundPort);
      statusText.value = "ON :$_boundPort";
      debugPrint("[BRIDGE] ON em 0.0.0.0:$_boundPort");
      _server!.listen(
        _handle,
        onError: (e, st) {
          debugPrint("[BRIDGE] erro no listen: $e");
          debugPrint("$st");
        },
      );
      try {
        await _discovery.start(httpPort: _boundPort);
      } catch (e) {
        debugPrint("[BRIDGE] discovery UDP falhou (HTTP segue): $e");
      }
      _touch("bridge on");
    } catch (e, st) {
      _server = null;
      statusText.value = "OFF (erro em :$_boundPort)";
      debugPrint("[BRIDGE] falha ao iniciar em :$_boundPort -> $e");
      debugPrint("$st");
      await _discovery.stop();
      rethrow;
    }
  }

  Future<void> stop() async {
    await _discovery.stop();
    final s = _server;
    _server = null;
    if (s != null) {
      await s.close(force: true);
      debugPrint("[BRIDGE] OFF (stop)");
    }
    statusText.value = "OFF";
  }

  Future<Map<String, Object?>> _identityPayload() async {
    final stationId = await _cfg.ensureStationId();
    final name = await _cfg.getStationDisplayName();
    final tipo = await _cfg.getTipoTrabalho();
    return {
      "service": StationDiscoveryProtocol.typeStation,
      "stationId": stationId,
      "name": name,
      "port": _boundPort,
      "version": StationDiscoveryProtocol.version,
      "tipoTrabalho": tipo,
      "claimSupported": true,
      "claimLeaseSeconds": StationClaim.claimLeaseDuration.inSeconds,
    };
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      final path = req.uri.path;
      _touch("REQ ${req.method} $path");

      if (req.method == "GET" && path == "/health") {
        final id = await _identityPayload();
        return _json(req, 200, {
          "ok": true,
          ...id,
        });
      }

      if (req.method == "GET" && (path == "/" || path.isEmpty)) {
        final id = await _identityPayload();
        return _json(req, 200, {
          "ok": true,
          ...id,
          "message": "Bridge ativo. Use /health ou /carregamentos.",
          "endpoints": [
            "GET /health",
            "GET /carregamentos",
            "GET /carregamentos/:id",
            "POST /carregamentos/:id/claim",
            "POST /carregamentos/:id/release",
            "POST /carregamentos/:id/ack",
          ],
        });
      }

      if (req.method == "GET" && path == "/carregamentos") {
        return _listCarregamentos(req);
      }

      if (req.method == "POST" && path.startsWith("/carregamentos/")) {
        final segs =
            path.split("/").where((e) => e.trim().isNotEmpty).toList();
        if (segs.length >= 3 && segs[0] == "carregamentos") {
          final id = segs[1].trim();
          final action = segs[2].toLowerCase();
          if (id.isEmpty) {
            return _json(req, 400, {
              "ok": false,
              "code": StationClaim.codeInvalid,
              "erro": "id_invalido",
            });
          }
          if (action == "claim") return _postClaim(req, id);
          if (action == "release") return _postRelease(req, id);
          if (action == "ack") return _postAck(req, id);
        }
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
    final truck = (req.uri.queryParameters["truckDeviceId"] ?? "").trim();
    final rows = await _repo.listDisponiveis(
      truckDeviceId: truck.isEmpty ? null : truck,
    );
    final items = rows
        .map(
          (m) {
            final fabStatus = fabricacaoStatusFromDb(m["fab_status"]);
            final fin = _toInt(m["finalizada"]);
            return {
              "idLocal": (m["id_local"] ?? "").toString(),
              "handoffId": (m["handoff_id"] ?? "").toString(),
              "data": (m["data"] ?? "").toString(),
              "hora": (m["hora"] ?? "").toString(),
              "nome_racao": (m["nome_racao"] ?? "").toString(),
              "total_fabricado_kg": _toNum(m["total_fabricado_kg"]),
              "status": fabricacaoStatusToApi(fabStatus),
              "fabStatus": fabricacaoStatusToDb(fabStatus),
              "finalizada": fin,
              "handoffMode": (m["handoff_mode"] ?? "").toString(),
              "claimStatus": (m["claim_status"] ?? StationClaim.statusAvailable)
                  .toString(),
              "claimExpiresAt": (m["claim_expires_at"] ?? "").toString(),
            };
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

    final resolvedId = (c["id_local"] ?? idLocal).toString();
    final insumos = await _repo.listInsumosFabricacao(resolvedId);

    final status = fabricacaoStatusFromDb(c["fab_status"]);
    final finCol = _toInt(c["finalizada"]);
    final handoffMode = resolveStationHandoffMode(
      fabStatus: c["fab_status"],
      finalizada: finCol,
    );
    final finFlag = finCol == 1 || status == FabricacaoStatus.finalizada;

    final payload = {
      "fabricacao": {
        "id_local": resolvedId,
        "id_origem": resolvedId,
        "handoff_id": (c["handoff_id"] ?? "").toString(),
        "status": fabricacaoStatusToApi(status),
        "fab_status": fabricacaoStatusToDb(status),
        "data": _coalesceStr(c["data_fabricacao"]),
        "hora_inicio": _coalesceStr(c["hora_inicio"]),
        "hora_fim": _coalesceStr(c["hora_fim"]),
        "id_racao": _coalesceStr(c["id_dieta"]),
        "nome_racao": _coalesceStr(c["nome_racao"]),
        "total_previsto_kg": _toNum(c["qtd_prevista"]),
        "total_realizado_kg": _toNum(c["qtd_realizada"]),
        "observacao": "",
        "finalizada": finFlag,
        "exportado_em": _coalesceStr(c["exportado_em"]),
        "origin_device":
            _coalesceStr(c["origin_device"], fallback: "ESTACIONARIO"),
        "handoff_mode": handoffMode?.apiValue ?? "",
      },
      "insumos": insumos,
      "meta": {
        "origem": "ESTACIONARIO",
        "versao": 1,
        "handoffMode": handoffMode?.apiValue ?? "",
      }
    };

    _touch("DETALHE $resolvedId");
    return _json(req, 200, payload);
  }

  Future<Map<String, dynamic>?> _readJsonBody(HttpRequest req) async {
    try {
      final raw = await utf8.decoder.bind(req).join();
      if (raw.trim().isEmpty) return <String, dynamic>{};
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return null;
    } catch (_) {
      return null;
    }
  }

  String _truckFromBody(Map<String, dynamic> body) {
    return (body["truckDeviceId"] ??
            body["truck_device_id"] ??
            body["device"] ??
            "")
        .toString()
        .trim();
  }

  Future<void> _postClaim(HttpRequest req, String id) async {
    final body = await _readJsonBody(req);
    if (body == null) {
      return _json(req, 400, {
        "ok": false,
        "code": StationClaim.codeInvalid,
        "erro": "json_invalido",
      });
    }
    final truck = _truckFromBody(body);
    final r = await _repo.claim(idOrHandoff: id, truckDeviceId: truck);

    switch (r.outcome) {
      case ClaimOutcome.ok:
      case ClaimOutcome.alreadyOwned:
        _touch("CLAIM_OK $id");
        return _json(req, 200, {
          "ok": true,
          "handoffId": r.handoffId,
          "claimedBy": r.claimedBy,
          "claimExpiresAt": r.claimExpiresAt,
          "alreadyOwned": r.alreadyOwned,
        });
      case ClaimOutcome.conflict:
        _touch("CLAIM_409 $id");
        return _json(req, 409, {
          "ok": false,
          "code": StationClaim.codeAlreadyClaimed,
          "claimExpiresAt": r.claimExpiresAt,
        });
      case ClaimOutcome.alreadyLoaded:
        return _json(req, 409, {
          "ok": false,
          "code": StationClaim.codeAlreadyLoaded,
        });
      case ClaimOutcome.notFound:
        return _json(req, 404, {
          "ok": false,
          "code": StationClaim.codeNotFound,
          "erro": "fabricacao_nao_encontrada",
        });
      case ClaimOutcome.invalid:
        return _json(req, 400, {
          "ok": false,
          "code": StationClaim.codeInvalid,
          "erro": r.message,
        });
      case ClaimOutcome.forbidden:
        return _json(req, 403, {
          "ok": false,
          "code": StationClaim.codeForbidden,
        });
    }
  }

  Future<void> _postRelease(HttpRequest req, String id) async {
    final body = await _readJsonBody(req);
    if (body == null) {
      return _json(req, 400, {
        "ok": false,
        "code": StationClaim.codeInvalid,
        "erro": "json_invalido",
      });
    }
    final truck = _truckFromBody(body);
    final r = await _repo.release(idOrHandoff: id, truckDeviceId: truck);

    switch (r.outcome) {
      case ClaimOutcome.ok:
      case ClaimOutcome.alreadyOwned:
        _touch("RELEASE_OK $id");
        return _json(req, 200, {"ok": true});
      case ClaimOutcome.forbidden:
      case ClaimOutcome.conflict:
        return _json(req, 409, {
          "ok": false,
          "code": StationClaim.codeForbidden,
        });
      case ClaimOutcome.notFound:
        return _json(req, 404, {
          "ok": false,
          "code": StationClaim.codeNotFound,
          "erro": "fabricacao_nao_encontrada",
        });
      case ClaimOutcome.invalid:
        return _json(req, 400, {
          "ok": false,
          "code": StationClaim.codeInvalid,
          "erro": r.message,
        });
      case ClaimOutcome.alreadyLoaded:
        return _json(req, 200, {"ok": true});
    }
  }

  Future<void> _postAck(HttpRequest req, String id) async {
    final body = await _readJsonBody(req);
    if (body == null) {
      return _json(req, 400, {
        "ok": false,
        "code": StationClaim.codeInvalid,
        "erro": "json_invalido",
      });
    }

    final truck = _truckFromBody(body);
    // Bridge novo: exige truckDeviceId válido.
    // Compat: body sem UUID → fluxo legado (sem claim).
    final requireClaim = StationClaim.isValidTruckDeviceId(truck);
    final r = await _repo.ack(
      idOrHandoff: id,
      truckDeviceId: requireClaim ? truck : null,
      requireClaim: requireClaim,
    );

    switch (r.outcome) {
      case ClaimOutcome.ok:
      case ClaimOutcome.alreadyOwned:
        _touch(r.alreadyAcked ? "ACK_IDEMP $id" : "ACK_OK $id");
        return _json(req, 200, {
          "ok": true,
          "alreadyAcked": r.alreadyAcked,
        });
      case ClaimOutcome.conflict:
        return _json(req, 409, {
          "ok": false,
          "code": StationClaim.codeAlreadyClaimed,
        });
      case ClaimOutcome.forbidden:
        return _json(req, 403, {
          "ok": false,
          "code": StationClaim.codeForbidden,
          "erro": r.message,
        });
      case ClaimOutcome.notFound:
        return _json(req, 404, {
          "ok": false,
          "code": StationClaim.codeNotFound,
          "erro": "fabricacao_nao_encontrada",
        });
      case ClaimOutcome.invalid:
        return _json(req, 400, {
          "ok": false,
          "code": StationClaim.codeInvalid,
          "erro": r.message,
        });
      case ClaimOutcome.alreadyLoaded:
        return _json(req, 200, {"ok": true, "alreadyAcked": true});
    }
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

  int _toInt(Object? v, {int fallback = 0}) {
    if (v == null) return fallback;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? fallback;
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
