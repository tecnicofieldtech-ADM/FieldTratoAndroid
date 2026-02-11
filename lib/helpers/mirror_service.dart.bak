import "dart:async";

import "mirror_client.dart";

typedef MirrorOnMessage = void Function(Map<String, dynamic> msg);

class MirrorService {
  MirrorService._();
  static final MirrorService instance = MirrorService._();

  MirrorClient? _client;

  bool _enabled = false;
  bool get enabled => _enabled;

  String _host = "";
  int _port = 0;

  String get host => _host;
  int get port => _port;

  bool get connected => _client?.connected ?? false;

  MirrorOnMessage? _externalOnMessage;

  Map<String, dynamic>? _lastState;

  /// usado para filtrar/deduplicar resposta de `req_state`
  String? _lastStateStream;

  /// evita "storm" de recreate quando configure é chamado várias vezes
  Timer? _debounceStart;

  /// Configure e liga (se host/port válidos).
  /// - Recria o socket somente se host/port mudou.
  /// - Responde automaticamente "req_state" devolvendo o último state enviado.
  Future<void> configure({
    required String host,
    required int port,
    MirrorOnMessage? onMessage,
  }) async {
    _externalOnMessage = onMessage;

    final h = host.trim();
    final p = port;

    // config inválida => desliga
    if (h.isEmpty || p <= 0) {
      await stop();
      _enabled = false;
      _host = "";
      _port = 0;
      return;
    }

    _enabled = true;

    final same = (_host == h && _port == p && _client != null);
    _host = h;
    _port = p;

    if (same) {
      _ensureStartedSoon();
      return;
    }

    // mudou host/port => recria
    await _stopInternal();

    _client = MirrorClient(
      host: _host,
      port: _port,
      onMessage: (msg) {
        final t = (msg["t"] ?? msg["cmd"] ?? "").toString();

        // 🔁 auto-resposta ao pedido de estado
        if (t == "req_state") {
          final st = _lastState;
          if (st != null) {
            final reqStream =
                (msg["stream"] ?? "").toString().trim();
            final lastStream =
                (_lastStateStream ?? "").trim();

            // responde se:
            // - não pediu stream específico
            // - ou stream bate com o último enviado
            if (reqStream.isEmpty || reqStream == lastStream) {
              _client?.sendLine(st); // resposta forçada
            }
          }
          return; // não repassa para controller
        }

        // demais mensagens seguem fluxo normal
        _externalOnMessage?.call(msg);
      },
    );

    _ensureStartedSoon();
  }

  void _ensureStartedSoon() {
    _debounceStart?.cancel();
    _debounceStart = Timer(const Duration(milliseconds: 80), () async {
      if (!_enabled) return;
      try {
        await _client?.start();
      } catch (_) {}
    });
  }

  /// Envia um state para o espelho.
  /// - force=true  → envia sempre
  /// - force=false → envia só se mudou (dedup)
  void sendState(Map<String, dynamic> state, {bool force = false}) {
    if (!_enabled) return;

    _lastState = state;
    _lastStateStream = (state["stream"] ?? "").toString();

    final c = _client;
    if (c == null) return;

    if (force) {
      c.sendLine(state);
    } else {
      c.sendStateIfChanged(state);
    }
  }

  Future<void> stop() async {
    _enabled = false;
    await _stopInternal();
  }

  Future<void> _stopInternal() async {
    _debounceStart?.cancel();
    _debounceStart = null;

    final c = _client;
    _client = null;

    try {
      await c?.stop();
    } catch (_) {}
  }
}
