enum FabricacaoFlowMode {
  fullOnStation,
  startStationFinishTruck,
}

enum FabricacaoStatus {
  emAndamento,
  pendenteCaminhao,
  finalizada,
}

const int fabricacaoStatusEmAndamento = 0;
const int fabricacaoStatusPendenteCaminhao = 1;
const int fabricacaoStatusFinalizada = 2;

int fabricacaoFlowModeToDb(FabricacaoFlowMode mode) {
  switch (mode) {
    case FabricacaoFlowMode.startStationFinishTruck:
      return 1;
    case FabricacaoFlowMode.fullOnStation:
      return 0;
  }
}

FabricacaoFlowMode fabricacaoFlowModeFromDb(Object? v) {
  final n = _toInt(v);
  if (n == 1) return FabricacaoFlowMode.startStationFinishTruck;
  return FabricacaoFlowMode.fullOnStation;
}

int fabricacaoStatusToDb(FabricacaoStatus status) {
  switch (status) {
    case FabricacaoStatus.pendenteCaminhao:
      return fabricacaoStatusPendenteCaminhao;
    case FabricacaoStatus.finalizada:
      return fabricacaoStatusFinalizada;
    case FabricacaoStatus.emAndamento:
      return fabricacaoStatusEmAndamento;
  }
}

FabricacaoStatus fabricacaoStatusFromDb(Object? v) {
  final n = _toInt(v);
  if (n == fabricacaoStatusPendenteCaminhao) {
    return FabricacaoStatus.pendenteCaminhao;
  }
  if (n == fabricacaoStatusFinalizada) return FabricacaoStatus.finalizada;
  return FabricacaoStatus.emAndamento;
}

String fabricacaoStatusToApi(FabricacaoStatus status) {
  switch (status) {
    case FabricacaoStatus.pendenteCaminhao:
      return "PENDENTE_CAMINHAO";
    case FabricacaoStatus.finalizada:
      return "FINALIZADA";
    case FabricacaoStatus.emAndamento:
      return "EM_ANDAMENTO";
  }
}

FabricacaoStatus fabricacaoStatusFromApi(String raw) {
  final v = raw.trim().toUpperCase();
  if (v == "PENDENTE_CAMINHAO") return FabricacaoStatus.pendenteCaminhao;
  if (v == "FINALIZADA") return FabricacaoStatus.finalizada;
  return FabricacaoStatus.emAndamento;
}

int _toInt(Object? v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? 0;
}
