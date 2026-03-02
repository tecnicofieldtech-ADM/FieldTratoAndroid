import "fabricacao_flow.dart";

// lib/features/fabricacao/domain/models.dart

class Dieta {
  final String id;
  final String nome;

  Dieta({required this.id, required this.nome});

  factory Dieta.fromMap(Map<String, Object?> m) => Dieta(
        id: (m['id'] ?? m['ID'] ?? '').toString(),
        nome: (m['nome'] ?? m['NOME'] ?? '').toString(),
      );
}

class FabIngrediente {
  final String idDet;
  final String idInsumo;
  final String insumoNome;

  final int ordem;
  final int previstoKg;
  final int realizadoKg;

  /// 0/1
  final int prePesado;

  FabIngrediente({
    required this.idDet,
    required this.idInsumo,
    required this.insumoNome,
    required this.ordem,
    required this.previstoKg,
    required this.realizadoKg,
    required this.prePesado,
  });

  bool get isPrePesado => prePesado == 1;

  FabIngrediente copyWith({int? realizadoKg}) {
    return FabIngrediente(
      idDet: idDet,
      idInsumo: idInsumo,
      insumoNome: insumoNome,
      ordem: ordem,
      previstoKg: previstoKg,
      realizadoKg: realizadoKg ?? this.realizadoKg,
      prePesado: prePesado,
    );
  }

  /// ✅ Aceita ORDEM (correto) e também ORDERM (legado) se existir
  factory FabIngrediente.fromMap(Map<String, Object?> m) => FabIngrediente(
        idDet: (m['id'] ?? m['ID'] ?? '').toString(),
        idInsumo: (m['id_insumo'] ?? m['ID_INSUMO'] ?? '').toString(),
        insumoNome: (m['insumo_nome'] ??
                m['INSUMO_NOME'] ??
                m['insumo'] ??
                m['INSUMO'] ??
                '')
            .toString(),
        ordem: _toInt(m['ordem'] ?? m['ORDEM'] ?? m['orderm'] ?? m['ORDERM']),
        previstoKg: _toInt(m['qtd_prevista'] ?? m['QTD_PREVISTA']),
        realizadoKg: _toInt(m['qtd_realizada'] ?? m['QTD_REALIZADA']),
        prePesado: _toInt(m['pre_pesado'] ?? m['PRE_PESADO']),
      );
}

class FabricacaoHeader {
  final String id;
  final String idDieta;
  final String dietaNome;

  final int trato;

  final double qtdPrevista;
  final double qtdRealizada;

  /// 0/1
  final int finalizada;
  final FabricacaoStatus status;
  final String handoffId;
  final String exportadoEm;
  final String originDevice;

  /// 0/1
  final int carregada;

  /// string (ISO) salva no banco
  final String dataFabricacao;

  FabricacaoHeader({
    required this.id,
    required this.idDieta,
    required this.dietaNome,
    required this.trato,
    required this.qtdPrevista,
    required this.qtdRealizada,
    required this.finalizada,
    required this.status,
    required this.handoffId,
    required this.exportadoEm,
    required this.originDevice,
    required this.carregada,
    required this.dataFabricacao,
  });

  factory FabricacaoHeader.fromMap(Map<String, Object?> m) => FabricacaoHeader(
        id: (m['id'] ?? m['ID'] ?? '').toString(),
        idDieta: (m['id_dieta'] ?? m['ID_DIETA'] ?? '').toString(),
        dietaNome: (m['dieta_nome'] ??
                m['DIETA_NOME'] ??
                m['dieta'] ??
                m['DIETA'] ??
                '')
            .toString(),
        trato: _toInt(m['trato'] ?? m['TRATO']),
        qtdPrevista: _toDouble(m['qtd_prevista'] ?? m['QTD_PREVISTA']),
        qtdRealizada: _toDouble(m['qtd_realizada'] ?? m['QTD_REALIZADA']),
        finalizada: _toInt(m['finalizada'] ?? m['FINALIZADA']),
        status: fabricacaoStatusFromDb(m["fab_status"] ?? m["FAB_STATUS"]),
        handoffId: (m["handoff_id"] ?? m["HANDOFF_ID"] ?? "").toString(),
        exportadoEm: (m["exportado_em"] ?? m["EXPORTADO_EM"] ?? "").toString(),
        originDevice:
            (m["origin_device"] ?? m["ORIGIN_DEVICE"] ?? "").toString(),
        carregada: _toInt(m['carregada'] ?? m['CARREGADA']),
        dataFabricacao: (m['data_fabricacao'] ??
                m['DATA_FABRICACAO'] ??
                m['data'] ??
                m['DATA'] ??
                '')
            .toString(),
      );

  bool get emAberto => finalizada == 0;
  bool get pendenteCaminhao => status == FabricacaoStatus.pendenteCaminhao;
  bool get finalizadaFlow => status == FabricacaoStatus.finalizada;
  bool get bloqueadaEdicaoEstacionario => pendenteCaminhao;

  /// ✅ usado no ListTile
  String get dataLabel {
    // tenta parsear "YYYY-MM-DD..." / ISO
    final s = dataFabricacao.trim();
    if (s.isEmpty) return '';
    try {
      final d = DateTime.parse(s);
      String dd(int v) => v.toString().padLeft(2, '0');
      final yy = (d.year % 100).toString().padLeft(2, '0');
      return '${dd(d.day)}-${dd(d.month)}-$yy';
    } catch (_) {
      return s;
    }
  }

  // =========================================================
  // ✅ copyWith (necessário para finalização correta)
  // =========================================================
  FabricacaoHeader copyWith({
    double? qtdPrevista,
    double? qtdRealizada,
    int? finalizada,
    FabricacaoStatus? status,
    String? handoffId,
    String? exportadoEm,
    String? originDevice,
    int? carregada,
  }) {
    return FabricacaoHeader(
      id: id,
      idDieta: idDieta,
      dietaNome: dietaNome,
      trato: trato,
      qtdPrevista: qtdPrevista ?? this.qtdPrevista,
      qtdRealizada: qtdRealizada ?? this.qtdRealizada,
      finalizada: finalizada ?? this.finalizada,
      status: status ?? this.status,
      handoffId: handoffId ?? this.handoffId,
      exportadoEm: exportadoEm ?? this.exportadoEm,
      originDevice: originDevice ?? this.originDevice,
      carregada: carregada ?? this.carregada,
      dataFabricacao: dataFabricacao,
    );
  }
}

// =========================
// helpers
// =========================
int _toInt(Object? v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? 0;
}

double _toDouble(Object? v) {
  if (v == null) return 0.0;
  if (v is double) return v;
  if (v is int) return v.toDouble();
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString().replaceAll(",", ".")) ?? 0.0;
}


