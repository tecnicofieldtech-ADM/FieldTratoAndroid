// lib/helpers/scale_comm.dart
import "dart:async";
import "dart:convert";
import "dart:io";
import "dart:math";

enum ScaleModel { topcom, dg500, alfa, raw }

enum ScaleStatus { disconnected, connecting, connected, error }

class ScaleEvent {
  final ScaleStatus status;
  final String? message;
  const ScaleEvent(this.status, {this.message});
}

class ScaleWeightEvent {
  final double weight;
  final DateTime readAt;
  final String rawLine;
  const ScaleWeightEvent({
    required this.weight,
    required this.readAt,
    required this.rawLine,
  });
}

class ScaleComm {
  ScaleComm({
    required String host,
    required int port,
    ScaleModel model = ScaleModel.topcom,
    bool allowNegative = true,
    double minDelta = 1.0,
    int minIntervalMs = 120,
    Duration connectTimeout = const Duration(seconds: 3),
    Duration reconnectDelay = const Duration(milliseconds: 800),
    bool autoReconnect = true,
  })  : _host = host,
        _port = port,
        _model = model,
        _allowNegative = allowNegative,
        _minDelta = minDelta,
        _minIntervalMs = minIntervalMs,
        _connectTimeout = connectTimeout,
        _reconnectDelay = reconnectDelay,
        _autoReconnect = autoReconnect {
    _reconnectEnabled = autoReconnect;
  }

  String _host;
  int _port;
  ScaleModel _model;
  bool _allowNegative;

  double _minDelta;
  int _minIntervalMs;

  final Duration _connectTimeout;
  Duration _reconnectDelay;

  final bool _autoReconnect;
  bool _reconnectEnabled = true;

  Socket? _socket;
  StreamSubscription<List<int>>? _sub;

  Timer? _reconnectTimer;

  bool _connecting = false;
  bool _shuttingDown = false;

  String _buf = "";
  static const int _maxBuf = 8192;

  double _lastPosted = -1.0e12;
  int _lastPostAtMs = 0;
  final Stopwatch _sw = Stopwatch();

  double? _lastWeight;
  DateTime? _lastReadAt;
  bool _hasNew = false;

  final _statusCtrl = StreamController<ScaleEvent>.broadcast();
  final _weightCtrl = StreamController<ScaleWeightEvent>.broadcast();

  Stream<ScaleEvent> get statusStream => _statusCtrl.stream;
  Stream<ScaleWeightEvent> get weightStream => _weightCtrl.stream;

  ScaleStatus _lastStatus = ScaleStatus.disconnected;
  ScaleStatus get lastStatus => _lastStatus;

  double? get lastWeight => _lastWeight;
  DateTime? get lastReadAt => _lastReadAt;

  void stopNow() {
    _shuttingDown = true;
    _reconnectEnabled = false;

    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    try {
      // ignore: unawaited_futures
      _sub?.cancel();
    } catch (_) {}
    _sub = null;

    try {
      _socket?.destroy();
    } catch (_) {}
    _socket = null;

    _emitStatus(ScaleStatus.disconnected);
  }

  ScaleWeightEvent? tryConsumeLatest() {
    if (!_hasNew || _lastWeight == null || _lastReadAt == null) return null;
    _hasNew = false;
    return ScaleWeightEvent(
      weight: _lastWeight!,
      readAt: _lastReadAt!,
      rawLine: "",
    );
  }

  void configure({
    required String host,
    required int port,
    ScaleModel? model,
    bool? allowNegative,
  }) {
    _host = host;
    _port = port;
    if (model != null) _model = model;
    if (allowNegative != null) _allowNegative = allowNegative;
  }

  void setThrottle({double? minDelta, int? minIntervalMs}) {
    if (minDelta != null) _minDelta = minDelta;
    if (minIntervalMs != null) _minIntervalMs = minIntervalMs;
  }

