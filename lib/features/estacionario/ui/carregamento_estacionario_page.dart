import "package:flutter/material.dart";
import "package:flutter/foundation.dart";
import "package:package_info_plus/package_info_plus.dart";
import "package:dio/dio.dart";

import "../../../repo/config_repo.dart";
import "../../../services/session_service.dart";
import "../data/carregamento_estacionario_api.dart";
import "../data/importador_fabricacao_estacionario.dart";
import "../domain/carregamento_payload.dart";
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
  final _cfgRepo = ConfigRepo();
  final _wifiSwitcher = WifiSwitcher();
  final _importador = ImportadorFabricacaoEstacionario();

  List<CarregamentoResumoDto> _itens = const [];

  bool _loading = false;
  bool _modoDistribuidor = false;
  bool _healthOk = false;

  String _stationSsid = "";
  String _stationSenha = "";
  String _stationBaseUrl = "";

  @override
  void initState() {
    super.initState();
    _boot();
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

    final ssid = await _cfgRepo.getStationWifiSsid();
    final senha = await _cfgRepo.getStationWifiPassword();
    final base = await _cfgRepo.getStationBaseUrl();

    if (!mounted) return;
    setState(() {
      _modoDistribuidor = true;
      _stationSsid = ssid.trim();
      _stationSenha = senha;
      _stationBaseUrl = base.trim();
    });
  }

  CarregamentoEstacionarioApi? _apiFromConfig() {
    final uri = Uri.tryParse(_stationBaseUrl);
    if (uri == null || uri.host.trim().isEmpty) {
      debugPrint("[CARREG_UI] baseUrl invalida: '$_stationBaseUrl'");
      return null;
    }
    final port = uri.hasPort
        ? uri.port
        : (uri.scheme.toLowerCase() == "https" ? 443 : 80);
    debugPrint(
      "[CARREG_UI] api configurada host=${uri.host.trim()} port=$port baseUrl=$_stationBaseUrl",
    );
    return CarregamentoEstacionarioApi(host: uri.host.trim(), port: port);
  }

  Future<void> _conectarRede() async {
    if (_stationSsid.isEmpty) {
      _msg("SSID nao configurado. Ajuste em Configuracao.");
      return;
    }

    setState(() => _loading = true);
    try {
      final res = await _wifiSwitcher.connect(
          ssid: _stationSsid, password: _stationSenha);
      _msg(res.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _testarConexao() async {
    final api = _apiFromConfig();
    if (api == null) {
      _msg("Base URL do estacionario invalida. Ajuste em Configuracao.");
      return;
    }

    setState(() => _loading = true);
    try {
      final ok = await api.health();
      if (mounted) setState(() => _healthOk = ok);
      _msg(ok ? "Conexao OK" : "Falha ao conectar no estacionario");
    } catch (e) {
      _msg("Erro no teste: $e");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _buscarCarregamentos() async {
    final api = _apiFromConfig();
    if (api == null) {
      _msg("Base URL do estacionario invalida. Ajuste em Configuracao.");
      return;
    }

    setState(() => _loading = true);
    try {
      final itens = await api.listCarregamentos();
      debugPrint("[CARREG_UI] carregamentos recebidos qtd=${itens.length}");
      if (!mounted) return;
      setState(() => _itens = itens);
    } catch (e) {
      if (e is DioException) {
        debugPrint(
          "[CARREG_UI] erro Dio type=${e.type} status=${e.response?.statusCode} "
          "data=${e.response?.data} msg=${e.message} error=${e.error}",
        );
        debugPrint("[CARREG_UI] stack=${e.stackTrace}");
      } else {
        debugPrint("[CARREG_UI] erro buscar carregamentos=$e");
      }
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

    final api = _apiFromConfig();
    if (api == null) {
      _msg("Base URL do estacionario invalida. Ajuste em Configuracao.");
      return;
    }

    setState(() => _loading = true);
    try {
      final detalhe = await api.getDetalhe(item.idLocal);

      final idUsuario = (SessionService.instance.userId ?? "").trim();
      final idFazenda = (await _cfgRepo.getIdFazendaSelecionada()).trim();

      if (idUsuario.isEmpty || idFazenda.isEmpty) {
        throw Exception(
          "Usuario/Fazenda nao configurados no tablet do caminhao.",
        );
      }

      await _importador.importar(
        payload: detalhe,
        idUsuario: idUsuario,
        idFazenda: idFazenda,
      );

      final info = await PackageInfo.fromPlatform();
      await api.ack(
        id: item.idLocal,
        device: "CAMINHAO",
        appVersion: info.version,
      );

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

  @override
  Widget build(BuildContext context) {
    if (!_modoDistribuidor) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Carregamento (Estacionario)")),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Dados vindos da Configuracao",
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                SelectableText(
                    "SSID: ${_stationSsid.isEmpty ? "-" : _stationSsid}"),
                SelectableText(
                  "Base URL: ${_stationBaseUrl.isEmpty ? "-" : _stationBaseUrl}",
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
                        child: Text("Nenhum carregamento disponivel."),
                      )
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
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
