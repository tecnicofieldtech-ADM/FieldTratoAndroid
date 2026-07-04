import "dart:async";
import "dart:convert";
import "dart:io";
import "dart:typed_data";

import "package:flutter/foundation.dart";

import "../data/mirror_targets_repo.dart";
import "../domain/mirror_target.dart";

/// PA controller that connects as a CLIENT to the wagon's MirrorServer.
///
/// The wagon broadcasts fabrication state; this controller receives it.
/// Commands (next, prev, finish) are sent back to the wagon.
class PaClientController extends ChangeNotifier {
  PaClientController({
    required this.repo,
  });

  final MirrorTargetsRepo repo;

  MirrorTarget? activeTarget;

  Socket? _sock;
  StreamSubscription<List<int>>? _sub;
  Timer? _reconnectTimer;
  Timer? _keepAliveTimer;

  bool _connecting = false;
  bool _stopping = false;

  bool connected = false;
  String status = "Parado";

  DateTime? lastMsgAt;
  String lastFromIp = "";

  Map<String, dynamic>? lastState;

  final List<int> _rx = [];

  int _uiPos = 0;
  bool _uiIsPre = false;

  Map<String, dynamic>? _lastAuto;
  DateTime? _lastAutoAt;

  String _latchedFinalFabId = "";
  String _latchedFinalMsg = "";

  // =========================
  // PUBLIC
  // =========================
  Future<void> loadActive() async {
    activeTarget = await repo.getActive();
    notifyListeners();
  }

  Future<void> start() async {
    await loadActive();
    if (connected || _connecting) return;

    final target = activeTarget;
    if (target == null || target.host.trim().isEmpty) {
      status = "Selecione um Vagao para conectar";
      notifyListeners();
      return;
    }

    status = "Conectando a ${target.host}:${target.porta}…";
    notifyListeners();

    await _connectOnce();
    _ensureReconnectLoop();
    _ensureKeepAlive();
  }

  Future<void> stop() async {
    _stopping = true;
    connected = false;
    status = "Parado";

    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;

    await _closeSocket();
    _clearStates();

    _stopping = false;
    notifyListeners();
  }

  Future<void> restart() async {
    await stop();
    await start();
  }

  Future<void> setActiveTargetById(int id) async {
    await repo.setActive(id);
    await loadActive();
    await restart();
  }

  bool get hasConnection => connected;

  Future<bool> sendNextCommand() => sendCommand("next");
  Future<bool> sendPrevCommand() => sendCommand("prev");
  Future<bool> sendFinishCommand() => sendCommand("finish");

  Future<bool> sendCommand(String cmd, {Map<String, dynamic>? extra}) async {
    final command = cmd.trim().toLowerCase();
    if (command.isEmpty || !connected) return false;

    final payload = <String, dynamic>{
      "t": command,
      "cmd": command,
      "stream": "fabricacao",
      "from": "pa",
      "ts": DateTime.now().toIso8601String(),
      ...?extra,
    };

    try {
      final line = "${jsonEncode(payload)}\n";
      _sock?.add(Uint8List.fromList(utf8.encode(line)));
      await _sock?.flush();
      status = "Comando enviado: $command";
      notifyListeners();
      return true;
    } catch (_) {
      _markDisconnected();
      status = "Falha ao enviar: $command";
      notifyListeners();
      return false;
    }
  }

  // helpers for UI
  Map<String, dynamic>? get autoState {
    final st = lastState;
    final a = (st != null && st["auto"] is Map)
        ? Map<String, dynamic>.from(st["auto"] as Map)
        : null;
    if (a != null) return a;
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
    _latchedFinalFabId = "";
    _latchedFinalMsg = "";
  }

  Future<void> _connectOnce() async {
    if (_stopping || _connecting) return;

    final target = activeTarget;
    if (target == null || target.host.trim().isEmpty) return;

    _connecting = true;

    try {
      final sock = await Socket.connect(
        target.host.trim(),
        target.porta,
        timeout: const Duration(seconds: 3),
      );

      if (_stopping) {
        sock.destroy();
        _connecting = false;
        return;
      }

      sock.setOption(SocketOption.tcpNoDelay, true);
      await _closeSocket();

      _sock = sock;
      connected = true;
      lastFromIp = target.host.trim();
      status = "Conectado a ${target.host}:${target.porta}";
      notifyListeners();

      _sub = sock.listen(
        _onData,
        onError: (_) => _markDisconnected(),
        onDone: _markDisconnected,
        cancelOnError: true,
      );

      // Request current state
      sendCommand("req_state");
    } catch (e) {
      _markDisconnected();
      status = "Falha: ${target.host}:${target.porta}";
      notifyListeners();
    } finally {
      _connecting = false;
    }
  }

