// lib/features/fabricacao/ui/pre_pesado_dialog.dart
import "package:flutter/material.dart";

import "../controller/fabricacao_controller.dart";

/// Mostra o diálogo de confirmação de pré-pesado.
///
/// Vinculado ao [controller] e ao [idDet]: se a Pá confirmar remotamente
/// (mirror), o realizado passa a > 0 e o diálogo se fecha sozinho.
Future<void> showPrePesadoDialog({
  required BuildContext context,
  required FabricacaoController controller,
  required String idDet,
  required String nome,
  required int previstoKg,
  required Future<void> Function(int realizadoKg) onConfirm,
}) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => _PrePesadoDialog(
      controller: controller,
      idDet: idDet,
      nome: nome,
      previstoKg: previstoKg,
      onConfirm: onConfirm,
    ),
  );
}

class _PrePesadoDialog extends StatefulWidget {
  const _PrePesadoDialog({
    required this.controller,
    required this.idDet,
    required this.nome,
    required this.previstoKg,
    required this.onConfirm,
  });

  final FabricacaoController controller;
  final String idDet;
  final String nome;
  final int previstoKg;
  final Future<void> Function(int realizadoKg) onConfirm;

  @override
  State<_PrePesadoDialog> createState() => _PrePesadoDialogState();
}

class _PrePesadoDialogState extends State<_PrePesadoDialog> {
  late final TextEditingController _ctrl;
  bool _autoClosed = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.previstoKg.toString());
    widget.controller.addListener(_onControllerChange);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChange);
    _ctrl.dispose();
    super.dispose();
  }

  void _fecharDialogoSeAberto() {
    if (_autoClosed) return;
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) return;
    _autoClosed = true;
    Navigator.of(context).pop();
  }

  void _onControllerChange() {
    if (_autoClosed) return;
    if (!mounted) return;

    final ings = widget.controller.ingredientes;
    final i = ings.indexWhere((e) => e.idDet == widget.idDet);
    if (i < 0) return;
    if (ings[i].realizadoKg <= 0) return;

    // Confirmação remota (mirror): fecha só o diálogo, não a tela de fabricação.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fecharDialogoSeAberto();
    });
  }

  Future<void> _confirmar() async {
    if (_autoClosed) return;
    final realizado = int.tryParse(_ctrl.text.trim()) ?? widget.previstoKg;
    _autoClosed = true;
    Navigator.of(context).pop();
    try {
      await widget.onConfirm(realizado);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Ingrediente Pré-Pesado"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.nome,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 12),
          Text("Previsto: ${widget.previstoKg} kg"),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _confirmar(),
            decoration: const InputDecoration(
              labelText: "Realizado (kg)",
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        ElevatedButton.icon(
          icon: const Icon(Icons.check),
          label: const Text("Confirmar"),
          onPressed: _confirmar,
        ),
      ],
    );
  }
}
