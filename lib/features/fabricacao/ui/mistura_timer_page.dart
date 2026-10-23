// lib/features/fabricacao/ui/mistura_timer_page.dart
import "dart:async";
import "package:flutter/material.dart";

import "../data/fabricacao_repo.dart";

class MisturaTimerPage extends StatefulWidget {
  const MisturaTimerPage({
    super.key,
    required this.minutos,

    // ✅ compat com sua chamada atual:
    this.repo,
    this.fabricacaoId,

    // opcionais
    this.titulo,
    this.onDonePopToRoot = false,
    this.segundosQuandoMinutosZero = 0,
    this.autoFinishWhenDone = false,
  });

  /// ✅ minutos de mistura (ex: 1 = 60s). Se <= 0, usa [segundosQuandoMinutosZero].
  final int minutos;

  /// Contagem quando [minutos] <= 0 (ex.: 10 s após finalizar sem tempo de mistura).
  final int segundosQuandoMinutosZero;

  /// opcional (compat)
  final FabricacaoRepo? repo;

  /// opcional (compat)
  final String? fabricacaoId;

  final String? titulo;

  /// Se true, ao finalizar faz `popUntil(isFirst)` — **evitar** no fluxo de
  /// fabricação (reconstrói/expõe a pesagem). Preferir `false` e deixar a
  /// página chamadora sair da pesagem com `pushNamedAndRemoveUntil`.
  final bool onDonePopToRoot;

  /// Fecha automaticamente ao concluir a contagem (sem exigir toque em Finalizar).
  final bool autoFinishWhenDone;

  @override
  State<MisturaTimerPage> createState() => _MisturaTimerPageState();
}

class _MisturaTimerPageState extends State<MisturaTimerPage> {
  Timer? _t;
  Timer? _autoFinishTimer;
  int _secs = 0;
  bool _done = false;
  bool _closing = false;

  @override
  void initState() {
    super.initState();

    final totalSecs = widget.minutos > 0
        ? widget.minutos * 60
        : widget.segundosQuandoMinutosZero;

    if (totalSecs <= 0) {
      _secs = 0;
      _done = true;
      _scheduleAutoFinish();
      return;
    }

    _secs = totalSecs;

    _t = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;

      setState(() {
        _secs--;
        if (_secs <= 0) {
          _secs = 0;
          _done = true;
          t.cancel();
          _scheduleAutoFinish();
        }
      });
    });
  }

  void _scheduleAutoFinish() {
    if (!widget.autoFinishWhenDone) return;
    _autoFinishTimer?.cancel();
    _autoFinishTimer = Timer(const Duration(milliseconds: 600), () {
      if (!mounted || !_done) return;
      _finish();
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    _t = null;
    _autoFinishTimer?.cancel();
    _autoFinishTimer = null;
    super.dispose();
  }

  String _fmt(int s) {
    final mm = (s ~/ 60).toString().padLeft(2, "0");
    final ss = (s % 60).toString().padLeft(2, "0");
    return "$mm:$ss";
  }

  void _finish() {
    if (!mounted || _closing) return;
    _closing = true;
    _autoFinishTimer?.cancel();

    // Sempre só fecha o timer; quem abriu decide o destino (lista / fornecimento).
    // popUntil(root) sozinho reconstruía a pesagem — isso era o bug.
    if (widget.onDonePopToRoot) {
      Navigator.of(context).popUntil((r) => r.isFirst);
    } else {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.titulo ?? "Mistura";

    return PopScope(
      canPop: _done,
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: _done ? () => Navigator.of(context).pop(false) : null,
            tooltip: "Fechar",
          ),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _done ? Icons.check_circle : Icons.timer,
                      size: 84,
                      color: _done ? Colors.green : null,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _done ? "Concluído" : "Tempo de mistura",
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _fmt(_secs),
                      style: const TextStyle(fontSize: 56, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 18),
                    if (widget.fabricacaoId != null && widget.fabricacaoId!.trim().isNotEmpty)
                      Text(
                        "Fabricação: ${widget.fabricacaoId}",
                        style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    const SizedBox(height: 22),
                    if (_done && !_closing)
                      FilledButton.icon(
                        onPressed: _finish,
                        icon: const Icon(Icons.check),
                        label: const Text("Finalizar"),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}


