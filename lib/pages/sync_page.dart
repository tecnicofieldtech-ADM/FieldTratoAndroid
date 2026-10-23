import "dart:async";

import "package:flutter/material.dart";
import "package:flutter/services.dart";

import "../domain/sync_pendencia_registro.dart";
import "../repo/config_repo.dart";
import "../repo/vagao_repo.dart";
import "../repo/fazenda_repo.dart";
import "../repo/user_repo.dart";
import "../services/bootstrap_sync.dart";
import "../services/fornecimento_audit_service.dart";
import "../services/fabricacao_audit_service.dart";
import "../services/sync_orchestrator.dart";
import "../services/wifi_guard.dart";

class SyncPage extends StatefulWidget {
  const SyncPage({super.key});

  @override
  State<SyncPage> createState() => _SyncPageState();
}

class _SyncPageState extends State<SyncPage> {
  final _cfgRepo = ConfigRepo();
  final _vagaoRepo = VagaoRepo();
  final _fazendaRepo = FazendaRepo();
  final _userRepo = UserRepo();

  late final BootstrapSync _bootstrap = BootstrapSync(
    cfgRepo: _cfgRepo,
    vagaoRepo: _vagaoRepo,
    fazendaRepo: _fazendaRepo,
    userRepo: _userRepo,
  );

  late final SyncOrchestrator _orchestrator = SyncOrchestrator(
    cfgRepo: _cfgRepo,
    bootstrap: _bootstrap,
  );

  final _fornecimentoAudit = FornecimentoAuditService();
  final _fabricacaoAudit = FabricacaoAuditService();

  bool _running = false;
  bool _auditRunning = false;
  SyncMode? _runningMode;
  int _currentIndex = -1;
  String _currentTitle = "";
  List<SyncStep> _steps = [];
  final List<String> _log = [];

  // ✅ pendências (cards)
  int _pendTag = 0;
  int _pendFab = 0;
  int _pendFor = 0;
  List<SyncPendenciaRegistro> _pendRegistros = const [];
  bool _loadingPend = false;
  ScaffoldMessengerState? _messenger;

  @override
  void initState() {
    super.initState();
    // carrega pendências ao abrir
    // ignore: unawaited_futures
    _loadPendencias();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _messenger = ScaffoldMessenger.maybeOf(context);
  }

  Future<void> _loadPendencias() async {
    if (!mounted) return;
    if (_loadingPend) return;
    setState(() => _loadingPend = true);

    try {
      final tag = await _cfgRepo.countGravaTagPendenteSync();
      final fab = await _cfgRepo.countFabricacaoPendenteSync();
      final forn = await _cfgRepo.countFornecimentoPendenteSync();
      final registros = await _cfgRepo.listPendenciasSyncDetalhe();

      if (!mounted) return;
      setState(() {
        _pendTag = tag;
        _pendFab = fab;
        _pendFor = forn;
        _pendRegistros = registros;
      });
    } finally {
      if (mounted) setState(() => _loadingPend = false);
    }
  }

  void _addLog(String msg) {
    final hhmmss = DateTime.now().toIso8601String().substring(11, 19);
    if (!mounted) return;
    setState(() => _log.insert(0, "$hhmmss - $msg"));
  }

  Future<void> _copyLog() async {
    if (_log.isEmpty) return;
    final text = _log.reversed.join("\n");
    await Clipboard.setData(ClipboardData(text: text));
    _toast("Log copiado — cole no WhatsApp ou e-mail");
  }

  void _toast(String msg) {
    if (!mounted) return;
    final messenger = _messenger;
    if (messenger == null) return;
    try {
      messenger.showSnackBar(SnackBar(content: Text(msg)));
    } catch (_) {}
  }

  double get _progress {
    if (_steps.isEmpty || _currentIndex < 0) return 0;
    final done = (_currentIndex + 1).clamp(0, _steps.length);
    return done / _steps.length;
  }

  String _fmtMs(int ms) {
    if (ms < 1000) return "${ms}ms";
    final s = ms / 1000.0;
    return "${s.toStringAsFixed(2)}s";
  }

