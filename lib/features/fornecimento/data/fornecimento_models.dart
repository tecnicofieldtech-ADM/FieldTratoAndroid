// lib/features/fornecimento/data/fornecimento_models.dart

/// Representa o previsto de fornecimento por curral
class CurralPrev {
  // IDs / identificação
  final String idBaia;
  final String nomeBaia;

  // dados de localização
  final String nomeLocal;
  final int linha;
  final String rfid;

  // ração / valores
  final String racaoNome;
  final double previstoKg;
  final double realizadoKg;

  // controle
  final int trato;
  final bool sincronizado;

  // extras (algumas telas/DAO usam)
  final String? idFornecimento;
  final String? idLote;
  final String? idDieta;
  final String? dataIso;
  final String? idRacao;

  CurralPrev({
    // ✅ NOVOS (opcionais para não quebrar DAO antigo)
    String? idBaia,
    String? nomeBaia,
    String? nomeLocal,
    int? linha,
    String? rfid,
    String? racaoNome,
    double? previstoKg,
    double? realizadoKg,
    int? trato,
    bool? sincronizado,

    // ✅ extras (opcionais)
    this.idFornecimento,
    this.idLote,
    this.idDieta,
    this.dataIso,
    this.idRacao,

    // ✅ NOMES ANTIGOS que seu DAO está usando
    String? idCurral,
    String? nome,
    int? linhaOld,
    String? racao,
    double? previsto,
    double? realizado,
    String? data,
    String? local,
    int? sync,
  })  : idBaia = (idBaia ?? idCurral ?? '').toString(),
        nomeBaia = (nomeBaia ?? nome ?? '').toString(),
        nomeLocal = (nomeLocal ?? local ?? '').toString(),
        linha = (linha ?? linhaOld ?? 0),
        rfid = (rfid ?? '').toString(),
        racaoNome = (racaoNome ?? racao ?? '').toString(),
        previstoKg = (previstoKg ?? previsto ?? 0).toDouble(),
        realizadoKg = (realizadoKg ?? realizado ?? 0).toDouble(),
        trato = (trato ?? 0),
        sincronizado = (sincronizado ?? ((sync ?? 0) == 1));

  /// ✅ para atualizar valores em memória sem mexer em `final`
  CurralPrev copyWith({
    String? idBaia,
    String? nomeBaia,
    String? nomeLocal,
    int? linha,
    String? rfid,
    String? racaoNome,
    double? previstoKg,
    double? realizadoKg,
    int? trato,
    bool? sincronizado,
    String? idFornecimento,
    String? idLote,
    String? idDieta,
    String? dataIso,
    String? idRacao,
  }) {
    return CurralPrev(
      idBaia: idBaia ?? this.idBaia,
      nomeBaia: nomeBaia ?? this.nomeBaia,
      nomeLocal: nomeLocal ?? this.nomeLocal,
      linha: linha ?? this.linha,
      rfid: rfid ?? this.rfid,
      racaoNome: racaoNome ?? this.racaoNome,
      previstoKg: previstoKg ?? this.previstoKg,
      realizadoKg: realizadoKg ?? this.realizadoKg,
      trato: trato ?? this.trato,
      sincronizado: sincronizado ?? this.sincronizado,
      idFornecimento: idFornecimento ?? this.idFornecimento,
      idLote: idLote ?? this.idLote,
      idDieta: idDieta ?? this.idDieta,
      dataIso: dataIso ?? this.dataIso,
      idRacao: idRacao ?? this.idRacao,
    );
  }

  // getters usados no card
  double get faltaKg {
    final f = previstoKg - realizadoKg;
    return f > 0 ? f : 0;
  }

  bool get concluido => faltaKg <= 0;

  bool get pendente => previstoKg > 0 && realizadoKg <= 0;

  bool get irregular =>
      realizadoKg > 0 && previstoKg > 0 && realizadoKg != previstoKg;

  // ✅ aliases p/ compatibilidade com código antigo
  String get idCurral => idBaia;
  String get nome => nomeBaia;
  String get racao => racaoNome;

  factory CurralPrev.fromMap(Map<String, dynamic> map) {
    double toD(Object? v) {
      if (v == null) return 0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString().replaceAll(",", ".")) ?? 0;
    }

    int toI(Object? v) {
      if (v == null) return 0;
      if (v is int) return v;
      return int.tryParse(v.toString()) ?? 0;
    }

    String toS(Object? v) => (v ?? "").toString();

    return CurralPrev(
      idBaia: toS(map['idBaia'] ?? map['idCurral'] ?? map['id_baia']),
      nomeBaia: toS(map['nomeBaia'] ?? map['nome'] ?? map['baia']),
      nomeLocal: toS(map['nomeLocal'] ?? map['local'] ?? map['nome_local']),
      linha: toI(map['linha'] ?? map['linhaOld'] ?? map['linha_local']),
      rfid: toS(map['rfid'] ?? map['tag'] ?? map['epc']),
      racaoNome: toS(map['racaoNome'] ?? map['racao'] ?? map['nomeRacao']),
      previstoKg: toD(map['previstoKg'] ?? map['previsto'] ?? map['previsto_kg']),
      realizadoKg: toD(map['realizadoKg'] ?? map['realizado'] ?? map['realizado_kg']),
      trato: toI(map['trato'] ?? map['orderTrato'] ?? map['ordem_trato']),
      sincronizado: toI(map['sync'] ?? map['sincronizado'] ?? map['flagSync']) == 1,
      idFornecimento: (map['idFornecimento'] ?? map['id_fornecimento'])?.toString(),
      idLote: (map['idLote'] ?? map['id_lote'])?.toString(),
      idDieta: (map['idDieta'] ?? map['id_dieta'])?.toString(),
      dataIso: (map['dataIso'] ?? map['data'] ?? map['data_iso'])?.toString(),
      idRacao: (map['idRacao'] ?? map['id_racao'])?.toString(),
    );
  }
}

/// Header simples do fornecimento (compatível com DAO antigo)
class FornecimentoHeader {
  final String id;
  final DateTime data;
  final int trato;
  final bool sincronizado;

  // extras comuns
  final String? dataIso;

  FornecimentoHeader({
    String? id,
    DateTime? data,
    int? trato,
    bool? sincronizado,
    this.dataIso,

    // ✅ nomes antigos que podem aparecer
    String? idCadastro,
    String? dataStr,
    int? sync,
  })  : id = (id ?? idCadastro ?? '').toString(),
        data = data ??
            (DateTime.tryParse((dataIso ?? dataStr ?? '').toString()) ??
                DateTime.now()),
        trato = (trato ?? 0),
        sincronizado = (sincronizado ?? ((sync ?? 0) == 1));

  factory FornecimentoHeader.fromMap(Map<String, dynamic> map) {
    final raw = (map['data'] ?? map['dataIso'] ?? map['data_iso'] ?? map['dataStr'] ?? '').toString();
    return FornecimentoHeader(
      id: (map['id'] ?? map['idCadastro'] ?? '').toString(),
      data: raw.isEmpty ? DateTime.now() : DateTime.parse(raw),
      trato: (map['trato'] ?? 0) as int,
      sincronizado: (map['sync'] ?? map['sincronizado'] ?? 0) == 1,
      dataIso: (map['dataIso'] ?? map['data_iso'])?.toString(),
    );
  }
}
