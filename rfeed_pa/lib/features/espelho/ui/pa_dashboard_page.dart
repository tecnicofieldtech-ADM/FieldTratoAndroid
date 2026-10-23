// lib/features/espelho/ui/pa_dashboard_page.dart
import "dart:async";

import "package:flutter/material.dart";
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
  bool _wasStale = false;
  String _styleMode = _styleRfeed;

  @override
  void initState() {
    super.initState();
    widget.client.addListener(_on);
    // ignore: discarded_futures
    _loadStyleMode();

    // ignore: unawaited_futures
    _ensureClientStarted();

    _ticker = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;
      final lastAt = widget.client.lastMsgAt;
      final nowStale = lastAt == null ||
          DateTime.now().difference(lastAt).inMilliseconds > 6000;
      if (nowStale != _wasStale) {
        _wasStale = nowStale;
        setState(() {});
      }
    });
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
    if (!ok) _toast("Falha ao enviar comando");
  }

  Future<void> _sendPrev() async {
    final ok = await widget.client.sendPrevCommand();
    if (!ok) _toast("Falha ao enviar comando");
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
    if (!ok) _toast("Falha ao enviar comando");
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
    final screenH = MediaQuery.of(context).size.height;
    final screenW = MediaQuery.of(context).size.width;
    final isPhone = screenW < 600 || screenH < 700;
    final hPad = isPhone ? 10.0 : 16.0;

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

    final lastAt = widget.client.lastMsgAt;
    final ageSec = lastAt == null
        ? null
        : DateTime.now().difference(lastAt).inMilliseconds / 1000.0;
    final stale = ageSec != null && ageSec > 6.0;

    IconData serverIcon;
    Color serverColor;
    String serverText;

    if (!widget.client.connected) {
      serverIcon = Icons.portable_wifi_off;
      serverColor = Colors.red;
      serverText = "Desconectado";
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
    final prevTotalFab = (st?["qtdPrevista"] as num?)?.toInt();
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
          // Header compacto: nome do vagão + status inline
          Padding(
            padding: EdgeInsets.fromLTRB(hPad, isPhone ? 4 : 10, hPad, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    activeName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: isPhone ? 18 : 34,
                      height: 1.0,
                      fontWeight: FontWeight.w900,
                      color: vehicleNameColor,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(serverIcon, color: serverColor, size: isPhone ? 16 : 18),
                const SizedBox(width: 4),
                Text(
                  serverText,
                  style: TextStyle(
                    fontSize: isPhone ? 11 : 13,
                    fontWeight: FontWeight.w800,
                    color: serverColor,
                  ),
                ),
              ],
            ),
          ),
          // Card de conexão (escondido em phone, compacto em tablet)
          if (!isPhone)
            Padding(
              padding: EdgeInsets.fromLTRB(hPad, 12, hPad, 0),
              child: _cardServerTopCompact(
                activeLabel: activeLabel,
                serverIcon: serverIcon,
                serverColor: serverColor,
                serverText: serverText,
                lastAt: lastAt,
              ),
            ),
          // Ingrediente atual
          Padding(
            padding: EdgeInsets.fromLTRB(hPad, isPhone ? 6 : 10, hPad, 0),
            child: _cardIngredienteResponsive(
              nomeAtual: nomeAtual,
              isPreNow: isPreNow,
              finalizada: finalizada,
              finalizacaoMsg: finalizacaoMsg,
              prox: prox,
              isPhone: isPhone,
            ),
          ),
          SizedBox(height: isPhone ? 6 : 10),
          // Card principal (peso/diferença)
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(hPad, 0, hPad, isPhone ? 4 : 8),
              child: finalizada
                  ? _cardFinalizacaoPrincipalFill(
                      mensagem: finalizacaoMsg ??
                          "Fabricação finalizada no caminhão",
                      bg: isMbTratos
                          ? const Color(0xFF2F7D45)
                          : Colors.blueGrey.shade700,
                      isPhone: isPhone,
                    )
                  : _cardDiferencaResponsive(
                      prev: prev,
                      real: real,
                      prevTotalFab: prevTotalFab,
                      difText: difText,
                      status: status,
                      pctLabel: pctLabel,
                      barValue: barValue,
                      bg: bg,
                      isPhone: isPhone,
                    ),
            ),
          ),
          _bottomNavResponsive(
            actionButtonBg: actionButtonBg,
            actionButtonFg: actionButtonFg,
            finalizada: finalizada,
            isLastIngredient: isLastIngredient,
            isPhone: isPhone,
          ),
        ],
      ),
    );
  }

  Widget _cardServerTopCompact({
    required String activeLabel,
    required IconData serverIcon,
    required Color serverColor,
    required String serverText,
    required DateTime? lastAt,
  }) {
    final lastAtTxt = _fmtTime(lastAt);
    final statusLabel = lastAt == null ? serverText : "$serverText · $lastAtTxt";

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    activeLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(serverIcon, color: serverColor, size: 16),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          statusLabel,
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
                ],
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _restartClientOnly,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text("Reconectar"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cardIngredienteResponsive({
    required String nomeAtual,
    required bool isPreNow,
    required bool finalizada,
    required String? finalizacaoMsg,
    required Map<String, dynamic>? prox,
    required bool isPhone,
  }) {
    final fontSize = isPhone ? 16.0 : 22.0;
    final pad = isPhone
        ? const EdgeInsets.fromLTRB(10, 8, 10, 8)
        : const EdgeInsets.fromLTRB(14, 12, 14, 12);

    return Card(
      child: Padding(
        padding: pad,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.inventory_2_outlined, size: isPhone ? 14 : 18),
                SizedBox(width: isPhone ? 6 : 8),
                Expanded(
                  child: Text(
                    nomeAtual.isEmpty
                        ? (finalizada
                            ? "Fabricação finalizada"
                            : "(Aguardando dados...)")
                        : nomeAtual,
                    maxLines: isPhone ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: fontSize,
                      height: 1.05,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (isPreNow) ...[
                  const SizedBox(width: 6),
                  _chip(icon: Icons.verified, label: "Pre"),
                ],
              ],
            ),
            if (!isPhone && !finalizada && prox != null) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: Colors.grey.shade100,
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.next_plan, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Proximo: ${(prox["nome"] ?? "").toString()}",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                    ),
                    Text(
                      "${(prox["prev"] as num?)?.toInt() ?? 0} kg",
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
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
    bool isPhone = false,
  }) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      padding: EdgeInsets.all(isPhone ? 16 : 28),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(isPhone ? 18 : 26),
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
          Icon(Icons.task_alt, color: Colors.white, size: isPhone ? 40 : 64),
          SizedBox(height: isPhone ? 10 : 18),
          Text(
            "FABRICAÇÃO FINALIZADA",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: isPhone ? 22 : 34,
              height: 1.05,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: 1.1,
            ),
          ),
          SizedBox(height: isPhone ? 8 : 16),
          Text(
            mensagem,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: isPhone ? 14 : 20,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardDiferencaResponsive({
    required int prev,
    required int real,
    required int? prevTotalFab,
    required String difText,
    required String status,
    required String pctLabel,
    required double barValue,
    required Color bg,
    required bool isPhone,
  }) {
    final radius = isPhone ? 18.0 : 26.0;
    final pad = isPhone
        ? const EdgeInsets.fromLTRB(14, 14, 14, 14)
        : const EdgeInsets.fromLTRB(24, 28, 24, 28);

    return Container(
      width: double.infinity,
      height: double.infinity,
      padding: pad,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
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
          // Header: título + pulo
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(Icons.scale, color: Colors.white, size: isPhone ? 18 : 28),
                    SizedBox(width: isPhone ? 6 : 10),
                    Flexible(
                      child: Text(
                        "A FABRICAR (kg)",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: isPhone ? 14 : 26,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.client.autoCountdown > 0)
                _PulseChip(
                  icon: Icons.timer,
                  active: true,
                  label: "${widget.client.autoCountdown}s",
                ),
            ],
          ),
          SizedBox(height: isPhone ? 4 : 6),
          // Número principal
          Expanded(
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  difText,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: isPhone ? 120 : 200,
                    height: 0.90,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
          SizedBox(height: isPhone ? 4 : 10),
          // Barra de progresso
          Stack(
            alignment: Alignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  minHeight: isPhone ? 12 : 18,
                  value: barValue,
                ),
              ),
              Text(
                pctLabel,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: isPhone ? 10 : 12,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          SizedBox(height: isPhone ? 6 : 10),
          // Previsto / Realizado do insumo
          Row(
            children: [
              Expanded(child: _midKvCenteredCompact("Previsto", "$prev kg", isPhone: isPhone)),
              SizedBox(width: isPhone ? 6 : 10),
              Expanded(child: _midKvCenteredCompact("Realizado", "$real kg", isPhone: isPhone)),
            ],
          ),
          if (prevTotalFab != null && prevTotalFab > 0) ...[
            SizedBox(height: isPhone ? 4 : 6),
            _midKvCenteredCompact(
              "Previsto total",
              "$prevTotalFab kg",
              isPhone: isPhone,
            ),
          ],
          SizedBox(height: isPhone ? 4 : 8),
          // Status
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(
              horizontal: isPhone ? 8 : 12,
              vertical: isPhone ? 5 : 8,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(isPhone ? 10 : 14),
              color: Colors.white.withValues(alpha: 0.16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
            ),
            child: Row(
              children: [
                Icon(
                  prev <= 0
                      ? Icons.help_outline
                      : (real < prev ? Icons.warning_amber : Icons.verified),
                  size: isPhone ? 14 : 18,
                  color: Colors.white,
                ),
                SizedBox(width: isPhone ? 6 : 8),
                Expanded(
                  child: Text(
                    status,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: isPhone ? 11 : 13,
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

  Widget _midKvCenteredCompact(String k, String v, {bool isPhone = false}) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isPhone ? 6 : 10,
        vertical: isPhone ? 6 : 10,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(isPhone ? 10 : 14),
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
              fontSize: isPhone ? 9 : 11,
            ),
          ),
          SizedBox(height: isPhone ? 2 : 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              v,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: isPhone ? 16 : 22,
                height: 1.0,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomNavResponsive({
    required Color? actionButtonBg,
    required Color? actionButtonFg,
    required bool finalizada,
    required bool isLastIngredient,
    required bool isPhone,
  }) {
    final canSend = widget.client.hasConnection;
    final canNext = canSend && !finalizada && !isLastIngredient;
    final canFinish = canSend && !finalizada && isLastIngredient;

    return SafeArea(
      top: false,
      minimum: EdgeInsets.only(bottom: isPhone ? 4 : 8),
      child: Container(
        padding: EdgeInsets.fromLTRB(
          isPhone ? 8 : 12,
          isPhone ? 6 : 10,
          isPhone ? 8 : 12,
          isPhone ? 6 : 12,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey.shade200)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: isPhone ? 36 : 44,
                      child: OutlinedButton.icon(
                        onPressed: canSend ? _sendPrev : null,
                        icon: Icon(Icons.skip_previous, size: isPhone ? 16 : 20),
                        label: Text("Voltar", style: TextStyle(fontSize: isPhone ? 11 : 14)),
                      ),
                    ),
                  ),
                  SizedBox(width: isPhone ? 4 : 8),
                  Expanded(
                    child: SizedBox(
                      height: isPhone ? 36 : 44,
                      child: OutlinedButton.icon(
                        onPressed: canNext ? _sendNext : null,
                        icon: Icon(Icons.skip_next, size: isPhone ? 16 : 20),
                        label: Text("Pular", style: TextStyle(fontSize: isPhone ? 11 : 14)),
                      ),
                    ),
                  ),
                  if (isLastIngredient) ...[
                    SizedBox(width: isPhone ? 4 : 8),
                    Expanded(
                      child: SizedBox(
                        height: isPhone ? 36 : 44,
                        child: FilledButton.icon(
                          onPressed: canFinish ? _sendFinish : null,
                          icon: Icon(Icons.task_alt, size: isPhone ? 16 : 20),
                          label: Text("Finalizar", style: TextStyle(fontSize: isPhone ? 11 : 14)),
                        ),
                      ),
                    ),
                  ],
                  SizedBox(width: isPhone ? 4 : 8),
                  SizedBox(
                    height: isPhone ? 36 : 44,
                    width: isPhone ? 36 : 44,
                    child: IconButton(
                      onPressed: _openTargets,
                      icon: Icon(Icons.settings, size: isPhone ? 18 : 22),
                      tooltip: "Config",
                    ),
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





