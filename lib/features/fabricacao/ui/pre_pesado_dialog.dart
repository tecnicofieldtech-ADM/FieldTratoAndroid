// lib/features/fabricacao/ui/pre_pesado_dialog.dart
import "package:flutter/material.dart";

Future<void> showPrePesadoDialog({
  required BuildContext context,
  required String nome,
  required int previstoKg,
  required Future<void> Function(int realizadoKg) onConfirm,
}) async {
  final ctrl = TextEditingController(text: previstoKg.toString());

  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) {
      return AlertDialog(
        title: const Text("Ingrediente Pré-Pesado"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              nome,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 12),
            Text("Previsto: $previstoKg kg"),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
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
            onPressed: () async {
              final v = int.tryParse(ctrl.text) ?? previstoKg;
              Navigator.of(context).pop();
              await onConfirm(v);
            },
          ),
        ],
      );
    },
  );
}
