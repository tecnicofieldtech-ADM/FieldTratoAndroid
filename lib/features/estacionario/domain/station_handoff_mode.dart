import "../../fabricacao/domain/fabricacao_flow.dart";

/// O que o vagão deve fazer depois de assumir a carga (não confundir com claim).
enum StationHandoffMode {
  /// Fabricação parcial na estação — continua ingredientes no vagão.
  continueFabrication,

  /// Fabricação já concluída na estação — só transferência física + fornecimento.
  fabricationComplete,
}

extension StationHandoffModeX on StationHandoffMode {
  String get apiValue {
    switch (this) {
      case StationHandoffMode.continueFabrication:
        return "CONTINUE_FABRICATION";
      case StationHandoffMode.fabricationComplete:
        return "FABRICATION_COMPLETE";
    }
  }

  String get uiLabel {
    switch (this) {
      case StationHandoffMode.continueFabrication:
        return "Continuar no vagão";
      case StationHandoffMode.fabricationComplete:
        return "Fabricação concluída";
    }
  }
}

/// Deriva handoffMode a partir dos campos reais da fabricação.
///
/// Retorna null se o estado for inconsistente ou não publicável.
StationHandoffMode? resolveStationHandoffMode({
  required Object? fabStatus,
  required Object? finalizada,
}) {
  final status = fabricacaoStatusFromDb(fabStatus);
  final fin = _toInt(finalizada);

  if (status == FabricacaoStatus.pendenteCaminhao && fin == 0) {
    return StationHandoffMode.continueFabrication;
  }
  if (status == FabricacaoStatus.finalizada && fin == 1) {
    return StationHandoffMode.fabricationComplete;
  }
  // Inconsistente (ex.: PENDENTE + FINALIZADA=1) → não publicar.
  return null;
}

StationHandoffMode? stationHandoffModeFromApi(String? raw) {
  final v = (raw ?? "").trim().toUpperCase();
  if (v == "CONTINUE_FABRICATION") {
    return StationHandoffMode.continueFabrication;
  }
  if (v == "FABRICATION_COMPLETE" ||
      v == "LOAD_READY" ||
      v == "READY_TO_DISTRIBUTE") {
    return StationHandoffMode.fabricationComplete;
  }
  return null;
}

int _toInt(Object? v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? 0;
}