  Future<int?> _tryGetStepCount(SyncStep step) async {
    try {
      final dyn = step as dynamic;

      final v1 = dyn.debugCount;
      if (v1 is int) return v1;
      if (v1 is num) return v1.toInt();

      final v2 = dyn.debugCount as dynamic;
      if (v2 is Future<int?> Function()) return await v2();
      if (v2 is Future<num?> Function()) {
        final r = await v2();
        return r?.toInt();
      }
      if (v2 is int? Function()) return v2();
      if (v2 is num? Function()) {
        final r = v2();
        return r?.toInt();
      }

      final meta = dyn.meta;
      if (meta is Map) {
        const keys = ["count", "total", "inserted", "rows", "itens", "items"];
        for (final k in keys) {
          if (meta.containsKey(k)) {
            final vv = meta[k];
            if (vv is int) return vv;
            if (vv is num) return vv.toInt();
            final p = int.tryParse(vv?.toString() ?? "");
            if (p != null) return p;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  bool _isLoopbackHost(String host) {
    final h = host.trim().toLowerCase();
    if (h.isEmpty) return true;
    if (h == "localhost" || h == "127.0.0.1" || h == "::1") return true;
    if (h.startsWith("127.")) return true;
    return false;
  }

  Future<bool> _preflightSyncNetwork() async {
    final cfg = await _cfgRepo.getConfig();
    if (!mounted) return false;
    if (cfg == null) {
      _toast("Config nao encontrada. Abra Config e salve HOST/PORTA.");
      return false;
    }

    final baseUrl = _cfgRepo.buildBaseUrl(cfg);
    final host = (cfg["HOST_API"] ??
            cfg["HOST"] ??
            cfg["SERVER"] ??
            cfg["IP"] ??
            cfg["API_HOST"] ??
            "")
        .toString()
        .trim();

    if (_isLoopbackHost(host) ||
        baseUrl.contains("127.0.0.1") ||
        baseUrl.contains("localhost")) {
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text("HOST da API invalido"),
          content: Text(
            "HOST atual aponta para o proprio tablet ($baseUrl).\n\n"
            "No TGC o fornecimento so sobe no Sync, e a request precisa "
            "ir para o IP do servidor da fazenda (ex.: 192.168.x.x), "
            "nao 127.0.0.1.\n\n"
            "Ajuste em Config > HOST_API / PORTA (padrao TGC: 3001).",
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("Entendi"),
            ),
          ],
        ),
      );
      return false;
    }

    final ssid = await WifiGuard.getCurrentSsid();
    if (!mounted) return false;

    if (WifiGuard.isFieldTratoSsid(ssid)) {
      final trocar = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text("Rede para sincronizacao"),
              content: Text(
                "Rede atual: ${ssid.isEmpty ? "FieldTrato" : ssid}.\n\n"
                "No Wi-Fi FieldTrato* a sync NAO envia nada ao servidor.\n"
                "Conecte no Wi-Fi da fazenda (onde a API TGC responde) e tente de novo.",
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text("Voltar"),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text("Abrir Wi-Fi"),
                ),
              ],
            ),
          ) ??
          false;

      if (trocar) {
        await WifiGuard.openWifiSelector();
      }
      return false;
    }