  void _ensureReconnectLoop() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      if (_stopping || connected || _connecting) return;
      _connectOnce();
    });
  }

  void _ensureKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (_stopping || !connected) return;
      sendCommand("ping");
    });
  }

  void _markDisconnected() {
    connected = false;
    if (!_stopping) {
      final target = activeTarget;
      status = target != null
          ? "Desconectado - reconectando a ${target.host}:${target.porta}…"
          : "Desconectado";
      notifyListeners();
    }
    _closeSocket();
  }

  Future<void> _closeSocket() async {
    try {
      await _sub?.cancel();
    } catch (_) {}
    _sub = null;

    final s = _sock;
    _sock = null;
    if (s != null) {
      try {
        s.destroy();
      } catch (_) {}
    }
    _rx.clear();
  }

  void _onData(List<int> bytes) {
    if (_stopping) return;

    _rx.addAll(bytes);

    while (true) {
      final nl = _rx.indexOf(10);
      if (nl < 0) break;

      final lineBytes = _rx.sublist(0, nl);
      _rx.removeRange(0, nl + 1);

      if (lineBytes.isEmpty) continue;

      String line;
      try {
        line = utf8.decode(lineBytes, allowMalformed: true).trim();
      } catch (_) {
        continue;
      }
      if (line.isEmpty) continue;

      try {
        final obj = jsonDecode(line);
        if (obj is! Map) continue;

        final map = Map<String, dynamic>.from(obj);

        final stream = (map["stream"] ?? "").toString();
        if (stream.isNotEmpty &&
            stream != "fabricacao" &&
            stream != "fabricacao_resumo") continue;

        final now = DateTime.now();

        _applyFinalizacaoLatch(map);

        if (map["auto"] is Map) {
          _lastAuto = Map<String, dynamic>.from(map["auto"] as Map);
          _lastAutoAt = now;
        }

        final atual = (map["atual"] is Map)
            ? Map<String, dynamic>.from(map["atual"] as Map)
            : null;

        final isPre = _isPreFromAtual(atual);
        final pos = _posFromAtual(atual);

        final hasAuto = _hasActiveAuto(map);

        if (!hasAuto) {
          if (!_acceptForUi(pos: pos, isPre: isPre)) continue;
        } else {
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
        lastMsgAt = now;
        notifyListeners();
      } catch (_) {}
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

  bool _isFinalizacaoEvent(Map<String, dynamic> map) {
    return (map["t"] ?? "").toString() == "event" &&
        (map["type"] ?? "").toString() == "finalizada";
  }

  String _fabIdFrom(Map<String, dynamic> map) {
    return (map["fabId"] ?? map["idFab"] ?? "").toString().trim();
  }

  void _applyFinalizacaoLatch(Map<String, dynamic> map) {
    final isEvent = _isFinalizacaoEvent(map);
    final isFinalizada = _isTrue(map["finalizada"]);
    final fabId = _fabIdFrom(map);
    final msg = (map["msg"] ?? "").toString().trim();

    if (isEvent || isFinalizada) {
      if (fabId.isNotEmpty) _latchedFinalFabId = fabId;
      if (msg.isNotEmpty) _latchedFinalMsg = msg;
      map["t"] = "event";
      map["type"] = "finalizada";
      map["finalizada"] = 1;
      if (_latchedFinalMsg.isNotEmpty && msg.isEmpty) {
        map["msg"] = _latchedFinalMsg;
      }
      return;
    }

    if (_latchedFinalFabId.isEmpty) return;

    if (fabId.isNotEmpty && fabId != _latchedFinalFabId) {
      _latchedFinalFabId = "";
      _latchedFinalMsg = "";
      return;
    }

    map["t"] = "event";
    map["type"] = "finalizada";
    map["finalizada"] = 1;
    if (_latchedFinalMsg.isNotEmpty && msg.isEmpty) {
      map["msg"] = _latchedFinalMsg;
    }
  }

  bool _acceptForUi({required int pos, required bool isPre}) {
    if (_uiPos == 0) {
      _uiPos = pos;
      _uiIsPre = isPre;
      return true;
    }
    if (pos != 0 && pos != _uiPos) {
      _uiPos = pos;
      _uiIsPre = isPre;
      return true;
    }
    if (!_uiIsPre && isPre) return false;
    if (_uiIsPre && !isPre) {
      _uiIsPre = false;
      return true;
    }
    return true;
  }
}
