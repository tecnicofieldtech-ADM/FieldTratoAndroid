import "dart:async";
import "dart:io";

import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:package_info_plus/package_info_plus.dart";
import "package:permission_handler/permission_handler.dart";

import "../../../repo/config_repo.dart";
import "../../../services/session_service.dart";
import "../../../services/wifi_guard.dart";
import "../data/carregamento_estacionario_api.dart";
import "../data/importador_fabricacao_estacionario.dart";
import "../data/rede_estacionario_repo.dart";
import "../domain/carregamento_payload.dart";
import "../domain/station_claim.dart";
import "../domain/station_discovery.dart";
import "../domain/station_handoff_mode.dart";
import "../services/station_discovery_service.dart";
import "../../fabricacao/data/fabricacao_repo.dart";
import "../../fabricacao/domain/fabricacao_flow.dart";
import "../../fabricacao/ui/fabricacao_carregamento_vagao_page.dart";
import "../../fabricacao/ui/fabricacao_recebimento_peso_caminhao_page.dart";
import "carregamento_sem_vinculo_page.dart";

enum _BeatBoxView { stations, loads }

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
  final _discovery = StationDiscoveryService();
  final _redeRepo = RedeEstacionarioRepo();

  List<CarregamentoResumoDto> _itens = const [];
  List<DiscoveredStation> _stations = const [];
  List<DiscoveredStation> _recentes = const [];
  DiscoveredStation? _selected;

  bool _loading = false;
  bool _discovering = false;
  bool _modoDistribuidor = false;
  bool _modoBeatBox = false;
  bool _healthOk = false;
  _BeatBoxView _beatView = _BeatBoxView.stations;

  String _stationSsid = "";
  String _truckDeviceId = "";

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

  Future<bool> _ensureRedeVagaoAposRecebimento() async {
    if (!Platform.isAndroid) return true;

    final station = _stationSsid.trim();
    if (station.isEmpty) {
      return _ensureOnFieldTratoNetwork();
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
    final truckId = await _cfgRepo.ensureTruckDeviceId();
    final recentes = await _loadRecentes();

    if (!mounted) return;
    setState(() {
      _modoDistribuidor = true;
      _stationSsid = ssid.trim();
      _truckDeviceId = truckId;
      _recentes = recentes;
    });
  }

  Future<List<DiscoveredStation>> _loadRecentes() async {
    final rows = await _redeRepo.listRecentes();
    return rows
        .where((r) => r.hostEstacionario.trim().isNotEmpty)
        .map(
          (r) => DiscoveredStation(
            stationId: r.stationId.trim().isEmpty
                ? "legacy:${r.hostEstacionario}:${r.portaEstacionario}"
                : r.stationId.trim(),
            name: r.nomeExibicao,
            host: r.hostEstacionario.trim(),
            port: r.portaEstacionario <= 0 ? 8080 : r.portaEstacionario,
            fromDiscovery: false,
            online: false,
          ),
        )
        .toList();
  }

  CarregamentoEstacionarioApi? _apiFor(DiscoveredStation s) {
    return CarregamentoEstacionarioApi(host: s.host, port: s.port);
  }

  Future<void> _buscarEstacoes() async {
    setState(() {
      _discovering = true;
      _beatView = _BeatBoxView.stations;
      _selected = null;
      _itens = const [];
      _healthOk = false;
    });
    debugPrint("[DISCOVERY_START] UI");
    try {
      final found = await _discovery.discover();
      final recentes = await _loadRecentes();
      if (!mounted) return;
      setState(() {
        _stations = found;
        _recentes = recentes;
      });
      if (found.isEmpty) {
        _msg(
          "Nenhuma estacionária encontrada nesta rede.",
        );
      }
    } catch (e) {
      _msg("Falha na busca: $e");
    } finally {
      if (mounted) setState(() => _discovering = false);
    }
  }

  Future<void> _selecionarEstacao(DiscoveredStation s) async {
    debugPrint(
      "[STATION_SELECTED] id=${s.stationId} host=${s.host}:${s.port}",
    );
    setState(() => _loading = true);
    try {
      final api = _apiFor(s);
      if (api == null) {
        _msg("Endereço inválido.");
        return;
      }
      final health = await api.tryHealth();
      if (!health.ok) {
        _msg("Estação indisponível: ${health.message}");
        return;
      }

      final resolved = s.copyWith(
        name: (health.name ?? s.name).trim().isEmpty
            ? s.name
            : (health.name ?? s.name),
        online: true,
      );

      // Bridge antigo sem stationId: identidade temporária só na sessão.
      final withId = (health.stationId == null || health.stationId!.isEmpty)
          ? resolved.copyWith()
          : DiscoveredStation(
              stationId: health.stationId!,
              name: resolved.name,
              host: resolved.host,
              port: resolved.port,
              fromDiscovery: resolved.fromDiscovery,
              online: true,
              lastSeen: DateTime.now(),
            );

      await _redeRepo.touchRecent(withId);

      final itens = await api.listCarregamentos(
        truckDeviceId: _truckDeviceId,
      );
      if (!mounted) return;
      setState(() {
        _selected = withId;
        _itens = itens;
        _healthOk = true;
        _beatView = _BeatBoxView.loads;
      });
      _msg(
        itens.isEmpty
            ? "Nenhum carregamento pendente nesta estação."
            : "${itens.length} carregamento(s) em ${withId.displayName}.",
      );
    } catch (e) {
      _msg(
        "Erro ao consultar estação: "
        "${CarregamentoEstacionarioApi.mensagemErroDio(e)}",
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _ipManual() async {
    final hostCtrl = TextEditingController();
    final portCtrl = TextEditingController(text: "8080");
    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("Informar IP manualmente"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: hostCtrl,
                  decoration: const InputDecoration(
                    labelText: "Host / IP",
                    hintText: "192.168.1.20",
                  ),
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: portCtrl,
                  decoration: const InputDecoration(labelText: "Porta"),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text("Cancelar"),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text("Conectar"),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return;

    final host = hostCtrl.text.trim();
    final port = int.tryParse(portCtrl.text.trim()) ?? 8080;
    if (host.isEmpty || port <= 0 || port > 65535) {
      _msg("Host/porta inválidos.");
      return;
    }

    debugPrint("[STATION_MANUAL] host=$host port=$port");
    final temp = DiscoveredStation(
      stationId: "manual:$host:$port",
      name: host,
      host: host,
      port: port,
      fromDiscovery: false,
      online: true,
    );
    await _selecionarEstacao(temp);
  }

  Future<void> _voltarEstacoes() async {
    setState(() {
      _beatView = _BeatBoxView.stations;
      _selected = null;
      _itens = const [];
      _healthOk = false;
    });
  }

  Future<void> _atualizarListaSelecionada() async {
    final s = _selected;
    if (s == null) return;
    await _selecionarEstacao(s);
  }

  Future<void> _receber(CarregamentoResumoDto item) async {
    final s = _selected;
    if (s == null) {
      _msg("Selecione uma estacionária.");
      return;
    }

    if (item.isClaimedByOther) {
      _msg("Em uso por outro vagão.");
      return;
    }

    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text("Receber carregamento"),
            content: Text(
              "Receber '${item.nomeRacao}' de ${s.displayName}?",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text("Cancelar"),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text("Carregar"),
              ),
            ],
          ),
        ) ??
        false;

    if (!ok) return;

    final api = _apiFor(s);
    if (api == null) {
      _msg("Estação inválida.");
      return;
    }

    var truckId = _truckDeviceId.trim();
    if (truckId.isEmpty) {
      truckId = await _cfgRepo.ensureTruckDeviceId();
      if (mounted) setState(() => _truckDeviceId = truckId);
    }
    if (!StationClaim.isValidTruckDeviceId(truckId)) {
      _msg("Identidade do vagão indisponível. Reinicie o app.");
      return;
    }

    setState(() => _loading = true);
    var claimed = false;
    var legacyBridge = false;
    try {
      // 1) CLAIM (ou legado sem /claim)
      final claimR = await api.claim(id: item.idLocal, truckDeviceId: truckId);
      if (claimR.isLegacyUnsupported) {
        legacyBridge = true;
        debugPrint("[${StationClaim.codeClaimUnsupported}] fluxo import→ack");
      } else if (claimR.isConflict) {
        _msg("Em uso por outro vagão.");
        await _atualizarListaSelecionada();
        return;
      } else if (!claimR.ok) {
        _msg(
          claimR.statusCode == 404
              ? "Carregamento não encontrado na estação."
              : "Não foi possível reservar a carga (${claimR.code.isEmpty ? claimR.statusCode : claimR.code}).",
        );
        return;
      } else {
        claimed = true;
      }

      // 2) Detalhe + import local
      final detalhe = await api.getDetalhe(item.idLocal);

      final idUsuario = (SessionService.instance.userId ?? "").trim();
      final idFazenda = (await _cfgRepo.getIdFazendaSelecionada()).trim();

      if (idUsuario.isEmpty || idFazenda.isEmpty) {
        throw Exception(
          "Usuário/Fazenda não configurados no tablet do caminhão.",
        );
      }

      late final ({String idFabricacaoLocal, bool inserido}) imp;
      try {
        imp = await _importador.importar(
          payload: detalhe,
          idUsuario: idUsuario,
          idFazenda: idFazenda,
        );
      } catch (e) {
        // Falha local: release (sem ACK). Lease expira sozinho se rede cair.
        if (claimed && !legacyBridge) {
          try {
            await api.release(id: item.idLocal, truckDeviceId: truckId);
          } catch (_) {}
        }
        rethrow;
      }
      final novoIdFab = imp.idFabricacaoLocal;

      // 3) ACK só após persistência local
      final info = await PackageInfo.fromPlatform();
      var ackOk = false;
      for (var attempt = 0; attempt < 3; attempt++) {
        // Renova lease se ainda suportado (mesmo /claim).
        if (claimed && !legacyBridge && attempt > 0) {
          await api.claim(id: item.idLocal, truckDeviceId: truckId);
        }
        ackOk = await api.ack(
          id: item.idLocal,
          // Bridge legado: sem truckDeviceId → ACK sem exigir claim.
          truckDeviceId: legacyBridge ? "" : truckId,
          appVersion: info.version,
          deviceLegacy: legacyBridge ? "CAMINHAO" : null,
        );
        if (ackOk) break;
        await Future<void>.delayed(Duration(milliseconds: 350 * (attempt + 1)));
      }

      if (!ackOk) {
        _msg(
          imp.inserido
              ? "Lote gravado, mas o estacionário não confirmou. Verifique Wi‑Fi/bridge e toque Carregar de novo."
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

      if (!await _ensureRedeVagaoAposRecebimento()) return;
      if (!mounted) return;

      final fabRepo = FabricacaoRepo();
      final mode = detalhe.fabricacao.handoffMode ??
          resolveStationHandoffMode(
            fabStatus: fabricacaoStatusToDb(detalhe.fabricacao.status),
            finalizada: detalhe.fabricacao.finalizada ? 1 : 0,
          );

      // CONTINUE_FABRICATION → pesagem + completar ingredientes.
      // FABRICATION_COMPLETE → só transferência física (peso no vagão).
      if (mode == StationHandoffMode.continueFabrication ||
          detalhe.fabricacao.status == FabricacaoStatus.pendenteCaminhao) {
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

  Widget _stationTile(DiscoveredStation s, {required bool recente}) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: Icon(
          recente && !s.online ? Icons.history : Icons.factory_outlined,
          color: s.online ? Colors.teal : Colors.grey,
        ),
        title: Text(s.displayName),
        subtitle: Text(
          "${s.host}:${s.port}"
          "${recente && !s.online ? " · recente (offline)" : ""}",
        ),
        trailing: FilledButton(
          onPressed: _loading || _discovering
              ? null
              : () => _selecionarEstacao(s),
          child: const Text("Selecionar"),
        ),
      ),
    );
  }

  Widget _beatBoxStationsBody() {
    final onlineIds = _stations.map((e) => e.stationId).toSet();
    final recentesOnly = _recentes
        .where((r) => !onlineIds.contains(r.stationId))
        .toList();

    if (_discovering) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text("Buscando estacionárias..."),
          ],
        ),
      );
    }

    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Text(
            "Estacionárias disponíveis",
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        if (_stations.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              "Nenhuma estacionária encontrada nesta rede.\n"
              "Use Buscar novamente ou Informe o IP manualmente.",
              textAlign: TextAlign.center,
            ),
          )
        else
          ..._stations.map((s) => _stationTile(s, recente: false)),
        if (recentesOnly.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 4),
            child: Text(
              "Recentes",
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          ...recentesOnly.map((s) => _stationTile(s, recente: true)),
        ],
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _beatBoxLoadsBody() {
    final s = _selected;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s?.displayName ?? "Estação",
                style: Theme.of(context).textTheme.titleMedium,
              ),
              SelectableText(
                s == null ? "-" : "${s.host}:${s.port}",
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(
                    label: Text(
                      _healthOk ? "Conectado" : "Desconectado",
                    ),
                    avatar: Icon(
                      _healthOk ? Icons.check_circle : Icons.wifi_off,
                      size: 18,
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _loading ? null : _voltarEstacoes,
                    icon: const Icon(Icons.arrow_back),
                    label: const Text("Estações"),
                  ),
                  FilledButton.icon(
                    onPressed: _loading ? null : _atualizarListaSelecionada,
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
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          "Nenhum carregamento pendente disponível.",
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: _itens.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final it = _itens[i];
                        final blocked = it.isClaimedByOther;
                        final mode = it.handoffMode;
                        final modeLabel = mode?.uiLabel ??
                            (it.isFabricationComplete
                                ? "Fabricação concluída"
                                : "Continuar no vagão");
                        final kg =
                            "${it.totalFabricadoKg.toStringAsFixed(0)} kg";
                        final subtitle = blocked
                            ? "$kg  ·  Em uso por outro vagão"
                            : it.isClaimedByMe
                                ? "$kg  ·  Reservada para este vagão\n$modeLabel"
                                : "$kg\n$modeLabel";
                        final btnLabel = blocked
                            ? "Em uso"
                            : it.isClaimedByMe
                                ? "Continuar"
                                : (mode ==
                                        StationHandoffMode.fabricationComplete
                                    ? "Carregar"
                                    : "Continuar");
                        return ListTile(
                          title: Text(it.nomeRacao),
                          subtitle: Text(subtitle),
                          isThreeLine: true,
                          trailing: FilledButton(
                            onPressed: (_loading || blocked)
                                ? null
                                : () => _receber(it),
                            child: Text(btnLabel),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
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
                  unawaited(_buscarEstacoes());
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
            if (_beatView == _BeatBoxView.stations)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed:
                          _discovering || _loading ? null : _buscarEstacoes,
                      icon: const Icon(Icons.wifi_find),
                      label: const Text("Buscar novamente"),
                    ),
                    OutlinedButton.icon(
                      onPressed: _discovering || _loading ? null : _ipManual,
                      icon: const Icon(Icons.dns_outlined),
                      label: const Text("Informar IP manualmente"),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: _beatView == _BeatBoxView.stations
                  ? _beatBoxStationsBody()
                  : _beatBoxLoadsBody(),
            ),
          ],
        ],
      ),
    );
  }
}
