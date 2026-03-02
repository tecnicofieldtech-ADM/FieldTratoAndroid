import "package:flutter/material.dart";
import "package:package_info_plus/package_info_plus.dart";

import "../../../repo/config_repo.dart";
import "../../../services/session_service.dart";
import "../data/carregamento_estacionario_api.dart";
import "../data/importador_fabricacao_estacionario.dart";
import "../data/rede_estacionario_repo.dart";
import "../domain/carregamento_payload.dart";
import "../domain/rede_estacionario.dart";
import "../services/wifi_switcher.dart";
import "../../fabricacao/domain/fabricacao_flow.dart";

class CarregamentoEstacionarioPage extends StatefulWidget {
  const CarregamentoEstacionarioPage({super.key});

  @override
  State<CarregamentoEstacionarioPage> createState() =>
      _CarregamentoEstacionarioPageState();
}

class _CarregamentoEstacionarioPageState
    extends State<CarregamentoEstacionarioPage> {
  final _redeRepo = RedeEstacionarioRepo();
  final _cfgRepo = ConfigRepo();
  final _wifiSwitcher = WifiSwitcher();
  final _importador = ImportadorFabricacaoEstacionario();

  final _hostCtrl = TextEditingController();
  final _portaCtrl = TextEditingController(text: "8080");

  List<RedeEstacionario> _redes = const [];
  RedeEstacionario? _selecionada;
  List<CarregamentoResumoDto> _itens = const [];

  bool _loading = false;
  bool _modoDistribuidor = false;
  bool _healthOk = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _hostCtrl.dispose();
    _portaCtrl.dispose();
    super.dispose();
  }

  void _msg(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _boot() async {
    final tipo = await _cfgRepo.getTipoTrabalho();
    final permitido = tipo == 2;
    if (!mounted) return;
    if (!permitido) {
      _msg("Tela de carregamento disponivel apenas no modo distribuidor.");
      Navigator.of(context).pop();
      return;
    }
    setState(() => _modoDistribuidor = true);
    final base = await _cfgRepo.getStationBaseUrl();
    final u = Uri.tryParse(base);
    if (u != null && u.host.trim().isNotEmpty) {
      _hostCtrl.text = u.host.trim();
      _portaCtrl.text = (u.hasPort ? u.port : 8080).toString();
    }
    await _loadRedes();
  }

  Future<void> _loadRedes() async {
    if (!_modoDistribuidor) return;
    final redes = await _redeRepo.listAll();
    if (!mounted) return;

    setState(() {
      _redes = redes;
      if (redes.isNotEmpty) {
        _selecionada = _selecionada == null
            ? redes.first
            : redes.where((e) => e.id == _selecionada!.id).firstOrNull;
      } else {
        _selecionada = null;
      }

      if (_selecionada != null) {
        _hostCtrl.text = _selecionada!.hostEstacionario;
        _portaCtrl.text = _selecionada!.portaEstacionario.toString();
      }
    });
  }

  CarregamentoEstacionarioApi _apiFromForm() {
    final host = _hostCtrl.text.trim();
    final porta = int.tryParse(_portaCtrl.text.trim()) ?? 8080;
    return CarregamentoEstacionarioApi(host: host, port: porta);
  }

  Future<void> _conectarRede() async {
    final r = _selecionada;
    final ssidCfg = await _cfgRepo.getStationWifiSsid();
    final senhaCfg = await _cfgRepo.getStationWifiPassword();

    final ssid = (r?.ssid ?? ssidCfg).trim();
    final senha = (r?.senha ?? senhaCfg).trim();
    if (ssid.isEmpty) {
      _msg("Cadastre e selecione uma rede do estacionario.");
      return;
    }

    setState(() => _loading = true);
    try {
      final res = await _wifiSwitcher.connect(ssid: ssid, password: senha);
      _msg(res.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _testarConexao() async {
    final host = _hostCtrl.text.trim();
    if (host.isEmpty) {
      _msg("Informe o IP do estacionario.");
      return;
    }

    setState(() => _loading = true);
    try {
      final ok = await _apiFromForm().health();
      if (mounted) setState(() => _healthOk = ok);
      _msg(ok ? "Conexao OK" : "Falha ao conectar no estacionario");
    } catch (e) {
      _msg("Erro no teste: $e");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _buscarCarregamentos() async {
    setState(() => _loading = true);
    try {
      final itens = await _apiFromForm().listCarregamentos();
      if (!mounted) return;
      setState(() => _itens = itens);
    } catch (e) {
      _msg("Erro ao buscar carregamentos: $e");
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

    setState(() => _loading = true);
    try {
      final api = _apiFromForm();
      final detalhe = await api.getDetalhe(item.idLocal);

      final idUsuario = (SessionService.instance.userId ?? "").trim();
      final idFazenda = (await _cfgRepo.getIdFazendaSelecionada()).trim();

      if (idUsuario.isEmpty || idFazenda.isEmpty) {
        throw Exception(
            "Usuario/Fazenda nao configurados no tablet do caminhao.");
      }

      await _importador.importar(
        payload: detalhe,
        idUsuario: idUsuario,
        idFazenda: idFazenda,
      );

      final info = await PackageInfo.fromPlatform();
      await api.ack(
          id: item.idLocal, device: "CAMINHAO", appVersion: info.version);

      _msg("Carregamento recebido com sucesso.");
      if (!mounted) return;
      if (detalhe.fabricacao.status == FabricacaoStatus.pendenteCaminhao) {
        final goFab = await showDialog<bool>(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text("Completar fabricação"),
                content: const Text(
                  "Carregamento importado como pendente. Deseja abrir a Fabricação para completar?",
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text("Depois"),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text("Completar agora"),
                  ),
                ],
              ),
            ) ??
            false;

        if (goFab) {
          Navigator.pushReplacementNamed(context, "/fabricacao");
        }
        return;
      }

      Navigator.pushNamed(context, "/fornecimento", arguments: {
        "idFazenda": idFazenda,
        "autoOpenNovoFornecimento": false,
      });
    } catch (e) {
      _msg("Falha ao receber: $e");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openRedeDialog({RedeEstacionario? edit}) async {
    final nome = TextEditingController(text: edit?.nome ?? "");
    final ssid = TextEditingController(text: edit?.ssid ?? "");
    final senha = TextEditingController(text: edit?.senha ?? "");
    final host =
        TextEditingController(text: edit?.hostEstacionario ?? _hostCtrl.text);
    final porta = TextEditingController(
      text: (edit?.portaEstacionario ?? int.tryParse(_portaCtrl.text) ?? 8080)
          .toString(),
    );

    final save = await showDialog<bool>(
          context: context,
          builder: (dialogCtx) => AlertDialog(
            title: Text(edit == null ? "Nova rede" : "Editar rede"),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                      controller: nome,
                      decoration: const InputDecoration(labelText: "Nome")),
                  TextField(
                      controller: ssid,
                      decoration: const InputDecoration(labelText: "SSID")),
                  TextField(
                      controller: senha,
                      decoration: const InputDecoration(labelText: "Senha")),
                  TextField(
                      controller: host,
                      decoration:
                          const InputDecoration(labelText: "IP Estacionario")),
                  TextField(
                      controller: porta,
                      decoration: const InputDecoration(labelText: "Porta"),
                      keyboardType: TextInputType.number),
                ],
              ),
            ),
            actions: [
              if (edit != null)
                TextButton(
                  onPressed: () async {
                    try {
                      await _redeRepo.delete(edit.id);
                      if (dialogCtx.mounted) Navigator.pop(dialogCtx, true);
                    } catch (e) {
                      _msg("Erro ao excluir rede: $e");
                    }
                  },
                  child: const Text("Excluir"),
                ),
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx, false),
                child: const Text("Cancelar"),
              ),
              FilledButton(
                onPressed: () async {
                  final ssidTxt = ssid.text.trim();
                  final hostTxt = host.text.trim();
                  final portaVal = int.tryParse(porta.text.trim()) ?? 0;
                  if (ssidTxt.isEmpty || hostTxt.isEmpty || portaVal <= 0) {
                    _msg("Informe SSID, IP e porta validos.");
                    return;
                  }

                  try {
                    await _redeRepo.upsert(
                      id: edit?.id,
                      nome: nome.text,
                      ssid: ssidTxt,
                      senha: senha.text,
                      host: hostTxt,
                      porta: portaVal,
                    );
                    if (dialogCtx.mounted) Navigator.pop(dialogCtx, true);
                  } catch (e) {
                    _msg("Erro ao salvar rede: $e");
                  }
                },
                child: const Text("Salvar"),
              ),
            ],
          ),
        ) ??
        false;

    nome.dispose();
    ssid.dispose();
    senha.dispose();
    host.dispose();
    porta.dispose();

    if (save) {
      await _loadRedes();
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
      appBar: AppBar(
        title: const Text("Carregamento (Estacionario)"),
        actions: [
          IconButton(
            onPressed: _loading ? null : () => _openRedeDialog(),
            icon: const Icon(Icons.wifi),
            tooltip: "Cadastrar rede",
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InputDecorator(
                  decoration:
                      const InputDecoration(labelText: "Rede do estacionario"),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<RedeEstacionario>(
                      isExpanded: true,
                      value: _selecionada,
                      items: _redes
                          .map(
                            (e) => DropdownMenuItem(
                              value: e,
                              child: Text(e.nomeExibicao),
                            ),
                          )
                          .toList(),
                      onChanged: _loading
                          ? null
                          : (v) {
                              setState(() => _selecionada = v);
                              if (v != null) {
                                _hostCtrl.text = v.hostEstacionario;
                                _portaCtrl.text =
                                    v.portaEstacionario.toString();
                              }
                            },
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _hostCtrl,
                        decoration: const InputDecoration(
                            labelText: "IP do estacionario"),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 90,
                      child: TextField(
                        controller: _portaCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: "Porta"),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Chip(
                      label: Text(
                        _healthOk
                            ? "Conectado ao estacionario"
                            : "Nao conectado",
                      ),
                      avatar: Icon(
                        _healthOk ? Icons.check_circle : Icons.error_outline,
                        size: 18,
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _loading ? null : _conectarRede,
                      icon: const Icon(Icons.wifi_find),
                      label: const Text("Conectar"),
                    ),
                    OutlinedButton.icon(
                      onPressed: _loading ? null : _testarConexao,
                      icon: const Icon(Icons.health_and_safety_outlined),
                      label: const Text("Testar conexao"),
                    ),
                    FilledButton.icon(
                      onPressed: _loading ? null : _buscarCarregamentos,
                      icon: const Icon(Icons.download),
                      label: const Text("Buscar carregamentos"),
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
                        child: Text("Nenhum carregamento disponivel."))
                    : ListView.separated(
                        itemCount: _itens.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final it = _itens[i];
                          return ListTile(
                            title: Text(it.nomeRacao),
                            subtitle: Text(
                              "${it.data} ${it.hora}  |  ${it.totalFabricadoKg.toStringAsFixed(3)} KG  |  ${it.statusApi}",
                            ),
                            trailing: FilledButton(
                              onPressed: _loading ? null : () => _receber(it),
                              child: const Text("Receber"),
                            ),
                            onLongPress: () {
                              final r = _selecionada;
                              if (r != null) {
                                _openRedeDialog(edit: r);
                              }
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
