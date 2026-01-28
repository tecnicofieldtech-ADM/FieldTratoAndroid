// lib/features/espelho/ui/pa_dashboard_page.dart
import "dart:async";

import "package:flutter/material.dart";
import "../controller/pa_server_controller.dart";
import "../data/mirror_targets_repo.dart";
import "targets_list_page.dart";

class PaDashboardPage extends StatefulWidget {
  const PaDashboardPage({super.key, required this.repo, required this.server});
  final MirrorTargetsRepo repo;
  final PaServerController server;

  @override
  State<PaDashboardPage> createState() => _PaDashboardPageState();
}

class _PaDashboardPageState extends State<PaDashboardPage> {
  Timer? _ticker;

  // ✅ para calcular progresso do pulo (total = valor inicial do countdown)
  int _jumpTotal = 0;
  int _lastCountdown = 0;

  @override
  void initState() {
    super.initState();
    widget.server.addListener(_on);

    // inicia server
    // ignore: unawaited_futures
    widget.server.start();

    // ✅ ticker só pra “há X segundos” (não precisa 250ms)
    _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    widget.server.removeListener(_on);
    super.dispose();
  }

  void _on() {
    if (!mounted) return;

    // ✅ captura total do pulo quando ele começa
    final enabled = widget.server.autoEnabled;
    final cd = widget.server.autoCountdown;

    if (!enabled || cd <= 0) {
      _jumpTotal = 0;
      _lastCountdown = 0;
    } else {
      // quando começa: total = countdown inicial
      if (_jumpTotal <= 0 || cd > _jumpTotal) _jumpTotal = cd;

      // se reiniciou pulo (cd aumentou), ajusta total
      if (_lastCountdown > 0 && cd > _lastCountdown) _jumpTotal = cd;

      _lastCountdown = cd;
    }

    setState(() {});
  }

