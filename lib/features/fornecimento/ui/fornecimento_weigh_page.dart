import "dart:async";
import "dart:math" as math;

import "package:flutter/material.dart";

import "../../../helpers/scale_comm.dart";
import "../../../helpers/rfid_comm.dart";

import "../data/fornecimento_repo.dart";
import "../domain/fornecimento_models.dart";
import "../../../widgets/scale_peso_highlight_card.dart";

class FornecimentoWeighPage extends StatefulWidget {
  const FornecimentoWeighPage({
    super.key,
    required this.curral,
    required this.idFazenda,
    required this.idUsuario,
    required this.repo,
    required this.scale,
    required this.rfid,
  });

  final CurralPrev curral;
  final String idFazenda;
  final String idUsuario;

  final FornecimentoRepo repo;
  final ScaleComm scale;
  final RfidComm rfid;

  @override
  State<FornecimentoWeighPage> createState() => _FornecimentoWeighPageState();
}

class _FornecimentoWeighPageState extends State<FornecimentoWeighPage> {
  StreamSubscription? _subPeso;
  StreamSubscription? _subEpc;

  num pesoAtual = 0;
  num? pesoInicial;

  bool invertDelta = false;
  double toleranciaPct = 2;
  bool concluirAutomatico = true;

  String lastEpc = "";
  String? info;
  String? error;

  DateTime _lastEpcAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _handlingPop = false;
  bool _savingByTag = false;

  CurralPrev get curral => widget.curral;

  @override
  void initState() {
    super.initState();
    _attach();
    _setRfidLeituraAtiva(true);
  }

  @override
  void dispose() {
    _setRfidLeituraAtiva(false);
    _subPeso?.cancel();
    _subEpc?.cancel();
    super.dispose();
  }

  // ---------------------------
  // STREAMS (compatível com seu ScaleComm/RfidComm)
  // ---------------------------
  Stream<num> _scaleWeightStream() {
    final d = widget.scale as dynamic;
    final candidates = <Object?>[
      _try(() => d.peso$),
      _try(() => d.weight$),
      _try(() => d.pesoStream),
      _try(() => d.weightStream),
      _try(() => d.streamPeso),
      _try(() => d.streamWeight),
    ];
    for (final c in candidates) {
      if (c is Stream) return c.cast<num>();
    }
    return const Stream<num>.empty();
  }

  Stream<String> _rfidEpcStream() {
    final d = widget.rfid as dynamic;
    final candidates = <Object?>[
      _try(() => d.epc$),
      _try(() => d.tag$),
      _try(() => d.epcStream),
      _try(() => d.tagStream),
      _try(() => d.streamEpc),
      _try(() => d.streamTag),
      _try(() => d.lines), // se o helper expõe lines
    ];
    for (final c in candidates) {
      if (c is Stream) return c.map((e) => e.toString()).cast<String>();
    }
    return const Stream<String>.empty();
  }

  Object? _try(Object? Function() fn) {
    try {
      return fn();
    } catch (_) {
      return null;
    }
  }

  void _setRfidLeituraAtiva(bool on) {
    try {
      final d = widget.rfid as dynamic;
      _try(() => d.setLeituraAtiva(on));
      _try(() => d.setActive(on));
      _try(() => d.setReading(on));
    } catch (_) {}
  }

  void _attach() {
    _subPeso ??= _scaleWeightStream().listen((v) {
      setState(() => pesoAtual = v);
    }, onError: (_) {});

    _subEpc ??= _rfidEpcStream().listen((raw) {
      unawaited(_onEpc(raw));
    }, onError: (_) {});
  }

  // ---------------------------
  // EPC
  // ---------------------------
  String _normalizeEpc(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return "";
    final idx = t.toUpperCase().indexOf("EPC:");
    if (idx >= 0) return t.substring(idx + 4).replaceAll(";", "").trim();
    return t.replaceAll(";", "").trim();
  }

  Future<void> _onEpc(String raw) async {
    final epc = _normalizeEpc(raw);
    if (epc.isEmpty) return;

    final now = DateTime.now();
    if (now.difference(_lastEpcAt).inMilliseconds < 350) return;
    _lastEpcAt = now;

    setState(() {
      lastEpc = epc;
      info = null;
      error = null;
    });

    final epcAtual = _rfidAtual().toUpperCase();
    final epcLido = epc.toUpperCase();
    final tagDiferente = epcAtual.isEmpty || epcAtual != epcLido;
    if (!tagDiferente || !hasSessaoAberta || _savingByTag) return;

    _savingByTag = true;
    try {
      await salvar();
      if (!mounted) return;
      if (error == null) {
        setState(() => info = "Sessao salva automaticamente por troca de tag.");
      }
    } finally {
      _savingByTag = false;
    }
  }

  // ---------------------------
  // PESAGEM
  // ---------------------------
  void registrarPesoInicial() {
    setState(() {
      info = null;
      error = null;
      pesoInicial = pesoAtual;
    });
  }

  void limparPesoInicial() {
    setState(() {
      info = null;
      error = null;
      pesoInicial = null;
    });
  }

  num get realizadoSessao {
    final ini = pesoInicial;
    if (ini == null) return 0;
    final delta = invertDelta ? (pesoAtual - ini) : (ini - pesoAtual);
    return math.max<num>(0, delta);
  }

  num get realizadoFinal => curral.realizadoKg + realizadoSessao;
  bool get hasSessaoAberta => pesoInicial != null;
  bool get hasSessaoAbertaComRealizado =>
      pesoInicial != null && realizadoSessao > 0;

