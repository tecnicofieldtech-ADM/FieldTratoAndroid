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

  bool get enabled => _enabled;
  bool get connected => _connected;
  String get address => _address;
  String get deviceName => _deviceName;
  String get deviceLabel =>
      _deviceName.trim().isNotEmpty ? _deviceName.trim() : _address;

  Future<void> configure({
    required String address,
    String name = "",
    int color = 1,
  }) async {
    final addr = address.trim().toUpperCase();
    if (addr.isEmpty) {
      await stop();
      return;
    }

    final same = _enabled && _address == addr;
    _enabled = true;
    _address = addr;
    _deviceName = name.trim();
    _color = color.clamp(0, 2);

    if (same && _connected) return;

    await _client.disconnect();
    _connected = false;
    await _connectOnce();
    _ensureReconnectLoop();
  }

  Future<void> stop() async {
    _enabled = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _busyTimer?.cancel();
    _busyTimer = null;
    _queue.clear();
    _busy = false;
    _currentMessage = "";
    await _client.disconnect();
    _connected = false;
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

  /// Nome do insumo: scroll 2× (~4 s/passagem). Substitui imediatamente fila/LED anterior.
  void enqueueIngredienteNome(String nome) => preemptIngredienteNome(nome);

  /// Troca de insumo (pulo manual/auto): limpa fila e envia o novo nome na hora.
  void preemptIngredienteNome(String nome) {
    if (!_enabled) return;

    final clean = _sanitize(nome);
    if (clean.isEmpty) return;

    _flushQueue();

    const passDelay = Duration(seconds: 4);
    final first = _LedJob(
      text: clean,
      mode: 2,
      scrollOnce: 1,
      postDelay: passDelay,
    );
    _queue.add(
      _LedJob(text: clean, mode: 2, scrollOnce: 1, postDelay: passDelay),
    );

    _currentMessage = clean;
    _busy = true;
    unawaited(_sendIngredienteNow(first, passDelay));
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

  void _markDisconnected() {
    _connected = false;
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

  Future<void> _sendNow(_LedJob job) async {
    if (!_enabled || !_connected) return;

    try {
      await _client.sendLatin1(_buildCommand(job));
    } catch (_) {
      _markDisconnected();
    }
  }

  int get _intensity => 9;

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
