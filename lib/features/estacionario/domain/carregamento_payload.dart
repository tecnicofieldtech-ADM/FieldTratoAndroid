import "../../fabricacao/domain/fabricacao_flow.dart";
import "station_handoff_mode.dart";

class CarregamentoResumoDto {
  CarregamentoResumoDto({
    required this.idLocal,
    required this.handoffId,
    required this.data,
    required this.hora,
    required this.nomeRacao,
    required this.totalFabricadoKg,
    required this.statusApi,
    this.claimStatus = "available",
    this.claimExpiresAt = "",
    this.handoffModeApi = "",
    this.finalizada = false,
  });

  final String idLocal;
  final String handoffId;
  final String data;
  final String hora;
  final String nomeRacao;
  final double totalFabricadoKg;
  final String statusApi;
  final String claimStatus;
  final String claimExpiresAt;
  final String handoffModeApi;
  final bool finalizada;

  FabricacaoStatus get status => fabricacaoStatusFromApi(statusApi);

  StationHandoffMode? get handoffMode {
    final fromApi = stationHandoffModeFromApi(handoffModeApi);
    if (fromApi != null) return fromApi;
    return resolveStationHandoffMode(
      fabStatus: fabricacaoStatusToDb(status),
      finalizada: finalizada ? 1 : 0,
    );
  }

  bool get isAvailable =>
      claimStatus == "available" || claimStatus.trim().isEmpty;

  bool get isClaimedByMe => claimStatus == "claimedByMe";

  bool get isClaimedByOther => claimStatus == "claimed";

  bool get isFabricationComplete =>
      handoffMode == StationHandoffMode.fabricationComplete;

  factory CarregamentoResumoDto.fromJson(Map<String, dynamic> j) {
    return CarregamentoResumoDto(
      idLocal: (j["idLocal"] ?? j["id_local"] ?? j["id"] ?? "").toString(),
      handoffId: (j["handoffId"] ?? j["handoff_id"] ?? "").toString(),
      data: (j["data"] ?? "").toString(),
      hora: (j["hora"] ?? "").toString(),
      nomeRacao: (j["nome_racao"] ?? "").toString(),
      totalFabricadoKg: _toDouble(j["total_fabricado_kg"]),
      statusApi: (j["status"] ?? "EM_ANDAMENTO").toString(),
      claimStatus: (j["claimStatus"] ?? j["claim_status"] ?? "available")
          .toString(),
      claimExpiresAt:
          (j["claimExpiresAt"] ?? j["claim_expires_at"] ?? "").toString(),
      handoffModeApi:
          (j["handoffMode"] ?? j["handoff_mode"] ?? "").toString(),
      finalizada: _toBool(j["finalizada"]),
    );
  }
}

class FabricacaoPayloadDto {
  FabricacaoPayloadDto({
    required this.idOrigem,
    required this.handoffId,
    required this.statusApi,
    required this.data,
    required this.horaInicio,
    required this.horaFim,
    required this.idRacao,
    required this.nomeRacao,
    required this.totalPrevistoKg,
    required this.totalRealizadoKg,
    required this.observacao,
    required this.finalizada,
    this.handoffModeApi = "",
  });

  final String idOrigem;
  final String handoffId;
  final String statusApi;
  final String data;
  final String horaInicio;
  final String horaFim;
  final String idRacao;
  final String nomeRacao;
  final double totalPrevistoKg;
  final double totalRealizadoKg;
  final String observacao;
  final bool finalizada;
  final String handoffModeApi;

  FabricacaoStatus get status => fabricacaoStatusFromApi(statusApi);

  StationHandoffMode? get handoffMode {
    final fromApi = stationHandoffModeFromApi(handoffModeApi);
    if (fromApi != null) return fromApi;
    return resolveStationHandoffMode(
      fabStatus: fabricacaoStatusToDb(status),
      finalizada: finalizada ? 1 : 0,
    );
  }

