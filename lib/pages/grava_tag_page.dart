import "dart:async";

import "package:flutter/material.dart";

import "../repo/config_repo.dart";
import "../repo/grava_tag_repo.dart";
import "../helpers/rfid_comm.dart";

class GravaTagPage extends StatefulWidget {
  const GravaTagPage({super.key});

  @override
  State<GravaTagPage> createState() => _GravaTagPageState();
}

class _GravaTagPageState extends State<GravaTagPage> {
  final _repo = GravaTagRepo();
  final _cfg = ConfigRepo();

  final _nomeCtrl = TextEditingController();

  bool _loading = false;
  String _idFazenda = "";
  String _linhaSel = "";
  String _ultimoEpc = "";
  String? _curralLendoId;

  List<String> _linhas = const [];
  List<GravaTagCurral> _currais = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_carregarTudo());
  }

  @override
  void dispose() {
    _nomeCtrl.dispose();
    super.dispose();
  }

  Future<void> _carregarTudo() async {
    setState(() => _loading = true);
    try {
      final backend = await _cfg.getBackend();
      final isFieldpec = backend == 1;
      final idFazenda = await _cfg.getIdFazendaSelecionada();
      final filtroFazenda = isFieldpec ? "" : idFazenda;

      final linhas = await _repo.listLinhas(idFazenda: filtroFazenda);
      final currais = await _repo.listCurrais(
        idFazenda: filtroFazenda,
        linha: _linhaSel,
        nomeCurral: _nomeCtrl.text,
      );

      if (!mounted) return;
      setState(() {
        _idFazenda = filtroFazenda;
        _linhas = linhas;
        _currais = currais;
      });
    } catch (e) {
      _toast("Erro ao carregar mapa de currais: $e");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _onLimparTag(GravaTagCurral curral) async {
    if (_curralLendoId != null) return;

    final tag = (curral.rfid ?? "").trim();
    if (tag.isEmpty) {
      _toast("Este curral ja esta sem tag vinculada.");
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Limpar tag"),
        content: Text(
          "Remover o vínculo da tag $tag do curral ${curral.nomeLocal}?\n\n"
          "Depois você pode gravar uma nova tag neste curral.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text("Cancelar"),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text("Limpar"),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;

    setState(() => _curralLendoId = curral.id);
    try {
      final removida = await _repo.limparVinculo(idCurral: curral.id);
      if (!mounted) return;
      if (removida != null && removida == _ultimoEpc) {
        setState(() => _ultimoEpc = "");
      }
      _toast("Tag removida do curral ${curral.nomeLocal}.");
      await _carregarTudo();
    } catch (e) {
      _toast("Erro ao limpar tag: $e");
    } finally {
      if (mounted) setState(() => _curralLendoId = null);
    }
  }

  Future<void> _onGravarTag(GravaTagCurral curral) async {
    if (_curralLendoId != null) return;

    final host = (await _cfg.getHostRfid()).trim();
    final port = await _cfg.getPortaRfid();

    if (!mounted) return;

    if (host.isEmpty || port <= 0) {
      _toast("Configure IP e porta do RFID antes de gravar tag.");
      return;
    }

    setState(() => _curralLendoId = curral.id);

    try {
      final epc = await showDialog<String?>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _ReadTagDialog(
          host: host,
          port: port,
          curralNome: curral.nomeLocal,
        ),
      );

      if (!mounted) return;
      if (epc == null || epc.trim().isEmpty) {
        return;
      }

      final epcNorm = epc.trim();
      setState(() => _ultimoEpc = epcNorm);

      final backend = await _cfg.getBackend();
      final isFieldpec = backend == 1;
      final filtroFazenda = isFieldpec ? "" : _idFazenda;

      final vinculo = await _repo.findCurralByEpc(
        epcNorm,
        idFazenda: filtroFazenda,
      );

      if (!mounted) return;

      if (vinculo != null && vinculo.id != curral.id) {
        final linhaTxt = vinculo.linha.trim().isEmpty ? "-" : vinculo.linha;
        await showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text("EPC ja vinculado"),
            content: Text(
              "O EPC $epcNorm ja esta vinculado ao curral ${vinculo.nomeLocal} (linha $linhaTxt).",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text("Fechar"),
              ),
            ],
          ),
        );
        return;
      }

      await _repo.salvarVinculo(idCurral: curral.id, epc: epcNorm);

      if (!mounted) return;
      _toast("Tag gravada: $epcNorm no curral ${curral.nomeLocal}.");
      await _carregarTudo();
    } catch (e) {
      _toast("Erro ao gravar tag: $e");
    } finally {
      if (mounted) setState(() => _curralLendoId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final linhasItems = <DropdownMenuItem<String>>[
      const DropdownMenuItem(value: "", child: Text("Todas as linhas")),
      ..._linhas.map(
        (l) => DropdownMenuItem(value: l, child: Text(l)),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text("Gravar TAG"),
        actions: [
          IconButton(
            tooltip: "Atualizar",
            onPressed: _loading ? null : _carregarTudo,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _nomeCtrl,
                    decoration: InputDecoration(
                      labelText: "Filtrar por nome do curral",
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        onPressed: _loading ? null : _carregarTudo,
                        icon: const Icon(Icons.search),
                      ),
                    ),
                    onSubmitted: (_) => _carregarTudo(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _linhaSel,
              items: linhasItems,
              onChanged: (v) {
                setState(() => _linhaSel = (v ?? "").trim());
                unawaited(_carregarTudo());
              },
              decoration: const InputDecoration(
                labelText: "Filtrar por linha",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            if (_ultimoEpc.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.green.withValues(alpha: 0.30)),
                ),
                child: Text(
                  "Ultimo EPC lido: $_ultimoEpc",
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            if (_ultimoEpc.isNotEmpty) const SizedBox(height: 10),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _currais.isEmpty
                      ? const Center(
                          child: Text("Nenhum curral encontrado para os filtros."),
                        )
                      : ListView.separated(
                          itemCount: _currais.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, i) {
                            final c = _currais[i];
                            final tag = (c.rfid ?? "").trim();
                            final lendo = _curralLendoId == c.id;

                            return Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.black12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    c.nomeLocal,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    "Linha: ${c.linha.isEmpty ? "-" : c.linha}",
                                    style: const TextStyle(color: Colors.black54),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    "TAG vinculada: ${tag.isEmpty ? "(sem tag)" : tag}",
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: tag.isEmpty ? Colors.black54 : Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      if (tag.isNotEmpty) ...[
                                        Expanded(
                                          child: OutlinedButton.icon(
                                            onPressed: lendo
                                                ? null
                                                : () => _onLimparTag(c),
                                            icon: const Icon(Icons.clear),
                                            label: const Text("Limpar tag"),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                      ],
                                      Expanded(
                                        flex: tag.isNotEmpty ? 2 : 1,
                                        child: ElevatedButton.icon(
                                          onPressed: lendo
                                              ? null
                                              : () => _onGravarTag(c),
                                          icon: lendo
                                              ? const SizedBox(
                                                  width: 16,
                                                  height: 16,
                                                  child:
                                                      CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                  ),
                                                )
                                              : const Icon(Icons.nfc),
                                          label: Text(
                                            lendo
                                                ? "Lendo TAG..."
                                                : tag.isEmpty
                                                    ? "Gravar TAG neste curral"
                                                    : "Gravar nova tag",
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadTagDialog extends StatefulWidget {
  const _ReadTagDialog({
    required this.host,
    required this.port,
    required this.curralNome,
  });

  final String host;
  final int port;
  final String curralNome;

  @override
  State<_ReadTagDialog> createState() => _ReadTagDialogState();
}

class _ReadTagDialogState extends State<_ReadTagDialog> {
  RfidComm? _rfid;
  StreamSubscription<RfidStatusEvent>? _statusSub;
  StreamSubscription<RfidTagEvent>? _tagSub;
  Timer? _timeout;

  String _status = "Conectando ao RFID...";
  String _epc = "";
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    unawaited(_startRead());
  }

  @override
  void dispose() {
    _timeout?.cancel();
    unawaited(_statusSub?.cancel());
    unawaited(_tagSub?.cancel());
    unawaited(_rfid?.dispose());
    super.dispose();
  }

  Future<void> _startRead() async {
    final comm = RfidComm(
      host: widget.host,
      port: widget.port,
      autoReconnect: false,
      connectTimeout: const Duration(seconds: 3),
      debounceMs: 500,
      readWatchdog: Duration.zero,
    );

    _rfid = comm;

    _statusSub = comm.statusStream.listen((ev) {
      if (!mounted) return;
      setState(() {
        switch (ev.status) {
          case RfidStatus.connecting:
            _status = "Conectando ao leitor...";
            break;
          case RfidStatus.connected:
            _status = "Conectado. Aproxime a tag.";
            break;
          case RfidStatus.error:
            _status = "Erro: ${ev.message ?? "desconhecido"}";
            break;
          case RfidStatus.disconnected:
            _status = "Desconectado.";
            break;
        }
      });
    });

    _tagSub = comm.tagStream.listen((ev) async {
      if (!mounted || _closing) return;
      setState(() {
        _epc = ev.epc.trim();
        _status = "EPC lido com sucesso.";
      });

      await Future.delayed(const Duration(milliseconds: 250));
      if (!mounted || _closing) return;
      _closing = true;
      Navigator.of(context).pop(_epc);
    });

    _timeout = Timer(const Duration(seconds: 8), () {
      if (!mounted || _closing) return;
      setState(() => _status = "Sem leitura no tempo limite. Tente novamente.");
    });

    comm.setLeituraAtiva(true);
    await comm.connect();
  }

  Future<void> _cancel() async {
    if (_closing) return;
    _closing = true;
    Navigator.of(context).pop(null);
  }

  void _limparLeitura() {
    if (_closing) return;
    _timeout?.cancel();
    _timeout = Timer(const Duration(seconds: 8), () {
      if (!mounted || _closing) return;
      setState(() => _status = "Sem leitura no tempo limite. Tente novamente.");
    });
    setState(() {
      _epc = "";
      _status = "Leitura limpa. Aproxime a nova tag.";
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Leitura de TAG"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Curral: ${widget.curralNome}"),
          const SizedBox(height: 10),
          Text(_status),
          const SizedBox(height: 10),
          Text(
            "EPC: ${_epc.isEmpty ? "-" : _epc}",
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _epc.isEmpty ? null : _limparLeitura,
          child: const Text("Limpar leitura"),
        ),
        TextButton(
          onPressed: _cancel,
          child: const Text("Cancelar"),
        ),
        if (_epc.isNotEmpty)
          FilledButton(
            onPressed: () {
              if (_closing) return;
              _closing = true;
              Navigator.of(context).pop(_epc);
            },
            child: const Text("Usar esta tag"),
          ),
      ],
    );
  }
}
