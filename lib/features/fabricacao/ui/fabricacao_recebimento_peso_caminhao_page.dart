import "dart:async";

import "package:flutter/material.dart";

import "../../../helpers/scale_comm.dart";
import "../../../repo/config_repo.dart";
import "../data/fabricacao_repo.dart";
import "../domain/fabricacao_flow.dart";
import "../domain/models.dart";
import "fabricacao_weigh_page.dart";

/// Tela de carregamento da ração no vagão (passos 5–11 do fluxo).
///
/// - Conecta TCP na balança
/// - Captura peso inicial automaticamente
/// - Mostra realizado = leitura atual − peso inicial
/// - Botão "Completar carregamento" → fabricação no insumo pendente
class FabricacaoRecebimentoPesoCaminhaoPage extends StatefulWidget {
  const FabricacaoRecebimentoPesoCaminhaoPage({
    super.key,
    required this.repo,
    required this.idFabricacao,
    this.autoConectarBalanca = false,
  });

  final FabricacaoRepo repo;
  final String idFabricacao;

  /// Quando true (fluxo vindo de Carregamento → Receber), conecta a balança ao abrir.
  final bool autoConectarBalanca;

  @override
  State<FabricacaoRecebimentoPesoCaminhaoPage> createState() =>
      _FabricacaoRecebimentoPesoCaminhaoPageState();
}