  Future<void> _openTargets() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TargetsListPage(repo: widget.repo, server: widget.server),
      ),
    );
    await widget.server.loadActive();
  }

  Future<void> _resetEspelho() async {
    await widget.server.stop();
    await widget.server.start();
  }

  Future<void> _restartServerOnly() async {
    await widget.server.stop();
    await widget.server.start();
  }

  String _statusLabel({required int prev, required int real}) {
    if (prev <= 0) return "Sem previsto";
    if (real < prev) return "Faltando";
    if (real > prev) return "Passou";
    return "No alvo ✅";
  }

  String _fmtTime(DateTime? dt) {
    if (dt == null) return "--:--:--";
    final h = dt.hour.toString().padLeft(2, "0");
    final m = dt.minute.toString().padLeft(2, "0");
    final s = dt.second.toString().padLeft(2, "0");
    return "$h:$m:$s";
  }

  bool _isTrue(dynamic v) => v == true || v == 1 || v == "1";

  /// ✅ compat: "pre" (novo) OU "prePesado" (antigo)
  bool _isPre(Map<String, dynamic>? atual) {
    if (atual == null) return false;
    if (atual.containsKey("pre")) return _isTrue(atual["pre"]);
    if (atual.containsKey("prePesado")) return _isTrue(atual["prePesado"]);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final st = widget.server.lastState;

    final active = widget.server.activeTarget;
    final activeLabel = active == null
        ? "Nenhum caminhão selecionado"
        : "${active.nome} • ${active.host}";

    // dados do payload
    final atual = (st != null && st["atual"] is Map)
        ? Map<String, dynamic>.from(st["atual"] as Map)
        : null;

    final prox = (st != null && st["prox"] is Map)
        ? Map<String, dynamic>.from(st["prox"] as Map)
        : null;

    final nomeAtual = (atual?["nome"] ?? "").toString();

    final prev = (atual?["prev"] as num?)?.toInt() ?? 0;
    final real = (atual?["real"] as num?)?.toInt() ?? 0;

    final difAbs = (real - prev).abs();

    final difColor = (prev <= 0)
        ? Colors.blueGrey
        : (real == prev
            ? Colors.blueGrey
            : (real > prev ? Colors.red : Colors.green));

    final percent = (prev > 0) ? (real * 100 / prev) : 0.0;
    final pctLabel = prev > 0 ? "${percent.toStringAsFixed(0)}%" : "--";
    final barValue = prev > 0 ? (real / prev).clamp(0.0, 1.0) : 0.0;

    final showPlus = prev > 0 && real > prev;
    final difText = showPlus ? "+$difAbs" : "$difAbs";

    // topo status server
    final topStatus = widget.server.listening
        ? "Escutando ${widget.server.listenBind}:${widget.server.port} • Clients ${widget.server.clientsCount}"
        : widget.server.status;

    final status = _statusLabel(prev: prev, real: real);

    // stale / last msg
    final lastAt = widget.server.lastMsgAt;
    final ageSec = lastAt == null
        ? null
        : DateTime.now().difference(lastAt).inMilliseconds / 1000.0;

    final stale = ageSec != null && ageSec > 2.5;
    final ageLabel = ageSec == null ? "--" : "${ageSec.toStringAsFixed(1)}s";

    final badgeColor = lastAt == null
        ? Colors.grey
        : (stale ? Colors.orange : Colors.green);

    final badgeText = lastAt == null
        ? "Sem dados"
        : (stale ? "Sem atualização ($ageLabel)" : "Atualizando ($ageLabel)");

    // header infos
    final dieta = (st?["dieta"] ?? "").toString();
    final trato = (st?["trato"] as num?)?.toInt();
    final fabId = (st?["fabId"] ?? "").toString();
    final finalizadaRaw = st?["finalizada"];
    final finalizada = _isTrue(finalizadaRaw);

    final isPreNow = _isPre(atual);

    // ✅ PULO (AGORA VINDO DO CONTROLLER)
    final jumpRunning = widget.server.autoEnabled && widget.server.autoCountdown > 0;
    final jumpCountdown = widget.server.autoCountdown;
    final jumpTotal = _jumpTotal;

    final progress = (jumpTotal > 0)
        ? ((jumpTotal - jumpCountdown) / jumpTotal).clamp(0.0, 1.0)
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Pá • Espelhamento"),
        actions: [
          IconButton(
            tooltip: "Caminhões",
            onPressed: _openTargets,
            icon: const Icon(Icons.directions_bus_filled_outlined),
          ),
          IconButton(
            tooltip: "Resetar espelho",
            onPressed: _resetEspelho,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              // ✅ Card topo
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Icon(
                              widget.server.clientsCount > 0
                                  ? Icons.cast_connected
                                  : Icons.cast,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                activeLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w900),
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: _openTargets,
                              icon: const Icon(Icons.swap_horiz, size: 18),
                              label: const Text("Trocar"),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            const Icon(Icons.sensors, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                topStatus,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(Icons.schedule, size: 18, color: badgeColor),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                "Última msg: ${_fmtTime(lastAt)} • ${widget.server.lastFromIp.isEmpty ? "-" : widget.server.lastFromIp}",
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: badgeColor.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: badgeColor.withOpacity(0.35)),
                              ),
                              child: Text(
                                badgeText,
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12,
                                  color: badgeColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _resetEspelho,
                                icon: const Icon(Icons.refresh, size: 18),
                                label: const Text("Resetar espelho"),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _restartServerOnly,
                                icon: const Icon(Icons.restart_alt, size: 18),
                                label: const Text("Reiniciar server"),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // ✅ Card ingrediente
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Card(
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
                                nomeAtual.isEmpty ? "(Aguardando dados…)" : nomeAtual,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 22,
                                  height: 1.05,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            if (isPreNow) ...[
                              const SizedBox(width: 10),
                              _chip("PRÉ", Colors.deepPurple),
                            ],
                            if (finalizada) ...[
                              const SizedBox(width: 8),
                              _chip("FINALIZADA", Colors.blueGrey),
                            ],
                          ],
                        ),
                        if (fabId.isNotEmpty || (trato != null) || dieta.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            [
                              if (trato != null) "Trato: $trato",
                              if (dieta.isNotEmpty) "Dieta: $dieta",
                            ].join(" • "),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                        if (prox != null) ...[
                          const SizedBox(height: 10),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                                    "Próximo: ${(prox["nome"] ?? "").toString()}",
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w800),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  "${(prox["prev"] as num?)?.toInt() ?? 0} kg",
                                  style: const TextStyle(fontWeight: FontWeight.w900),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 10),

              // ✅ Diferença (kg)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Container(
                    width: double.infinity,
                    height: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: difColor.withOpacity(0.35)),
                      color: difColor.withOpacity(0.08),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.swap_horiz),
                            const SizedBox(width: 10),
                            const Text(
                              "Diferença (kg)",
                              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.75),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: Text(
                                status,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12,
                                ),
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
                                  fontSize: 90,
                                  height: 1.0,
                                  fontWeight: FontWeight.w900,
                                  color: difColor,
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
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(child: _kvCompact("Previsto", "$prev kg")),
                            const SizedBox(width: 10),
                            Expanded(child: _kvCompact("Realizado", "$real kg")),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),

          // ✅ OVERLAY DO PULO
          if (jumpRunning)
            Positioned(
              left: 16,
              right: 16,
              bottom: 18,
              child: IgnorePointer(
                ignoring: true,
                child: _jumpOverlay(
                  countdown: jumpCountdown,
                  total: jumpTotal,
                  progress: progress,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _chip(String text, Color c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withOpacity(0.35)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: 12,
          color: c,
        ),
      ),
    );
  }

  Widget _jumpOverlay({
    required int countdown,
    required int total,
    required double? progress,
  }) {
    final cd = countdown < 0 ? 0 : countdown;

    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(16),
      color: Colors.black.withOpacity(0.75),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            const Icon(Icons.fast_forward, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Pulando automaticamente…",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      minHeight: 10,
                      value: progress, // null = indeterminado
                      backgroundColor: Colors.white.withOpacity(0.18),
                    ),
                  ),
                  if (total > 0) ...[
                    const SizedBox(height: 4),
                    Text(
                      "em $cd s",
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.85),
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.12),
                border: Border.all(color: Colors.white.withOpacity(0.25)),
              ),
              child: Text(
                cd.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kvCompact(String k, String v) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade300),
        color: Colors.white.withOpacity(0.70),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
}
