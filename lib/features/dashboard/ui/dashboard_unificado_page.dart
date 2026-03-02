import "package:flutter/material.dart";
import "package:fl_chart/fl_chart.dart";

import "../data/dashboard_unificado_repo.dart";

class DashboardUnificadoPage extends StatefulWidget {
  const DashboardUnificadoPage({super.key, required this.repo});

  final DashboardUnificadoRepo repo;

  @override
  State<DashboardUnificadoPage> createState() => _DashboardUnificadoPageState();
}

class _DashboardUnificadoPageState extends State<DashboardUnificadoPage> {
  static const _prevColor = Color(0xFF2563EB);
  static const _realColor = Color(0xFF16A34A);
  bool _loading = true;
  DateTime _date = DateTime.now();

  Map<String, num> _fabTotais = const {
    "previsto": 0,
    "realizado": 0,
    "qtd": 0,
    "tempo_medio_seg": 0,
  };
  Map<String, num> _fornTotais = const {
    "previsto": 0,
    "realizado": 0,
    "qtd": 0,
    "currais": 0,
  };
  List<Map<String, Object?>> _analise = const [];
  List<Map<String, Object?>> _fornDesvios = const [];
  List<Map<String, Object?>> _fabDesvioRacao = const [];
  List<Map<String, Object?>> _fabDesvioInsumo = const [];
  int? _tratoFiltro;
  String? _idDietaFiltro;
  List<int> _tratoOptions = const [];
  List<Map<String, String>> _dietaOptions = const [];

  final Map<String, Future<List<Map<String, Object?>>>> _cacheCurrais = {};

  String _iso(DateTime d) =>
      "${d.year.toString().padLeft(4, "0")}-${d.month.toString().padLeft(2, "0")}-${d.day.toString().padLeft(2, "0")}";

