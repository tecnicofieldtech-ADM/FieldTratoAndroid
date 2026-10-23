import "dart:async";
import "dart:collection";

import "bt_permissions.dart";
import "spp_client.dart";

/// Envio ao painel LED via conversor serial Bluetooth (ex.: BS1C TGY Cyber).
/// Tablet → SPP → BS1C → RS232 → LED.
///
/// Protocolo: `&XXXXTEXTO#`
/// - 1º X: modo (1=estático, 2=scroll, 3=repetidor, 4=pág. inicial)
/// - 2º X: intensidade (0=padrão, 1–9 = 11%–99%)
/// - 3º X: cor (0=verde, 1=vermelho, 2=azul)
/// - 4º X: scroll (0=loop, 1=uma vez) — válido no modo scroll
/// - TEXTO: até 50 caracteres
class LedService {
  LedService._();
  static final LedService instance = LedService._();

  final SppClient _client = SppClient();
  Timer? _reconnectTimer;
  Timer? _busyTimer;

  bool _enabled = false;
  bool _connected = false;

  String _address = "";
  String _deviceName = "";

  int _color = 1;

  final ListQueue<_LedJob> _queue = ListQueue<_LedJob>();
  bool _busy = false;
  String _currentMessage = "";

  /// Sessão da fabricação que abriu o LED. `stop` de uma sessão antiga
  /// não derruba a conexão da fabricação seguinte.
  int _session = 0;
  int _connectedSession = 0;
  Future<void> _tail = Future<void>.value();
  Timer? _repousoTimer;

  bool get enabled => _enabled;
  bool get connected => _connected;
  String get address => _address;
  String get deviceName => _deviceName;
  String get deviceLabel =>
      _deviceName.trim().isNotEmpty ? _deviceName.trim() : _address;

  /// Reserva o LED para esta fabricação. Chamar de forma síncrona
  /// antes de qualquer `await`, para o `stop` da tela anterior perder a vez.
  int openSession() {
    _repousoTimer?.cancel();
    _repousoTimer = null;
    _session += 1;
    return _session;
  }

  /// FIM em scroll por 10 s, depois "Field Trato" em scroll até a próxima fabricação.
  /// Abre outra sessão para o stop da tela anterior não desligar o painel.
  Future<void> mostrarFimDepoisMarca() {
    final sid = openSession();
    return _serialized(() async {
      if (sid != _session || !_enabled) return;
      await _emitirScroll("FIM");
      if (sid != _session || !_enabled) return;
      _repousoTimer?.cancel();
      _repousoTimer = Timer(const Duration(seconds: 10), () {
        unawaited(_serialized(() async {
          if (sid != _session || !_enabled) return;
          await _emitirScroll("Field Trato");
        }));
      });
    });
  }

  Future<void> _serialized(Future<void> Function() op) {
    final run = _tail.then((_) => op());
    _tail = run.catchError((Object _) {});
    return run;
  }

  Future<void> configure({
    required String address,
    String name = "",
    int color = 1,
    int? session,
  }) async {
    final sid = session ?? openSession();
    final addr = address.trim().toUpperCase();
    if (addr.isEmpty) {
      await stop(session: sid);
      return;
    }

    await _serialized(() async {
      if (sid != _session) return;

      _enabled = true;
      _address = addr;
      _deviceName = name.trim();
      _color = color.clamp(0, 2);

      final already =
          _connected && _connectedSession == sid && _client.isConnected;
      if (already) {
        _ensureReconnectLoop();
        return;
      }

      // Nova fabricação: solta o socket da sessão anterior antes de conectar.
      await _client.disconnect();
      if (sid != _session) return;
      _connected = false;
      _connectedSession = 0;
      await _connectOnce();
      if (sid != _session || !_enabled) return;
      if (_connected) _connectedSession = sid;
      _ensureReconnectLoop();
    });
  }

  /// [session] nulo encerra a sessão atual. Sessão antiga é ignorada.
  Future<void> stop({int? session}) async {
    final sid = session ?? _session;
    await _serialized(() async {
      if (sid != _session) return;

      _repousoTimer?.cancel();
      _repousoTimer = null;
      _enabled = false;
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      _busyTimer?.cancel();
      _busyTimer = null;
      _queue.clear();
      _busy = false;
      _currentMessage = "";
      await _client.disconnect();
      if (sid != _session) return;
      _connected = false;
      _connectedSession = 0;
    });
  }

  /// Grava o texto parado no LED agora, sem esperar a fila do peso ao vivo.
  Future<void> sendStaticNow(String msg) {
    final clean = _sanitize(msg);
    if (clean.isEmpty) return Future<void>.value();

    return _serialized(() async {
      if (!_enabled) return;
      _flushQueue();
      if (!_connected) {
        await _connectOnce();
      }
      if (!_enabled || !_connected) return;
      try {
        await _client.sendLatin1(_buildStaticCommand(clean));
        _currentMessage = clean;
      } catch (_) {
        _markDisconnected();
      }
    });
  }

