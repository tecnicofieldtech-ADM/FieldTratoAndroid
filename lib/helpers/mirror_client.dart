import "dart:async";
import "dart:convert";
import "dart:io";
import "dart:typed_data";

typedef MirrorOnMessage = void Function(Map<String, dynamic> msg);

class MirrorClient {
  MirrorClient({
    required this.host,
    required this.port,
    this.onMessage,
    this.connectTimeout = const Duration(seconds: 2),
    this.reconnectDelay = const Duration(milliseconds: 900),
    this.keepAliveInterval = const Duration(seconds: 4),
  });

  final String host;
  final int port;

  final MirrorOnMessage? onMessage;

  final Duration connectTimeout;
  final Duration reconnectDelay;
  final Duration keepAliveInterval;

  Socket? _sock;
  StreamSubscription<List<int>>? _sub;
  Timer? _reconnectTimer;
  Timer? _keepAliveTimer;

  bool _starting = false;
  bool _stopping = false;
  bool _connected = false;

  bool get connected => _connected;

  // ✅ buffer de BYTES (não de String) — evita quebrar UTF-8 no meio
  final List<int> _rx = [];

  // dedup state
  String _lastStateHash = "";

  Future<void> start() async {
    if (_starting || _stopping) return;
    _starting = true;

    try {
      await _connectOnce();
      _ensureReconnectLoop();
      _ensureKeepAlive();
    } finally {
      _starting = false;
    }
  }

  Future<void> stop() async {
    if (_stopping) return;
    _stopping = true;

    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;

    _lastStateHash = "";

    await _closeSocket();

    _connected = false;
    _starting = false;
  }

  Future<void> _connectOnce() async {
    if (_stopping) return;
    if (_connected) return;

    try {
      final s = await Socket.connect(host, port, timeout: connectTimeout);
      if (_stopping) {
        try {
          s.destroy();
        } catch (_) {}
        return;
      }

      s.setOption(SocketOption.tcpNoDelay, true);

      await _closeSocket();

      _sock = s;
      _connected = true;

      await _sub?.cancel();
      _sub = s.listen(
        _onData,
        onError: (_) => _markDisconnected(),
        onDone: _markDisconnected,
        cancelOnError: true,
      );
    } catch (_) {
      _markDisconnected();
    }
  }

  void _ensureReconnectLoop() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer.periodic(reconnectDelay, (_) async {
      if (_stopping) return;
      if (_connected) return;
      await _connectOnce();
    });
  }

  void _ensureKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;

    if (keepAliveInterval <= Duration.zero) return;

    _keepAliveTimer = Timer.periodic(keepAliveInterval, (_) {
      if (_stopping) return;
      if (!_connected) return;
      sendLine({"t": "ping", "ts": DateTime.now().toIso8601String()});
    });
  }

  // ✅ parse por LINHA usando bytes + utf8.decode só depois da linha completa
  void _onData(List<int> chunk) {
    if (_stopping) return;

    _rx.addAll(chunk);

    while (true) {
      final nl = _rx.indexOf(10); // '\n'
      if (nl < 0) break;

      final lineBytes = _rx.sublist(0, nl);
      _rx.removeRange(0, nl + 1);

      if (lineBytes.isEmpty) continue;

      String line;
      try {
        // ✅ agora UTF-8 decodifica certo (não está “quebrado”)
        line = utf8.decode(lineBytes, allowMalformed: false).trim();
      } catch (_) {
        // se vier lixo, ignora a linha
        continue;
      }

      if (line.isEmpty) continue;

      try {
        final obj = jsonDecode(line);
        if (obj is Map) {
          onMessage?.call(Map<String, dynamic>.from(obj));
        }
      } catch (_) {
        // ignora linha inválida
      }
    }
  }

  void _markDisconnected() {
    _connected = false;

    if (_stopping) {
      _closeSocket(); // fire-and-forget
    }
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
        await s.flush();
        await s.close();
      } catch (_) {
        try {
          s.destroy();
        } catch (_) {}
      }
    }

    _rx.clear();
  }

  void sendLine(Map<String, dynamic> msg) {
    if (_stopping) return;
    final s = _sock;
    if (s == null || !_connected) return;

    final encoded = jsonEncode(msg);
    final line = '$encoded\n';


    try {
      // ✅ UTF-8 sempre
      s.add(Uint8List.fromList(utf8.encode(line)));
    } catch (_) {
      _markDisconnected();
    }
  }

  /// manda só se mudou (dedup), ideal pra state
  void sendStateIfChanged(Map<String, dynamic> state) {
    if (_stopping) return;
    final hash = _stableHash(state);
    if (hash == _lastStateHash) return;
    _lastStateHash = hash;
    sendLine(state);
  }

  // hash estável (ordena chaves)
  String _stableHash(Object? v) {
    String norm(Object? x) {
      if (x == null) return "null";
      if (x is num || x is bool) return x.toString();
      if (x is String) return jsonEncode(x);
      if (x is List) return "[${x.map(norm).join(",")}]";
      if (x is Map) {
        final keys = x.keys.map((e) => e.toString()).toList()..sort();
        return "{${keys.map((k) => "${jsonEncode(k)}:${norm(x[k])}").join(",")}}";
      }

      return jsonEncode(x.toString());
    }

    return norm(v);
  }
}