  String _br(DateTime d) =>
      "${d.day.toString().padLeft(2, "0")}/${d.month.toString().padLeft(2, "0")}/${d.year}";

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 2, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (picked == null || !mounted) return;
    setState(() => _date = DateTime(picked.year, picked.month, picked.day));
    await _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final dataIso = _iso(_date);
    try {
      final filtros = await widget.repo.filtrosDoDia(dataIso);
      final tratos = filtros["tratos"] ?? const <Map<String, Object?>>[];
      final dietas = filtros["dietas"] ?? const <Map<String, Object?>>[];

      var tratoFiltro = _tratoFiltro;
      var idDietaFiltro = _idDietaFiltro;

      final tratoOptions = tratos
          .map((e) => ((e["trato"] as num?) ?? 0).toInt())
          .toSet()
          .toList()
        ..sort();
      if (tratoFiltro != null && !tratoOptions.contains(tratoFiltro)) {
        tratoFiltro = null;
      }

      final dietaOptions = dietas
          .map((e) => {
                "id": (e["id_dieta"] ?? "").toString().trim(),
                "nome": (e["dieta"] ?? "").toString().trim(),
              })
          .where((e) => (e["id"] ?? "").isNotEmpty)
          .toList();
      if ((idDietaFiltro ?? "").isNotEmpty &&
          !dietaOptions.any((d) => d["id"] == idDietaFiltro)) {
        idDietaFiltro = null;
      }

      final fab = await widget.repo.fabricacaoTotaisDoDia(
        dataIso,
        trato: tratoFiltro,
        idDieta: idDietaFiltro,
      );
      final forn = await widget.repo.fornecimentoTotaisDoDia(
        dataIso,
        trato: tratoFiltro,
        idDieta: idDietaFiltro,
      );
      final analise = await widget.repo.fabricacaoVsFornecidoDoDia(
        dataIso,
        trato: tratoFiltro,
        idDieta: idDietaFiltro,
      );
      final fornDesvios =
          await widget.repo.fornecimentoDesviosPorCurralTrato(
        dataIso,
        trato: tratoFiltro,
        idDieta: idDietaFiltro,
      );
      final fabDesvioRacao = await widget.repo.fabricacaoDesvioPorRacao(
        dataIso,
        trato: tratoFiltro,
        idDieta: idDietaFiltro,
      );
      final fabDesvioInsumo =
          await widget.repo.fabricacaoDesvioPorInsumo(
        dataIso,
        trato: tratoFiltro,
        idDieta: idDietaFiltro,
      );

      if (!mounted) return;
      setState(() {
        _tratoOptions = tratoOptions;
        _dietaOptions = dietaOptions;
        _tratoFiltro = tratoFiltro;
        _idDietaFiltro = idDietaFiltro;
        _fabTotais = fab;
        _fornTotais = forn;
        _analise = analise;
        _fornDesvios = fornDesvios;
        _fabDesvioRacao = fabDesvioRacao;
        _fabDesvioInsumo = fabDesvioInsumo;
        _cacheCurrais.clear();
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<List<Map<String, Object?>>> _curraisFuture(String idFab) {
    return _cacheCurrais.putIfAbsent(
      idFab,
      () => widget.repo.curraisDaFabricacao(
        idFab,
        dataIso: _iso(_date),
        trato: _tratoFiltro,
        idDieta: _idDietaFiltro,
      ),
    );
  }

  double _n(dynamic v) => (v as num?)?.toDouble() ?? 0;

  String _fmtDuracaoMedia(double totalSeg) {
    if (totalSeg <= 0) return "--";
    final seg = totalSeg.round();
    final h = seg ~/ 3600;
    final m = (seg % 3600) ~/ 60;
    final s = seg % 60;

    String two(int v) => v.toString().padLeft(2, "0");
    if (h > 0) return "${two(h)}:${two(m)}:${two(s)}";
    return "${two(m)}:${two(s)}";
  }

  Widget _kpi(String title, String value, {Color? valueColor}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  color: valueColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chartCard({
    required String title,
    required List<Map<String, Object?>> rows,
    required String xKey,
  }) {
    if (rows.isEmpty) {
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Text("$title: sem dados para o dia."),
      );
    }

    final maxY = rows
        .map(
          (e) => ((_n(e["previsto"]) > _n(e["realizado"]))
              ? _n(e["previsto"])
              : _n(e["realizado"])),
        )
        .fold<double>(0, (a, b) => a > b ? a : b);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 220,
            child: BarChart(
              BarChartData(
                maxY: maxY <= 0 ? 10 : (maxY * 1.15),
                groupsSpace: 12,
                barGroups: List.generate(rows.length, (i) {
                  final prev = _n(rows[i]["previsto"]);
                  final real = _n(rows[i]["realizado"]);
                  return BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: prev,
                        width: 8,
                        color: _prevColor,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      BarChartRodData(
                        toY: real,
                        width: 8,
                        color: _realColor,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ],
                  );
                }),
                borderData: FlBorderData(show: false),
                gridData: const FlGridData(show: true),
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    fitInsideHorizontally: true,
                    fitInsideVertically: true,
                    tooltipRoundedRadius: 8,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final label = rodIndex == 0 ? "Prev" : "Real";
                      final cor = rodIndex == 0 ? _prevColor : _realColor;
                      return BarTooltipItem(
                        "$label ${rod.toY.toStringAsFixed(0)}",
                        TextStyle(
                          color: cor,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: true, reservedSize: 40),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 34,
                      getTitlesWidget: (value, meta) {
                        final i = value.toInt();
                        if (i < 0 || i >= rows.length) {
                          return const SizedBox.shrink();
                        }
                        final txt = (rows[i][xKey] ?? "").toString();
                        final short = txt.length > 7 ? "${txt.substring(0, 7)}..." : txt;
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            short,
                            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: const [
              _LegendDot(color: _prevColor, label: "Previsto"),
              SizedBox(width: 12),
              _LegendDot(color: _realColor, label: "Realizado"),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            "Toque na barra para ver o valor.",
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _diffChartCard({
    required String title,
    required List<Map<String, Object?>> rows,
    required String xKey,
  }) {
    if (rows.isEmpty) return const SizedBox.shrink();

    final diffs = rows.map((e) => _n(e["realizado"]) - _n(e["previsto"])).toList();
    final maxAbs = diffs
        .map((e) => e.abs())
        .fold<double>(0, (a, b) => a > b ? a : b);
    final lim = maxAbs <= 0 ? 10.0 : (maxAbs * 1.15);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 220,
            child: BarChart(
              BarChartData(
                minY: -lim,
                maxY: lim,
                baselineY: 0,
                groupsSpace: 12,
                barGroups: List.generate(rows.length, (i) {
                  final dif = _n(rows[i]["realizado"]) - _n(rows[i]["previsto"]);
                  return BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: dif,
                        width: 10,
                        color: dif >= 0 ? Colors.deepOrange : Colors.indigo,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ],
                  );
                }),
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    fitInsideHorizontally: true,
                    fitInsideVertically: true,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final val = rod.toY;
                      final txt =
                          val >= 0 ? "+${val.toStringAsFixed(0)}" : val.toStringAsFixed(0);
                      return BarTooltipItem(
                        "Desvio $txt",
                        const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      );
                    },
                  ),
                ),
                borderData: FlBorderData(show: false),
                gridData: const FlGridData(show: true),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: true, reservedSize: 42),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 34,
                      getTitlesWidget: (value, meta) {
                        final i = value.toInt();
                        if (i < 0 || i >= rows.length) {
                          return const SizedBox.shrink();
                        }
                        final txt = (rows[i][xKey] ?? "").toString();
                        final short = txt.length > 7 ? "${txt.substring(0, 7)}..." : txt;
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            short,
                            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            "Desvio = Realizado - Previsto (acima/abaixo de zero).",
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fabReal = _n(_fabTotais["realizado"]);
    final fornReal = _n(_fornTotais["realizado"]);
    final difGeral = fabReal - fornReal;
    final tempoMedioFabSeg = _n(_fabTotais["tempo_medio_seg"]);

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text("Dashboard Unificado"),
        actions: [
          IconButton(onPressed: _pickDate, icon: const Icon(Icons.event)),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Text(
                    "Data: ${_br(_date)}",
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<int?>(
                              initialValue: _tratoFiltro,
                              decoration: const InputDecoration(
                                labelText: "Trato",
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
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
                                setState(() => _tratoFiltro = v);
                                await _load();
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: DropdownButtonFormField<String?>(
                              initialValue: _idDietaFiltro,
                              decoration: const InputDecoration(
                                labelText: "Racao",
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                              items: [
                                const DropdownMenuItem<String?>(
                                  value: null,
                                  child: Text("Todas"),
                                ),
                                ..._dietaOptions.map(
                                  (d) => DropdownMenuItem<String?>(
                                    value: d["id"],
                                    child: Text(
                                      (d["nome"] ?? "").isEmpty ? (d["id"] ?? "") : (d["nome"] ?? ""),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ],
                              onChanged: (v) async {
                                setState(() => _idDietaFiltro = v);
                                await _load();
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () async {
                            setState(() {
                              _tratoFiltro = null;
                              _idDietaFiltro = null;
                            });
                            await _load();
                          },
                          icon: const Icon(Icons.clear),
                          label: const Text("Limpar filtros"),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _kpi("Fab Previsto", _n(_fabTotais["previsto"]).toStringAsFixed(0)),
                    const SizedBox(width: 8),
                    _kpi("Fab Realizado", fabReal.toStringAsFixed(0)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _kpi("Forn Previsto", _n(_fornTotais["previsto"]).toStringAsFixed(0)),
                    const SizedBox(width: 8),
                    _kpi("Forn Realizado", fornReal.toStringAsFixed(0)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _kpi("Fabricoes", (_fabTotais["qtd"] ?? 0).toString()),
                    const SizedBox(width: 8),
                    _kpi("Fornecimentos", (_fornTotais["qtd"] ?? 0).toString()),
                    const SizedBox(width: 8),
                    _kpi("Currais", (_fornTotais["currais"] ?? 0).toString()),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _kpi(
                      "Tempo medio/fabricacao",
                      _fmtDuracaoMedia(tempoMedioFabSeg),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _kpi(
                      "Diferenca Geral",
                      difGeral.toStringAsFixed(0),
                      valueColor: difGeral.abs() < 0.001
                          ? Colors.black
                          : (difGeral > 0 ? Colors.orange.shade900 : Colors.green.shade800),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _chartCard(
                  title: "Desvios de Fornecimento (Curral + Trato)",
                  rows: _fornDesvios.map((e) {
                    final curral = (e["curral"] ?? "").toString();
                    final trato = (e["trato"] ?? 0).toString();
                    return {
                      ...e,
                      "label": "$curral T$trato",
                    };
                  }).toList(),
                  xKey: "label",
                ),
                _diffChartCard(
                  title: "Desvio Puro - Fornecimento (Real - Prev)",
                  rows: _fornDesvios.map((e) {
                    final curral = (e["curral"] ?? "").toString();
                    final trato = (e["trato"] ?? 0).toString();
                    return {
                      ...e,
                      "label": "$curral T$trato",
                    };
                  }).toList(),
                  xKey: "label",
                ),
                _chartCard(
                  title: "Fabricacao: Diferenca por Racao",
                  rows: _fabDesvioRacao,
                  xKey: "racao",
                ),
                _diffChartCard(
                  title: "Desvio Puro - Fabricacao por Racao",
                  rows: _fabDesvioRacao,
                  xKey: "racao",
                ),
                _chartCard(
                  title: "Fabricacao: Diferenca por Insumo",
                  rows: _fabDesvioInsumo,
                  xKey: "insumo",
                ),
                _diffChartCard(
                  title: "Desvio Puro - Fabricacao por Insumo",
                  rows: _fabDesvioInsumo,
                  xKey: "insumo",
                ),
                const SizedBox(height: 6),
                const Text(
                  "Analise Fabricacao x Fornecido",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                if (_analise.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: const Text("Sem dados para os filtros selecionados."),
                  )
                else
                  ..._analise.map((row) {
                    final idFab = (row["id_fabricacao"] ?? "").toString();
                    final dieta = (row["dieta"] ?? "").toString().trim();
                    final trato = (row["trato"] ?? 0).toString();
                    final fabricado = _n(row["fabricado_kg"]);
                    final fornecido = _n(row["fornecido_kg"]);
                    final diferenca = _n(row["diferenca_kg"]);

                    final progress = fabricado <= 0 ? 0.0 : (fornecido / fabricado).clamp(0.0, 1.0);

                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: ExpansionTile(
                        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        title: Text(
                          dieta.isEmpty ? "(Sem dieta)" : dieta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        subtitle: Text(
                          "Trato $trato | Fab ${fabricado.toStringAsFixed(0)} kg | Forn ${fornecido.toStringAsFixed(0)} kg",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Text(
                          diferenca >= 0
                              ? "+${diferenca.toStringAsFixed(0)} kg"
                              : "${diferenca.toStringAsFixed(0)} kg",
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: diferenca.abs() < 0.001
                                ? Colors.black
                                : (diferenca > 0 ? Colors.orange.shade900 : Colors.green.shade800),
                          ),
                        ),
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: LinearProgressIndicator(value: progress, minHeight: 8),
                          ),
                          const SizedBox(height: 10),
                          FutureBuilder<List<Map<String, Object?>>>(
                            future: _curraisFuture(idFab),
                            builder: (_, snap) {
                              if (snap.connectionState == ConnectionState.waiting) {
                                return const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 10),
                                  child: Center(child: CircularProgressIndicator()),
                                );
                              }
                              final currais = snap.data ?? const <Map<String, Object?>>[];
                              if (currais.isEmpty) {
                                return const Text("Sem fornecimento vinculado a esta fabricacao.");
                              }

                              return Column(
                                children: currais.map((c) {
                                  final nome = (c["curral"] ?? "").toString();
                                  final tratoCurral = (c["trato"] ?? 0).toString();
                                  final kg = _n(c["fornecido_kg"]);
                                  return ListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    visualDensity: VisualDensity.compact,
                                    title: Text(
                                      nome.isEmpty ? "(Sem curral)" : nome,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontWeight: FontWeight.w800),
                                    ),
                                    subtitle: Text("Trato $tratoCurral"),
                                    trailing: Text(
                                      "${kg.toStringAsFixed(0)} kg",
                                      style: const TextStyle(fontWeight: FontWeight.w900),
                                    ),
                                  );
                                }).toList(),
                              );
                            },
                          ),
                        ],
                      ),
                    );
                  }),
              ],
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
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}
