import "../constants/config_options.dart";
import "../repo/config_repo.dart";

/// Congela a carga Planilha no momento da criação da operação.
/// A outbox NÃO deve reler CONFIG.IMPORTACAO_ID na hora do POST.
class PlanilhaImportacao {
  /// Carga ativa no CONFIG, somente se BACKEND=3.
  static String? freezeFromConfig({
    required int? backend,
    required String? configImportacaoId,
  }) {
    final b = ConfigOptions.normalizeBackend(backend);
    if (!ConfigOptions.isPlanilhaBackend(b)) return null;
    final id = (configImportacaoId ?? "").trim();
    return id.isEmpty ? null : id;
  }

  /// Carga gravada no registro local, para montar o POST Planilha.
  static String? forOutbox({
    required int backend,
    required String? registroImportacaoId,
  }) {
    if (!ConfigOptions.isPlanilhaBackend(backend)) return null;
    final id = (registroImportacaoId ?? "").trim();
    return id.isEmpty ? null : id;
  }

  static Future<String?> freezeFromDb() async {
    final cfg = await ConfigRepo().getConfig();
    if (cfg == null) return null;
    final backend = int.tryParse((cfg["BACKEND"] ?? "0").toString()) ?? 0;
    return freezeFromConfig(
      backend: backend,
      configImportacaoId: (cfg["IMPORTACAO_ID"] ?? "").toString(),
    );
  }
}