  num get metaConcluirKg {
    final previsto = curral.previstoKg;
    final tolKg = previsto * (toleranciaPct / 100.0);
    return math.max<num>(0, previsto - tolKg);
  }

  bool get deveConcluir =>
      concluirAutomatico && (realizadoFinal >= metaConcluirKg);

  // ---------------------------
  // SALVAR
  // ---------------------------
  String get _idFornec {
    final dynamic d = curral as dynamic;
    final Object? raw = _try(() => d.idFornecimento);
    final String id = (raw?.toString().trim() ?? "");
    if (id.isEmpty) {
      throw Exception("CurralPrev.idFornecimento está vazio/null.");
    }
    return id;
  }

  Future<void> salvar({bool forcarConcluir = false}) async {
    setState(() {
      info = null;
      error = null;
    });

    try {
      final novoRealizado = realizadoFinal;
      final concluiu = forcarConcluir ? true : deveConcluir;

      final d = widget.repo as dynamic;

      try {
        await d.updateRealizado(
          idFornecimento: _idFornec,
          realizadoKg: novoRealizado,
          concluido: concluiu,
          idUsuario: widget.idUsuario,
        );
      } catch (_) {
        await d.updateRealizado(_idFornec, novoRealizado, concluiu);
      }

      setState(() {
        pesoInicial = null;
        info = concluiu ? "Salvo e concluído ?" : "Salvo ?";
      });
    } catch (e) {
      setState(() => error = "Falha ao salvar: $e");
    }
  }

  // ---------------------------
  // UI
  // ---------------------------
  @override
  Widget build(BuildContext context) {
    final previsto = curral.previstoKg;
    final finalKg = realizadoFinal;

    final prog =
        (previsto <= 0) ? 0.0 : (finalKg / previsto).clamp(0, 1).toDouble();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || _handlingPop) return;
        _handlingPop = true;
        try {
          final nav = Navigator.of(context);
          if (!hasSessaoAbertaComRealizado) {
            if (!mounted) return;
            nav.pop();
            return;
          }

          if (!mounted) return;
          final acao = await showDialog<_ExitAction>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text("Sessao em aberto"),
              content: const Text(
                "Existe fornecimento em andamento com realizado maior que zero. Deseja salvar antes de sair?",
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(_ExitAction.cancel),
                  child: const Text("Cancelar"),
                ),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(_ExitAction.discard),
                  child: const Text("Sair sem salvar"),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(_ExitAction.save),
                  child: const Text("Salvar e sair"),
                ),
              ],
            ),
          );

          if (!mounted || acao == null || acao == _ExitAction.cancel) return;
          if (acao == _ExitAction.discard) {
            nav.pop();
            return;
          }

          await salvar();
          if (!mounted) return;
          if (error == null) nav.pop();
        } finally {
          _handlingPop = false;
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Pesagem"),
        ),
        body: SafeArea(
          child: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            ScalePesoHighlightCard(
              pesoKg: pesoAtual.toDouble(),
              pesoLabel: "Peso balança",
              secondaryLabel: "Previsto (curral)",
              secondaryKg: widget.curral.previstoKg,
            ),
            const SizedBox(height: 12),
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("RFID", style: TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Text("Último EPC: ${lastEpc.isEmpty ? "—" : lastEpc}"),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Sessão de pesagem", style: TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: registrarPesoInicial,
                            icon: const Icon(Icons.flag),
                            label: Text(pesoInicial == null
                                ? "Registrar peso inicial"
                                : "Atualizar peso inicial"),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: pesoInicial == null ? null : limparPesoInicial,
                          child: const Text("Limpar"),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      pesoInicial == null
                          ? "Peso inicial: "
                          : "Peso inicial: ${pesoInicial!.toStringAsFixed(3)}",
                    ),
                    const SizedBox(height: 10),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: invertDelta,
                      onChanged: (v) => setState(() => invertDelta = v),
                      title: const Text("Inverter delta"),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Resumo", style: TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Text("Previsto: ${previsto.toStringAsFixed(3)}"),
                    Text("Realizado (final): ${finalKg.toStringAsFixed(3)}"),
                    Text("Meta concluir: ${metaConcluirKg.toStringAsFixed(3)}"),
                    const SizedBox(height: 10),
                    LinearProgressIndicator(value: prog),
                    const SizedBox(height: 6),
                    Text("${(prog * 100).toStringAsFixed(0)}%"),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => salvar(),
                            icon: const Icon(Icons.save),
                            label: const Text("Salvar"),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => salvar(forcarConcluir: true),
                            icon: const Icon(Icons.check_circle),
                            label: const Text("Concluir e salvar"),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            if (info != null)
              _BannerInfo(text: info!)
            else if (error != null)
              _BannerError(text: error!),
          ],
          ),
        ),
      ),
    );
  }

  String _rfidAtual() {
    final dynamic d = curral as dynamic;
    final Object? raw = _try(() => d.rfid);
    return (raw?.toString().trim() ?? "");
  }
}

enum _ExitAction { save, discard, cancel }

class _BannerInfo extends StatelessWidget {
  const _BannerInfo({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final bg = Colors.blue.withValues(alpha: 0.08);
    final bd = Colors.blue.withValues(alpha: 0.25);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: bd),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _BannerError extends StatelessWidget {
  const _BannerError({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final bg = Colors.red.withValues(alpha: 0.08);
    final bd = Colors.red.withValues(alpha: 0.25);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: bd),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}



