// lib/helpers/scale_comm.dart
import "dart:async";
import "dart:convert";
import "dart:io";

enum ScaleModel { topcom, dg500, alfa, hook, raw }

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

/// Extrai kg de eventos do [weightStream] ([ScaleWeightEvent], [num], etc.).
double scaleWeightFromStreamEvent(Object? event) {
  if (event is ScaleWeightEvent) return event.weight;
  if (event is num) return event.toDouble();
  return 0;
}

/// Alfa/Digistar: após `PB:` ou `**:`, sempre [alfaPbFieldLength] caracteres → kg inteiro.
/// Ex.: `PB: 0-176 T: 00000` → ` 0-176` → -176
const int alfaPbFieldLength = 6;

/// Índice logo após `PB:` ou `**:` (-1 se não houver marcador).
int alfaMarkerEndIndex(String raw) {
  final up = raw.toUpperCase();
  final iPb = up.indexOf("PB:");
  if (iPb >= 0) return iPb + 3;

  final iAst = raw.indexOf("**:");
  if (iAst >= 0) return iAst + 3;

  return -1;
}

/// Os 6 caracteres de peso logo após `PB:` / `**:` (null se incompleto).
String? extractAlfaFixed6Field(String raw) {
  final start = alfaMarkerEndIndex(raw);
  if (start < 0) return null;

  final rest = raw.substring(start);
  if (rest.length < alfaPbFieldLength) return null;

  return rest.substring(0, alfaPbFieldLength);
}

/// Converte o campo fixo de 6 posições em kg inteiro (negativo com `0-` ou sinal).
int? parseAlfaFixed6FieldToInt(String field) {
  if (field.length != alfaPbFieldLength) return null;

  // T:* pode entrar no 6º char se não houver espaço após PB: (ex.: "0-15 T").
  var f = field;
  final leak = f.indexOf(RegExp(r"[T\*]"));
  if (leak > 0) f = f.substring(0, leak);

  // 0-15 / 0-176 (negativo Alfa) — traço é o sinal, não separador decimal.
  final negZero = RegExp(r"0\s*-\s*(\d+)").firstMatch(f);
  if (negZero != null) {
    return -int.parse(negZero.group(1)!);
  }

  // Sinal explícito: -15 / +1234
  final signed = RegExp(r"([+-])\s*(\d+)").firstMatch(f.trim());
  if (signed != null) {
    final n = int.parse(signed.group(2)!);
    return signed.group(1) == "-" ? -n : n;
  }

  // 15- / 0176- (traço no fim)
  final trail = RegExp(r"(\d+)\s*-\s*$").firstMatch(f.trim());
  if (trail != null) {
    return -int.parse(trail.group(1)!);
  }

  // Traço no campo mas formato atípico
  if (f.contains("-")) {
    final dashNum = RegExp(r"-\s*(\d+)").firstMatch(f);
    if (dashNum != null) return -int.parse(dashNum.group(1)!);
  }

  // Positivo: só dígitos (sem traço no campo)
  if (!f.contains("-")) {
    final digits = f.replaceAll(RegExp(r"\D"), "");
    if (digits.isNotEmpty) return int.parse(digits);
  }

  return null;
}

int? parseAlfaFixed6Kg(String raw) {
  final field = extractAlfaFixed6Field(raw);
  if (field == null) return null;
  return parseAlfaFixed6FieldToInt(field);
}

/// Campo PB (Alfa): 6 posições após `PB:` / `**:`.
String? parsePbWeightField(String raw) {
  final kg = parseAlfaFixed6Kg(raw);
  return kg?.toString();
}

/// Já recebeu os 6 caracteres de peso após o marcador?
bool alfaWeightFrameComplete(String raw) {
  final start = alfaMarkerEndIndex(raw);
  if (start < 0) return false;
  return raw.length >= start + alfaPbFieldLength;
}

bool lineHasAlfaWeightField(String raw) {
  final up = raw.toUpperCase();
  return up.contains("PB:") || raw.contains("**:");
}

/// Interpreta uma linha bruta da balança (todos os modelos, aceita negativo).
double? parseScaleWeightKg(String line, {ScaleModel model = ScaleModel.raw}) {
  final pesoStr = extractScaleWeightString(line);
  return _parseWeightStringStatic(pesoStr);
}

/// Extrai string numérica do frame TCP (Topcon, DG500, Alfa, Hook, etc.).
String? extractScaleWeightString(String raw) {
  final s = _normalizeScaleLineStatic(raw.trim());
  if (s.isEmpty) return null;

  if (lineHasAlfaWeightField(s)) {
    if (!alfaWeightFrameComplete(s)) return null;
    final kg = parseAlfaFixed6Kg(s);
    return kg?.toString();
  }

  final nearKg = _weightNearKg(s);
  if (nearKg != null) return nearKg;

  final signed = _firstSignedNumber(s);
  if (signed != null) return signed;

  return null;
}

