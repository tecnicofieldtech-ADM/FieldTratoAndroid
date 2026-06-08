import "package:flutter/material.dart";

import "../../domain/fornecimento_models.dart";

class FornecimentoSessoesDialog extends StatelessWidget {
  const FornecimentoSessoesDialog({
    super.key,
    required this.curral,
    required this.sessoes,
  });

  final CurralPrev curral;
  final List<Map<String, Object?>> sessoes;

  static String _s(dynamic v) => (v ?? "").toString().trim();

  static double _n(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().replaceAll(",", ".")) ?? 0;
  }

  static String _fmtNum(dynamic v, {int dec = 0}) {
    return _n(v).toStringAsFixed(dec);
  }

  static Future<void> show(
    BuildContext context, {
    required CurralPrev curral,
    required List<Map<String, Object?>> sessoes,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => FornecimentoSessoesDialog(
        curral: curral,
        sessoes: sessoes,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = sessoes.fold<double>(0, (a, r) => a + _n(r["realizado"]));

    return AlertDialog(
      title: const Text("Registros de fornecimento"),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "${curral.nomeLocal ?? curral.idBaia} · Trato ${curral.trato}",
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                "${sessoes.length} registro(s) · Total ${_fmtNum(total, dec: 0)} kg",
                style: TextStyle(color: Colors.black.withValues(alpha: 0.65)),
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowHeight: 36,
                  dataRowMinHeight: 32,
                  dataRowMaxHeight: 40,
                  columns: const [
                    DataColumn(label: Text("#")),
                    DataColumn(label: Text("Hora ini")),
                    DataColumn(label: Text("Hora fim")),
                    DataColumn(label: Text("Peso ini")),
                    DataColumn(label: Text("Peso fim")),
                    DataColumn(label: Text("Realizado")),
                    DataColumn(label: Text("Sync")),
                  ],
                  rows: [
                    for (var i = 0; i < sessoes.length; i++)
                      DataRow(
                        cells: [
                          DataCell(Text("${i + 1}")),
                          DataCell(Text(_s(sessoes[i]["hora_inicio"]))),
                          DataCell(Text(_s(sessoes[i]["hora_fim"]))),
                          DataCell(Text(_fmtNum(sessoes[i]["peso_inicio"], dec: 0))),
                          DataCell(Text(_fmtNum(sessoes[i]["peso_fim"], dec: 0))),
                          DataCell(Text(_fmtNum(sessoes[i]["realizado"], dec: 0))),
                          DataCell(
                            Text(
                              _n(sessoes[i]["flag_sync"]) == 1 ? "Sim" : "Não",
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text("Fechar"),
        ),
      ],
    );
  }
}
