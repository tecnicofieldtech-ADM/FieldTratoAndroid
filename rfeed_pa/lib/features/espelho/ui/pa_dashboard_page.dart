// lib/features/espelho/ui/pa_dashboard_page.dart
import "dart:async";

import "package:flutter/material.dart";
import "package:package_info_plus/package_info_plus.dart";
import "package:shared_preferences/shared_preferences.dart";
import "../controller/pa_client_controller.dart";
import "../data/mirror_targets_repo.dart";
import "targets_list_page.dart";

class PaDashboardPage extends StatefulWidget {
  const PaDashboardPage({super.key, required this.repo, required this.client});
  final MirrorTargetsRepo repo;
  final PaClientController client;

  @override
  State<PaDashboardPage> createState() => _PaDashboardPageState();
}

class _PaDashboardPageState extends State<PaDashboardPage> {
  static const String _styleRfeed = "rfeed";
  static const String _styleMbTratos = "mbtratos";
  static const String _stylePrefKey = "pa_style_mode";

  Timer? _ticker;
  String _versionLabel = "--";
  String _styleMode = _styleRfeed;

  @override
  void initState() {
    super.initState();
    widget.client.addListener(_on);
    // ignore: discarded_futures
    _loadVersion();
    // ignore: discarded_futures
    _loadStyleMode();

    // ignore: unawaited_futures
    _ensureClientStarted();

    _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  Future<void> _loadVersion() async {
    try {
      final p = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _versionLabel = "${p.version}+${p.buildNumber}");
    } catch (_) {
      if (!mounted) return;
      setState(() => _versionLabel = "--");
    }
  }

  Future<void> _loadStyleMode() async {
    try {
      final pref = await SharedPreferences.getInstance();
      final mode = (pref.getString(_stylePrefKey) ?? _styleRfeed).trim();
      if (!mounted) return;
      setState(() {
        _styleMode = (mode == _styleMbTratos) ? _styleMbTratos : _styleRfeed;
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _ticker?.cancel();
    widget.client.removeListener(_on);
    super.dispose();
  }

  void _on() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _ensureClientStarted() async {
    await widget.client.loadActive();
    if (!mounted) return;

    final active = widget.client.activeTarget;
    final hasTarget = active != null && active.host.trim().isNotEmpty;
    if (!hasTarget) {
      widget.client.status = "Selecione um Vagao para conectar";
      setState(() {});
      return;
    }

    await widget.client.start();
  }

  Future<void> _openTargets() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => TargetsListPage(
      repo: widget.repo,
      client: widget.client,
          autoPopOnSelect: true,
        ),
      ),
    );
    await _ensureClientStarted();
  }

  Future<void> _resetEspelho() async {
    await widget.client.stop();
    await _ensureClientStarted();
  }

