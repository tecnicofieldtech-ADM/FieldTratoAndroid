// lib/features/fabricacao/ui/fabricacao_weigh_page.dart
import "dart:async";
import "package:flutter/material.dart";

import "../../../repo/config_repo.dart"; // ✅ novo (pra pegar tipoTrabalho e vagão)
import "../controller/fabricacao_controller.dart";
import "../data/fabricacao_repo.dart";
import "../domain/models.dart";
import "pre_pesado_dialog.dart";
import "ingredientes_modal.dart";
import "mistura_timer_page.dart";
import "fabricacao_list_page.dart";

class FabricacaoWeighPage extends StatefulWidget {
  const FabricacaoWeighPage({super.key, required this.repo});

  final FabricacaoRepo repo;

  @override
  State<FabricacaoWeighPage> createState() => _FabricacaoWeighPageState();
}

class _FabricacaoWeighPageState extends State<FabricacaoWeighPage> {
  late final FabricacaoController c;

  bool _booting = true;
  String? _bootError;

  Timer? _uiTicker;
  bool _reconnecting = false;

  String _prePesadoShownForDetId = "";
  bool _showingPrePesado = false;

  bool _finishing = false; // ✅ trava duplo clique no finalizar

  final _cfgRepo = ConfigRepo(); // ✅ config pra criar carregamento

  bool get _recebendoAgora {
    final dt = c.lastPacketAt;
    if (dt == null) return false;
    return DateTime.now().difference(dt).inSeconds <= 2;
  }

  // ✅ troca withOpacity (deprecated) por withValues(alpha: ...)
  Color _alpha(Color color, double opacity) {
    final o = opacity.clamp(0.0, 1.0);
    return color.withValues(alpha: o);
  }

  String _fmtTime(DateTime? dt) {
    if (dt == null) return "--:--:--";
    final h = dt.hour.toString().padLeft(2, "0");
    final m = dt.minute.toString().padLeft(2, "0");
    final s = dt.second.toString().padLeft(2, "0");
    return "$h:$m:$s";
  }

