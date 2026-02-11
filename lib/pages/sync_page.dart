import "dart:async";

import "package:flutter/material.dart";

import "../repo/config_repo.dart";
import "../repo/vagao_repo.dart";
import "../repo/fazenda_repo.dart";
import "../repo/user_repo.dart";
import "../services/bootstrap_sync.dart";
import "../services/sync_orchestrator.dart";

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

  bool _running = false;
  int _currentIndex = -1;
  String _currentTitle = "";
  List<SyncStep> _steps = [];
  final List<String> _log = [];

  // ✅ pendências (cards)
  int _pendFab = 0;
  int _pendFor = 0;
  bool _loadingPend = false;

  @override
  void initState() {
    super.initState();
    // carrega pendências ao abrir
    // ignore: unawaited_futures
    _loadPendencias();
  }

  Future<void> _loadPendencias() async {
    if (_loadingPend) return;
    setState(() => _loadingPend = true);

    try {
      final fab = await _cfgRepo.countFabricacaoPendenteSync();
      final forn = await _cfgRepo.countFornecimentoPendenteSync();

      if (!mounted) return;
      setState(() {
        _pendFab = fab;
        _pendFor = forn;
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

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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

  Future<void> _runSync() async {
    if (_running) return;

    setState(() {
      _running = true;
      _currentIndex = -1;
      _currentTitle = "";
      _log.clear();
      _steps = [];
    });

    final swAll = Stopwatch()..start();

    try {
      // ✅ antes de começar, atualiza cards
      await _loadPendencias();

      _addLog("Preparando etapas de sincronização...");
      _steps = await _orchestrator.buildSteps(log: _addLog);
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
      _addLog("🏁 FIM: sincronização concluída em ${_fmtMs(swAll.elapsedMilliseconds)}");
      _toast("Sincronização concluída com sucesso.");
    } catch (e, st) {
      swAll.stop();
      _addLog("❌ FALHA GERAL: $e");
      _addLog("🧠 Stack: ${st.toString().split("\n").take(6).join(" | ")}");
      _toast("Falha na sincronização.");
    } finally {
      // ✅ depois da sync, atualiza cards de novo (muito importante)
      await _loadPendencias();

      if (mounted) {
        setState(() {
          _running = false;
          _currentTitle = "Pronto";
        });
      }
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
          IconButton(
            tooltip: "Atualizar pendências",
            onPressed: _running ? null : _loadPendencias,
            icon: _loadingPend
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: "Limpar log",
            onPressed: _running ? null : () => setState(() => _log.clear()),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // ✅ CARDS DE PENDÊNCIA
            Row(
              children: [
                Expanded(
                  child: _PendingCard(
                    title: "Fabricação",
                    subtitle: "pendente para enviar",
                    count: _pendFab,
                    icon: Icons.factory_outlined,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _PendingCard(
                    title: "Fornecimento",
                    subtitle: "pendente para enviar",
                    count: _pendFor,
                    icon: Icons.local_shipping_outlined,
                  ),
                ),
              ],
            ),

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
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _running ? null : _runSync,
                      icon: _running
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.sync),
                      label: Text(_running ? "Sincronizando..." : "Sincronizar Agora"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
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
