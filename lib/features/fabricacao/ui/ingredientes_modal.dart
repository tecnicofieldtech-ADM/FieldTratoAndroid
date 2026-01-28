import "package:flutter/material.dart";
import "package:fl_chart/fl_chart.dart";

import "../data/fabricacao_repo.dart";
import "../domain/models.dart";

class IngredientesModal extends StatefulWidget {
  const IngredientesModal({
    super.key,
    required this.repo,
    required this.fabId,
  });

  final FabricacaoRepo repo;
  final String fabId;

  @override
  State<IngredientesModal> createState() => _IngredientesModalState();
}

class _IngredientesModalState extends State<IngredientesModal> {
  bool _loading = true;
  List<FabIngrediente> _itens = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await widget.repo.listIngredientesDaFabricacao(widget.fabId);
      if (!mounted) return;
      setState(() => _itens = list);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.of(context).size.height * 0.92;

    return SafeArea(
      child: Container(
        constraints: BoxConstraints(maxHeight: maxH),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    "Ingredientes",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                ),
                IconButton(
                  tooltip: "Atualizar",
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                ),
                IconButton(
                  tooltip: "Fechar",
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 8),

            if (_loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (_itens.isEmpty)
              const Expanded(child: Center(child: Text("Sem ingredientes.")))
            else
              Expanded(
                child: ListView(
                  children: [
                    _chartCard(_itens),
                    const SizedBox(height: 10),
                    ..._itens.asMap().entries.map((e) {
                      final i = e.key;
                      final it = e.value;

                      final prev = it.previstoKg.toDouble();
                      final real = it.realizadoKg.toDouble();
                      final dif = real - prev;

                      return Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(color: Colors.grey.shade200),
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.blueGrey.withOpacity(0.12),
                            child: Text("${i + 1}", style: const TextStyle(fontWeight: FontWeight.w900)),
                          ),
                          title: Text(
                            (it.insumoNome ?? "").trim().isEmpty ? "Ingrediente ${i + 1}" : (it.insumoNome ?? "").trim(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              "Prev ${prev.toStringAsFixed(0)}  •  Real ${real.toStringAsFixed(0)}  •  Dif ${dif.toStringAsFixed(0)}",
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _chartCard(List<FabIngrediente> itens) {
    final previstos = itens.map((e) => e.previstoKg.toDouble()).toList();
    final realizados = itens.map((e) => e.realizadoKg.toDouble()).toList();

    final totalPrev = previstos.fold<double>(0, (a, b) => a + b);
    final totalReal = realizados.fold<double>(0, (a, b) => a + b);
    final totalDif = totalReal - totalPrev;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Previsto x Realizado (por ingrediente)", style: TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),

            // resumo totals
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                _pill("Prev", totalPrev.toStringAsFixed(0), Colors.blueGrey),
                _pill("Real", totalReal.toStringAsFixed(0), Colors.green),
                _pill("Dif", totalDif.toStringAsFixed(0), Colors.orange),
              ],
            ),

            const SizedBox(height: 10),
            SizedBox(
              height: 220,
              child: _barChart(previstos, realizados),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              children: const [
                _LegendDot(color: Colors.blueGrey, label: "Previsto"),
                _LegendDot(color: Colors.green, label: "Realizado"),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.30)),
      ),
      child: Text(
        "$label $value",
        style: TextStyle(fontWeight: FontWeight.w900, color: color),
      ),
    );
  }

  Widget _barChart(List<double> previstos, List<double> realizados) {
    final n = previstos.length;

    double maxY = 0;
    for (var i = 0; i < n; i++) {
      final m = previstos[i] > realizados[i] ? previstos[i] : realizados[i];
      if (m > maxY) maxY = m;
    }
    if (maxY <= 0) maxY = 1;

    return BarChart(
      BarChartData(
        maxY: maxY * 1.15,
        barTouchData: BarTouchData(enabled: true),
        gridData: FlGridData(show: true),
        borderData: FlBorderData(show: true),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (v, meta) => Text(v.toStringAsFixed(0), style: const TextStyle(fontSize: 10)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: (n > 10) ? 2 : 1,
              getTitlesWidget: (v, meta) {
                final i = v.round();
                if (i < 0 || i >= n) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text("${i + 1}", style: const TextStyle(fontSize: 10)),
                );
              },
            ),
          ),
        ),
        barGroups: List.generate(n, (i) {
          return BarChartGroupData(
            x: i,
            barsSpace: 6,
            barRods: [
              BarChartRodData(toY: previstos[i], width: 10, color: Colors.blueGrey),
              BarChartRodData(toY: realizados[i], width: 10, color: Colors.green),
            ],
          );
        }),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
      ],
    );
  }
}
