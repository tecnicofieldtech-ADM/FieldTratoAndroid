import "package:flutter/material.dart";
import "../repo/config_repo.dart";
import "../repo/vagao_repo.dart";
import "../repo/fazenda_repo.dart";
import "../repo/user_repo.dart";
import "../services/bootstrap_sync.dart";
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

  bool _running = false;
  int _currentIndex = -1;
  String _currentTitle = "";
  List<SyncStep> _steps = [];
  final List<String> _log = [];

  void _addLog(String msg) {
    final hhmmss = DateTime.now().toIso8601String().substring(11, 19);
    setState(() => _log.insert(0, "$hhmmss - $msg"));
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  double get _progress {
    if (_steps.isEmpty) return 0;
    if (_currentIndex < 0) return 0;
    final done = (_currentIndex + 1).clamp(0, _steps.length);
    return done / _steps.length;
  }

  Future<void> _runSync() async {
    if (_running) return;

    // ✅ Guard: só bloqueia se SSID começar com RFeed
    final ssid = await WifiGuard.getCurrentSsid();

    if (WifiGuard.isBlockedSsid(ssid)) {
      if (!mounted) return;

      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text("Atenção"),
          content: const Text(
            "Conecte-se à rede Wi-Fi do servidor de dados (não RFeed*) e volte a este botão para sincronizar.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("OK"),
            )
          ],
        ),
      );

      return; // ✅ não continua a sincronização
    }

    setState(() {
      _running = true;
      _currentIndex = -1;
      _currentTitle = "";
      _log.clear();
      _steps = [];
    });

    try {
      _addLog("SSID: ${ssid.isEmpty ? "(não detectado)" : ssid}");
      _addLog("Preparando etapas...");

      _steps = await _orchestrator.buildSteps(log: _addLog);
      _addLog("Total de etapas: ${_steps.length}");

      for (int i = 0; i < _steps.length; i++) {
        final step = _steps[i];
        setState(() {
          _currentIndex = i;
          _currentTitle = step.title;
        });

        _addLog("▶ ${step.title}");
        await step.run();
        _addLog("✅ OK: ${step.title}");
        await Future.delayed(const Duration(milliseconds: 100));
      }

      _toast("Sincronização concluída.");
    } catch (e) {
      _addLog("❌ ERRO: $e");
      _toast("Falha: $e");
    } finally {
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
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Card status / botão
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

            // Card Log
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
                        itemBuilder: (_, i) => Text(
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
