import "dart:async";
import "dart:collection";
import "dart:convert";
import "dart:io";

class LedService {
  LedService._();
  static final LedService instance = LedService._();

  Socket? _sock;
  Timer? _reconnectTimer;

  bool _enabled = false;
  bool _connected = false;

  String _host = "";
  int _port = 9000;

  int _model = 0;
  int _color = 1;

  final ListQueue<String> _queue = ListQueue<String>();
  bool _busy = false;
  String _currentMessage = "";

  bool get enabled => _enabled;
  bool get connected => _connected;
  String get host => _host;
  int get port => _port;

  Future<void> configure({
    required String host,
    required int port,
    int model = 0,
    int color = 1,
  }) async {
    final h = host.trim();
    if (h.isEmpty || port <= 0) {
      await stop();
      return;
    }

    final same = _enabled && _host == h && _port == port;
    _enabled = true;
    _host = h;
    _port = port;
    _model = model;
    _color = color;

    if (same && _connected) return;

    await _closeSocket();
    await _connectOnce();
    _ensureReconnectLoop();
  }

  Future<void> stop() async {
    _enabled = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _queue.clear();
    _busy = false;
    _currentMessage = "";
    await _closeSocket();
  }

  void enqueueText(String msg) {
    if (!_enabled) return;

    final clean = _sanitize(msg);
    if (clean.isEmpty) return;

    if (_currentMessage == clean && _busy) return;
    if (_queue.isNotEmpty && _queue.last == clean) return;

    _queue.add(clean);
    _trySendNext();
  }

  Future<void> _connectOnce() async {
    if (!_enabled) return;

    try {
      final s = await Socket.connect(_host, _port,
          timeout: const Duration(seconds: 2));
      s.setOption(SocketOption.tcpNoDelay, true);
      _sock = s;
      _connected = true;

      s.listen(
        (_) {},
        onDone: _markDisconnected,
        onError: (_) => _markDisconnected(),
        cancelOnError: true,
      );
    } catch (_) {
      _markDisconnected();
    }
  }

  void _ensureReconnectLoop() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer.periodic(const Duration(milliseconds: 900), (_) {
      if (!_enabled || _connected) return;
      _connectOnce();
    });
  }

  Future<void> _closeSocket() async {
    final s = _sock;
    _sock = null;
    _connected = false;

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
  }

  void _markDisconnected() {
    _connected = false;
  }

  void _trySendNext() {
    if (!_enabled || _busy) return;
    if (_queue.isEmpty) return;

    final msg = _queue.removeFirst();
    _currentMessage = msg;
    _busy = true;

    _sendNow(msg);

    Timer(const Duration(seconds: 2), () {
      _busy = false;
      _trySendNext();
    });
  }

  void _sendNow(String msg) {
    final s = _sock;
    if (!_enabled || !_connected || s == null) return;

    final cmd = _buildCommand(msg);
    try {
      s.add(latin1.encode(cmd));
    } catch (_) {
      _markDisconnected();
    }
  }

  String _buildCommand(String msg) {
    if (_model == 0) {
      return "&1000$msg#";
    }
    return "&19${_color}0$msg#";
  }

  String _sanitize(String v) {
    return v
        .replaceAll("\n", " ")
        .replaceAll("\r", " ")
        .replaceAll("#", "")
        .replaceAll("&", "")
        .trim();
  }
}
