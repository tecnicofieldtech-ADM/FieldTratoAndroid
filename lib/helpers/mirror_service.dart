import "mirror_server.dart";

typedef MirrorOnMessage = void Function(Map<String, dynamic> msg);

/// Service that manages the wagon's mirror server.
///
/// The wagon tablet opens a TCP server on a configurable port.
/// PA tablets connect to it and receive state broadcasts.
/// Commands from PAs (next, prev, finish) are forwarded via [onCommand].
class MirrorService {
  MirrorService._();
  static final MirrorService instance = MirrorService._();

  MirrorServer? _server;

  bool _enabled = false;
  bool get enabled => _enabled;

  int _port = 9000;
  int get port => _port;

  bool get running => _server?.running ?? false;
  int get clientCount => _server?.clientCount ?? 0;
  List<String> get clientIps => _server?.clientIps ?? [];

  MirrorOnMessage? _onCommand;

  /// Configure and start the mirror server.
  /// [port] is the TCP port to listen on (default 9000).
  /// [onCommand] receives commands sent by PA clients (next, prev, finish).
  Future<void> configure({
    required int port,
    MirrorOnMessage? onCommand,
  }) async {
    _onCommand = onCommand;

    if (port <= 0) {
      await stop();
      _enabled = false;
      _port = 0;
      return;
    }

    _enabled = true;

    final same = (_port == port && _server != null && _server!.running);
    _port = port;

    if (same) return;

    await _stopInternal();

    _server = MirrorServer(
      port: _port,
      onCommand: (cmd) {
        _onCommand?.call(cmd);
      },
    );

    try {
      await _server?.start();
    } catch (e) {
      _server = null;
      _enabled = false;
      rethrow;
    }
  }

  /// Broadcast state to all connected PAs.
  /// Deduplicates by default (only sends if changed).
  void sendState(Map<String, dynamic> state, {bool force = false}) {
    if (!_enabled) return;

    final s = _server;
    if (s == null || !s.running) return;

    if (force) {
      s.broadcastForce(state);
    } else {
      s.broadcastState(state);
    }
  }

  Future<void> stop() async {
    _enabled = false;
    await _stopInternal();
  }

  Future<void> _stopInternal() async {
    final s = _server;
    _server = null;

    try {
      await s?.stop();
    } catch (_) {}
  }
}
