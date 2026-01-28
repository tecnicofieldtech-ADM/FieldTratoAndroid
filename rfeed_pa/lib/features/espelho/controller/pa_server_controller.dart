// lib/features/espelho/controller/pa_server_controller.dart
import "dart:convert";
import "dart:io";

import "package:flutter/foundation.dart";

import "../data/mirror_targets_repo.dart";
import "../domain/mirror_target.dart";

class PaServerController extends ChangeNotifier {
  PaServerController({
    required this.repo,
    this.port = 9000,
  });

  final MirrorTargetsRepo repo;
  final int port;

  ServerSocket? _server;

  final Map<String, Socket> _clients = {}; // key = "ip:remotePort"
  final Map<String, StringBuffer> _buffers = {};

  String? _activeClientKey;
  MirrorTarget? activeTarget;

  bool listening = false;
  String listenBind = "0.0.0.0";
  String status = "Parado";

  DateTime? lastMsgAt;
  String lastFromIp = "";

  Map<String, dynamic>? lastState;

  int accepted = 0;
  int dropped = 0;

  // ✅ anti-flicker por ingrediente/posição
  int _uiPos = 0;
  bool _uiIsPre = false;

  // ✅ cache do auto pra UI não “sumir” se vier state sem auto
  Map<String, dynamic>? _lastAuto;
  DateTime? _lastAutoAt;

  // =========================
  // PUBLIC
  // =========================
  Future<void> loadActive() async {
    activeTarget = await repo.getActive();
    notifyListeners();
  }

  Future<void> start() async {
    await loadActive();
    if (listening) return;

    status = "Iniciando…";
    notifyListeners();

    try {
      await _safeCloseServer();

      _server = await ServerSocket.bind(InternetAddress.anyIPv4, port);

      listening = true;
      listenBind = await _getLocalIpv4Label();
      status = "Escutando $listenBind:$port";
      notifyListeners();

      _server!.listen(
        _onClient,
        onError: (e) {
          status = "Erro server: $e";
          listening = false;
          notifyListeners();
        },
        onDone: () {
          status = "Server finalizado";
          listening = false;
          notifyListeners();
        },
      );
    } catch (e) {
      status = "Falha ao abrir porta $port: $e";
      listening = false;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    listening = false;
    status = "Parando…";
    notifyListeners();

    _dropAllClients();
    await _safeCloseServer();

    _clearStates();

    status = "Parado";
    notifyListeners();
  }

  Future<void> restart() async {
    await stop();
    await start();
  }

  Future<void> setActiveTargetById(int id) async {
    await repo.setActive(id);
    await loadActive();

    _dropAllClients();
    _clearStates();

    notifyListeners();
  }

  int get clientsCount => _clients.length;

  // ✅ helpers “prontos” pra UI
  Map<String, dynamic>? get autoState {
    // se veio auto no state atual
    final st = lastState;
    final a = (st != null && st["auto"] is Map)
        ? Map<String, dynamic>.from(st["auto"] as Map)
        : null;

    if (a != null) return a;

    // fallback: se chegou recentemente
    final dt = _lastAutoAt;
    if (dt != null && DateTime.now().difference(dt).inSeconds <= 5) {
      return _lastAuto;
    }
    return null;
  }

  bool get autoEnabled {
    final a = autoState;
    if (a == null) return false;
    final v = a["enabled"];
    return v == 1 || v == true || v == "1";
  }

  int get autoCountdown {
    final a = autoState;
    if (a == null) return 0;
    final v = a["countdown"];
    return (v is num) ? v.toInt() : int.tryParse("$v") ?? 0;
  }

  // =========================
  // INTERNAL
  // =========================
  void _clearStates() {
    lastState = null;
    lastFromIp = "";
    lastMsgAt = null;
    _uiPos = 0;
    _uiIsPre = false;

    _lastAuto = null;
    _lastAutoAt = null;
  }

  Future<void> _safeCloseServer() async {
    final s = _server;
    _server = null;
    if (s != null) {
      try {
        await s.close();
      } catch (_) {}
    }
  }

  Future<String> _getLocalIpv4Label() async {
    try {
      final ifaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );

      final ips = <String>[];
      for (final i in ifaces) {
        for (final a in i.addresses) {
          final ip = a.address;
          if (ip.startsWith("127.")) continue;
          ips.add(ip);
        }
      }

      if (ips.isEmpty) return "0.0.0.0";
      return ips.join(", ");
    } catch (_) {
      return "0.0.0.0";
    }
  }

  void _dropAllClients() {
    _activeClientKey = null;
    for (final s in _clients.values) {
      try {
        s.destroy();
      } catch (_) {}
    }
    _clients.clear();
    _buffers.clear();
  }

  void _drop(String key) {
    final s = _clients.remove(key);
    _buffers.remove(key);

    if (_activeClientKey == key) {
      _activeClientKey = null;
    }

    try {
      s?.destroy();
    } catch (_) {}

    notifyListeners();
  }

