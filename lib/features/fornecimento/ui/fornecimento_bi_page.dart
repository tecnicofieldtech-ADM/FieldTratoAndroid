import "package:flutter/material.dart";

import "../data/fornecimento_repo.dart";
import "../domain/fornecimento_models.dart";

class FornecimentoBiPage extends StatefulWidget {
  const FornecimentoBiPage({
    super.key,
    required this.idFazenda,
    required this.repo,
    this.dataInicial,
    this.tratoInicial,
  });

  final String idFazenda;
  final FornecimentoRepo repo;
  final DateTime? dataInicial;
  final int? tratoInicial;

  @override
  State<FornecimentoBiPage> createState() => _FornecimentoBiPageState();
}

class _FornecimentoBiPageState extends State<FornecimentoBiPage> {
  bool _loading = true;
  DateTime _data = DateTime.now();
  int? _trato;

  List<CurralPrev> _items = const [];

  @override
  void initState() {
    super.initState();
    _data = widget.dataInicial ?? DateTime.now();
    _trato = widget.tratoInicial;
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final rows = await widget.repo.listPrevisao(
        idFazenda: widget.idFazenda,
        data: _data,
        trato: _trato,
      );
      if (!mounted) return;
      setState(() => _items = rows);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmtDate(DateTime d) {
    String two(int x) => x.toString().padLeft(2, "0");
    return "${two(d.day)}/${two(d.month)}/${d.year}";
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _data,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 2),
    );
    if (d == null) return;
    setState(() => _data = d);
    await _load();
  }

  double _eff(double previsto, double realizado) {
    if (previsto <= 0) return 0;
    final score = 100 - ((realizado - previsto).abs() * 100 / previsto);
    return score.clamp(0, 100).toDouble();
  }

  List<int> get _tratoOptions {
    final s = <int>{};
    for (final i in _items) {
      s.add(i.trato);
    }
    final out = s.toList()..sort();
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final totalPrev = _items.fold<double>(0, (a, b) => a + b.previstoKg);
    final totalReal = _items.fold<double>(0, (a, b) => a + b.realizadoKg);
    final totalDiff = totalReal - totalPrev;
    final eficiencia = _eff(totalPrev, totalReal);

    final byCurral = <String, _CurralBi>{};
    for (final i in _items) {
      final key = i.idBaia;
      byCurral.putIfAbsent(
        key,
        () => _CurralBi(
          idBaia: i.idBaia,
          nome: (i.nomeLocal ?? "").trim().isEmpty ? i.idBaia : i.nomeLocal!,
        ),
      );
      byCurral[key]!.previsto += i.previstoKg;
      byCurral[key]!.realizado += i.realizadoKg;
    }

    final maioresErros = byCurral.values.toList()
      ..sort((a, b) => b.erroAbs.compareTo(a.erroAbs));

    final tom = eficiencia >= 98
        ? Colors.green
        : (eficiencia >= 93 ? Colors.orange : Colors.red);

    final mensagem = eficiencia >= 98
        ? "Excelente precisão. Continue nesse ritmo."
        : (eficiencia >= 93
            ? "Bom trabalho. Pequenos ajustes já elevam seu resultado."
            : "Foco nos currais com maior desvio para recuperar eficiência.");

    return Scaffold(
      appBar: AppBar(
        title: const Text("BI Fornecimento"),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: _pickDate,
                              borderRadius: BorderRadius.circular(10),
                              child: InputDecorator(
                                decoration: const InputDecoration(
                                  labelText: "Data",
                                  suffixIcon: Icon(Icons.calendar_month),
                                ),
                                child: Text(_fmtDate(_data)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: DropdownButtonFormField<int?>(
                              initialValue: _trato,
                              decoration:
                                  const InputDecoration(labelText: "Trato"),
                              items: [
                                const DropdownMenuItem<int?>(
                                  value: null,
                                  child: Text("Todos"),
                                ),
                                ..._tratoOptions.map(
                                  (t) => DropdownMenuItem<int?>(
                                    value: t,
                                    child: Text("Trato $t"),
                                  ),
                                ),
                              ],
                              onChanged: (v) async {
                                setState(() => _trato = v);
                                await _load();
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Card(
                    color: tom.withValues(alpha: 0.10),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: tom.withValues(alpha: 0.20),
                            child: Icon(Icons.insights, color: tom),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Eficiência: ${eficiencia.toStringAsFixed(1)}%",
                                  style: TextStyle(
                                    color: tom,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 18,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(mensagem),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: Row(
                    children: [
                      _kpi("Previsto", totalPrev.toStringAsFixed(0)),
                      const SizedBox(width: 8),
                      _kpi("Realizado", totalReal.toStringAsFixed(0)),
                      const SizedBox(width: 8),
                      _kpi(
                        "Diferença",
                        totalDiff.toStringAsFixed(0),
                        valueColor: totalDiff.abs() <= 0.001
                            ? Colors.black
                            : (totalDiff > 0 ? Colors.red : Colors.green),
                      ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(12, 4, 12, 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "Maiores erros por curral",
                      style:
                          TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                    ),
                  ),
                ),
                Expanded(
                  child: maioresErros.isEmpty
                      ? const Center(child: Text("Sem dados para o período."))
                      : ListView.separated(
                          itemCount: maioresErros.length > 8
                              ? 8
                              : maioresErros.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 6),
                          itemBuilder: (_, i) {
                            final c = maioresErros[i];
                            final passou = c.dif > 0;
                            return Card(
                              margin:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor:
                                      Colors.black.withValues(alpha: 0.07),
                                  child: Text("${i + 1}"),
                                ),
                                title: Text(
                                  c.nome,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                subtitle: Text(
                                  "Prev ${c.previsto.toStringAsFixed(0)} kg  •  Real ${c.realizado.toStringAsFixed(0)} kg",
                                ),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      "${c.erroAbs.toStringAsFixed(0)} kg",
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    Text(
                                      passou ? "Passou" : "Faltou",
                                      style: TextStyle(
                                        color: passou
                                            ? Colors.red
                                            : Colors.green,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _kpi(String title, String value, {Color? valueColor}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.black.withValues(alpha: 0.10)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: valueColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CurralBi {
  _CurralBi({
    required this.idBaia,
    required this.nome,
  });

  final String idBaia;
  final String nome;
  double previsto = 0;
  double realizado = 0;

  double get dif => realizado - previsto;
  double get erroAbs => dif.abs();
}
