import "dart:async";
import "dart:io";

import "package:flutter/material.dart";
import "package:package_info_plus/package_info_plus.dart";
import "package:permission_handler/permission_handler.dart";

import "../../../repo/config_repo.dart";
import "../../../services/session_service.dart";
import "../../../services/wifi_guard.dart";
import "../data/carregamento_estacionario_api.dart";
import "../data/importador_fabricacao_estacionario.dart";
import "../domain/carregamento_payload.dart";
import "../../fabricacao/data/fabricacao_repo.dart";
import "../../fabricacao/domain/fabricacao_flow.dart";
import "../../fabricacao/ui/fabricacao_carregamento_vagao_page.dart";
import "../../fabricacao/ui/fabricacao_recebimento_peso_caminhao_page.dart";
import "carregamento_sem_vinculo_page.dart";

class CarregamentoEstacionarioPage extends StatefulWidget {
  const CarregamentoEstacionarioPage({super.key});

  @override
  State<CarregamentoEstacionarioPage> createState() =>
      _CarregamentoEstacionarioPageState();
}

class _CarregamentoEstacionarioPageState
    extends State<CarregamentoEstacionarioPage> with WidgetsBindingObserver {
  final _cfgRepo = ConfigRepo();
  final _importador = ImportadorFabricacaoEstacionario();

  List<CarregamentoResumoDto> _itens = const [];

  bool _loading = false;
  bool _modoDistribuidor = false;
  bool _modoBeatBox = false;
  bool _healthOk = false;
  bool _buscarAoRetornarDoWifi = false;

  String _stationSsid = "";
  String _stationBaseUrl = "";
  String _alvoBridge = "";

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _boot();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (!_buscarAoRetornarDoWifi || _loading) return;
    unawaited(_tentarBuscarSeNaRedeBeatBox());
  }

  void _msg(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
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

  /// Ração pronta / vagão: exige rede FieldTrato* (balança e RFID).
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

  /// Passo 1: Wi‑Fi BeatBox / estacionário.
  Future<bool> _ensureOnStationNetwork({bool abrirWifi = true}) async {
    final expected = _stationSsid.trim();
    if (expected.isEmpty) {
      _msg("Configure o SSID da rede BeatBox/estacionário em Configuração.");
      return false;
    }
    if (!Platform.isAndroid) return true;

    final ssid = await _readSsidWithGate();
    if (ssid == null) return false;
    if (WifiGuard.ssidMatchesExpected(ssid, expected)) return true;
    if (!mounted) return false;

    if (abrirWifi) {
      await WifiGuard.openWifiSelector();
      _msg("Conecte na rede $expected (BeatBox) e aguarde.");
    }
    return false;
  }

  /// Passo 4: obriga sair da rede BeatBox/estacionário (SSID diferente do config).
  Future<bool> _ensureRedeVagaoAposRecebimento() async {
    if (!Platform.isAndroid) return true;

    final station = _stationSsid.trim();
    if (station.isEmpty) {
      _msg(
        "Configure o SSID da rede estacionária em Configuração para o app "
        "validar a troca de rede após o recebimento.",
      );
      return false;
    }

    for (;;) {
      if (!mounted) return false;
      final ssid = await _readSsidWithGate();
      if (ssid == null) return false;

      if (WifiGuard.isVagaoNetworkAfterCarregamento(
        current: ssid,
        stationSsid: station,
      )) {
        return true;
      }

      if (!mounted) return false;

      final aindaNaEstacao = WifiGuard.ssidMatchesExpected(ssid, station);
      await WifiGuard.openWifiSelector();

      final action = await showDialog<String>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              title: const Text("Troque para a rede do vagão"),
              content: Text(
                aindaNaEstacao
                    ? "Você ainda está na rede do estacionário:\n\n"
                        "• Rede atual: $ssid\n"
                        "• Rede estacionária (config): $station\n\n"
                        "Conecte na rede FieldTrato do vagão (SSID diferente de $station) "
                        "para pesar e completar o carregamento."
                    : "Conecte na rede FieldTrato do vagão para pesar o carregamento.\n\n"
                        "Rede atual: ${ssid.isEmpty ? "não identificada" : ssid}\n"
                        "Rede estacionária (config): $station\n\n"
                        "A rede deve começar com FieldTrato e ser diferente de $station.",
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop("back"),
                  child: const Text("Cancelar"),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop("wifi"),
                  child: const Text("Abrir Wi‑Fi"),
                ),
                OutlinedButton(
                  onPressed: () => Navigator.of(ctx).pop("recheck"),
                  child: const Text("Verificar"),
                ),
              ],
            ),
          ) ??
          "back";

      if (action == "back") return false;
      if (action == "wifi") await WifiGuard.openWifiSelector();
    }
  }

  Future<void> _boot() async {
    final tipo = await _cfgRepo.getTipoTrabalho();
    if (!mounted) return;
    if (tipo != 2) {
      _msg("Tela de carregamento disponível apenas no modo distribuidor.");
      Navigator.of(context).pop();
      return;
    }

    final ssid = await _cfgRepo.getStationWifiSsid();
    final base = await _cfgRepo.getStationBaseUrl();
    final alvo = CarregamentoEstacionarioApi.tryParseHostPort(base);

    if (!mounted) return;
    setState(() {
      _modoDistribuidor = true;
      _stationSsid = ssid.trim();
      _stationBaseUrl = base.trim();
      _alvoBridge =
          alvo == null ? "-" : "http://${alvo.host}:${alvo.port} (bridge)";
    });
  }

  /// Passos 1–2: abrir Wi‑Fi BeatBox e listar carregamentos.
  Future<void> _iniciarFluxoEntrada() async {
    if (_stationSsid.isEmpty) {
      _msg("Configure o SSID da rede BeatBox em Configuração.");
      return;
    }

    final jaNaRede = await _ensureOnStationNetwork(abrirWifi: false);
    if (jaNaRede) {
      await _buscarCarregamentos(silencioso: true);
      return;
    }

    _buscarAoRetornarDoWifi = true;
    await WifiGuard.openWifiSelector();
    _msg("Selecione a rede $_stationSsid (BeatBox). A lista carregará ao voltar.");
  }

  Future<void> _tentarBuscarSeNaRedeBeatBox() async {
    if (!await _ensureOnStationNetwork(abrirWifi: false)) return;
    _buscarAoRetornarDoWifi = false;
    await _buscarCarregamentos(silencioso: true);
  }

  CarregamentoEstacionarioApi? _apiFromConfig() {
    return CarregamentoEstacionarioApi.tryFromBaseUrl(_stationBaseUrl);
  }

  Future<void> _testarConexao() async {
    final api = _apiFromConfig();
    if (api == null) {
      _msg("Base URL do estacionário inválida. Ajuste em Configuração.");
      return;
    }

    setState(() => _loading = true);
    try {
      final r = await api.tryHealth();
      if (mounted) setState(() => _healthOk = r.ok);
      _msg(r.ok ? r.message : "Falha: ${r.message}");
    } catch (e) {
      _msg("Erro no teste: $e");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _buscarCarregamentos({bool silencioso = false}) async {
    if (!await _ensureOnStationNetwork()) {
      _buscarAoRetornarDoWifi = true;
      return;
    }

    final api = _apiFromConfig();
    if (api == null) {
      _msg("Base URL do estacionário inválida. Ajuste em Configuração.");
      return;
    }

    setState(() => _loading = true);
    try {
      final itens = await api.listCarregamentos();
      if (!mounted) return;
      setState(() {
        _itens = itens;
        _healthOk = true;
      });
      if (!silencioso) {
        _msg(itens.isEmpty
            ? "Nenhum carregamento pendente no estacionário."
            : "${itens.length} carregamento(s) disponível(is).");
      }
    } catch (e) {
      _msg(
        "Erro ao buscar carregamentos ($_alvoBridge): "
        "${CarregamentoEstacionarioApi.mensagemErroDio(e)}",
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _receber(CarregamentoResumoDto item) async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text("Receber carregamento"),
            content: Text(
              "Receber o carregamento '${item.nomeRacao}' no caminhão?",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text("Cancelar"),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text("Receber"),
              ),
            ],
          ),
        ) ??
        false;

    if (!ok) return;
    if (!await _ensureOnStationNetwork()) return;

    final api = _apiFromConfig();
    if (api == null) {
      _msg("Base URL do estacionário inválida.");
      return;
    }

    setState(() => _loading = true);
    try {
      final detalhe = await api.getDetalhe(item.idLocal);

      final idUsuario = (SessionService.instance.userId ?? "").trim();
      final idFazenda = (await _cfgRepo.getIdFazendaSelecionada()).trim();

      if (idUsuario.isEmpty || idFazenda.isEmpty) {
        throw Exception(
          "Usuário/Fazenda não configurados no tablet do caminhão.",
        );
      }

      final imp = await _importador.importar(
        payload: detalhe,
        idUsuario: idUsuario,
        idFazenda: idFazenda,
      );
      final novoIdFab = imp.idFabricacaoLocal;

      final info = await PackageInfo.fromPlatform();
      var ackOk = false;
      for (var attempt = 0; attempt < 3; attempt++) {
        ackOk = await api.ack(
          id: item.idLocal,
          device: "CAMINHAO",
          appVersion: info.version,
        );
        if (ackOk) break;
        await Future<void>.delayed(Duration(milliseconds: 350 * (attempt + 1)));
      }

      if (!ackOk) {
        _msg(
          imp.inserido
              ? "Lote gravado, mas o estacionário não confirmou. Verifique Wi‑Fi/bridge e toque Receber de novo."
              : "Não foi possível confirmar no estacionário. Verifique Wi‑Fi/bridge.",
        );
        return;
      }

      if (!mounted) return;
      setState(() {
        _itens = _itens.where((x) => x.idLocal != item.idLocal).toList();
      });

      _msg(imp.inserido
          ? "Carregamento recebido. Conecte na rede do vagão."
          : "Carregamento já existia — estacionário atualizado.");

      // Passo 4: Wi‑Fi vagão (SSID ≠ estacionário)
      if (!await _ensureRedeVagaoAposRecebimento()) return;
      if (!mounted) return;

      final fabRepo = FabricacaoRepo();

      // Passos 5–11: balança TCP + tela de carregamento da ração
      if (detalhe.fabricacao.status == FabricacaoStatus.pendenteCaminhao) {
        await Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => FabricacaoRecebimentoPesoCaminhaoPage(
              repo: fabRepo,
              idFabricacao: novoIdFab,
              autoConectarBalanca: true,
            ),
          ),
        );
        return;
      }

      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => FabricacaoCarregamentoVagaoPage(
            repo: fabRepo,
            idFabricacao: novoIdFab,
          ),
        ),
      );
    } catch (e) {
      _msg("Falha ao receber: $e");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_modoDistribuidor) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Carregamento")),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  label: Text("Ração pronta"),
                  icon: Icon(Icons.scale),
                ),
                ButtonSegment(
                  value: true,
                  label: Text("BeatBox"),
                  icon: Icon(Icons.download),
                ),
              ],
              selected: {_modoBeatBox},
              onSelectionChanged: (s) {
                setState(() => _modoBeatBox = s.first);
                if (_modoBeatBox) {
                  unawaited(_iniciarFluxoEntrada());
                }
              },
            ),
          ),
          if (!_modoBeatBox)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      "Carregue a ração já fabricada na balança do vagão, "
                      "sem importar lote da BeatBox.",
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () async {
                        if (!await _ensureOnFieldTratoNetwork()) return;
                        if (!mounted) return;
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const CarregamentoSemVinculoPage(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.arrow_forward),
                      label: const Text("Iniciar carregamento sem vínculo"),
                    ),
                  ],
                ),
              ),
            )
          else ...[
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Rede BeatBox: ${_stationSsid.isEmpty ? "-" : _stationSsid}",
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                SelectableText("Bridge: $_alvoBridge"),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Chip(
                      label: Text(
                        _healthOk ? "Conectado ao estacionário" : "Aguardando rede",
                      ),
                      avatar: Icon(
                        _healthOk ? Icons.check_circle : Icons.wifi_find,
                        size: 18,
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _loading ? null : () => _ensureOnStationNetwork(),
                      icon: const Icon(Icons.wifi),
                      label: const Text("Wi‑Fi BeatBox"),
                    ),
                    OutlinedButton.icon(
                      onPressed: _loading ? null : _testarConexao,
                      icon: const Icon(Icons.health_and_safety_outlined),
                      label: const Text("Testar"),
                    ),
                    FilledButton.icon(
                      onPressed: _loading ? null : () => _buscarCarregamentos(),
                      icon: const Icon(Icons.refresh),
                      label: const Text("Atualizar lista"),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _itens.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            _buscarAoRetornarDoWifi
                                ? "Conecte na rede BeatBox ($_stationSsid) para listar os carregamentos."
                                : "Nenhum carregamento pendente disponível.",
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : ListView.separated(
                        itemCount: _itens.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final it = _itens[i];
                          return ListTile(
                            title: Text(it.nomeRacao),
                            subtitle: Text(
                              "${it.data} ${it.hora}  |  "
                              "${it.totalFabricadoKg.toStringAsFixed(0)} kg",
                            ),
                            trailing: FilledButton(
                              onPressed: _loading ? null : () => _receber(it),
                              child: const Text("Receber"),
                            ),
                          );
                        },
                      ),
          ),
          ],
        ],
      ),
    );
  }
}