  /// Envio imediato (teste na configuração).
  Future<void> sendTest(String msg) async {
    final allowed = await BtPermissions.ensureBluetoothPermissions();
    if (!allowed) {
      throw StateError("Permissões Bluetooth não concedidas.");
    }

    final addr = _address.trim();
    if (addr.isEmpty) {
      throw StateError("Nenhum LED Bluetooth selecionado.");
    }

    final wasEnabled = _enabled;
    final wasConnected = _connected;
    final clean = _sanitize(msg);

    try {
      if (!_connected) {
        await _client.connect(addr);
        _connected = true;
      }
      await _client.sendLatin1(_buildStaticCommand(clean));
    } finally {
      if (!wasEnabled) {
        await _client.disconnect();
        _connected = false;
      } else if (!wasConnected) {
        _connected = _client.isConnected;
      }
    }
  }

  /// Texto estático (kg faltando, PAUSE, FIM).
  /// [dropPendingStatic]: descarta peso pendente na fila (atualização ~500 ms).
  void enqueueText(
    String msg, {
    Duration postDelay = const Duration(milliseconds: 500),
    bool dropPendingStatic = false,
  }) {
    if (!_enabled) return;

    final clean = _sanitize(msg);
    if (clean.isEmpty) return;

    if (dropPendingStatic) {
      _queue.removeWhere((j) => j.mode == 1);
    }

    if (_currentMessage == clean && _busy) return;
    if (_queue.isNotEmpty && _queue.last.text == clean && _queue.last.mode == 1) {
      return;
    }

    _queue.add(
      _LedJob(text: clean, mode: 1, scrollOnce: 0, postDelay: postDelay),
    );
    _trySendNext();
  }

  /// Nome do insumo em scroll contínuo (modo 2). Estático só cabe 5 caracteres.
  void enqueueIngredienteNome(String nome) => preemptIngredienteNome(nome);

  /// Troca de insumo: limpa a fila e deixa o nome passando até o próximo comando.
  void preemptIngredienteNome(String nome) {
    if (!_enabled) return;

    final clean = _sanitize(nome);
    if (clean.isEmpty) return;

    _flushQueue();

    final job = _LedJob(
      text: clean,
      mode: 2,
      scrollOnce: 0,
      postDelay: const Duration(milliseconds: 200),
    );

    _currentMessage = clean;
    _busy = true;
    unawaited(_sendIngredienteNow(job, job.postDelay));
  }

  void _flushQueue() {
    _busyTimer?.cancel();
    _busyTimer = null;
    _queue.clear();
    _busy = false;
    _currentMessage = "";
  }

  Future<void> _sendIngredienteNow(_LedJob job, Duration passDelay) async {
    await _sendNow(job);
    if (!_enabled) return;

    _busyTimer?.cancel();
    _busyTimer = Timer(passDelay, () {
      _busy = false;
      _trySendNext();
    });
  }

  Future<void> _connectOnce() async {
    if (!_enabled || _address.isEmpty) return;

    try {
      final allowed = await BtPermissions.ensureBluetoothPermissions();
      if (!allowed) {
        _markDisconnected();
        return;
      }

      await _client.connect(_address);
      _connected = true;
      _connectedSession = _session;
    } catch (_) {
      _markDisconnected();
    }
  }

  void _ensureReconnectLoop() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer.periodic(const Duration(milliseconds: 900), (_) {
      if (!_enabled || _connected) return;
      final sid = _session;
      unawaited(_serialized(() async {
        if (sid != _session || !_enabled || _connected) return;
        await _connectOnce();
      }));
    });
  }

  void _markDisconnected() {
    _connected = false;
    _connectedSession = 0;
  }

  void _trySendNext() {
    if (!_enabled || _busy) return;
    if (_queue.isEmpty) return;

    final job = _queue.removeFirst();
    _currentMessage = job.text;
    _busy = true;

    unawaited(_sendNow(job));

    _busyTimer?.cancel();
    _busyTimer = Timer(job.postDelay, () {
      _busy = false;
      _trySendNext();
    });
  }

  Future<void> _sendNow(_LedJob job) {
    return _serialized(() async {
      if (!_enabled || !_connected) return;
      try {
        await _client.sendLatin1(_buildCommand(job));
      } catch (_) {
        _markDisconnected();
      }
    });
  }

  int get _intensity => 9;

  /// Scroll contínuo. O modo estático só mostra 5 caracteres.
  Future<void> _emitirScroll(String msg) async {
    final clean = _sanitize(msg);
    if (clean.isEmpty || !_enabled) return;
    _flushQueue();
    if (!_connected) {
      await _connectOnce();
    }
    if (!_enabled || !_connected) return;
    final job = _LedJob(text: clean, mode: 2, scrollOnce: 0);
    try {
      await _client.sendLatin1(_buildCommand(job));
      _currentMessage = clean;
    } catch (_) {
      _markDisconnected();
    }
  }

  String _buildStaticCommand(String msg) =>
      _buildCommand(_LedJob(text: msg, mode: 1, scrollOnce: 0));

  String _buildCommand(_LedJob job) {
    final text = job.text.length > 50 ? job.text.substring(0, 50) : job.text;
    return "&${job.mode}$_intensity$_color${job.scrollOnce}$text#";
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

class _LedJob {
  const _LedJob({
    required this.text,
    required this.mode,
    required this.scrollOnce,
    this.postDelay = const Duration(seconds: 2),
  });

  final String text;
  final int mode;
  final int scrollOnce;
  final Duration postDelay;
}