  factory FabricacaoPayloadDto.fromJson(Map<String, dynamic> j) {
    return FabricacaoPayloadDto(
      idOrigem: (j["id_origem"] ?? "").toString(),
      handoffId: (j["handoff_id"] ?? "").toString(),
      statusApi: (j["status"] ?? "EM_ANDAMENTO").toString(),
      data: (j["data"] ?? "").toString(),
      horaInicio: (j["hora_inicio"] ?? "").toString(),
      horaFim: (j["hora_fim"] ?? "").toString(),
      idRacao: (j["id_racao"] ?? "").toString(),
      nomeRacao: (j["nome_racao"] ?? "").toString(),
      totalPrevistoKg: _toDouble(j["total_previsto_kg"]),
      totalRealizadoKg: _toDouble(j["total_realizado_kg"]),
      observacao: (j["observacao"] ?? "").toString(),
      finalizada: _toBool(j["finalizada"]),
      handoffModeApi: (j["handoff_mode"] ?? j["handoffMode"] ?? "").toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        "id_origem": idOrigem,
        "handoff_id": handoffId,
        "status": statusApi,
        "data": data,
        "hora_inicio": horaInicio,
        "hora_fim": horaFim,
        "id_racao": idRacao,
        "nome_racao": nomeRacao,
        "total_previsto_kg": totalPrevistoKg,
        "total_realizado_kg": totalRealizadoKg,
        "observacao": observacao,
        "finalizada": finalizada,
        "handoff_mode": handoffModeApi,
      };
}

class InsumoPayloadDto {
  InsumoPayloadDto({
    required this.idInsumo,
    required this.nomeInsumo,
    required this.previstoKg,
    required this.realizadoKg,
    required this.ordem,
  });

  final String idInsumo;
  final String nomeInsumo;
  final double previstoKg;
  final double realizadoKg;
  final int ordem;

  factory InsumoPayloadDto.fromJson(Map<String, dynamic> j) {
    return InsumoPayloadDto(
      idInsumo: (j["id_insumo"] ?? "").toString(),
      nomeInsumo: (j["nome_insumo"] ?? "").toString(),
      previstoKg: _toDouble(j["previsto_kg"]),
      realizadoKg: _toDouble(j["realizado_kg"]),
      ordem: _toInt(j["ordem"]),
    );
  }

  Map<String, dynamic> toJson() => {
        "id_insumo": idInsumo,
        "nome_insumo": nomeInsumo,
        "previsto_kg": previstoKg,
        "realizado_kg": realizadoKg,
        "ordem": ordem,
      };
}

class CarregamentoMetaDto {
  CarregamentoMetaDto({
    required this.origem,
    required this.versaoPayload,
  });

  final String origem;
  final int versaoPayload;

  factory CarregamentoMetaDto.fromJson(Map<String, dynamic> j) {
    return CarregamentoMetaDto(
      origem: (j["origem"] ?? "ESTACIONARIO").toString(),
      versaoPayload: _toInt(j["versao_payload"], def: 1),
    );
  }

  Map<String, dynamic> toJson() => {
        "origem": origem,
        "versao_payload": versaoPayload,
      };
}

class CarregamentoDetalheDto {
  CarregamentoDetalheDto({
    required this.fabricacao,
    required this.insumos,
    required this.meta,
  });

  final FabricacaoPayloadDto fabricacao;
  final List<InsumoPayloadDto> insumos;
  final CarregamentoMetaDto meta;

  factory CarregamentoDetalheDto.fromJson(Map<String, dynamic> j) {
    final fab = Map<String, dynamic>.from((j["fabricacao"] ?? const {}) as Map);
    final insumosRaw = (j["insumos"] as List?) ?? const [];
    final meta = Map<String, dynamic>.from((j["meta"] ?? const {}) as Map);

    // Preferir handoffMode do meta se fabricacao não trouxe.
    if ((fab["handoff_mode"] ?? fab["handoffMode"] ?? "")
            .toString()
            .trim()
            .isEmpty &&
        (meta["handoffMode"] ?? meta["handoff_mode"] ?? "")
            .toString()
            .trim()
            .isNotEmpty) {
      fab["handoff_mode"] = meta["handoffMode"] ?? meta["handoff_mode"];
    }

    return CarregamentoDetalheDto(
      fabricacao: FabricacaoPayloadDto.fromJson(fab),
      insumos: insumosRaw
          .whereType<Map>()
          .map((e) => InsumoPayloadDto.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      meta: CarregamentoMetaDto.fromJson(meta),
    );
  }

  Map<String, dynamic> toJson() => {
        "fabricacao": fabricacao.toJson(),
        "insumos": insumos.map((e) => e.toJson()).toList(),
        "meta": meta.toJson(),
      };
}

double _toDouble(Object? v) {
  if (v == null) return 0.0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString().replaceAll(",", ".")) ?? 0.0;
}

int _toInt(Object? v, {int def = 0}) {
  if (v == null) return def;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? def;
}

bool _toBool(Object? v) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  final s = (v ?? "").toString().trim().toLowerCase();
  return s == "1" || s == "true" || s == "sim" || s == "yes";
}
