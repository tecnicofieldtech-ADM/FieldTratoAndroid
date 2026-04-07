import "../features/fabricacao/domain/fabricacao_flow.dart";
import "../repo/config_repo.dart";
import "api_service.dart";
import "bootstrap_sync.dart";
import "outbox_sync.dart";

class SyncStep {
  final String title;
  final Future<void> Function() run;
  SyncStep({required this.title, required this.run});
}

class SyncOrchestrator {
  final ConfigRepo cfgRepo;
  final BootstrapSync bootstrap;

  SyncOrchestrator({
    required this.cfgRepo,
    required this.bootstrap,
  });

  Future<List<SyncStep>> buildSteps({
    required void Function(String) log,
  }) async {
    final cfg = await cfgRepo.getConfig();
    if (cfg == null) {
      throw Exception("Config nao encontrada.");
    }

    final baseUrl = cfgRepo.buildBaseUrl(cfg);
    if (baseUrl.isEmpty) throw Exception("HOST/PORTA invalidos.");

    final idFazenda = (cfg["ID_FAZENDA"] ?? "").toString().trim();
    if (idFazenda.isEmpty) {
      throw Exception("ID_FAZENDA vazio (selecione e confirme).");
    }

    final idVagao = (cfg["ID_VAGAO"] ?? "").toString().trim();
    final tipoTrabalho = int.tryParse((cfg["TIPO_TRABALHO"] ?? "0").toString()) ?? 0;
    final backend = int.tryParse((cfg["BACKEND"] ?? "0").toString()) ?? 0;
    final flowMode = fabricacaoFlowModeFromDb(cfg["FLOW_MODE"]);

    final api = ApiService(baseUrl: baseUrl, backend: backend);
    final outbox = OutboxSync(api: api);

    final today = _todayYmd();

    return [
      SyncStep(
        title: "Testando servidor...",
        run: () async {
          final ok = await api.getTeste();
          if (!ok) throw Exception("Servidor indisponivel.");
          log("Servidor online");
        },
      ),
      SyncStep(title: "Sincronizando TAGs", run: () => outbox.syncGravaTag(log)),
      SyncStep(
        title: "Sincronizando Fabrica Racao",
        run: () => outbox.syncFabricacao(
          log,
          idVagao,
          flowMode: flowMode,
          tipoTrabalho: tipoTrabalho,
        ),
      ),
      SyncStep(
        title: "Sincronizando Fornecimento",
        run: () => outbox.syncFornecimento(log),
      ),
      SyncStep(
        title: "Baixando Usuarios",
        run: () => bootstrap.baixarUsuarios(cfg, idFazenda),
      ),
      SyncStep(
        title: "Baixando Baias",
        run: () => bootstrap.baixarBaias(cfg, idFazenda),
      ),
      SyncStep(
        title: "Baixando Dietas",
        run: () => bootstrap.baixarDietas(cfg, idFazenda),
      ),
      SyncStep(
        title: "Baixando Dietas Detalhes",
        run: () => bootstrap.baixarDietasDetalhes(cfg, idFazenda),
      ),
      SyncStep(
        title: "Baixando Previsao de Trato (hoje)",
        run: () => bootstrap.baixarPrevisaoTrato(
          cfg,
          idFazenda,
          today,
          log: log,
        ),
      ),
    ];
  }

  static String _todayYmd() {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, "0");
    final m = now.month.toString().padLeft(2, "0");
    final d = now.day.toString().padLeft(2, "0");
    return "$y-$m-$d";
  }
}
