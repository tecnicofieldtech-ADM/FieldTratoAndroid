import "dart:async";
import "dart:io";

import "package:flutter/material.dart";
import "package:permission_handler/permission_handler.dart";

import "../../../helpers/scale_comm.dart";
import "../../../repo/config_repo.dart";
import "../../../repo/dieta_repo.dart";
import "../../../services/wifi_guard.dart";
import "../../fabricacao/ui/mistura_timer_page.dart";
import "../../fornecimento/data/fornecimento_repo.dart";

/// Distribuidor: carrega ração pronta (ex.: BeatBox) sem vínculo com fabricação local.
class CarregamentoSemVinculoPage extends StatefulWidget {
  const CarregamentoSemVinculoPage({super.key});

  @override
  State<CarregamentoSemVinculoPage> createState() =>
      _CarregamentoSemVinculoPageState();
}

class _CarregamentoSemVinculoPageState extends State<CarregamentoSemVinculoPage>
    with WidgetsBindingObserver {
  final _cfg = ConfigRepo();
  final _dietaRepo = DietaRepo();
  final _fornRepo = FornecimentoRepo();

  List<Map<String, Object?>> _dietas = [];
  String? _dietaId;
  int? _trato;

  bool _loadingDietas = true;
  bool _carregando = false;
  bool _saving = false;
  bool _iniciandoCarregamento = false;
  bool _scaleConnecting = false;
  bool _scaleConnected = false;

  double? _pesoInicio;
  double _lastKg = 0;
  DateTime? _lastKgAt;

  ScaleComm? _scale;
  StreamSubscription<ScaleEvent>? _stSub;
  StreamSubscription<ScaleWeightEvent>? _wtSub;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadDietas();
    unawaited(_boot());
    _ticker = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    unawaited(_disconnectScale());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    unawaited(_boot(reconnectOnly: true));
  }

  Future<void> _boot({bool reconnectOnly = false}) async {
    if (!await _ensureOnFieldTratoNetwork(abrirWifi: false)) return;
    if (reconnectOnly &&
        (_scale?.lastStatus == ScaleStatus.connected || _carregando)) {
      return;
    }
    await _connectScale();
  }

  Future<String?> _readSsidWithGate() async {
    if (!Platform.isAndroid) return "";

    var ssid = await WifiGuard.getCurrentSsid();
    if (WifiGuard.isSsidIdentifiable(ssid)) return ssid;

    final granted = await WifiGuard.requestLocationPermissionIfNeeded();
    if (!mounted) return null;
    if (!granted) {
      ssid = await WifiGuard.getCurrentSsid();
      if (WifiGuard.isSsidIdentifiable(ssid)) return ssid;

      final abrir = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text("Permissão necessária"),
              content: const Text(
                "Para verificar o nome da rede Wi‑Fi, permita Localização e "
                "Dispositivos próximos (Wi‑Fi) nas permissões do app.",
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text("Cancelar"),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text("Abrir permissões"),
                ),
              ],
            ),
          ) ??
          false;
      if (abrir) await openAppSettings();
      return null;
    }

    ssid = await WifiGuard.getCurrentSsid();
    if (!mounted) return null;
    if (ssid.isEmpty) {
      final locOn = await WifiGuard.isLocationServiceEnabled();
      if (!mounted) return null;
      if (!locOn) {
        final abrirLoc = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text("Ative a localização"),
                content: const Text(
                  "Ative a localização para o app conseguir ler o nome da rede Wi‑Fi.",
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: const Text("Cancelar"),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: const Text("Abrir localização"),
                  ),
                ],
              ),
            ) ??
            false;
        if (abrirLoc) await WifiGuard.openLocationSettings();
        return null;
      }
    }
    return ssid;
  }

  Future<bool> _ensureOnFieldTratoNetwork({bool abrirWifi = true}) async {
    if (!Platform.isAndroid) return true;

    final ssid = await _readSsidWithGate();
    if (ssid == null) return false;
    if (WifiGuard.isFieldTratoSsid(ssid)) return true;
    if (!mounted) return false;

    final trocar = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("Rede FieldTrato necessária"),
            content: Text(
              "Para carregar na balança do vagão, conecte em uma rede FieldTrato*.\n\n"
              "Rede atual: ${ssid.isEmpty ? "não identificada" : ssid}",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text("Cancelar"),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text("Abrir Wi‑Fi"),
              ),
            ],
          ),
        ) ??
        false;

    if (trocar && abrirWifi) {
      await WifiGuard.openWifiSelector();
      _msg("Conecte na rede FieldTrato do vagão e tente novamente.");
    }
    return false;
  }

  double get _pesoLiquido {
    if (_pesoInicio == null) return 0;
    final v = _lastKg - _pesoInicio!;
    return v > 0 ? v : 0;
  }

  ScaleModel _mapModel(int v) {
    switch (v) {
      case 0:
        return ScaleModel.topcom;
      case 1:
        return ScaleModel.dg500;
      case 2:
        return ScaleModel.alfa;
      default:
        return ScaleModel.raw;
    }
  }

  Future<void> _loadDietas() async {
    setState(() => _loadingDietas = true);
    try {
      final backend = await _cfg.getBackend();
      final isFieldpec = backend == 1;
      final idFazenda = await _cfg.getIdFazendaSelecionada();
      var dietas = await _dietaRepo.listAll(
        idFazenda: isFieldpec ? null : idFazenda,
      );
      if (!isFieldpec && dietas.isEmpty && idFazenda.trim().isNotEmpty) {
        dietas = await _dietaRepo.listAll();
      }
      if (!mounted) return;
      setState(() {
        _dietas = dietas;
        if (_dietas.isNotEmpty) {
          _dietaId = (_dietas.first["ID"] ?? "").toString();
        }
      });
    } finally {
      if (mounted) setState(() => _loadingDietas = false);
    }
  }

  Future<void> _connectScale() async {
    if (!await _ensureOnFieldTratoNetwork(abrirWifi: false)) {
      if (mounted) {
        setState(() {
          _scaleConnecting = false;
          _scaleConnected = false;
        });
      }
      return;
    }

    await _disconnectScale();

    final host = (await _cfg.getHostBalanca()).trim();
    final port = await _cfg.getPortaBalanca();
    final modelInt = await _cfg.getModeloBalanca();
    if (host.isEmpty || port <= 0) {
      if (mounted) {
        setState(() {
          _scaleConnecting = false;
          _scaleConnected = false;
        });
      }
      return;
    }

    if (mounted) setState(() => _scaleConnecting = true);

    final scale = ScaleComm(
      host: host,
      port: port,
      model: _mapModel(modelInt),
      allowNegative: true,
      autoReconnect: true,
      connectTimeout: const Duration(seconds: 5),
      reconnectDelay: const Duration(milliseconds: 800),
    );
    scale.setThrottle(minDelta: 0.5, minIntervalMs: 80);
    _scale = scale;

    _stSub = scale.statusStream.listen((ev) {
      if (!mounted) return;
      switch (ev.status) {
        case ScaleStatus.connecting:
          setState(() {
            _scaleConnecting = true;
            _scaleConnected = false;
          });
          break;
        case ScaleStatus.connected:
          setState(() {
            _scaleConnecting = false;
            _scaleConnected = true;
          });
          _aplicarLeituraBalanca(scale.lastWeight, scale.lastReadAt);
          break;
        case ScaleStatus.disconnected:
        case ScaleStatus.error:
          setState(() {
            _scaleConnecting = false;
            _scaleConnected = false;
          });
          break;
      }
    });

    _wtSub = scale.weightStream.listen((w) {
      if (!mounted) return;
      _aplicarLeituraBalanca(w.weight, w.readAt);
    });

    await scale.connect();
    if (mounted) {
      _aplicarLeituraBalanca(scale.lastWeight, scale.lastReadAt);
      setState(() => _scaleConnecting = false);
    }
  }

  void _aplicarLeituraBalanca(double? kg, DateTime? at) {
    if (at == null) return;
    setState(() {
      _lastKg = kg ?? 0;
      _lastKgAt = at;
    });
  }

  /// Primeira leitura da balança (0, negativo ou positivo), como na fabricação.
  Future<double?> _capturarPesoInicialAgora({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final scale = _scale;
    if (scale == null || scale.lastStatus != ScaleStatus.connected) return null;

    if (_lastKgAt != null) return _lastKg;

    final cached = scale.tryConsumeLatest();
    if (cached != null) {
      _aplicarLeituraBalanca(cached.weight, cached.readAt);
      return cached.weight;
    }

    final completer = Completer<double?>();
    late final StreamSubscription<ScaleWeightEvent> sub;
    final timer = Timer(timeout, () {
      if (completer.isCompleted) return;
      if (scale.lastReadAt != null) {
        completer.complete(scale.lastWeight ?? _lastKg);
      } else {
        completer.complete(null);
      }
    });

    sub = scale.weightStream.listen((w) {
      if (completer.isCompleted) return;
      _aplicarLeituraBalanca(w.weight, w.readAt);
      completer.complete(w.weight);
    });

    try {
      return await completer.future;
    } finally {
      timer.cancel();
      await sub.cancel();
    }
  }

  Future<void> _alertBalanca(String message) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Balança"),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  Future<void> _disconnectScale() async {
    await _stSub?.cancel();
    await _wtSub?.cancel();
    _stSub = null;
    _wtSub = null;
    final s = _scale;
    _scale = null;
    if (s != null) {
      try {
        await s.dispose();
      } catch (_) {}
    }
  }

  void _msg(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _iniciarCarregamento() async {
    if ((_dietaId ?? "").trim().isEmpty) {
      _msg("Selecione a ração.");
      return;
    }
    if (_trato == null || _trato! <= 0) {
      _msg("Selecione o trato.");
      return;
    }
    if (!await _ensureOnFieldTratoNetwork()) return;

    final host = (await _cfg.getHostBalanca()).trim();
    final port = await _cfg.getPortaBalanca();
    if (host.isEmpty || port <= 0) {
      await _alertBalanca(
        "Configure o IP e a porta da balança em Configuração antes de iniciar.",
      );
      return;
    }

    setState(() => _iniciandoCarregamento = true);
    try {
      if (_scale == null || _scale!.lastStatus != ScaleStatus.connected) {
        await _connectScale();
      }

      if (!mounted) return;
      if (_scale == null || _scale!.lastStatus != ScaleStatus.connected) {
        await _alertBalanca(
          "Não foi possível conectar à balança em $host:$port.\n"
          "Verifique a rede Wi‑Fi e as configurações da balança.",
        );
        return;
      }

      final peso = await _capturarPesoInicialAgora();
      if (!mounted) return;

      if (peso == null) {
        await _alertBalanca(
          "Não foi possível ler o peso inicial da balança.\n"
          "Verifique a conexão TCP (mesmo teste da Configuração).",
        );
        return;
      }

      setState(() {
        _carregando = true;
        _pesoInicio = peso;
        _lastKg = peso;
        _lastKgAt = DateTime.now();
      });
      _msg(
        "Peso inicial: ${peso.toStringAsFixed(0)} kg. Carregue a ração.",
      );
    } finally {
      if (mounted) setState(() => _iniciandoCarregamento = false);
    }
  }

  Future<void> _salvarCarregamento() async {
    final dieta = (_dietaId ?? "").trim();
    final trato = _trato;
    if (dieta.isEmpty) return _msg("Selecione a ração.");
    if (trato == null || trato <= 0) return _msg("Selecione o trato.");
    if (!_carregando || _pesoInicio == null) {
      return _msg("Toque em Carregar para registrar o peso inicial.");
    }

    final liquido = _pesoLiquido;
    if (liquido <= 0) {
      return _msg("Peso carregado deve ser maior que zero.");
    }

    setState(() => _saving = true);
    try {
      await _fornRepo.criarCarregamentoSemVinculo(
        idDieta: dieta,
        pesoCarregadoKg: liquido,
      );

      if (!mounted) return;

      final minutos = await _cfg.getTempoMisturaMinutos();
      await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => MisturaTimerPage(
            minutos: minutos,
            segundosQuandoMinutosZero: 10,
            titulo: minutos > 0 ? "Mistura" : "Aguardando",
            onDonePopToRoot: false,
          ),
        ),
      );

      if (!mounted) return;
      await _perguntarFornecimento(trato: trato);
    } catch (e) {
      _msg("Erro ao salvar carregamento: $e");
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _perguntarFornecimento({required int trato}) async {
    final go = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("Fornecimento"),
            content: const Text("Deseja realizar o fornecimento agora?"),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text("Não"),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text("Sim"),
              ),
            ],
          ),
        ) ??
        false;

    if (!mounted) return;
    if (!go) {
      Navigator.of(context).popUntil((r) => r.isFirst);
      return;
    }

    final idFazenda = (await _cfg.getIdFazendaSelecionada()).trim();
    if (!mounted) return;
    if (idFazenda.isEmpty) {
      _msg("Nenhuma fazenda selecionada na configuração.");
      Navigator.of(context).popUntil((r) => r.isFirst);
      return;
    }

    try {
      await _fornRepo.prefetchMapaDoDia(idFazenda: idFazenda);
    } catch (_) {}

    if (!mounted) return;

    Navigator.of(context).pushNamedAndRemoveUntil(
      "/fornecimento",
      (r) => r.isFirst,
      arguments: {
        "idFazenda": idFazenda,
        "autoOpenNovoFornecimento": true,
        "tratoSugerido": trato,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final liquido = _pesoLiquido;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Carregar ração pronta"),
      ),
      body: _loadingDietas
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    "Ração fabricada fora do vagão (ex.: BeatBox). "
                    "O carregamento fica só com a dieta, sem vínculo de fabricação.",
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    key: ValueKey(_dietaId),
                    initialValue: _dietaId,
                    items: _dietas
                        .map(
                          (d) => DropdownMenuItem<String>(
                            value: (d["ID"] ?? "").toString(),
                            child: Text((d["NOME"] ?? d["ID"] ?? "").toString()),
                          ),
                        )
                        .toList(),
                    onChanged: _carregando
                        ? null
                        : (v) => setState(() => _dietaId = v),
                    decoration: const InputDecoration(
                      labelText: "Ração",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    "Trato",
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [1, 2, 3, 4].map((t) {
                      final sel = _trato == t;
                      return ChoiceChip(
                        label: Text("Trato $t"),
                        selected: sel,
                        onSelected: _carregando
                            ? null
                            : (_) => setState(() => _trato = t),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 28,
                        horizontal: 16,
                      ),
                      child: Column(
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              liquido.toStringAsFixed(0),
                              style: const TextStyle(
                                fontSize: 128,
                                fontWeight: FontWeight.w900,
                                height: 1,
                                letterSpacing: -4,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "kg carregados",
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (_scaleConnecting)
                            const Text(
                              "Conectando balança...",
                              style: TextStyle(fontWeight: FontWeight.w600),
                            )
                          else if (_carregando)
                            Text(
                              "Início: ${_pesoInicio!.toStringAsFixed(0)} kg  |  "
                              "Atual: ${_lastKg.toStringAsFixed(0)} kg",
                              style: Theme.of(context).textTheme.titleSmall,
                            )
                          else if (_scaleConnected)
                            Text(
                              "Balança: ${_lastKg.toStringAsFixed(0)} kg",
                              style: Theme.of(context).textTheme.titleSmall,
                            )
                          else
                            Text(
                              "Toque em Iniciar carregamento para ler a balança.",
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          if (_lastKgAt != null && _carregando)
                            Text(
                              "Última leitura: "
                              "${_lastKgAt!.hour.toString().padLeft(2, "0")}:"
                              "${_lastKgAt!.minute.toString().padLeft(2, "0")}:"
                              "${_lastKgAt!.second.toString().padLeft(2, "0")}",
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (!_carregando)
                    FilledButton.icon(
                      onPressed: (_saving || _iniciandoCarregamento)
                          ? null
                          : _iniciarCarregamento,
                      icon: _iniciandoCarregamento
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.play_arrow),
                      label: Text(
                        _iniciandoCarregamento
                            ? "Lendo balança..."
                            : "Iniciar carregamento",
                      ),
                    )
                  else ...[
                    FilledButton.icon(
                      onPressed: _saving ? null : _salvarCarregamento,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save),
                      label: const Text("Salvar carregamento"),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: _saving
                          ? null
                          : () => setState(() {
                                _carregando = false;
                                _pesoInicio = null;
                              }),
                      child: const Text("Reiniciar pesagem"),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}