  Widget _wrapPop(Widget child) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) async {
        if (_reconnecting) return;
        await c.shutdown();
      },
      child: child,
    );
  }

  @override
  void initState() {
    super.initState();
    c = FabricacaoController(widget.repo)..addListener(_onChange);
    _boot();

    _uiTicker = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _uiTicker?.cancel();
    c.removeListener(_onChange);

    // ignore: unawaited_futures
    unawaited(c.shutdown());

    c.dispose();
    super.dispose();
  }

  void _onChange() {
    if (!mounted) return;
    setState(() {});
    _maybeShowPrePesado();
  }

  void _showParabensIfDentroTol({
    required int prev,
    required int real,
    required double tolPct,
  }) {
    if (!mounted) return;
    if (prev <= 0) return;

    final dif = (real - prev).abs().toDouble();
    final tolKg = prev.toDouble() * (tolPct / 100.0);

    final dentro = (tolPct <= 0) ? (dif == 0.0) : (dif <= tolKg);
    if (!dentro) return;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        content: Row(
          children: const [
            Icon(Icons.celebration, color: Colors.white),
            SizedBox(width: 10),
            Expanded(child: Text("Parabéns! Ingrediente no alvo ✅")),
          ],
        ),
      ),
    );
  }

  // =========================================================
  // BOOT
  // =========================================================
  Future<void> _boot() async {
    setState(() {
      _booting = true;
      _bootError = null;
    });

    try {
      final ok = await c.bootTruckSide();
      if (!ok) {
        setState(() {
          _bootError = "Nenhuma fabricação em aberto para hoje.";
          _booting = false;
        });
        return;
      }

      if (!mounted) return;
      setState(() => _booting = false);

      _maybeShowPrePesado();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _bootError = e.toString();
        _booting = false;
      });
    }
  }

  Future<void> _reconnectAll() async {
    if (_reconnecting) return;

    try {
      setState(() {
        _reconnecting = true;
        _bootError = null;
      });

      try {
        await c.startMirrorFromConfig();
      } catch (_) {}

      await c.reconnectScale();

      if (!mounted) return;
      setState(() => _reconnecting = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _reconnecting = false;
        _bootError = "Erro ao reconectar: $e";
      });
    }
  }

  // =========================================================
  // ✅ CARREGAMENTO ABERTO (STATUS=0) após finalizar
  // =========================================================
  Future<void> _ensureCarregamentoAbertoAposFinalizar() async {
    final h = c.header;
    if (h == null) return;

    // tipoTrabalho: 0 = já considera carregado junto, senão 0
    int tipoTrabalho = 0;
    try {
      tipoTrabalho = await _cfgRepo.getTipoTrabalho();
    } catch (_) {
      tipoTrabalho = 0;
    }

    // ✅ ID_VAGAO é STRING (UUID)
    String idVagao = "";

    // 1) tenta pelo CONFIG
    try {
      idVagao = ((await _cfgRepo.getIdVagao()) ?? "").toString().trim();
    } catch (_) {
      idVagao = "";
    }

    // 2) se não tiver, pega da FABRICAÇÃO (ID_VAGAO do header) usando o ID da fabricação (h.id)
    if (idVagao.isEmpty) {
      try {
        idVagao = (await widget.repo.getIdVagaoByFabricacaoId(h.id)).trim();
      } catch (_) {
        idVagao = "";
      }
    }

    if (idVagao.isEmpty) {
      throw Exception(
          "Vagão não configurado. Selecione um vagão nas configurações.");
    }

    final totalReal = (h.qtdRealizada is num)
        ? (h.qtdRealizada as num).toDouble()
        : (h.qtdRealizada?.toDouble() ?? 0.0);

    final pesoFabricado = totalReal;
    final pesoCarregado = (tipoTrabalho == 0) ? totalReal : 0.0;

    await widget.repo.ensureCarregamentoAberto(
      idFabricacao: h.id,
      idDieta: (h.idDieta ?? "").toString(),
      pesoFabricado: pesoFabricado,
      pesoCarregado: pesoCarregado,
      idVagao: idVagao, // ✅ string (UUID)
    );
  }

  // =========================================================
  // PRÉ-PESADO
  // =========================================================
  void _maybeShowPrePesado() {
    if (!mounted) return;
    if (_booting) return;
    if (_bootError != null) return;

    final ing = c.atual;
    if (ing == null) return;
    if (!ing.isPrePesado) return;

    if (_prePesadoShownForDetId == ing.idDet) return;
    if (_showingPrePesado) return;

    _prePesadoShownForDetId = ing.idDet;
    _showingPrePesado = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      await showPrePesadoDialog(
        context: context,
        nome: ing.insumoNome,
        previstoKg: ing.previstoKg,
        onConfirm: (realizado) async {
          c.setRealizadoLocalByDetId(ing.idDet, realizado);

          try {
            await c.confirmarIngredientePrePesado(realizado);
          } catch (_) {
            final isLast = c.idx == c.ingredientes.length - 1;
            if (!mounted) return;
            if (!isLast) await c.next();
          }
        },
      );

      _showingPrePesado = false;
    });
  }

  // =========================================================
  // Ingredientes modal
  // =========================================================
  void _openIngredientesModal() async {
    final h = c.header;
    if (h == null) return;

    final selectedIndex = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => IngredientesModal(
        repo: widget.repo,
        fabId: h.id,
      ),
    );

    if (!mounted) return;
    if (selectedIndex == null) return;

    await c.goToIndex(selectedIndex);
    _maybeShowPrePesado();
  }

  FabIngrediente? get _prox {
    final i = c.idx + 1;
    if (i < 0 || i >= c.ingredientes.length) return null;
    return c.ingredientes[i];
  }

  // =========================================================
  // Helpers de tolerância (%)
  // =========================================================
  double _tolKgDoIngrediente(int previstoKg, double toleranciaPct) {
    if (previstoKg <= 0) return 0.0;
    if (toleranciaPct <= 0) return 0.0;
    return previstoKg.toDouble() * (toleranciaPct / 100.0);
  }

  bool _dentroTolPct({
    required int previstoKg,
    required int realizadoKg,
    required double toleranciaPct,
  }) {
    if (previstoKg <= 0) return false;

    final dif = (realizadoKg - previstoKg).abs().toDouble();

    if (toleranciaPct <= 0) return dif == 0.0;

    final tolKg = _tolKgDoIngrediente(previstoKg, toleranciaPct);
    return dif <= tolKg;
  }

  // =========================
  // UI
  // =========================
  @override
  Widget build(BuildContext context) {
    if (_booting) {
      return const Scaffold(
        appBar: _TopAppBar(title: "Fabricação"),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_bootError != null) {
      return Scaffold(
        appBar: const _TopAppBar(title: "Fabricação"),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _bootError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: _boot,
                  child: const Text("Tentar novamente"),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text("Voltar"),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final header = c.header!;
    final ing = c.atual!;
    final nextIng = _prox;
    final isLast = c.idx == c.ingredientes.length - 1;

    final prev = ing.previstoKg;
    final real = ing.realizadoKg;

    final difAbs = (real - prev).abs();

    final tolPct = c.toleranciaPct;
    final tolKg = _tolKgDoIngrediente(prev, tolPct);

    final dentroTol = _dentroTolPct(
      previstoKg: prev,
      realizadoKg: real,
      toleranciaPct: tolPct,
    );

    final difColor = prev <= 0
        ? Colors.blueGrey
        : (dentroTol
            ? Colors.blueGrey
            : (real > prev ? Colors.red : Colors.green));

    return _wrapPop(
      Scaffold(
        appBar: _TopAppBar(
          title: "Fabricação",
          subtitle: "Trato ${header.trato} • ${header.dietaNome}",
          actions: [
            IconButton(
              tooltip: "Ingredientes",
              onPressed: _openIngredientesModal,
              icon: const Icon(Icons.list_alt),
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _cardBalancaTopCompact(previstoKg: prev, tolPct: tolPct),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: _cardIngredienteTop(ing: ing, nextIng: nextIng),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: _cardDiferencaPrincipalFill(
                  prev: prev,
                  real: real,
                  difAbs: difAbs,
                  difColor: difColor,
                  dentroTol: dentroTol,
                  tolPct: tolPct,
                  tolKg: tolKg,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: _bottomListaBar(),
            ),
            _bottomNav(isLast: isLast),
          ],
        ),
      ),
    );
  }

  // =========================
  // Card Balança (TOP compacto)
  // =========================
  Widget _cardBalancaTopCompact(
      {required int previstoKg, required double tolPct}) {
    final connected = c.scaleConnected;
    final connecting = c.scaleConnecting;
    final recebendo = _recebendoAgora;

    final mirrorOn = c.mirrorEnabled;
    final mirrorOk = c.mirrorConnected;

    Color color;
    IconData icon;
    String text;

    if (connecting) {
      color = Colors.blueGrey;
      icon = Icons.wifi_tethering;
      text = "Conectando…";
    } else if (!connected) {
      color = Colors.red;
      icon = Icons.portable_wifi_off;
      text = "Desconectada";
    } else if (!recebendo) {
      color = Colors.orange;
      icon = Icons.sync_problem;
      text = "Sem dados";
    } else {
      color = Colors.green;
      icon = Icons.check_circle;
      text = "OK";
    }

    final lastAtTxt = _fmtTime(c.lastPacketAt);
    final canReconnect = !_reconnecting && !connecting;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Text(
                      "${c.lastWeight.toStringAsFixed(0)} kg",
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: canReconnect ? _reconnectAll : null,
                  icon: _reconnecting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh, size: 18),
                  label: Text(_reconnecting ? "..." : "Reconectar"),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(icon, color: color, size: 18),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          "Balança: $text • $lastAtTxt",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: color,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Row(
                    children: [
                      Icon(
                        mirrorOn
                            ? (mirrorOk ? Icons.cast_connected : Icons.cast)
                            : Icons.cast_outlined,
                        size: 18,
                        color: mirrorOn
                            ? (mirrorOk ? Colors.green : Colors.orange)
                            : Colors.grey,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          c.mirrorLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: mirrorOn
                                ? (mirrorOk ? Colors.green : Colors.orange)
                                : Colors.grey,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _cardIngredienteTop({
    required FabIngrediente ing,
    required FabIngrediente? nextIng,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.inventory_2_outlined, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    ing.insumoNome.isEmpty ? "(Sem nome)" : ing.insumoNome,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 22,
                      height: 1.05,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (ing.isPrePesado) ...[
                  const SizedBox(width: 8),
                  _chip(icon: Icons.verified, label: "Pré-pesado"),
                ],
              ],
            ),
            if (nextIng != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.grey.shade100,
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.next_plan, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        "Próximo: ${nextIng.insumoNome}",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      "${nextIng.previstoKg} kg",
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    if (nextIng.isPrePesado) ...[
                      const SizedBox(width: 10),
                      const Icon(Icons.verified, size: 18),
                    ]
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _cardDiferencaPrincipalFill({
    required int prev,
    required int real,
    required int difAbs,
    required Color difColor,
    required bool dentroTol,
    required double tolPct,
    required double tolKg,
  }) {
    String status;
    if (prev <= 0) {
      status = "Sem previsto";
    } else if (dentroTol) {
      status = tolPct > 0 ? "No alvo ✅" : "No alvo ✅ (exato)";
    } else if (real < prev) {
      status = "Faltando $difAbs kg";
    } else {
      status = "Passou $difAbs kg";
    }

    final percent = (prev > 0) ? (real * 100 / prev) : 0.0;
    final pctLabel = prev > 0 ? "${percent.toStringAsFixed(0)}%" : "--";
    final barValue = prev > 0 ? (real / prev).clamp(0.0, 1.0) : 0.0;

    final faltando = prev > 0 ? (prev - real) : 0;
    final faltandoShow = faltando < 0 ? 0 : faltando;
    final difText = "$faltandoShow";

    Color bg;
    if (prev <= 0) {
      bg = Colors.blueGrey.shade700;
    } else if (dentroTol) {
      bg = Colors.green.shade700;
    } else if (real > prev) {
      bg = Colors.deepOrange.shade700;
    } else {
      bg = Colors.black;
    }

    return Container(
      width: double.infinity,
      height: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        color: bg,
        boxShadow: [
          BoxShadow(
            blurRadius: 22,
            spreadRadius: 0,
            offset: const Offset(0, 12),
            color: Colors.black.withValues(alpha: 0.22),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.scale, color: Colors.white, size: 28),
              const SizedBox(width: 10),
              const Text(
                "A FABRICAR (kg)",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 26,
                ),
              ),
              const Spacer(),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 132),
                child: _PulseChip(
                  icon: Icons.timer,
                  active: c.autoCountdown > 0,
                  label: c.autoCountdown > 0
                      ? "Pulo: ${c.autoCountdown}s"
                      : "Pulo: pronto",
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  difText,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 200,
                    height: 0.90,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Stack(
            alignment: Alignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  minHeight: 18,
                  value: barValue,
                ),
              ),
              Text(
                pctLabel,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _midKvCenteredCompact("Previsto", "$prev kg")),
              const SizedBox(width: 10),
              Expanded(child: _midKvCenteredCompact("Realizado", "$real kg")),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: Colors.white.withValues(alpha: 0.16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
            ),
            child: Row(
              children: [
                Icon(
                  dentroTol
                      ? Icons.verified
                      : (prev <= 0
                          ? Icons.help_outline
                          : (real < prev
                              ? Icons.warning_amber
                              : Icons.error_outline)),
                  size: 18,
                  color: Colors.white,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    status,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                      color: Colors.white,
                    ),
                  ),
                ),
                if (prev > 0 && tolPct > 0)
                  Text(
                    "±${tolPct.toStringAsFixed(1)}% (±${tolKg.toStringAsFixed(0)}kg)",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomListaBar() {
    final total = c.ingredientes.length;
    final pos = (c.idx + 1).clamp(1, total);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                "Progresso $pos/$total",
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            TextButton.icon(
              onPressed: _openIngredientesModal,
              icon: const Icon(Icons.list_alt, size: 18),
              label: const Text("Ver lista"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _midKvCenteredCompact(String k, String v) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade300),
        color: _alpha(Colors.white, 0.70),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            k,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w800,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              v,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22,
                height: 1.0,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomNav({required bool isLast}) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey.shade200)),
        ),
        child: Row(
          children: [
            IconButton(
              onPressed: c.idx == 0 ? null : () => c.prev(),
              icon: const Icon(Icons.arrow_back),
              tooltip: "Anterior",
            ),
            const SizedBox(width: 6),
            Expanded(
              child: FilledButton.icon(
                onPressed: _finishing
                    ? null
                    : () async {
                        if (!isLast) {
                          final ingAntes = c.atual;

                          final prevAntes = ingAntes?.previstoKg ?? 0;
                          final realAntes = ingAntes?.realizadoKg ?? 0;
                          final tolPct = c.toleranciaPct;

                          await c.next();

                          if (!mounted) return;

                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            _showParabensIfDentroTol(
                              prev: prevAntes,
                              real: realAntes,
                              tolPct: tolPct,
                            );
                          });

                          return;
                        }

                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text("Finalizar fabricação"),
                            content:
                                const Text("Deseja finalizar a fabricação?"),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(false),
                                child: const Text("Não"),
                              ),
                              FilledButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(true),
                                child: const Text("Sim"),
                              ),
                            ],
                          ),
                        );

                        if (ok != true) return;

                        setState(() => _finishing = true);
                        try {
                          final minutos =
                              await c.finalizarFabricacaoAntesDoTimer();
                          if (!mounted) return;

                          // ✅ cria/garante carregamento aberto (STATUS=0)
                          try {
                            await _ensureCarregamentoAbertoAposFinalizar();
                          } catch (e) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                behavior: SnackBarBehavior.floating,
                                content: Text("Erro ao criar carregamento: $e"),
                              ),
                            );
                          }

                          if (!mounted) return;

                          if (minutos <= 0) {
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute(
                                builder: (_) =>
                                    FabricacaoListPage(repo: widget.repo),
                              ),
                            );
                            return;
                          }

                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(
                              builder: (_) => MisturaTimerPage(
                                minutos: minutos,
                                repo: widget.repo,
                                fabricacaoId: c.header?.id,
                                titulo: "Mistura",
                                onDonePopToRoot: true,
                              ),
                            ),
                          );
                        } finally {
                          if (mounted) setState(() => _finishing = false);
                        }
                      },
                icon: Icon(isLast ? Icons.check : Icons.arrow_forward),
                label: Text(isLast ? "Finalizar" : "Próximo"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PulseChip extends StatefulWidget {
  const _PulseChip({
    required this.icon,
    required this.label,
    required this.active,
  });

  final IconData icon;
  final String label;
  final bool active;

  @override
  State<_PulseChip> createState() => _PulseChipState();
}

class _PulseChipState extends State<_PulseChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ac = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  )..repeat(reverse: true);

  Color _alpha(Color color, double opacity) {
    final o = opacity.clamp(0.0, 1.0);
    return color.withValues(alpha: o);
  }

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) {
      return _chipBase(
        icon: widget.icon,
        label: widget.label,
        color: Colors.grey.shade100,
        border: Colors.grey.shade300,
        iconColor: Colors.black87,
        textColor: Colors.black87,
      );
    }

    return AnimatedBuilder(
      animation: _ac,
      builder: (_, __) {
        final t = _ac.value;
        final scale = 1.0 + (t * 0.06);
        final glow = 0.10 + (t * 0.20);

        return Transform.scale(
          scale: scale,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              boxShadow: [
                BoxShadow(
                  color: _alpha(Colors.orange, glow),
                  blurRadius: 18,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: _chipBase(
              icon: widget.icon,
              label: widget.label,
              color: _alpha(Colors.orange, 0.15),
              border: _alpha(Colors.orange, 0.45),
              iconColor: Colors.deepOrange,
              textColor: Colors.deepOrange,
            ),
          ),
        );
      },
    );
  }

  Widget _chipBase({
    required IconData icon,
    required String label,
    required Color color,
    required Color border,
    required Color iconColor,
    required Color textColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _TopAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _TopAppBar({required this.title, this.subtitle, this.actions});

  final String title;
  final String? subtitle;
  final List<Widget>? actions;

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      titleSpacing: 12,
      actions: actions,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title),
          if (subtitle != null)
            Text(
              subtitle!,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
            ),
        ],
      ),
    );
  }
}
