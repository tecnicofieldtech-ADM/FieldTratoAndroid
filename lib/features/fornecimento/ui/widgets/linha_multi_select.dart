import "package:flutter/material.dart";

import "../../domain/linha_filtro.dart";

/// Filtro de linhas com checkbox. Conjunto vazio significa "Todas".
class LinhaMultiSelect extends StatelessWidget {
  const LinhaMultiSelect({
    super.key,
    required this.opcoes,
    required this.selecionadas,
    required this.onChanged,
    this.border,
  });

  final List<String> opcoes;
  final Set<String> selecionadas;
  final ValueChanged<Set<String>> onChanged;
  final InputBorder? border;

  String get _rotulo {
    if (selecionadas.isEmpty) return "Todas";
    final list = selecionadas.toList()..sort();
    return list.join(", ");
  }

  Future<void> _abrir(BuildContext context) async {
    final draft = normalizarLinhas(selecionadas);
    final applied = await showDialog<Set<String>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: const Text("Linhas"),
              content: SizedBox(
                width: 320,
                child: opcoes.isEmpty
                    ? const Text("Nenhuma linha na previsão.")
                    : SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final l in opcoes)
                              CheckboxListTile(
                                value: draft.contains(l.trim().toUpperCase()),
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                contentPadding: EdgeInsets.zero,
                                title: Text(l),
                                onChanged: (v) {
                                  setLocal(() {
                                    final key = l.trim().toUpperCase();
                                    if (v == true) {
                                      draft.add(key);
                                    } else {
                                      draft.remove(key);
                                    }
                                  });
                                },
                              ),
                          ],
                        ),
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, <String>{}),
                  child: const Text("Todas"),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, draft),
                  child: const Text("Aplicar"),
                ),
              ],
            );
          },
        );
      },
    );
    if (applied != null) onChanged(normalizarLinhas(applied));
  }

  @override
  Widget build(BuildContext context) {
    final b = border ??
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.10)),
        );
    return InkWell(
      onTap: () => _abrir(context),
      borderRadius: BorderRadius.circular(10),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: "Linha",
          border: b,
          enabledBorder: b,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          suffixIcon: const Icon(Icons.arrow_drop_down),
        ),
        child: Text(
          _rotulo,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
