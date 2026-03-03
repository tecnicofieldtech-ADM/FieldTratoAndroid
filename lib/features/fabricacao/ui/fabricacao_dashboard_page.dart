import "dart:math";
import "package:fl_chart/fl_chart.dart";
import "package:flutter/material.dart";

import "../data/fabricacao_dashboard_repo.dart";
import "../data/fabricacao_repo.dart";
import "../domain/fabricacao_flow.dart";
import "ingredientes_modal.dart";
import "../../../repo/config_repo.dart";

class FabricacaoDashboardPage extends StatefulWidget {
  const FabricacaoDashboardPage({super.key, required this.repo});
  final FabricacaoRepo repo;

  @override
  State<FabricacaoDashboardPage> createState() =>
      _FabricacaoDashboardPageState();
}

class _FabricacaoDashboardPageState extends State<FabricacaoDashboardPage> {
  final _dash = FabricacaoDashboardRepo();
  final _cfgRepo = ConfigRepo();

  bool _loading = true;
  DateTime _date = DateTime.now();

  Map<String, num> _totals = const {"previsto": 0, "realizado": 0, "qtd": 0};
  int _pendentes = 0;
  int _irreg = 0;

  List<Map<String, Object?>> _porRacao = const [];
  List<Map<String, Object?>> _porTrato = const [];
  List<Map<String, Object?>> _topInsumos = const [];
  List<Map<String, Object?>> _irregList = const [];
  List<Map<String, Object?>> _pendList = const [];

  // RANKING + META
  double _metaAcertoPct = 0.0; // ? vem da config (TOLERANCIA_CARREGAMENTO)
  List<Map<String, Object?>> _ranking = const [];
  List<Map<String, Object?>> _racoes = const [];
  String? _idDietaFiltro;

  String _iso(DateTime d) =>
      "${d.year.toString().padLeft(4, "0")}-${d.month.toString().padLeft(2, "0")}-${d.day.toString().padLeft(2, "0")}";

  String _br(DateTime d) =>
      "${d.day.toString().padLeft(2, "0")}/${d.month.toString().padLeft(2, "0")}/${(d.year % 100).toString().padLeft(2, "0")}";

  @override
  void initState() {
    super.initState();
    _load();
  }