  void _onClient(Socket sock) {
    final ip = sock.remoteAddress.address;
    final key = "$ip:${sock.remotePort}";

    // ✅ filtra IP do caminhão ativo (se selecionado)
    final allowedIp = activeTarget?.host.trim();
    if (allowedIp != null && allowedIp.isNotEmpty && ip != allowedIp) {
      dropped++;
      try {
        sock.destroy();
      } catch (_) {}
      notifyListeners();
      return;
    }

    accepted++;
    _clients[key] = sock;
    _buffers[key] = StringBuffer();

    sock.listen(
      (bytes) => _onData(key, ip, bytes),
      onError: (_) => _drop(key),
      onDone: () => _drop(key),
      cancelOnError: true,
    );

    notifyListeners();
  }

  void _electActiveAndCloseOthersSameIp(String ip, String winnerKey) {
    _activeClientKey = winnerKey;

    final others = _clients.keys
        .where((k) => k.startsWith("$ip:") && k != winnerKey)
        .toList();

    for (final k in others) {
      dropped++;
      _drop(k);
    }
  }

  bool _isTrue(dynamic v) => v == true || v == 1 || v == "1";

  bool _isPreFromAtual(Map<String, dynamic>? atual) {
    if (atual == null) return false;
    if (atual.containsKey("pre")) return _isTrue(atual["pre"]);
    if (atual.containsKey("prePesado")) return _isTrue(atual["prePesado"]);
    return false;
  }

  int _posFromAtual(Map<String, dynamic>? atual) {
    if (atual == null) return 0;
    final p = atual["pos"];
    return (p is num) ? p.toInt() : int.tryParse("$p") ?? 0;
  }

  bool _hasActiveAuto(Map<String, dynamic> map) {
    if (map["auto"] is! Map) return false;
    final a = Map<String, dynamic>.from(map["auto"] as Map);
    final enabled = _isTrue(a["enabled"]);
    final cd = a["countdown"];
    final countdown = (cd is num) ? cd.toInt() : int.tryParse("$cd") ?? 0;
    return enabled && countdown > 0;
  }

  bool _acceptForUi({required int pos, required bool isPre}) {
    // Primeiro state
    if (_uiPos == 0) {
      _uiPos = pos;
      _uiIsPre = isPre;
      return true;
    }

    // Mudou de ingrediente -> aceita sempre
    if (pos != 0 && pos != _uiPos) {
      _uiPos = pos;
      _uiIsPre = isPre;
      return true;
    }

    // Mesmo ingrediente:
    // Se já estamos em MAIN, ignora PRE (evita piscar)
    if (!_uiIsPre && isPre) return false;

    // Se estamos em PRE e chega MAIN do mesmo pos -> troca e aceita
    if (_uiIsPre && !isPre) {
      _uiIsPre = false;
      return true;
    }

    // Caso contrário, aceita (mesmo tipo)
    return true;
  }

  void _onData(String key, String ip, List<int> bytes) {
    final buf = _buffers[key];
    if (buf == null) return;

    final chunk = const Utf8Decoder(allowMalformed: true).convert(bytes);
    buf.write(chunk);

    var s = buf.toString();
    int idxNl;

    while ((idxNl = s.indexOf("\n")) >= 0) {
      final line = s.substring(0, idxNl).trim();
      s = s.substring(idxNl + 1);

      if (line.isEmpty) continue;

      try {
        final obj = jsonDecode(line);
        if (obj is! Map) continue;

        final map = Map<String, dynamic>.from(obj);

        // ✅ aceita "fabricacao" (novo) e "fabricacao_resumo" (antigo)
        final stream = (map["stream"] ?? "").toString();
        if (stream != "fabricacao" && stream != "fabricacao_resumo") continue;

        // escolhe ativo
        if (_activeClientKey == null) {
          _electActiveAndCloseOthersSameIp(ip, key);
        } else {
          if (_activeClientKey != key && _activeClientKey!.startsWith("$ip:")) {
            _electActiveAndCloseOthersSameIp(ip, key);
          }
        }

        if (_activeClientKey != null && key != _activeClientKey) continue;

        final now = DateTime.now();

        // ✅ sempre cacheia AUTO (mesmo se o anti-flicker rejeitar)
        if (map["auto"] is Map) {
          _lastAuto = Map<String, dynamic>.from(map["auto"] as Map);
          _lastAutoAt = now;
        }

        final atual = (map["atual"] is Map)
            ? Map<String, dynamic>.from(map["atual"] as Map)
            : null;

        final isPre = _isPreFromAtual(atual);
        final pos = _posFromAtual(atual);

        // ✅ regra: se auto está ativo, NÃO bloqueia update
        // porque o countdown precisa aparecer 1x por segundo.
        final hasAuto = _hasActiveAuto(map);

        if (!hasAuto) {
          if (!_acceptForUi(pos: pos, isPre: isPre)) {
            continue;
          }
        } else {
          // mantém tracking da UI coerente, mas sem bloquear
          if (_uiPos == 0) {
            _uiPos = pos;
            _uiIsPre = isPre;
          } else if (pos != 0 && pos != _uiPos) {
            _uiPos = pos;
            _uiIsPre = isPre;
          } else if (_uiIsPre && !isPre) {
            _uiIsPre = false;
          }
        }

        lastState = map;
        lastFromIp = ip;
        lastMsgAt = now;

        notifyListeners();
      } catch (_) {
        // ignora linha inválida
      }
    }

    _buffers[key]!
      ..clear()
      ..write(s);
  }
}
