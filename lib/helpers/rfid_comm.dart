import "dart:async";
import "dart:convert";
import "dart:io";

enum RfidStatus { disconnected, connecting, connected, error }

class RfidStatusEvent {
  final RfidStatus status;
  final String? message;
  const RfidStatusEvent(this.status, {this.message});
}

class RfidTagEvent {
  final String epc;
  final DateTime readAt;
  final String rawLine;
  const RfidTagEvent({
    required this.epc,
    required this.readAt,
    required this.rawLine,
  });
}

class RfidComm {
  RfidComm({
    required String host,
    required int port,
    bool autoReconnect = true,
    Duration connectTimeout = const Duration(seconds: 3),
    Duration reconnectDelay = const Duration(milliseconds: 800),
    Duration readWatchdog = const Duration(seconds: 6),
    int debounceMs = 700,
  })  : _host = host,
        _port = port,
        _autoReconnect = autoReconnect,
        _connectTimeout = connectTimeout,
        _reconnectDelay = reconnectDelay,
        _readWatchdog = readWatchdog,
        _debounceMs = debounceMs;

  String _host;
  int _port;

  final bool _autoReconnect;
  final Duration _connectTimeout;
  final Duration _reconnectDelay;
  final Duration _readWatchdog;
  final int _debounceMs;

  Socket? _socket;
  StreamSubscription<List<int>>? _sub;

  bool _connecting = false;
  bool _shuttingDown = false;

  bool leituraAtiva = false;

  String _buf = "";
  static const int _maxBuf = 8192;

  String _lastTag = "";
  DateTime _lastTagAt = DateTime.fromMillisecondsSinceEpoch(0);

  DateTime _lastAnyDataAt = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _watchdogTimer;

  final _statusCtrl = StreamController<RfidStatusEvent>.broadcast();
  final _tagCtrl = StreamController<RfidTagEvent>.broadcast();

  Stream<RfidStatusEvent> get statusStream => _statusCtrl.stream;
  Stream<RfidTagEvent> get tagStream => _tagCtrl.stream;

  void configure({required String host, required int port}) {
    _host = host;
    _port = port;
  }

  void setLeituraAtiva(bool on) {
    leituraAtiva = on;
    if (leituraAtiva) {
      _lastTag = "";
      _lastTagAt = DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  Future<void> connect() async {
    // ✅ RECONEXÃO MANUAL: destrava disconnect()
    _shuttingDown = false;

    if (_connecting) return;

    _connecting = true;
    _emitStatus(RfidStatus.connecting);

    try {
      _stopWatchdog();

      await _stopReader();
      await _safeCloseSocket(); // ✅ garante fechar socket antigo antes de reconectar

      final sock = await Socket.connect(_host, _port, timeout: _connectTimeout);
      sock.setOption(SocketOption.tcpNoDelay, true);

      _socket = sock;
      _buf = "";
      _lastAnyDataAt = DateTime.now();

      _sub = sock.listen(
        _onData,
        onError: (e, st) => _onSocketError(e),
        onDone: _onSocketDone,
        cancelOnError: true,
      );

      _startWatchdog();
      _emitStatus(RfidStatus.connected);
    } catch (e) {
      _emitStatus(RfidStatus.error, message: e.toString());
      await _safeCloseSocket();
      if (_autoReconnect && !_shuttingDown) _scheduleReconnect();
    } finally {
      _connecting = false;
    }
  }

  Future<void> disconnect() async {
    _shuttingDown = true;
    _emitStatus(RfidStatus.disconnected);
    _stopWatchdog();
    await _stopReader();
    await _safeCloseSocket();
  }

  Future<void> dispose() async {
    await disconnect();
    await _statusCtrl.close();
    await _tagCtrl.close();
  }

  // ============ internals ============

  void _onData(List<int> bytes) {
    if (_shuttingDown) return;

    _lastAnyDataAt = DateTime.now();

    final chunk = _normalizeControls(utf8.decode(bytes, allowMalformed: true));
    if (chunk.isEmpty) return;

    _buf += chunk;
    if (_buf.length > _maxBuf) {
      _buf = _buf.substring(_buf.length - _maxBuf);
    }

    final parts = _buf.split(RegExp(r"[\r\n]+", multiLine: true));
    if (parts.length <= 1) {
      _buf = parts.isEmpty ? "" : parts.first;
      return;
    }

    _buf = parts.last;

    for (var i = 0; i < parts.length - 1; i++) {
      final line = parts[i].trim();
      if (line.isEmpty) continue;

      final epc = extractEpc(line);
      if (epc.isEmpty) continue;

      if (!leituraAtiva) continue;

      final now = DateTime.now();
      if (_equalsIgnoreCase(epc, _lastTag) &&
          now.difference(_lastTagAt).inMilliseconds < _debounceMs) {
        continue;
      }

      _lastTag = epc;
      _lastTagAt = now;

      if (!_tagCtrl.isClosed) {
        _tagCtrl.add(RfidTagEvent(epc: epc, readAt: now, rawLine: line));
      }
    }
  }

  void _onSocketError(Object e) {
    if (_shuttingDown) return;
    _emitStatus(RfidStatus.error, message: e.toString());
    _stopWatchdog();
    _safeCloseSocket();
    if (_autoReconnect) _scheduleReconnect();
  }

  void _onSocketDone() {
    if (_shuttingDown) return;
    _emitStatus(RfidStatus.disconnected);
    _stopWatchdog();
    _safeCloseSocket();
    if (_autoReconnect) _scheduleReconnect();
  }

  void _scheduleReconnect() {
    Future.delayed(_reconnectDelay, () {
      if (_shuttingDown) return;
      connect();
    });
  }

  Future<void> _stopReader() async {
    try {
      await _sub?.cancel();
    } catch (_) {}
    _sub = null;
  }

  Future<void> _safeCloseSocket() async {
    try {
      _socket?.destroy();
    } catch (_) {}
    _socket = null;
  }

  void _emitStatus(RfidStatus s, {String? message}) {
    if (_statusCtrl.isClosed) return;
    _statusCtrl.add(RfidStatusEvent(s, message: message));
  }

  void _startWatchdog() {
    _stopWatchdog();
    _watchdogTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_shuttingDown) return;
      if (_socket == null) return;

      final now = DateTime.now();
      if (now.difference(_lastAnyDataAt) > _readWatchdog) {
        try {
          _socket?.destroy();
        } catch (_) {}
        _socket = null;
        if (_autoReconnect) _scheduleReconnect();
      }
    });
  }

  void _stopWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
  }

  String _normalizeControls(String s) {
    final sb = StringBuffer();
    for (final code in s.codeUnits) {
      if (code == 10 || code == 13) {
        sb.writeCharCode(code);
      } else if (code < 32) {
        sb.write("\n");
      } else {
        sb.writeCharCode(code);
      }
    }
    return sb.toString();
  }

  bool _equalsIgnoreCase(String a, String b) =>
      a.toLowerCase() == b.toLowerCase();

  static String extractEpc(String s) {
    var t = s.trim();
    if (t.isEmpty) return "";

    t = t.replaceAll("\u0000", "").trim();
    final low = t.toLowerCase();

    final idx = low.indexOf("epc:");
    if (idx >= 0) {
      var rest = t.substring(idx + 4).trim();
      rest = rest.replaceAll(";", "").replaceAll(" ", "").trim();
      final m = RegExp(r"^[A-Za-z0-9]+").firstMatch(rest);
      return (m?.group(0) ?? "").trim();
    }

    t = t.replaceAll(";", "").trim();
    return t;
  }
}