    if (!WifiGuard.isSsidIdentifiable(ssid)) {
      final seguir = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text("Wi-Fi nao identificado"),
              content: const Text(
                "Nao foi possivel ler o SSID (permissao de localizacao "
                "ou OEM).\n\n"
                "Se o tablet ainda estiver no Wi-Fi FieldTrato*, as requests "
                "nao chegam na API TGC.\n\n"
                "Confirme a rede da fazenda e continue somente se tiver certeza.",
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text("Voltar"),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text("Continuar sync"),
                ),
              ],
            ),
          ) ??
          false;
      if (!seguir) return false;
    }

    return true;
  }

  String _modeLabel(SyncMode mode) {
    switch (mode) {
      case SyncMode.downloadOnly:
        return "Baixar dados";
      case SyncMode.uploadOnly:
        return "Enviar pendências";
      case SyncMode.full:
        return "Baixar e enviar tudo";
    }
  }

  Future<void> _runSync(SyncMode mode) async {
    if (_running || _auditRunning) return;

    final okNet = await _preflightSyncNetwork();
    if (!okNet || !mounted) return;

    final cfg = await _cfgRepo.getConfig();
    if (!mounted) return;
    final baseUrl = cfg == null ? "" : _cfgRepo.buildBaseUrl(cfg);
    final backend = int.tryParse((cfg?["BACKEND"] ?? "0").toString()) ?? 0;
    final ssid = await WifiGuard.getCurrentSsid();
    if (!mounted) return;

    final modeLabel = _modeLabel(mode);

    setState(() {
      _running = true;
      _runningMode = mode;
      _currentIndex = -1;
      _currentTitle = "";
      _log.clear();
      _steps = [];
    });

    final swAll = Stopwatch()..start();

    try {
      // ✅ antes de começar, atualiza cards
      await _loadPendencias();

      _addLog("Modo: $modeLabel");
      _addLog("Destino API: $baseUrl");
      _addLog(
        "Backend: ${backend == 2 ? "Outros (TGC)" : "codigo $backend"} · "
        "SSID: ${WifiGuard.isSsidIdentifiable(ssid) ? ssid : "(nao lido)"}",
      );
      if (backend != 2) {
        _addLog(
          "AVISO: cliente TGC deve usar Config > Backend = 'Outros (TGC)'. "
          "Com outro backend a ordem fab→fornecimento fica incorreta.",
        );
      }

      _addLog("Preparando etapas ($modeLabel)...");
      _steps = await _orchestrator.buildSteps(log: _addLog, mode: mode);
      _addLog("Total de etapas: ${_steps.length}");

      for (int i = 0; i < _steps.length; i++) {
        final step = _steps[i];

        if (!mounted) return;
        setState(() {
          _currentIndex = i;
          _currentTitle = step.title;
        });

        _addLog("▶ ${step.title}");
        final sw = Stopwatch()..start();

        try {
          await step.run();
          sw.stop();

          final count = await _tryGetStepCount(step);
          if (count != null) {
            _addLog(
              "📦 ${step.title}: $count registro(s) (${_fmtMs(sw.elapsedMilliseconds)})",
            );
          } else {
            _addLog("✅ OK: ${step.title} (${_fmtMs(sw.elapsedMilliseconds)})");
          }
        } catch (e, st) {
          sw.stop();
          _addLog(
            "❌ ERRO em ${step.title}: $e (${_fmtMs(sw.elapsedMilliseconds)})",
          );
          _addLog(
            "🧠 Stack: ${st.toString().split("\n").take(4).join(" | ")}",
          );
          rethrow;
        }

        await Future.delayed(const Duration(milliseconds: 80));
      }

      swAll.stop();
      _addLog(
        "🏁 FIM: $modeLabel concluído em ${_fmtMs(swAll.elapsedMilliseconds)}",
      );
      _toast("$modeLabel concluído com sucesso.");
    } catch (e, st) {
      swAll.stop();
      _addLog("❌ FALHA GERAL: $e");
      _addLog("🧠 Stack: ${st.toString().split("\n").take(6).join(" | ")}");
      _toast("Falha: $modeLabel.");
    } finally {
      // ✅ depois da sync, atualiza cards de novo (muito importante)
      await _loadPendencias();

      if (mounted) {
        setState(() {
          _running = false;
          _runningMode = null;
          _currentTitle = "Pronto";
        });
      }
    }
  }

  Widget _syncActionButton({
    required SyncMode mode,
    required IconData icon,
    required String label,
    required Color color,
    bool primary = false,
  }) {
    final busy = _running || _auditRunning;
    final thisRunning = _running && _runningMode == mode;
    return SizedBox(
      width: double.infinity,
      height: primary ? 52 : 48,
      child: primary
          ? ElevatedButton.icon(
              onPressed: busy ? null : () => _runSync(mode),
              icon: thisRunning
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(icon),
              label: Text(thisRunning ? "Sincronizando..." : label),
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            )
          : OutlinedButton.icon(
              onPressed: busy ? null : () => _runSync(mode),
              icon: thisRunning
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: color,
                      ),
                    )
                  : Icon(icon, color: busy ? null : color),
              label: Text(thisRunning ? "Sincronizando..." : label),
              style: OutlinedButton.styleFrom(
                foregroundColor: color,
                side: BorderSide(color: color.withValues(alpha: 0.55)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
    );
  }

  Future<void> _enviarAuditoriaFornecimento() async {
    if (_running || _auditRunning) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Auditoria fornecimento"),
        content: const Text(
          "Enviar todos os registros locais de CADASTRO_FORNECIMENTO "
          "para a API gravar em disco no servidor?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text("Cancelar"),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text("Enviar"),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _auditRunning = true);
    _addLog("Iniciando auditoria CADASTRO_FORNECIMENTO...");

    try {
      final resp = await _fornecimentoAudit.enviarAuditoriaCompleta(
        log: _addLog,
      );
      final qtd = resp["registros"] ?? resp["total"];
      final path = resp["saved_path"] ?? resp["filename"] ?? "";
      _addLog("Auditoria OK: $qtd registro(s) salvos em $path");
      _toast("Auditoria enviada com sucesso.");
    } catch (e) {
      _addLog("Falha auditoria: $e");
      _toast("Falha ao enviar auditoria.");
    } finally {
      if (mounted) setState(() => _auditRunning = false);
    }
  }

  Future<void> _enviarAuditoriaFabricacao() async {
    if (_running || _auditRunning) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Auditoria fabricação"),
        content: const Text(
          "Enviar todos os registros locais de CADASTRO_FABRICA_RACAO "
          "para a API gravar em disco no servidor?\n\n"
          "Use para verificar quais fabricações não foram para o CGPec.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text("Cancelar"),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text("Enviar"),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _auditRunning = true);
    _addLog("Iniciando auditoria CADASTRO_FABRICA_RACAO...");

    try {
      final resp = await _fabricacaoAudit.enviarAuditoriaCompleta(
        log: _addLog,
      );
      final qtd = resp["registros"] ?? resp["total"];
      final path = resp["saved_path"] ?? resp["filename"] ?? "";
      _addLog("Auditoria fabricação OK: $qtd registro(s) salvos em $path");
      _toast("Auditoria de fabricação enviada.");
    } catch (e) {
      _addLog("Falha auditoria fabricação: $e");
      _toast("Falha ao enviar auditoria de fabricação.");
    } finally {
      if (mounted) setState(() => _auditRunning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _steps.length;
    final idx = _currentIndex;
    final stepText = (total > 0 && idx >= 0)
        ? "Etapa ${idx + 1} de $total"
        : "Pronto para sincronizar";

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Sincronização"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
        actions: [
          PopupMenuButton<String>(
            tooltip: "Auditoria (enviar tabelas ao servidor)",
            enabled: !_running && !_auditRunning,
            onSelected: (v) {
              if (v == "forn") _enviarAuditoriaFornecimento();
              if (v == "fab") _enviarAuditoriaFabricacao();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: "fab",
                child: ListTile(
                  leading: Icon(Icons.factory_outlined),
                  title: Text("Auditoria fabricação"),
                  subtitle: Text("CADASTRO_FABRICA_RACAO"),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: "forn",
                child: ListTile(
                  leading: Icon(Icons.fact_check_outlined),
                  title: Text("Auditoria fornecimento"),
                  subtitle: Text("CADASTRO_FORNECIMENTO"),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
            icon: _auditRunning
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.upload_file_outlined),
          ),
          IconButton(
            tooltip: "Atualizar pendências",
            onPressed: (_running || _auditRunning) ? null : _loadPendencias,
            icon: _loadingPend
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: "Copiar log",
            onPressed: (_running || _auditRunning || _log.isEmpty)
                ? null
                : _copyLog,
            icon: const Icon(Icons.copy_outlined),
          ),
          IconButton(
            tooltip: "Limpar log",
            onPressed: (_running || _auditRunning)
                ? null
                : () => setState(() => _log.clear()),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.all(
          MediaQuery.of(context).size.width < 600 ? 10 : 16,
        ),
        child: Column(
          children: [
            // ✅ CARDS DE PENDÊNCIA
            Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _PendingCard(
                        title: "Grava TAG",
                        subtitle: "pendente para enviar",
                        count: _pendTag,
                        icon: Icons.nfc_outlined,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _PendingCard(
                        title: "Fabricação",
                        subtitle: "pendente para enviar",
                        count: _pendFab,
                        icon: Icons.factory_outlined,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _PendingCard(
                  title: "Fornecimento",
                  subtitle: "pendente para enviar",
                  count: _pendFor,
                  icon: Icons.local_shipping_outlined,
                ),
              ],
            ),

            if (_pendRegistros.isNotEmpty) ...[
              const SizedBox(height: 12),
              _PendenciasLista(registros: _pendRegistros),
            ],

            const SizedBox(height: 12),

            // ✅ BOX PRINCIPAL (PROGRESSO + BOTÃO)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.black12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(stepText, style: const TextStyle(color: Colors.black54)),
                  const SizedBox(height: 6),
                  Text(
                    _currentTitle.isEmpty ? "—" : _currentTitle,
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: _running ? _progress : 0,
                      minHeight: 10,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _syncActionButton(
                    mode: SyncMode.downloadOnly,
                    icon: Icons.cloud_download_outlined,
                    label: "Baixar dados",
                    color: const Color(0xFF2E7D32),
                  ),
                  const SizedBox(height: 8),
                  _syncActionButton(
                    mode: SyncMode.uploadOnly,
                    icon: Icons.cloud_upload_outlined,
                    label: "Enviar pendências",
                    color: const Color(0xFFEF6C00),
                  ),
                  const SizedBox(height: 8),
                  _syncActionButton(
                    mode: SyncMode.full,
                    icon: Icons.sync,
                    label: "Baixar e enviar tudo",
                    color: const Color(0xFF25A7CF),
                    primary: true,
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: (_running || _auditRunning)
                          ? null
                          : _enviarAuditoriaFornecimento,
                      icon: const Icon(Icons.upload_file_outlined),
                      label: Text(
                        _auditRunning
                            ? "Enviando auditoria..."
                            : "Auditoria fornecimento (tabela completa)",
                      ),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // ✅ LOG
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.black12),
                ),
                child: _log.isEmpty
                    ? const Center(
                        child: Text(
                          "Sem log ainda.",
                          style: TextStyle(color: Colors.black45),
                        ),
                      )
                    : ListView.separated(
                        itemCount: _log.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 10, color: Colors.black12),
                        itemBuilder: (_, i) => SelectableText(
                          _log[i],
                          style: const TextStyle(
                            color: Colors.black87,
                            fontSize: 12,
                          ),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PendenciasLista extends StatelessWidget {
  const _PendenciasLista({required this.registros});

  final List<SyncPendenciaRegistro> registros;

  IconData _icon(SyncPendenciaTipo tipo) {
    switch (tipo) {
      case SyncPendenciaTipo.gravaTag:
        return Icons.nfc_outlined;
      case SyncPendenciaTipo.fabricacao:
        return Icons.factory_outlined;
      case SyncPendenciaTipo.fornecimento:
        return Icons.local_shipping_outlined;
    }
  }

  Color _accent(SyncPendenciaTipo tipo) {
    switch (tipo) {
      case SyncPendenciaTipo.gravaTag:
        return Colors.indigo.shade800;
      case SyncPendenciaTipo.fabricacao:
        return Colors.deepOrange.shade800;
      case SyncPendenciaTipo.fornecimento:
        return Colors.teal.shade800;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black12),
        color: Colors.orange.withValues(alpha: 0.04),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Text(
              "Registros pendentes (${registros.length})",
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 14,
              ),
            ),
          ),
          const Divider(height: 1, color: Colors.black12),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              itemCount: registros.length,
              separatorBuilder: (_, __) => const Divider(
                height: 8,
                color: Colors.black12,
              ),
              itemBuilder: (_, i) {
                final r = registros[i];
                final accent = _accent(r.tipo);
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(_icon(r.tipo), size: 18, color: accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            r.titulo,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            "${r.tipoLabel} · ${r.subtitulo}",
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.black.withValues(alpha: 0.62),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PendingCard extends StatelessWidget {
  const _PendingCard({
    required this.title,
    required this.subtitle,
    required this.count,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final int count;
  final IconData icon;

  Color _bg() {
    if (count <= 0) return Colors.green.withValues(alpha: 0.10);
    if (count < 10) return Colors.amber.withValues(alpha: 0.16);
    return Colors.red.withValues(alpha: 0.14);
  }

  Color _accent() {
    if (count <= 0) return Colors.green.shade800;
    if (count < 10) return Colors.amber.shade900;
    return Colors.red.shade800;
  }

  @override
  Widget build(BuildContext context) {
    final accent = _accent();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black12),
        color: _bg(),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                    )),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.black.withValues(alpha: 0.60),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            count.toString(),
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }
}
