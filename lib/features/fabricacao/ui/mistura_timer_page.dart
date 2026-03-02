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
    this.onDonePopToRoot = true,
  });

  /// ✅ minutos de mistura (ex: 1 = 60s)
  /// Regra:
  /// - <= 0: não deveria abrir (tratado na weigh_page),
  ///   mas se abrir, encerra imediatamente.
  final int minutos;

  /// opcional (compat)
  final FabricacaoRepo? repo;

  /// opcional (compat)
  final String? fabricacaoId;

  final String? titulo;

  /// quando terminar, volta pra tela inicial/raiz (padrão)
  final bool onDonePopToRoot;

  @override
  State<MisturaTimerPage> createState() => _MisturaTimerPageState();
}

class _MisturaTimerPageState extends State<MisturaTimerPage> {
  Timer? _t;
  int _secs = 0;
  bool _done = false;

  @override
  void initState() {
    super.initState();

    // ✅ se vier 0 ou negativo, encerra imediatamente
    if (widget.minutos <= 0) {
      _secs = 0;
      _done = true;

      // garante 1 frame e já habilita "Finalizar"
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {});
      });
      return;
    }

    _secs = widget.minutos * 60;

    _t = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;

      setState(() {
        _secs--;
        if (_secs <= 0) {
          _secs = 0;
          _done = true;
          t.cancel();
        }
      });
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    _t = null;
    super.dispose();
  }

  String _fmt(int s) {
    final mm = (s ~/ 60).toString().padLeft(2, "0");
    final ss = (s % 60).toString().padLeft(2, "0");
    return "$mm:$ss";
  }

  void _finish() {
    if (!mounted) return;

    if (widget.onDonePopToRoot) {
      Navigator.of(context).popUntil((r) => r.isFirst);
    } else {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.titulo ?? "Mistura";

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(false),
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
                  if (!_done) ...[
                    OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).pop(false),
                      icon: const Icon(Icons.arrow_back),
                      label: const Text("Voltar"),
                    ),
                  ] else ...[
                    FilledButton.icon(
                      onPressed: _finish,
                      icon: const Icon(Icons.check),
                      label: const Text("Finalizar"),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}


