import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

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
        _autoReconnect = autoReconnect;

  String _host;
  int _port;
  ScaleModel _model;
  bool _allowNegative;

  double _minDelta;
  int _minIntervalMs;

  Duration _connectTimeout;
  Duration _reconnectDelay;
  bool _autoReconnect;

  Socket? _socket;
  StreamSubscription<List<int>>? _sub;

  // ✅ timer cancelável do reconnect
  Timer? _reconnectTimer;

  // lock anti-dupla-conexão
  bool _connecting = false;
  bool _shuttingDown = false;

  // buffer de texto
  String _buf = '';
  static const int _maxBuf = 8192;

  // throttle
  double _lastPosted = -1.0e12;
  int _lastPostAtMs = 0;
  final Stopwatch _sw = Stopwatch();

  // snapshot (último peso)
  double? _lastWeight;
  DateTime? _lastReadAt;
  bool _hasNew = false;

  // streams
  final _statusCtrl = StreamController<ScaleEvent>.broadcast();
  final _weightCtrl = StreamController<ScaleWeightEvent>.broadcast();

  Stream<ScaleEvent> get statusStream => _statusCtrl.stream;
  Stream<ScaleWeightEvent> get weightStream => _weightCtrl.stream;

  double? get lastWeight => _lastWeight;
  DateTime? get lastReadAt => _lastReadAt;

  // ✅ para tudo IMEDIATO (sem await)
  void stopNow() {
    _shuttingDown = true;
    _autoReconnect = false;

    // cancela reconnect pendente
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    // cancela stream sem travar
    try {
      // ignore: unawaited_futures
      _sub?.cancel();
    } catch (_) {}
    _sub = null;

    // mata socket agora
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
        weight: _lastWeight!, readAt: _lastReadAt!, rawLine: '');
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
    if (autoReconnect != null) _autoReconnect = autoReconnect;
    if (reconnectDelay != null) _reconnectDelay = reconnectDelay;
  }

  // =========================================================
  // ✅ START
  // =========================================================
  Future<void> connect() async {
    if (_connecting) return;
    if (_shuttingDown) return;

    // ✅ se tinha reconnect pendente, cancela
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

      _buf = '';
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

      if (_autoReconnect && !_shuttingDown) {
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

    // ✅ desliga reconexão e cancela qualquer agendamento pendente
    _autoReconnect = false;
    _cancelReconnectTimer();

    _emitStatus(ScaleStatus.disconnected);

    await _stopReader();
    await _safeCloseSocket();
  }

  // mantive disconnect por compat, mas agora chama stop()
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

    final parts = _buf.split(RegExp(r'[\r\n]+', multiLine: true));
    if (parts.length <= 1) {
      _buf = parts.isEmpty ? '' : parts.first;
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
          ScaleWeightEvent(weight: weight, readAt: _lastReadAt!, rawLine: line),
        );
      }
    }
  }

  void _onSocketError(Object e) {
    if (_shuttingDown) return;
    _emitStatus(ScaleStatus.error, message: e.toString());
    _stopReader();
    _safeCloseSocket();
    if (_autoReconnect) _scheduleReconnect();
  }

  void _onSocketDone() {
    if (_shuttingDown) return;
    _emitStatus(ScaleStatus.disconnected);
    _stopReader();
    _safeCloseSocket();
    if (_autoReconnect) _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_shuttingDown) return;
    if (!_autoReconnect) return;

    // ✅ evita múltiplos agendamentos
    if (_reconnectTimer?.isActive == true) return;

    _reconnectTimer = Timer(_reconnectDelay, () {
      if (_shuttingDown) return;
      if (!_autoReconnect) return;
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
    if (_statusCtrl.isClosed) return;
    _statusCtrl.add(ScaleEvent(s, message: message));
  }

  String _normalizeControls(String s) {
    final sb = StringBuffer();
    for (final code in s.codeUnits) {
      if (code == 10 || code == 13) {
        sb.writeCharCode(code);
      } else if (code < 32) {
        sb.write('\n');
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

    final sComma = s.replaceAll(',', '.');
    return double.tryParse(sComma);
  }

  String? _extractWeightStr(String dados) {
    final s = dados.trim();

    String onlyDigits(String x) {
      final b = StringBuffer();
      for (int i = 0; i < x.length; i++) {
        final c = x[i];
        if (c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57) b.write(c);
      }
      return b.toString();
    }

    try {
      switch (_model) {
        case ScaleModel.topcom:
          {
            final up = s.toUpperCase();
            final p = up.indexOf('K');
            if (p > 0) return onlyDigits(s.substring(0, p));
            return null;
          }

        case ScaleModel.dg500:
          {
            final up = s.toUpperCase();
            int p = up.indexOf('PB:');
            if (p >= 0) {
              p += 3;
            } else {
              p = s.indexOf(':');
              if (p < 0) return null;
              p += 1;
            }

            while (p < s.length && s[p] == ' ') p++;

            String sign = '';
            if (p < s.length && (s[p] == '+' || s[p] == '-')) {
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
            return sign.isEmpty ? num : (sign + num);
          }

        case ScaleModel.alfa:
          {
            if (s.length >= 9)
              return onlyDigits(s.substring(4, min(9, s.length)));
            return onlyDigits(s);
          }

        case ScaleModel.raw:
          return s;
      }
    } catch (_) {
      return null;
    }
  }
}