  void setReconnect({bool? autoReconnect, Duration? reconnectDelay}) {
    if (autoReconnect != null) _reconnectEnabled = autoReconnect;
    if (reconnectDelay != null) _reconnectDelay = reconnectDelay;
  }

  // =========================================================
  // ✅ START
  // =========================================================
  Future<void> connect() async {
    // ✅ RECONEXÃO MANUAL: destrava stopNow()
    // Se o usuário apertou "Reconectar", a intenção é religar.
    _shuttingDown = false;

    // ✅ volta pro padrão runtime (permite auto-reconnect de novo)
    _reconnectEnabled = _autoReconnect;

    if (_connecting) return;

    _cancelReconnectTimer();

    _connecting = true;
    _emitStatus(ScaleStatus.connecting);

    try {
      await _stopReader();
      await _safeCloseSocket();

      final sock = await Socket.connect(
        _host,
        _port,
        timeout: _connectTimeout,
      );

      sock.setOption(SocketOption.tcpNoDelay, true);
      _socket = sock;

      _buf = "";
      _lastPosted = -1.0e12;
      _lastPostAtMs = 0;

      if (!_sw.isRunning) _sw.start();
      _sw.reset();
      _sw.start();

      _sub = sock.listen(
        _onData,
        onError: (e, st) => _onSocketError(e),
        onDone: _onSocketDone,
        cancelOnError: true,
      );

      _emitStatus(ScaleStatus.connected);
    } catch (e) {
      _emitStatus(ScaleStatus.error, message: e.toString());
      await _stopReader();
      await _safeCloseSocket();

      if (_autoReconnect && _reconnectEnabled && !_shuttingDown) {
        _scheduleReconnect();
      }
    } finally {
      _connecting = false;
    }
  }

  // =========================================================
  // ✅ STOP HARD (usar ao sair da tela)
  // =========================================================
  Future<void> stop() async {
    _shuttingDown = true;

    _reconnectEnabled = false;
    _cancelReconnectTimer();

    _emitStatus(ScaleStatus.disconnected);

    await _stopReader();
    await _safeCloseSocket();
  }

  Future<void> disconnect() async => stop();

  Future<void> dispose() async {
    await stop();
    await _statusCtrl.close();
    await _weightCtrl.close();
  }

  // ================== internals ==================