  Future<void> _restartClientOnly() async {
    await widget.client.stop();
    await _ensureClientStarted();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(msg),
      ),
    );
  }

  Future<void> _sendNext() async {
    final ok = await widget.client.sendNextCommand();
    _toast(ok ? "Comando enviado: pular ingrediente" : "Falha ao enviar comando");
  }

  Future<void> _sendPrev() async {
    final ok = await widget.client.sendPrevCommand();
    _toast(ok ? "Comando enviado: voltar ingrediente" : "Falha ao enviar comando");
  }

  Future<void> _sendFinish() async {
    final confirm = await showDialog<bool>(
          context: context,
          builder: (dialogCtx) => AlertDialog(
            title: const Text("Finalizar fabricação"),
            content: const Text(
              "Deseja enviar o comando para finalizar a fabricação no caminhão?",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(false),
                child: const Text("Não"),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogCtx).pop(true),
                child: const Text("Sim"),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirm) return;
    final ok = await widget.client.sendFinishCommand();
    _toast(ok ? "Comando enviado: finalizar fabricação" : "Falha ao enviar comando");
  }

  String _fmtTime(DateTime? dt) {
    if (dt == null) return "--:--:--";
    final h = dt.hour.toString().padLeft(2, "0");
    final m = dt.minute.toString().padLeft(2, "0");
    final s = dt.second.toString().padLeft(2, "0");
    return "$h:$m:$s";
  }

  bool _isTrue(dynamic v) => v == true || v == 1 || v == "1";

  bool _isPre(Map<String, dynamic>? atual) {
    if (atual == null) return false;
    if (atual.containsKey("pre")) return _isTrue(atual["pre"]);
    if (atual.containsKey("prePesado")) return _isTrue(atual["prePesado"]);
    return false;
  }

  Color _alpha(Color color, double opacity) {
    final o = opacity.clamp(0.0, 1.0);
    return color.withValues(alpha: o);
  }

  @override
  Widget build(BuildContext context) {
    final isMbTratos = _styleMode == _styleMbTratos;
    final screenBg = isMbTratos ? const Color(0xFFE6F0E8) : null;
    final appBarBg = isMbTratos ? const Color(0xFF2F7D45) : null;
    final appBarFg = isMbTratos ? Colors.white : null;
    final actionButtonBg = isMbTratos ? const Color(0xFF00B5B2) : null;
    final actionButtonFg = isMbTratos ? Colors.white : null;
    final vehicleNameColor = isMbTratos ? const Color(0xFF205B33) : Colors.black87;

    final st = widget.client.lastState;
    final active = widget.client.activeTarget;
    final activeName = active?.nome.trim().isNotEmpty == true
        ? active!.nome.trim()
        : "Sem Vagao selecionado";

    final activeLabel = active == null
        ? "Nenhum Vagao selecionado"
        : "${active.nome} - ${active.host}";

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

    final percent = (prev > 0) ? (real * 100 / prev) : 0.0;
    final pctLabel = prev > 0 ? "${percent.toStringAsFixed(0)}%" : "--";
    final barValue = prev > 0 ? (real / prev).clamp(0.0, 1.0) : 0.0;
    final faltando = prev > 0 ? (prev - real) : 0;
    final faltandoShow = faltando < 0 ? 0 : faltando;
    final showPlus = prev > 0 && real > prev;
    final difText = showPlus ? "+$difAbs" : "$faltandoShow";

    String status;
    if (prev <= 0) {
      status = "Sem previsto";
    } else if (real == prev) {
      status = "No alvo";
    } else if (real < prev) {
      status = "Faltando $difAbs kg";
    } else {
      status = "Passou $difAbs kg";
    }

    Color bg;
    if (isMbTratos) {
      if (prev <= 0) {
        bg = const Color(0xFF3D7F4B);
      } else if (real == prev) {
        bg = const Color(0xFF2F7D45);
      } else if (real > prev) {
        bg = const Color(0xFF1E6032);
      } else {
        bg = const Color(0xFF245F35);
      }
    } else {
      if (prev <= 0) {
        bg = Colors.blueGrey.shade700;
      } else if (real == prev) {
        bg = Colors.green.shade700;
      } else if (real > prev) {
        bg = Colors.deepOrange.shade700;
      } else {
        bg = Colors.black;
      }
    }

    final topStatus = widget.client.connected
        ? "Conectado a ${widget.client.activeTarget?.host ?? ''}:${widget.client.activeTarget?.porta ?? 9000}"
        : widget.client.status;

    final lastAt = widget.client.lastMsgAt;
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
        : (stale ? "Sem atualizacao ($ageLabel)" : "Atualizando ($ageLabel)");

    IconData serverIcon;
    Color serverColor;
    String serverText;

    if (!widget.client.connected) {
      serverIcon = Icons.portable_wifi_off;
      serverColor = Colors.red;
      serverText = "Parado";
    } else if (stale || lastAt == null) {
      serverIcon = Icons.sync_problem;
      serverColor = Colors.orange;
      serverText = "Sem dados";
    } else {
      serverIcon = Icons.check_circle;
      serverColor = Colors.green;
      serverText = "OK";
    }

    final dieta = (st?["dieta"] ?? "").toString();
    final trato = (st?["trato"] as num?)?.toInt();
    final isFinalizacaoEvent =
      (st?["t"] ?? "").toString() == "event" &&
      (st?["type"] ?? "").toString() == "finalizada";
    final finalizada = _isTrue(st?["finalizada"]) || isFinalizacaoEvent;
    final finalizacaoMsgRaw = (st?["msg"] ?? "").toString().trim();
    final finalizacaoMsg = finalizada
      ? (finalizacaoMsgRaw.isNotEmpty
        ? finalizacaoMsgRaw
        : "Fabricação finalizada no caminhão")
      : null;
    final isPreNow = _isPre(atual);
    final atualPos = (atual?["pos"] as num?)?.toInt() ?? 0;
    final atualTotal = (atual?["total"] as num?)?.toInt() ?? 0;
    final isLastIngredient =
        !finalizada && atualPos > 0 && atualTotal > 0 && atualPos >= atualTotal;

    final subtitleParts = <String>[];
    if (trato != null) subtitleParts.add("Trato $trato");
    if (dieta.isNotEmpty) subtitleParts.add(dieta);
    final subtitle = subtitleParts.isEmpty ? null : subtitleParts.join(" - ");

    return Scaffold(
      backgroundColor: screenBg,
      appBar: _TopAppBar(
        title: "PA - Espelhamento",
        subtitle: subtitle,
        backgroundColor: appBarBg,
        foregroundColor: appBarFg,
        actions: [
          IconButton(
            tooltip: "Vagoes",
            onPressed: _openTargets,
            icon: const Icon(Icons.list_alt),
          ),
          IconButton(
            tooltip: "Resetar espelho",
            onPressed: _resetEspelho,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                activeName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 34,
                  height: 1.0,
                  fontWeight: FontWeight.w900,
                  color: vehicleNameColor,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: _cardServerTopCompact(
              activeLabel: activeLabel,
              localIp: widget.client.lastFromIp.isEmpty ? "--" : widget.client.lastFromIp,
              versionLabel: _versionLabel,
              topStatus: topStatus,
              serverIcon: serverIcon,
              serverColor: serverColor,
              serverText: serverText,
              lastAt: lastAt,
              badgeColor: badgeColor,
              badgeText: badgeText,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: _cardIngredienteTop(
              nomeAtual: nomeAtual,
              isPreNow: isPreNow,
              finalizada: finalizada,
              finalizacaoMsg: finalizacaoMsg,
              prox: prox,
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: finalizada
                  ? _cardFinalizacaoPrincipalFill(
                      mensagem: finalizacaoMsg ??
                          "Fabricação finalizada no caminhão",
                      bg: isMbTratos
                          ? const Color(0xFF2F7D45)
                          : Colors.blueGrey.shade700,
                    )
                  : _cardDiferencaPrincipalFill(
                      prev: prev,
                      real: real,
                      difText: difText,
                      status: status,
                      pctLabel: pctLabel,
                      barValue: barValue,
                      bg: bg,
                    ),
            ),
          ),
          _bottomNav(
            actionButtonBg: actionButtonBg,
            actionButtonFg: actionButtonFg,
            finalizada: finalizada,
            isLastIngredient: isLastIngredient,
          ),
        ],
      ),
    );
  }

  Widget _cardServerTopCompact({
    required String activeLabel,
    required String localIp,
    required String versionLabel,
    required String topStatus,
    required IconData serverIcon,
    required Color serverColor,
    required String serverText,
    required DateTime? lastAt,
    required Color badgeColor,
    required String badgeText,
  }) {
    final lastAtTxt = _fmtTime(lastAt);

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
                      activeLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _restartClientOnly,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text("Reconectar"),
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
                      Icon(serverIcon, color: serverColor, size: 18),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          "Server: $serverText - $lastAtTxt",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: serverColor,
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
                        Icons.cast_connected,
                        size: 18,
                        color: badgeColor,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          badgeText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: badgeColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "Vagao: $localIp",
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade700,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "Versao: v$versionLabel",
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade700,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                topStatus,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cardIngredienteTop({
    required String nomeAtual,
    required bool isPreNow,
    required bool finalizada,
    required String? finalizacaoMsg,
    required Map<String, dynamic>? prox,
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
                    nomeAtual.isEmpty
                        ? (finalizada
                            ? "Fabricação finalizada"
                            : "(Aguardando dados...)")
                        : nomeAtual,
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
                  const SizedBox(width: 8),
                  _chip(icon: Icons.verified, label: "Pre-pesado"),
                ],
                if (finalizada) ...[
                  const SizedBox(width: 8),
                  _chip(icon: Icons.task_alt, label: "Finalizada"),
                ],
              ],
            ),
            if (finalizada && finalizacaoMsg != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.green.shade50,
                  border: Border.all(color: Colors.green.shade300),
                ),
                child: Row(
                  children: [
                    Icon(Icons.campaign, size: 18, color: Colors.green.shade800),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        finalizacaoMsg,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Colors.green.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (!finalizada && prox != null) ...[
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
                        "Proximo: ${(prox["nome"] ?? "").toString()}",
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
    );
  }

  Widget _cardFinalizacaoPrincipalFill({
    required String mensagem,
    required Color bg,
  }) {
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
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.task_alt, color: Colors.white, size: 64),
          const SizedBox(height: 18),
          const Text(
            "FABRICAÇÃO FINALIZADA",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 34,
              height: 1.05,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            mensagem,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardDiferencaPrincipalFill({
    required int prev,
    required int real,
    required String difText,
    required String status,
    required String pctLabel,
    required double barValue,
    required Color bg,
  }) {
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
              const Expanded(
                child: Row(
                  children: [
                    Icon(Icons.scale, color: Colors.white, size: 28),
                    SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        "A FABRICAR (kg)",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 26,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 132),
                    child: _PulseChip(
                      icon: Icons.timer,
                      active: widget.client.autoCountdown > 0,
                      label: widget.client.autoCountdown > 0
                          ? "Pulo: ${widget.client.autoCountdown}s"
                          : "Pulo: pronto",
                    ),
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
                  style: const TextStyle(
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
                  prev <= 0
                      ? Icons.help_outline
                      : (real < prev ? Icons.warning_amber : Icons.verified),
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
              ],
            ),
          ),
        ],
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

  Widget _bottomNav({
    required Color? actionButtonBg,
    required Color? actionButtonFg,
    required bool finalizada,
    required bool isLastIngredient,
  }) {
    final canSend = widget.client.hasConnection;
    final canNext = canSend && !finalizada && !isLastIngredient;
    final canFinish = canSend && !finalizada && isLastIngredient;

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey.shade200)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: canSend ? _sendPrev : null,
                          icon: const Icon(Icons.skip_previous),
                          label: const Text("Voltar"),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: canNext ? _sendNext : null,
                          icon: const Icon(Icons.skip_next),
                          label: const Text("Pular"),
                        ),
                      ),
                      if (isLastIngredient) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: canFinish ? _sendFinish : null,
                            icon: const Icon(Icons.task_alt),
                            label: const Text("Finalizar"),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      IconButton(
                        onPressed: _resetEspelho,
                        icon: const Icon(Icons.restart_alt),
                        tooltip: "Resetar",
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _openTargets,
                          style: (actionButtonBg == null && actionButtonFg == null)
                              ? null
                              : FilledButton.styleFrom(
                                  backgroundColor: actionButtonBg,
                                  foregroundColor: actionButtonFg,
                                ),
                          icon: const Icon(Icons.swap_horiz),
                          label: const Text("Trocar Vagao Carregamento"),
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
      builder: (_, child) {
        final t = _ac.value;
        final scale = 1.0 + (t * 0.06);
        final glow = 0.08 + (t * 0.14);

        return Transform.scale(
          scale: scale,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              boxShadow: [
                BoxShadow(
                  color: _alpha(Colors.white, glow),
                  blurRadius: 14,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: _chipBase(
              icon: widget.icon,
              label: widget.label,
              color: _alpha(Colors.white, 0.92),
              border: _alpha(Colors.black, 0.28),
              iconColor: Colors.black87,
              textColor: Colors.black87,
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
  const _TopAppBar({
    required this.title,
    this.subtitle,
    this.actions,
    this.backgroundColor,
    this.foregroundColor,
  });

  final String title;
  final String? subtitle;
  final List<Widget>? actions;
  final Color? backgroundColor;
  final Color? foregroundColor;

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      titleSpacing: 12,
      actions: actions,
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
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





