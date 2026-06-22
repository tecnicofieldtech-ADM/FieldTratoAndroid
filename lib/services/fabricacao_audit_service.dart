import "../features/fabricacao/data/fabricacao_repo.dart";
import "../repo/config_repo.dart";
import "api_service.dart";

class FabricacaoAuditService {
  final ConfigRepo cfgRepo;
  final FabricacaoRepo repo;

  FabricacaoAuditService({
    ConfigRepo? cfgRepo,
    FabricacaoRepo? repo,
  })  : cfgRepo = cfgRepo ?? ConfigRepo(),
        repo = repo ?? FabricacaoRepo();

  Future<ApiService> _api() async {
    final cfg = await cfgRepo.getConfig();
    if (cfg == null) {
      throw Exception("CONFIG nao encontrada.");
    }
    final base = cfgRepo.buildBaseUrl(cfg);
    if (base.isEmpty) {
      throw Exception("HOST/PORTA da API invalidos.");
    }
    final backend = int.tryParse((cfg["BACKEND"] ?? "0").toString()) ?? 0;
    return ApiService(baseUrl: base, backend: backend);
  }

  Future<String> _deviceId() async {
    final nome = (await cfgRepo.getNomeVagao()).trim();
    if (nome.isNotEmpty) return nome;

    final id = (await cfgRepo.getIdVagao()).trim();
    if (id.isNotEmpty) return id;

    return "tablet";
  }

  Future<Map<String, dynamic>> buildPayload() async {
    final rows = await repo.listAllForAudit();
    var pendentesSync = 0;
    var pendentesComRealizado = 0;

    for (final r in rows) {
      final sync = (r["flag_sync"] ?? 0).toString() == "1";
      final real = _toDouble(r["qtd_realizada"]);
      if (!sync && real > 0) pendentesComRealizado++;
      if (!sync) pendentesSync++;
    }

    return {
      "device_id": await _deviceId(),
      "exported_at": DateTime.now().toIso8601String(),
      "origem": "CADASTRO_FABRICA_RACAO",
      "total": rows.length,
      "pendentes_sync": pendentesSync,
      "pendentes_com_realizado": pendentesComRealizado,
      "registros": rows,
    };
  }

  double _toDouble(Object? v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().replaceAll(",", ".")) ?? 0;
  }

  Future<Map<String, dynamic>> enviarAuditoriaCompleta({
    void Function(String)? log,
  }) async {
    final payload = await buildPayload();
    final total = payload["total"] as int? ?? 0;
    final pend = payload["pendentes_com_realizado"] as int? ?? 0;
    log?.call(
      "Auditoria fabricacao: $total registro(s); $pend nao sincronizado(s) com peso.",
    );

    final api = await _api();
    final resp = await api.postFabricacaoAudit(payload, log: log);
    if (resp == null) {
      throw Exception("Falha ao enviar auditoria para a API.");
    }
    return resp;
  }
}
