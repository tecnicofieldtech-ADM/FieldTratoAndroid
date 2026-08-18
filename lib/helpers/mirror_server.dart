import "dart:async";
import "dart:convert";
import "dart:io";
import "dart:typed_data";

typedef MirrorServerOnCommand = void Function(Map<String, dynamic> cmd);

/// TCP server on the wagon tablet that broadcasts fabrication state
/// to all connected PA clients.
///
/// PAs connect to this server and receive JSON-line state updates.
/// PAs can also send commands (next, prev, finish, etc.) back.
class MirrorServer {
  MirrorServer({
    this.port = 9000,
    this.onCommand,
  });

  final int port;
  final MirrorServerOnCommand? onCommand;

  ServerSocket? _server;
  bool _running = false;

  final Map<String, _PaClient> _clients = {};

  bool get running => _running;
  int get clientCount => _clients.length;
  List<String> get clientIps =>
      _clients.values.map((c) => c.ip).toSet().toList();

  String _lastStateJson = "";

  Future<void> start() async {
    if (_running) return;

    try {
      _server = await ServerSocket.bind(InternetAddress.anyIPv4, port);
      _running = true;

      _server!.listen(
        _onNewClient,
        onError: (_) {},
        onDone: () {
          _running = false;
        },
      );
    } catch (e) {
      _running = false;
      rethrow;
    }
  }

  Future<void> stop() async {
    _running = false;

    for (final c in _clients.values) {
      c.dispose();
    }
    _clients.clear();

    final s = _server;
    _server = null;
    if (s != null) {
      try {
        await s.close();
      } catch (_) {}
    }

    _lastStateJson = "";
  }

  /// Broadcast state to all connected PA clients.
  void broadcastState(Map<String, dynamic> state) {
    if (!_running) return;

    final json = jsonEncode(state);
    if (json == _lastStateJson) return;
    _lastStateJson = json;

    final line = Uint8List.fromList(utf8.encode("$json\n"));
    final deadKeys = <String>[];

    for (final entry in _clients.entries) {
      try {
        entry.value.socket.add(line);
      } catch (_) {
        deadKeys.add(entry.key);
      }
    }

    for (final key in deadKeys) {
      _drop(key);
    }
  }

  /// Force-send (no dedup) to all clients.
  void broadcastForce(Map<String, dynamic> state) {
    if (!_running) return;

    final json = jsonEncode(state);
    _lastStateJson = json;

    final line = Uint8List.fromList(utf8.encode("$json\n"));
    final deadKeys = <String>[];

    for (final entry in _clients.entries) {
      try {
        entry.value.socket.add(line);
      } catch (_) {
        deadKeys.add(entry.key);
      }
    }

    for (final key in deadKeys) {
      _drop(key);
    }
  }

  void _onNewClient(Socket sock) {
    final ip = sock.remoteAddress.address;
    final key = "$ip:${sock.remotePort}";

    sock.setOption(SocketOption.tcpNoDelay, true);

    final client = _PaClient(
      socket: sock,
      ip: ip,
      key: key,
      onLine: (line) => _onClientLine(key, line),
      onGone: () => _drop(key),
    );
    _clients[key] = client;

    // Send last known state immediately so the PA catches up.
    if (_lastStateJson.isNotEmpty) {
      try {
        sock.add(Uint8List.fromList(utf8.encode("$_lastStateJson\n")));
      } catch (_) {
        _drop(key);
      }
    }
  }

  void _onClientLine(String key, String line) {
    if (line.isEmpty) return;
    try {
      final obj = jsonDecode(line);
      if (obj is Map) {
        final cmd = Map<String, dynamic>.from(obj);
        final t = (cmd["t"] ?? cmd["cmd"] ?? "").toString();

        if (t == "ping") {
          final client = _clients[key];
          if (client != null) {
            try {
              client.socket.add(
                Uint8List.fromList(utf8.encode('{"t":"pong"}\n')),
              );
            } catch (_) {}
          }
          return;
        }

        if (t == "req_state") {
          if (_lastStateJson.isNotEmpty) {
            final client = _clients[key];
            if (client != null) {
              try {
                client.socket
                    .add(Uint8List.fromList(utf8.encode("$_lastStateJson\n")));
              } catch (_) {}
            }
            return;
          }

          onCommand?.call(cmd);
          return;
        }

        onCommand?.call(cmd);
      }
    } catch (_) {}
  }

  void _drop(String key) {
    final c = _clients.remove(key);
    c?.dispose();
  }
}

class _PaClient {
  _PaClient({
    required this.socket,
    required this.ip,
    required this.key,
    required void Function(String) onLine,
    required void Function() onGone,
  }) {
    _sub = socket.listen(
      (bytes) => _onData(bytes, onLine),
      onError: (_) => onGone(),
      onDone: onGone,
      cancelOnError: true,
    );
  }

  final Socket socket;
  final String ip;
  final String key;
  StreamSubscription<List<int>>? _sub;
  final List<int> _rx = [];

  void _onData(List<int> bytes, void Function(String) onLine) {
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
      if (line.isNotEmpty) onLine(line);
    }
  }

  void dispose() {
    try {
      _sub?.cancel();
    } catch (_) {}
    _sub = null;
    try {
      socket.destroy();
    } catch (_) {}
  }
}
