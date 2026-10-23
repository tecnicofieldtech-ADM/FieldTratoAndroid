import "../constants/config_options.dart";
import "../db/app_db.dart";
import "../features/fabricacao/domain/fabricacao_flow.dart";
import "../repo/config_repo.dart";
import "api_service.dart";
import "bootstrap_sync.dart";
import "outbox_sync.dart";

enum SyncMode {
  /// Só GET: usuarios, baias, dietas, detalhes, previsao.
  downloadOnly,

  /// Só POST: TAG, fabricacao, fornecimento.
  uploadOnly,

  /// Baixa cadastros, envia pendencias e baixa previsao.
  full,
}

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
    SyncMode mode = SyncMode.full,
  }) async {
    final cfg = await cfgRepo.getConfig();
    if (cfg == null) {
      throw Exception("Config nao encontrada.");
    }

    final baseUrl = cfgRepo.buildBaseUrl(cfg);
    if (baseUrl.isEmpty) throw Exception("HOST/PORTA invalidos.");

    final backend = int.tryParse((cfg["BACKEND"] ?? "0").toString()) ?? 0;
    final idFazenda = (cfg["ID_FAZENDA"] ?? "").toString().trim();
    if (idFazenda.isEmpty && !ConfigOptions.ignoresFazendaId(backend)) {
      throw Exception("ID_FAZENDA vazio (selecione e confirme).");
    }

    final idVagao = (cfg["ID_VAGAO"] ?? "").toString().trim();
    final tipoTrabalho = int.tryParse((cfg["TIPO_TRABALHO"] ?? "0").toString()) ?? 0;
    final flowMode = fabricacaoFlowModeFromDb(cfg["FLOW_MODE"]);

    final api = ApiService(
      baseUrl: baseUrl,
      backend: backend,
      clientCode: cfgRepo.clienteCodigoFromCfg(cfg),
    );
    final outbox = OutboxSync(api: api);

    final today = _todayYmd();
    final pendingDates = await _pendingFornecimentoDates(today);
    final wantDownload =
        mode == SyncMode.downloadOnly || mode == SyncMode.full;
    final wantUpload = mode == SyncMode.uploadOnly || mode == SyncMode.full;

    final steps = <SyncStep>[
      SyncStep(
        title: "Testando servidor...",
        run: () async {
          final meta = await api.getTesteMeta();
          if (meta["ok"] != true) throw Exception("Servidor indisponivel.");
          log("Servidor online");
          final backendName =
              ConfigOptions.backends[backend] ?? "Backend $backend";
          log("Backend app: $backendName");
          final importacaoId =
              (meta["importacao_id"] ?? "").toString().trim();
          if (ConfigOptions.isPlanilhaBackend(backend) &&
              importacaoId.isNotEmpty) {
            await cfgRepo.setImportacaoId(importacaoId);
            log("Importacao ativa: $importacaoId");
          }
          if (!ConfigOptions.isTgcBackend(backend) &&
              !ConfigOptions.isPlanilhaBackend(backend)) {
            log(
              "AVISO: cliente TGC deve usar Config > Backend = "
              "'Outros (TGC)'. Com FieldPec a ordem da sync e o "
              "fornecimento ficam incorretos.",
            );
          }
        },
      ),
    ];

    // Dietas ANTES do outbox no modo full: fornecimento/fab exigem DIETA.MS.
    if (wantDownload) {
      steps.addAll([
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
      ]);
    }

    if (wantUpload) {
      steps.add(
        SyncStep(title: "Sincronizando TAGs", run: () => outbox.syncGravaTag(log)),
      );
      if (ConfigOptions.usesFieldPecSyncOrder(backend)) {
        steps.addAll([
          SyncStep(
            title: "Sincronizando Fornecimento",
            run: () => outbox.syncFornecimento(log),
          ),
          SyncStep(
            title: "Sincronizando Fabrica Racao",
            run: () => outbox.syncFabricacao(
              log,
              idVagao,
              idFazendaCfg: idFazenda,
              flowMode: flowMode,
              tipoTrabalho: tipoTrabalho,
            ),
          ),
        ]);
      } else {
        // TGC e demais: fab antes de fornecimento.
        steps.addAll([
          SyncStep(
            title: "Sincronizando Fabrica Racao",
            run: () => outbox.syncFabricacao(
              log,
              idVagao,
              idFazendaCfg: idFazenda,
              flowMode: flowMode,
              tipoTrabalho: tipoTrabalho,
            ),
          ),
          SyncStep(
            title: "Sincronizando Fornecimento",
            run: () => outbox.syncFornecimento(log),
          ),
        ]);
      }
    }

    if (wantDownload) {
      steps.addAll([
        SyncStep(
          title: "Baixando Previsao de Trato (pendentes)",
          run: () async {
            if (pendingDates.isEmpty) {
              log("Nenhuma data pendente de fornecimento para baixar previsao.");
              return;
            }
            for (final d in pendingDates) {
              log("Baixando previsao do dia $d (fornecimento pendente)...");
              await bootstrap.baixarPrevisaoTrato(
                cfg,
                idFazenda,
                d,
                log: log,
              );
            }
          },
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
      ]);
    }

    return steps;
  }

  /// Datas com fornecimento local ainda nao sincronizado (exceto hoje).
  static Future<List<String>> _pendingFornecimentoDates(String todayYmd) async {
    final db = await AppDb.instance.db;
    final rows = await db.rawQuery("""
      SELECT DISTINCT substr(COALESCE(DATA, ''), 1, 10) AS d
      FROM CADASTRO_FORNECIMENTO
      WHERE COALESCE(REALIZADO, 0) > 0
        AND IFNULL(FLAG_SYNC, 0) = 0
        AND length(substr(COALESCE(DATA, ''), 1, 10)) = 10
      ORDER BY d
    """);

    final out = <String>[];
    for (final r in rows) {
      final d = (r["d"] ?? "").toString().trim();
      if (d.isEmpty || d == todayYmd) continue;
      out.add(d);
    }
    return out;
  }

  static String _todayYmd() {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, "0");
    final m = now.month.toString().padLeft(2, "0");
    final d = now.day.toString().padLeft(2, "0");
    return "$y-$m-$d";
  }
}