  void _onData(List<int> bytes) {
    if (_shuttingDown) return;

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

      final w = _parseWeightFromLine(line);
      if (w == null) continue;

      double weight = w;
      if (!_allowNegative && weight < 0) weight = 0;

      final nowMs = _sw.elapsedMilliseconds;
      if ((weight - _lastPosted).abs() < _minDelta &&
          (nowMs - _lastPostAtMs) < _minIntervalMs) {
        continue;
      }

      _lastPosted = weight;
      _lastPostAtMs = nowMs;

      _lastWeight = weight;
      _lastReadAt = DateTime.now();
      _hasNew = true;

      if (!_weightCtrl.isClosed) {
        _weightCtrl.add(
          ScaleWeightEvent(
            weight: weight,
            readAt: _lastReadAt!,
            rawLine: line,
          ),
        );
      }
    }
  }

  void _onSocketError(Object e) {
    if (_shuttingDown) return;
    _emitStatus(ScaleStatus.error, message: e.toString());
    // ignore: unawaited_futures
    _stopReader();
    // ignore: unawaited_futures
    _safeCloseSocket();
    if (_autoReconnect && _reconnectEnabled) _scheduleReconnect();
  }

  void _onSocketDone() {
    if (_shuttingDown) return;
    _emitStatus(ScaleStatus.disconnected);
    // ignore: unawaited_futures
    _stopReader();
    // ignore: unawaited_futures
    _safeCloseSocket();
    if (_autoReconnect && _reconnectEnabled) _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_shuttingDown) return;
    if (!_autoReconnect) return;
    if (!_reconnectEnabled) return;

    if (_reconnectTimer?.isActive == true) return;

    _reconnectTimer = Timer(_reconnectDelay, () {
      if (_shuttingDown) return;
      if (!_autoReconnect) return;
      if (!_reconnectEnabled) return;
      // ignore: unawaited_futures
      connect();
    });
  }

  void _cancelReconnectTimer() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
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

  void _emitStatus(ScaleStatus s, {String? message}) {
    _lastStatus = s;
    if (_statusCtrl.isClosed) return;
    _statusCtrl.add(ScaleEvent(s, message: message));
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

  double? _parseWeightFromLine(String line) {
    final pesoStr = _extractWeightStr(line);
    if (pesoStr == null || pesoStr.trim().isEmpty) return null;

    final s = pesoStr.trim();
    final tryDot = double.tryParse(s);
    if (tryDot != null) return tryDot;

    final sComma = s.replaceAll(",", ".");
    return double.tryParse(sComma);
  }

  String? _extractWeightStr(String dados) {
    final s = dados.trim();

    String onlyDigits(String x) {
      final b = StringBuffer();
      for (int i = 0; i < x.length; i++) {
        final c = x[i];
        final u = c.codeUnitAt(0);
        if (u >= 48 && u <= 57) b.write(c);
      }
      return b.toString();
    }

    String? firstSignedNumber(String x) {
      final signed = RegExp(r"[-+]?\d+(?:[.,]\d+)?").firstMatch(x)?.group(0);
      if (signed != null) return signed;

      final trailingMinus =
          RegExp(r"(\d+(?:[.,]\d+)?)\s*-\b").firstMatch(x)?.group(1);
      if (trailingMinus != null) return "-$trailingMinus";

      final unsigned = RegExp(r"\d+(?:[.,]\d+)?").firstMatch(x)?.group(0);
      if (unsigned == null) return null;

      final hasMinus = x.contains("-");
      final hasPlus = x.contains("+");
      if (hasMinus && !hasPlus) return "-$unsigned";
      if (hasPlus && !hasMinus) return "+$unsigned";
      return unsigned;
    }

    String? weightNearKg(String x) {
      final re = RegExp(
        r"([+-]?\s*\d+(?:[.,]\d+)?)\s*K(?:G)?\b",
        caseSensitive: false,
      );
      final all = re.allMatches(x).toList();
      if (all.isEmpty) return null;
      final raw = all.last.group(1)?.trim();
      if (raw == null || raw.isEmpty) return null;
      return raw.replaceAll(" ", "");
    }

    try {
      switch (_model) {
        case ScaleModel.topcom:
          return weightNearKg(s) ?? firstSignedNumber(s);

        case ScaleModel.dg500:
          final up = s.toUpperCase();
          int p = up.indexOf("PB:");
          if (p >= 0) {
            p += 3;
          } else {
            p = s.indexOf(":");
            if (p < 0) return null;
            p += 1;
          }

          while (p < s.length && s[p] == " ") {
            p++;
          }

          String sign = "";
          if (p < s.length && (s[p] == "+" || s[p] == "-")) {
            sign = s[p];
            p++;
          }

          int i = p;
          int count = 0;
          while (i < s.length && count < 6) {
            final ch = s[i];
            final cu = ch.codeUnitAt(0);
            final isDigit = cu >= 48 && cu <= 57;
            if (!isDigit) break;
            i++;
            count++;
          }

          if (count == 0) return null;
          final num = s.substring(p, p + count);
          return sign.isEmpty ? num : "$sign$num";

        case ScaleModel.alfa:
          if (s.length >= 9) {
            final cut = s.substring(4, min(9, s.length));
            return firstSignedNumber(cut) ?? onlyDigits(cut);
          }
          return firstSignedNumber(s) ?? onlyDigits(s);

        case ScaleModel.raw:
          return s;
      }
    } catch (_) {
      return null;
    }
  }
}
