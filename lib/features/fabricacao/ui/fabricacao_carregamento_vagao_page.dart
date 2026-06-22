import "dart:async";

import "package:flutter/material.dart";

import "../../../helpers/scale_comm.dart";
import "../../../repo/config_repo.dart";
import "../../../services/session_service.dart";
import "../data/fabricacao_repo.dart";
import "../domain/fabricacao_flow.dart";
import "../domain/models.dart";

/// Distribuidor: após receber fabricação do estacionário, registra na balança do vagão
/// o peso carregado ([CARREGAMENTO].PESO_CARREGADO) para auditoria (misturador vs vagão).
class FabricacaoCarregamentoVagaoPage extends StatefulWidget {
  const FabricacaoCarregamentoVagaoPage({
    super.key,
    required this.repo,
    required this.idFabricacao,
  });

  final FabricacaoRepo repo;
  final String idFabricacao;

  @override
  State<FabricacaoCarregamentoVagaoPage> createState() =>
      _FabricacaoCarregamentoVagaoPageState();
}

class _FabricacaoCarregamentoVagaoPageState
    extends State<FabricacaoCarregamentoVagaoPage> {
  final _cfg = ConfigRepo();
  final _pesoCtrl = TextEditingController();

  FabricacaoHeader? _header;
  Map<String, Object?>? _carregStatus;
  String? _loadError;

  ScaleComm? _scale;
  StreamSubscription<ScaleEvent>? _stSub;
  StreamSubscription<ScaleWeightEvent>? _wtSub;

  bool _scaleConnecting = false;
  bool _scaleConnected = false;
  double _lastKg = 0;
  DateTime? _lastKgAt;

  bool _saving = false;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _boot();
    _ticker = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _pesoCtrl.dispose();
    unawaited(_disconnectScale());
    super.dispose();
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

  Future<void> _boot() async {
    setState(() {
      _loadError = null;
    });
    try {
      final h =
          await widget.repo.getFabricacaoById(widget.idFabricacao.trim());
      final st = await widget.repo
          .getCarregamentoStatusByFabricacao(widget.idFabricacao.trim());
      if (!mounted) return;
      if (h == null) {
        setState(() => _loadError = "Fabricação não encontrada.");
        return;
      }
      setState(() {
        _header = h;
        _carregStatus = st;
      });
      final pesoAtual = (st?["peso_carregado"] as num?)?.toDouble() ?? 0;
      if (pesoAtual > 0) {
        _pesoCtrl.text = pesoAtual.toStringAsFixed(0);
      }
      await _connectScale();
    } catch (e) {
      if (mounted) setState(() => _loadError = e.toString());
    }
  }

  Future<void> _connectScale() async {
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

    setState(() => _scaleConnecting = true);

    final scale = ScaleComm(
      host: host,
      port: port,
      model: _mapModel(modelInt),
      allowNegative: true,
      autoReconnect: true,
      connectTimeout: const Duration(seconds: 3),
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
      setState(() {
        _lastKg = w.weight;
        _lastKgAt = w.readAt;
      });
    });

    await scale.connect();
    if (mounted) setState(() => _scaleConnecting = false);
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

  void _aplicarPesoBalanca() {
    final v = _lastKg;
    if (v <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Sem leitura válida da balança.")),
      );
      return;
    }
    _pesoCtrl.text = v.toStringAsFixed(0);
  }

  Future<void> _salvar({required bool concluirFabricacaoNoVagao}) async {
    final raw = _pesoCtrl.text.trim().replaceAll(",", ".");
    final kg = double.tryParse(raw);
    if (kg == null || kg <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Informe o peso carregado (kg).")),
      );
      return;
    }

    if (concluirFabricacaoNoVagao) {
      final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text("Concluir no vagão"),
              content: const Text(
                "Marca a fabricação como finalizada com origem CAMINHÃO "
                "(além de gravar o peso carregado). Use se o ciclo de produção "
                "deve ser encerrado neste tablet. Para apenas seguir distribuindo "
                "com o mesmo lote, prefira \"Salvar e distribuir\".",
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text("Cancelar"),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text("Confirmar"),
                ),
              ],
            ),
          ) ??
          false;
      if (!ok) return;
    }

    setState(() => _saving = true);
    try {
      final idVagao = (await _cfg.getIdVagao()).trim();
      await widget.repo.registrarCarregamentoDistribuidorVagao(
        idFabricacao: widget.idFabricacao.trim(),
        pesoCarregadoKg: kg,
        idVagao: idVagao,
        concluirFabricacaoNoVagao: concluirFabricacaoNoVagao,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            concluirFabricacaoNoVagao
                ? "Peso registrado e fabricação concluída no vagão."
                : "Peso carregado registrado. Pode iniciar o fornecimento.",
          ),
        ),
      );

      final st = await widget.repo
          .getCarregamentoStatusByFabricacao(widget.idFabricacao.trim());
      if (mounted) {
        setState(() => _carregStatus = st);
      }

      if (!concluirFabricacaoNoVagao && mounted) {
        final go = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text("Fornecimento"),
                content: const Text("Deseja abrir o fornecimento agora?"),
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
        if (go && mounted) {
          final idFazenda = (await _cfg.getIdFazendaSelecionada()).trim();
          if (!mounted) return;
          Navigator.pushNamed(context, "/fornecimento", arguments: {
            "idFazenda": idFazenda,
            "autoOpenNovoFornecimento": false,
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erro: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _fmtHora(DateTime? d) {
    if (d == null) return "—";
    return "${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}:${d.second.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    final h = _header;
    final carAberto = _carregStatus != null &&
        (_carregStatus!["status_text"] ?? "").toString().toUpperCase().contains(
              "ABERTO",
            );

    return Scaffold(
      appBar: AppBar(
        title: const Text("Carregar vagão"),
        actions: [
          IconButton(
            tooltip: "Reconectar balança",
            onPressed: _saving ? null : _connectScale,
            icon: const Icon(Icons.scale),
          ),
        ],
      ),
      body: _loadError != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_loadError!, textAlign: TextAlign.center),
              ),
            )
          : h == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(
                      h.dietaNome.trim().isEmpty
                          ? "Ração (sem nome)"
                          : h.dietaNome,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Fabricação na estação: ${h.qtdRealizada.toStringAsFixed(0)} kg realizados "
                      "(previsto ${h.qtdPrevista.toStringAsFixed(0)} kg).",
                      style: TextStyle(color: Colors.grey.shade800),
                    ),
                    if (_carregStatus != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        "Peso fabricado (referência carregamento): "
                        "${(_carregStatus!["peso_fabricado"] as num?)?.toStringAsFixed(0) ?? "—"} kg",
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.blueGrey.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    FutureBuilder<String>(
                      future: _cfg.getNomeVagao(),
                      builder: (_, snap) {
                        final nome = (snap.data ?? "").trim();
                        return Text(
                          nome.isEmpty
                              ? "Vagão: (configure na tela de configuração)"
                              : "Vagão: $nome",
                          style: TextStyle(
                            color: Colors.brown.shade800,
                            fontWeight: FontWeight.w700,
                          ),
                        );
                      },
                    ),
                    if (h.status == FabricacaoStatus.pendenteCaminhao) ...[
                      const SizedBox(height: 12),
                      Material(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.info_outline,
                                  color: Colors.amber.shade900),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  "Esta fabricação ainda está pendente no misturador/caminho "
                                  "completo. Você pode registrar o peso no vagão para auditoria; "
                                  "se ainda falta completar a mistura, use «Fabricação» → abrir o lote.",
                                  style: TextStyle(
                                    color: Colors.amber.shade900,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Icon(
                          _scaleConnected
                              ? Icons.link
                              : Icons.link_off,
                          color: _scaleConnected ? Colors.green : Colors.grey,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _scaleConnecting
                                ? "Conectando à balança…"
                                : _scaleConnected
                                    ? "Balança conectada"
                                    : "Balança desconectada (ajuste IP/porta na config.)",
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Leitura: ${_lastKg.toStringAsFixed(1)} kg  ·  ${_fmtHora(_lastKgAt)}",
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _aplicarPesoBalanca,
                      icon: const Icon(Icons.download),
                      label: const Text("Usar peso da balança"),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _pesoCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: "Peso carregado no vagão (kg)",
                        border: OutlineInputBorder(),
                        helperText:
                            "Auditoria: comparar com o realizado na estação.",
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (!carAberto)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          "Não há carregamento aberto para este lote. "
                          "Receba novamente do estacionário se precisar alterar o peso.",
                          style: TextStyle(color: Colors.red.shade800),
                        ),
                      ),
                    FilledButton.icon(
                      onPressed: !carAberto || _saving
                          ? null
                          : () => _salvar(concluirFabricacaoNoVagao: false),
                      icon: const Icon(Icons.local_shipping_outlined),
                      label: const Text("Salvar e distribuir"),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: !carAberto || _saving
                          ? null
                          : () => _salvar(concluirFabricacaoNoVagao: true),
                      icon: const Icon(Icons.flag),
                      label: const Text("Salvar e concluir fabricação no vagão"),
                    ),
                    const SizedBox(height: 24),
                    OutlinedButton(
                      onPressed: _saving
                          ? null
                          : () => Navigator.pop(context),
                      child: const Text("Voltar"),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Usuário: ${SessionService.instance.userId ?? "—"}",
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ],
                ),
    );
  }
}