class _FabricacaoRecebimentoPesoCaminhaoPageState
    extends State<FabricacaoRecebimentoPesoCaminhaoPage> {
  final _cfg = ConfigRepo();
  final _pesoManualCtrl = TextEditingController();

  FabricacaoHeader? _header;
  String? _loadError;

  ScaleComm? _scale;
  StreamSubscription<ScaleEvent>? _stSub;
  StreamSubscription<ScaleWeightEvent>? _wtSub;

  bool _scaleConnecting = false;
  bool _scaleConnected = false;
  double _lastKg = 0;
  DateTime? _lastKgAt;

  double? _pesoInicio;
  bool _saving = false;
  Timer? _ticker;
  bool _balancaIniciada = false;

  @override
  void initState() {
    super.initState();
    _boot();
    _ticker = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (!mounted) return;
      _maybeAutoCapturarPesoInicio();
      setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _pesoManualCtrl.dispose();
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
    setState(() => _loadError = null);
    try {
      final h = await widget.repo.getFabricacaoById(widget.idFabricacao.trim());
      if (!mounted) return;
      if (h == null) {
        setState(() => _loadError = "Fabricação não encontrada.");
        return;
      }
      if (h.status != FabricacaoStatus.pendenteCaminhao) {
        setState(() {
          _loadError =
              "Esta tela é só para lotes pendentes recebidos do estacionário.";
        });
        return;
      }
      setState(() => _header = h);

      if (widget.autoConectarBalanca) {
        await _iniciarBalanca();
      }
    } catch (e) {
      if (mounted) setState(() => _loadError = e.toString());
    }
  }

  Future<void> _iniciarBalanca() async {
    if (_balancaIniciada) return;
    _balancaIniciada = true;
    await _connectScale();
  }

  void _maybeAutoCapturarPesoInicio() {
    if (_pesoInicio != null) return;
    if (!_scaleConnected) return;
    if (_lastKgAt == null) return;

    setState(() => _pesoInicio = _lastKg);
    _pesoManualCtrl.clear();
  }

  void _recapturarPesoInicio() {
    if (!_scaleConnected || _lastKgAt == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Aguarde conexão e leitura da balança.")),
      );
      return;
    }
    setState(() => _pesoInicio = _lastKg);
    _pesoManualCtrl.clear();
  }

  Future<void> _connectScale() async {
    await _disconnectScale();
    final host = (await _cfg.getHostBalanca()).trim();
    final port = await _cfg.getPortaBalanca();
    final modelInt = await _cfg.getModeloBalanca();
    if (host.isEmpty || port <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "IP/porta da balança não configurados. Informe o kg manualmente ou ajuste em Configuração.",
            ),
          ),
        );
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
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _maybeAutoCapturarPesoInicio();
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
      _maybeAutoCapturarPesoInicio();
    });

    try {
      await scale.connect();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Falha ao conectar balança TCP ($host:$port): $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _scaleConnecting = false);
    }
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

  double? get _pesoDeltaCalculado {
    if (_pesoInicio == null) return null;
    final d = _lastKg - _pesoInicio!;
    return d > 0 ? d : 0.0;
  }

  Future<void> _completarCarregamento() async {
    final manual = _pesoManualCtrl.text.trim().replaceAll(",", ".");
    final manualKg = double.tryParse(manual);

    double kg;
    if (manualKg != null && manualKg > 0) {
      kg = manualKg;
    } else {
      final d = _pesoDeltaCalculado;
      if (_pesoInicio == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Aguarde a captura do peso inicial na balança "
              "(ou informe o kg carregado manualmente).",
            ),
          ),
        );
        return;
      }
      if (d == null || d <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Peso carregado zero ou inválido. Carregue a ração ou informe o kg manualmente.",
            ),
          ),
        );
        return;
      }
      kg = d;
    }

    if (!mounted) return;
    final irParaFab = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("Completar carregamento"),
            content: Text(
              "Registrar ${kg.toStringAsFixed(0)} kg carregados e abrir a fabricação "
              "para completar o lote?",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text("Só registrar"),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text("Completar e fabricar"),
              ),
            ],
          ),
        ) ??
        true;

    setState(() => _saving = true);
    try {
      final idVagao = (await _cfg.getIdVagao()).trim();
      await widget.repo.registrarCarregamentoDistribuidorVagao(
        idFabricacao: widget.idFabricacao.trim(),
        pesoCarregadoKg: kg,
        idVagao: idVagao,
        concluirFabricacaoNoVagao: false,
      );
      if (!mounted) return;

      if (irParaFab) {
        await _disconnectScale();
        await Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => FabricacaoWeighPage(
              repo: widget.repo,
              initialFabricacaoId: widget.idFabricacao.trim(),
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Carregamento registrado: ${kg.toStringAsFixed(0)} kg.",
            ),
          ),
        );
        Navigator.pop(context);
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
    return "${d.hour.toString().padLeft(2, "0")}:"
        "${d.minute.toString().padLeft(2, "0")}:"
        "${d.second.toString().padLeft(2, "0")}";
  }

  @override
  Widget build(BuildContext context) {
    final h = _header;
    final delta = _pesoDeltaCalculado;
    final manual = _pesoManualCtrl.text.trim().replaceAll(",", ".");
    final manualKg = double.tryParse(manual);
    final realizadoExibido =
        (manualKg != null && manualKg > 0) ? manualKg : (delta ?? 0.0);

    if (_loadError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text("Carregamento da ração")),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(_loadError!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Voltar"),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (h == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Carregamento da ração"),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            h.dietaNome.trim().isEmpty ? "Lote pendente" : h.dietaNome,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            "Peso inicial = leitura ao abrir. Realizado = peso atual − inicial.",
            style: TextStyle(color: Colors.grey.shade700, height: 1.35),
          ),
          const SizedBox(height: 20),

          // Status balança
          Row(
            children: [
              Icon(
                _scaleConnected ? Icons.link : Icons.link_off,
                color: _scaleConnected ? Colors.green : Colors.orange,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _scaleConnecting
                      ? "Conectando balança (TCP)…"
                      : _scaleConnected
                          ? "Balança conectada"
                          : "Sem conexão — toque Reconectar",
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              if (!_scaleConnected && !_scaleConnecting)
                TextButton(
                  onPressed: _saving ? null : _iniciarBalanca,
                  child: const Text("Reconectar"),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // Peso atual
          Text(
            "Peso na balança",
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
          Text(
            "${_lastKg.toStringAsFixed(0)} kg",
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          Text(
            "Atualizado: ${_fmtHora(_lastKgAt)}",
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 16),

          // Peso inicial
          if (_pesoInicio == null)
            Card(
              color: Colors.orange.shade50,
              child: const Padding(
                padding: EdgeInsets.all(14),
                child: Text(
                  "Capturando peso inicial automaticamente…",
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            )
          else ...[
            Text(
              "Peso inicial: ${_pesoInicio!.toStringAsFixed(0)} kg",
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            OutlinedButton.icon(
              onPressed: _saving ? null : _recapturarPesoInicio,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text("Atualizar peso inicial"),
            ),
          ],
          const SizedBox(height: 24),

          // Realizado — número grande (passo 9)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.brown.shade50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.brown.shade200, width: 2),
            ),
            child: Column(
              children: [
                Text(
                  "REALIZADO",
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: Colors.brown.shade700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _pesoInicio == null && (manualKg == null || manualKg <= 0)
                      ? "—"
                      : realizadoExibido.toStringAsFixed(0),
                  style: TextStyle(
                    fontSize: 64,
                    fontWeight: FontWeight.w900,
                    height: 1,
                    color: Colors.brown.shade900,
                  ),
                ),
                Text(
                  "kg",
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Colors.brown.shade700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          TextField(
            controller: _pesoManualCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: "Kg manual (opcional)",
              border: OutlineInputBorder(),
              helperText: "Se preencher, substitui o calculado pela balança.",
            ),
          ),
          const SizedBox(height: 28),

          // Passo 10–11
          FilledButton.icon(
            onPressed: _saving ? null : _completarCarregamento,
            icon: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_circle_outline),
            label: const Text("Completar carregamento"),
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 52),
              textStyle: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text("Cancelar"),
          ),
        ],
      ),
    );
  }
}