  // double seguro para % (aceita virgula e ponto)
  double _asDouble(dynamic v, double def) {
    final s = (v ?? "").toString().trim();
    if (s.isEmpty) return def;
    return double.tryParse(s.replaceAll(",", ".")) ?? def;
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 2, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (!mounted || picked == null) return;
    setState(() => _date = DateTime(picked.year, picked.month, picked.day));
    await _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final dataIso = _iso(_date);
    final idDieta =
        (_idDietaFiltro ?? "").trim().isEmpty ? null : _idDietaFiltro;

    try {
      // ? carrega META da configuracao (TOLERANCIA_CARREGAMENTO)
      final cfg = await _cfgRepo.getConfig();
      final meta = _asDouble(cfg?["TOLERANCIA_CARREGAMENTO"], 0.0);
      final flowMode = await _cfgRepo.getFabricacaoFlowMode();
      final tipoTrabalho = await _cfgRepo.getTipoTrabalho();

      final racoes = await _dash.racoesDoDia(dataIso);
      final totals = await _dash.totalsDoDia(dataIso, idDieta: idDieta);
      int pend = await _dash.pendentesSyncDoDia(dataIso, idDieta: idDieta);
      final irreg = await _dash.irregularesCount(dataIso, idDieta: idDieta);

      final porRacao = await _dash.porRacao(dataIso, idDieta: idDieta);
      final porTrato = await _dash.porTrato(dataIso, idDieta: idDieta);
      final topInsumos =
          await _dash.topInsumosDif(dataIso, limit: 10, idDieta: idDieta);

      final irregList =
          await _dash.irregularesList(dataIso, limit: 30, idDieta: idDieta);
      List<Map<String, Object?>> pendList =
          await _dash.pendentesSyncList(dataIso, limit: 30, idDieta: idDieta);

      if (flowMode == FabricacaoFlowMode.startStationFinishTruck &&
          tipoTrabalho == 1) {
        pend = 0;
        pendList = const [];
      }

      // ? ranking
      final ranking =
          await _dash.topAcertosDoDia(dataIso, limit: 10, idDieta: idDieta);

      if (!mounted) return;
      setState(() {
        _racoes = racoes;
        if (_idDietaFiltro != null && _idDietaFiltro!.trim().isNotEmpty) {
          final exists = _racoes.any(
            (e) =>
                (e["idDieta"] ?? "").toString().trim() ==
                _idDietaFiltro!.trim(),
          );
          if (!exists) _idDietaFiltro = null;
        }

        _metaAcertoPct = meta;
        _totals = totals;
        _pendentes = pend;
        _irreg = irreg;
        _porRacao = porRacao;
        _porTrato = porTrato;
        _topInsumos = topInsumos;
        _irregList = irregList;
        _pendList = pendList;
        _ranking = ranking;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  double get _prev => (_totals["previsto"] ?? 0).toDouble();
  double get _real => (_totals["realizado"] ?? 0).toDouble();
  int get _qtd => (_totals["qtd"] ?? 0).toInt();

  // CARD blindado (nao estoura)
  Widget _card({
    required String title,
    required String value,
    String? subtitle,
    IconData? icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          if (icon != null)
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon),
            ),
          if (icon != null) const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String s, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              s,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  // =========================================================
  // Frases de incentivo
  // =========================================================
  String _incentivo(double acerto, double meta) {
    if (acerto >= meta) {
      const wins = [
        "Parabens! Voce ta em outro patamar.",
        "Meta batida! Hoje o vagao ta ON.",
        "Precisao cirurgica! Da ate gosto.",
        "Ta voando baixo!",
        "Isso ai e nivel PRO.",
      ];
      return wins[Random().nextInt(wins.length)];
    }

    if (acerto >= meta - 2) {
      const near = [
        "Quase la! So ajustar a pontinha.",
        "Ta no cheiro da meta! Bora fechar.",
        "Faltou so um tiquinho!",
        "Ta muito bom... da pra cravar!",
      ];
      return near[Random().nextInt(near.length)];
    }

    if (acerto >= meta - 6) {
      const mid = [
        "Bom! Mas da pra caprichar mais.",
        "Ta legal... bora afinar esse trato.",
        "Hoje ta quase perfeito.",
        "Vamos buscar o modo sniper.",
      ];
      return mid[Random().nextInt(mid.length)];
    }

    const low = [
      "Sem crise! Amanha a gente amassa.",
      "Hoje foi treino... amanha e campeonato.",
      "Respira... recalcula... e bora!",
      "Ainda da tempo de virar o jogo.",
    ];
    return low[Random().nextInt(low.length)];
  }

  Widget _metaBanner(double realizPct) {
    // Se meta for 0 (nao configurado), evita comparar e mostra aviso neutro
    final meta = _metaAcertoPct;
    final metaOk = meta > 0;

    final ok = metaOk ? (realizPct >= meta) : true;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: metaOk
            ? (ok
                ? Colors.green.withValues(alpha: 0.10)
                : Colors.orange.withValues(alpha: 0.10))
            : Colors.blueGrey.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: metaOk
              ? (ok
                  ? Colors.green.withValues(alpha: 0.25)
                  : Colors.orange.withValues(alpha: 0.25))
              : Colors.blueGrey.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          Icon(
            metaOk
                ? (ok ? Icons.celebration : Icons.tips_and_updates)
                : Icons.info_outline,
            color: metaOk
                ? (ok ? Colors.green.shade800 : Colors.orange.shade800)
                : Colors.blueGrey.shade800,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              metaOk
                  ? (ok
                      ? "Meta do dia batida! ${_incentivo(realizPct, meta)}"
                      : "Ainda da pra bater a meta. ${_incentivo(realizPct, meta)}")
                  : "Meta nao configurada. Defina em Configuracao > Fabricacao (Tolerancia %).",
              style: const TextStyle(fontWeight: FontWeight.w900),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  String _medal(int pos) {
    if (pos == 0) return "1o";
    if (pos == 1) return "2o";
    if (pos == 2) return "3o";
    return "Top";
  }

  Widget _rankingCard() {
    if (_ranking.isEmpty) {
      return Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: const Text("Sem dados de ranking no dia."),
      );
    }

    final top1 = _ranking.first;
    final topPct = ((top1["acerto_pct"] as num?) ?? 0).toDouble();

    final metaTxt =
        _metaAcertoPct > 0 ? "${_metaAcertoPct.toStringAsFixed(1)}%" : "-";

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.emoji_events),
            title: const Text(
              "Ranking de Acerto (Top 10)",
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            subtitle: Text(
              "Meta: $metaTxt - ${_incentivo(topPct, _metaAcertoPct)}",
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Divider(height: 1),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _ranking.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final r = _ranking[i];

              final id = (r["id"] ?? "").toString();
              final dieta = (r["dieta"] ?? "").toString().trim();
              final trato = (r["trato"] ?? 0).toString();

              final prev = ((r["previsto"] as num?) ?? 0).toDouble();
              final real = ((r["realizado"] as num?) ?? 0).toDouble();
              final pct = ((r["acerto_pct"] as num?) ?? 0).toDouble();

              final dentro =
                  _metaAcertoPct <= 0 ? true : (pct >= _metaAcertoPct);

              final tile = ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                minVerticalPadding: 6,
                leading: Text(_medal(i), style: const TextStyle(fontSize: 18)),
                title: Text(
                  dieta.isEmpty ? "(Sem nome de racao)" : dieta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  "Trato $trato - Prev ${prev.toStringAsFixed(0)} - Real ${real.toStringAsFixed(0)}",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: SizedBox(
                  width: 92,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        "${pct.toStringAsFixed(1)}%",
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: dentro ? Colors.green.shade800 : null,
                        ),
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: (pct / 100.0).clamp(0, 1),
                          minHeight: 6,
                        ),
                      ),
                    ],
                  ),
                ),
                onTap: () => _openInsumos(id),
              );

              if (!dentro) return tile;

              // animacao pulse ao renderizar
              return TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.98, end: 1.0),
                duration: const Duration(milliseconds: 450),
                curve: Curves.easeOutBack,
                builder: (_, s, child) =>
                    Transform.scale(scale: s, child: child),
                child: tile,
              );
            },
          ),
        ],
      ),
    );
  }

  // =========================================================
  // CHARTS / LISTAS EXISTENTES
  // =========================================================
  Widget _barCompareChart(List<Map<String, Object?>> rows,
      {required String xKey}) {
    if (rows.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(14),
        child: Text("Sem dados para o periodo."),
      );
    }

    final maxY = rows
        .map((e) => max(
              (e["previsto"] as num?)?.toDouble() ?? 0,
              (e["realizado"] as num?)?.toDouble() ?? 0,
            ))
        .fold<double>(0, (a, b) => max(a, b));

    final groups = <BarChartGroupData>[];
    for (var i = 0; i < rows.length; i++) {
      final prev = ((rows[i]["previsto"] as num?) ?? 0).toDouble();
      final real = ((rows[i]["realizado"] as num?) ?? 0).toDouble();

      groups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(toY: prev, width: 7),
            BarChartRodData(toY: real, width: 7),
          ],
        ),
      );
    }

    String label(int i) {
      final v = rows[i][xKey];
      return (v ?? "").toString();
    }

    return SizedBox(
      height: 220,
      child: BarChart(
        BarChartData(
          maxY: maxY <= 0 ? 10 : (maxY * 1.15),
          barGroups: groups,
          groupsSpace: 14,
          gridData: const FlGridData(show: true),
          borderData: FlBorderData(show: false),
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
                  if (i < 0 || i >= rows.length) return const SizedBox.shrink();
                  final txt = label(i);
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      txt.length > 7 ? "${txt.substring(0, 7)}..." : txt,
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _barDiffChart(List<Map<String, Object?>> rows,
      {required String xKey}) {
    if (rows.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(14),
        child: Text("Sem dados para o perï¿½odo."),
      );
    }

    final diffs = rows
        .map((e) =>
            ((e["realizado"] as num?) ?? 0).toDouble() -
            ((e["previsto"] as num?) ?? 0).toDouble())
        .toList();
    final maxAbs = diffs.map((v) => v.abs()).fold<double>(0, max);
    final lim = maxAbs <= 0 ? 10.0 : maxAbs * 1.2;

    String label(int i) {
      final v = rows[i][xKey];
      return (v ?? "").toString();
    }

    return SizedBox(
      height: 220,
      child: BarChart(
        BarChartData(
          minY: -lim,
          maxY: lim,
          baselineY: 0,
          groupsSpace: 14,
          barGroups: List.generate(rows.length, (i) {
            final dif = diffs[i];
            return BarChartGroupData(
              x: i,
              showingTooltipIndicators: const [0],
              barRods: [
                BarChartRodData(
                  toY: dif,
                  width: 9,
                  color: dif >= 0 ? Colors.deepOrange : Colors.indigo,
                  borderRadius: BorderRadius.circular(3),
                ),
              ],
            );
          }),
          gridData: const FlGridData(show: true),
          borderData: FlBorderData(show: false),
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: BarTouchTooltipData(
              fitInsideHorizontally: true,
              fitInsideVertically: true,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final val = rod.toY;
                final txt = val >= 0
                    ? "+${val.toStringAsFixed(0)}"
                    : val.toStringAsFixed(0);
                return BarTooltipItem(
                  "Dif $txt",
                  const TextStyle(
                    color: Colors.white,
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
              sideTitles: SideTitles(showTitles: true, reservedSize: 42),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 34,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= rows.length) return const SizedBox.shrink();
                  final txt = label(i);
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      txt.length > 7 ? "${txt.substring(0, 7)}..." : txt,
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _topInsumosList() {
    if (_topInsumos.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(14),
        child: Text("Sem dados de insumos."),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _topInsumos.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final e = _topInsumos[i];

        final ins = (e["insumo"] ?? "").toString();
        final prev = ((e["previsto"] as num?) ?? 0).toDouble();
        final real = ((e["realizado"] as num?) ?? 0).toDouble();
        final dif = ((e["dif"] as num?) ?? 0).toDouble();

        return ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          minVerticalPadding: 6,
          title: Text(ins, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            "Prev ${prev.toStringAsFixed(0)} - Real ${real.toStringAsFixed(0)}",
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              dif >= 0 ? "+${dif.toStringAsFixed(0)}" : dif.toStringAsFixed(0),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        );
      },
    );
  }

  Widget _miniList(
    List<Map<String, Object?>> rows, {
    required String title,
    required IconData icon,
    required void Function(Map<String, Object?> row) onTap,
    String emptyText = "Sem itens.",
  }) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Icon(icon),
            title: Text(title,
                style: const TextStyle(fontWeight: FontWeight.w900)),
          ),
          const Divider(height: 1),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.all(14),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(emptyText),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: rows.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, idx) {
                final r = rows[idx];
                final dieta = (r["dieta"] ?? "").toString();
                final trato = (r["trato"] ?? 0).toString();
                final prev = ((r["previsto"] as num?) ?? 0).toDouble();
                final real = ((r["realizado"] as num?) ?? 0).toDouble();

                return ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  minVerticalPadding: 6,
                  title:
                      Text(dieta, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    "Trato $trato - Prev ${prev.toStringAsFixed(0)} - Real ${real.toStringAsFixed(0)}",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => onTap(r),
                );
              },
            ),
        ],
      ),
    );
  }

  Future<void> _openInsumos(String fabId) async {
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => IngredientesModal(
        repo: widget.repo,
        fabId: fabId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dif = _real - _prev;
    final pct = _prev <= 0 ? 0.0 : (_real / _prev) * 100.0;
    final difPct = _prev <= 0 ? 0.0 : (dif / _prev) * 100.0;

    final w = MediaQuery.of(context).size.width;
    final isWide = w > 520;
    final isNarrow = w < 380;

    final cardHeight = isWide ? 104.0 : (isNarrow ? 112.0 : 108.0);

    final cards = <Widget>[
      _card(
        title: "Previsto (kg)",
        value: _prev.toStringAsFixed(0),
        icon: Icons.flag,
      ),
      _card(
        title: "Realizado (kg)",
        value: _real.toStringAsFixed(0),
        icon: Icons.check_circle,
      ),
      _card(
        title: "Diferenca (kg)",
        value: dif >= 0 ? "+${dif.toStringAsFixed(0)}" : dif.toStringAsFixed(0),
        subtitle: isNarrow
            ? null
            : (_prev <= 0
                ? null
                : "Dif % ${difPct >= 0 ? "+" : ""}${difPct.toStringAsFixed(1)}"),
        icon: Icons.swap_vert,
      ),
      _card(
        title: "Fabricacoes",
        value: _qtd.toString(),
        icon: Icons.receipt_long,
      ),
      _card(
        title: "Pend. Sync",
        value: _pendentes.toString(),
        icon: Icons.cloud_upload,
      ),
      _card(
        title: "Irregulares",
        value: _irreg.toString(),
        icon: Icons.warning_amber,
      ),
    ];

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text("Dashboard - Fabricacao"),
        actions: [
          IconButton(onPressed: _pickDate, icon: const Icon(Icons.event)),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Text(
                          "Dia: ${_br(_date)}",
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        "Realizacao: ${pct.toStringAsFixed(1)}%",
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                  child: DropdownButtonFormField<String?>(
                    initialValue: _idDietaFiltro,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: "Racao",
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text("Todas"),
                      ),
                      ..._racoes.map((e) {
                        final id = (e["idDieta"] ?? "").toString().trim();
                        final nome = (e["dieta"] ?? "").toString().trim();
                        return DropdownMenuItem<String?>(
                          value: id,
                          child: Text(
                            nome.isEmpty ? id : nome,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }),
                    ],
                    onChanged: (v) {
                      setState(() => _idDietaFiltro = v);
                      _load();
                    },
                  ),
                ),

                // ? banner com incentivo (agora com meta da config)
                _metaBanner(pct),

                // ? GRID BLINDADO
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: GridView.builder(
                    itemCount: cards.length,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: isWide ? 3 : 2,
                      mainAxisExtent: cardHeight,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                    ),
                    itemBuilder: (_, i) => cards[i],
                  ),
                ),

                // ? RANKING TOP ACERTOS
                _rankingCard(),

                _sectionTitle("Por Racao (Prev x Real)"),
                Container(
                  margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: _barCompareChart(_porRacao, xKey: "dieta"),
                ),
                _sectionTitle("Por Racao (Diferenca: Real - Prev)"),
                Container(
                  margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: _barDiffChart(_porRacao, xKey: "dieta"),
                ),

                _sectionTitle("Por Trato (Prev x Real)"),
                Container(
                  margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: _barCompareChart(_porTrato, xKey: "trato"),
                ),
                _sectionTitle("Por Trato (Diferenca: Real - Prev)"),
                Container(
                  margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: _barDiffChart(_porTrato, xKey: "trato"),
                ),

                _sectionTitle("Top Insumos (maior diferenca)"),
                Container(
                  margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: _topInsumosList(),
                ),

                _miniList(
                  _irregList,
                  title: "Irregulares (finalizadas com insumo zerado)",
                  icon: Icons.warning_amber,
                  onTap: (row) => _openInsumos((row["id"] ?? "").toString()),
                ),

                _miniList(
                  _pendList,
                  title: "Pendentes de sincronizacao",
                  icon: Icons.cloud_upload,
                  onTap: (row) => _openInsumos((row["id"] ?? "").toString()),
                ),

                const SizedBox(height: 18),
              ],
            ),
    );
  }
}
