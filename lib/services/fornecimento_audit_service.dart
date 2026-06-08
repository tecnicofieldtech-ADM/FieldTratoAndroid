import "../features/fornecimento/data/fornecimento_dao.dart";
import "../repo/config_repo.dart";
import "api_service.dart";

class FornecimentoAuditService {
  final ConfigRepo cfgRepo;
  final FornecimentoDao dao;

  FornecimentoAuditService({
    ConfigRepo? cfgRepo,
    FornecimentoDao? dao,
  })  : cfgRepo = cfgRepo ?? ConfigRepo(),
        dao = dao ?? FornecimentoDao();

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
    final rows = await dao.listAllCadastroForAudit();
    return {
      "device_id": await _deviceId(),
      "exported_at": DateTime.now().toIso8601String(),
      "origem": "CADASTRO_FORNECIMENTO",
      "total": rows.length,
      "registros": rows,
    };
  }

  Future<Map<String, dynamic>> enviarAuditoriaCompleta({
    void Function(String)? log,
  }) async {
    final payload = await buildPayload();
    final total = payload["total"] as int? ?? 0;
    log?.call("Auditoria fornecimento: $total registro(s) no tablet.");

    final api = await _api();
    final resp = await api.postFornecimentoAudit(payload, log: log);
    if (resp == null) {
      throw Exception("Falha ao enviar auditoria para a API.");
    }
    return resp;
  }
}