String _normalizeScaleLineStatic(String s) {
  var t = s.trim();
  t = t.replaceAll(RegExp(r"[\u2212\u2013\u2014]"), "-");
  t = t.replaceAllMapped(
    RegExp(r"([-+])\s+(?=\d)"),
    (m) => m.group(1)!,
  );
  return t;
}

String? _firstSignedNumber(String x) {
  final norm = _normalizeScaleLineStatic(x);

  final paren = RegExp(r"\(\s*(\d+(?:[.,]\d+)?)\s*\)").firstMatch(norm);
  if (paren != null) return "-${paren.group(1)}";

  // Antes do signed genérico: senão `PB: 0-176` vira só `0`.
  final zeroDash = RegExp(
    r"(?:^|\D)0\s*-\s*(\d+(?:[.,]\d+)?)",
  ).firstMatch(norm);
  if (zeroDash != null) return "-${zeroDash.group(1)}";

  final signed =
      RegExp(r"[-+]?\s*\d+(?:[.,]\d+)?").firstMatch(norm)?.group(0);
  if (signed != null) return signed.replaceAll(RegExp(r"\s+"), "");

  final kgMinus = RegExp(
    r"(\d+(?:[.,]\d+)?)\s*K?G?\s*-\s*$",
    caseSensitive: false,
  ).firstMatch(norm)?.group(1);
  if (kgMinus != null) return "-$kgMinus";

  final trailingMinus =
      RegExp(r"(\d+(?:[.,]\d+)?)\s*-\s*$").firstMatch(norm)?.group(1);
  if (trailingMinus != null) return "-$trailingMinus";

  final unsigned = RegExp(r"\d+(?:[.,]\d+)?").firstMatch(norm)?.group(0);
  if (unsigned == null) return null;

  final hasMinus = norm.contains("-");
  final hasPlus = norm.contains("+");
  if (hasMinus && !hasPlus) return "-$unsigned";
  if (hasPlus && !hasMinus) return "+$unsigned";
  return unsigned;
}

String? _weightNearKg(String x) {
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

double? _parseWeightStringStatic(String? pesoStr) {
  if (pesoStr == null || pesoStr.trim().isEmpty) return null;

  final s = _normalizeScaleLineStatic(pesoStr.trim());
  var tryDot = double.tryParse(s);
  if (tryDot != null) return tryDot;

  final compact = s.replaceAll(RegExp(r"\s+"), "");
  tryDot = double.tryParse(compact);
  if (tryDot != null) return tryDot;

  final sComma = compact.replaceAll(",", ".");
  return double.tryParse(sComma);
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
  ScaleModel get model => _model;

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

  /// Diagnóstico / testes: interpreta uma linha bruta da balança.
  double? parseWeightLine(String line) => _parseWeightFromLine(line);

  // ================== internals ==================

  bool _looksLikeShortWeightFrame(String s) {
    final t = s.trim();
    if (t.isEmpty || t.length > 24) return false;
    return RegExp(r"^[-+]?\s*\d+(?:[.,]\d+)?\s*$").hasMatch(t);
  }

  void _onData(List<int> bytes) {
    if (_shuttingDown) return;

    final chunk = _normalizeControls(utf8.decode(bytes, allowMalformed: true));
    if (chunk.isEmpty) return;

    final short = chunk.trim();
    if (_looksLikeShortWeightFrame(short)) {
      _emitWeightLine(short);
      if (!chunk.contains("\n") && !chunk.contains("\r")) {
        _buf = "";
        return;
      }
    }

    _buf += chunk;
    if (_buf.length > _maxBuf) {
      _buf = _buf.substring(_buf.length - _maxBuf);
    }

    final parts = _buf.split(RegExp(r"[\r\n]+", multiLine: true));
    if (parts.length <= 1) {
      _buf = parts.isEmpty ? "" : parts.first;
      final pending = _buf.trim();
      if (pending.isNotEmpty) {
        final w = _parseWeightFromLine(pending);
        if (w != null &&
            (_looksLikeShortWeightFrame(pending) ||
                pending.length >= 4 && !lineHasAlfaWeightField(pending) ||
                (lineHasAlfaWeightField(pending) &&
                    alfaWeightFrameComplete(pending)) ||
                pending.toUpperCase().startsWith("ST,"))) {
          _emitWeightLine(pending);
          if (_looksLikeShortWeightFrame(pending)) {
            _buf = "";
          }
        }
      }
      return;
    }

    _buf = parts.last;

    for (var i = 0; i < parts.length - 1; i++) {
      _emitWeightLine(parts[i].trim());
    }
  }

  void _emitWeightLine(String line) {
    if (line.isEmpty) return;

    final w = _parseWeightFromLine(line);
    if (w == null) return;

    final weight = w;

    final nowMs = _sw.elapsedMilliseconds;
    final throttled = (weight - _lastPosted).abs() < _minDelta &&
        (nowMs - _lastPostAtMs) < _minIntervalMs;
    // Peso negativo sempre atualiza a tela (todos os modelos).
    if (throttled && weight >= 0) {
      return;
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

  double? _parseWeightFromLine(String line) =>
      _parseWeightStringStatic(extractScaleWeightString(line));
}
