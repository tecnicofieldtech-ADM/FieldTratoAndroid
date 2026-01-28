// lib/features/fornecimento/domain/fornecimento_models.dart

enum ModeloBalanca { topcon, dinamica, alfa }

class CurralPrev {
  CurralPrev({
    required this.idBaia,
    required this.nomeLocal,
    required this.linha,
    required this.previstoKg,
    required this.realizadoKg,
    required this.trato,
    required this.data, // yyyy-mm-dd
    required this.idFornecimento,
    this.rfid,
    required this.idLote,
    this.idRacao,
  });

  final String idBaia;
  final String nomeLocal;
  final String linha;
  final double previstoKg;
  final double realizadoKg;
  final int trato;
  final String data;
  final String idFornecimento;
  final String? rfid;
  final String idLote;
  final String? idRacao;

  double get faltaKg => previstoKg - realizadoKg;
  bool get concluido => realizadoKg >= (previstoKg - 0.001);
}

class CurralSnapshot {
  CurralSnapshot({
    required this.idFornecimento,
    required this.idCurral,
    required this.nome,
    required this.linha,
    required this.idLote,
    required this.rfid,
    required this.previstoKg,
    required this.realizadoKg,
    this.idRacao,
  });

  final String idFornecimento;
  final String idCurral;
  final String nome;
  final String linha;
  final String idLote;
  final String rfid;
  final double previstoKg;
  final double realizadoKg;
  final String? idRacao;
}

class FornecimentoAberto {
  FornecimentoAberto({
    required this.id,
    required this.idFornecimento,
    required this.idFabricacao,
    required this.idBaia,
    required this.data,
    required this.trato,
    required this.previsto,
    required this.pesoInicio,
    this.horaInicio,
    required this.idUsuario,
    this.idDieta,
  });

  final String id;
  final String idFornecimento;
  final String idFabricacao;
  final String idBaia;
  final String data;
  final int trato;
  final double previsto;
  final double pesoInicio;
  final String? horaInicio;
  final String idUsuario;
  final String? idDieta;
}

class FornecimentoAbertoMini {
  FornecimentoAbertoMini({
    required this.idCadastro,
    required this.pesoInicio,
    required this.horaInicio,
    required this.previsto,
    required this.idUsuario,
    required this.idFabricacao,
  });

  final String idCadastro;
  final double pesoInicio;
  final String horaInicio;
  final double previsto;
  final String idUsuario;
  final String idFabricacao;
}

class FornecimentoRow {
  FornecimentoRow({
    required this.id,
    required this.idFornecimento,
    required this.idFabricacao,
    required this.idBaia,
    required this.data,
    required this.horaInicio,
    this.horaFim,
    required this.pesoInicio,
    required this.pesoFim,
    required this.previsto,
    this.realizado,
    required this.flagSync,
    required this.trato,
    required this.idUsuario,
    this.idDieta,
  });

  final String id;
  final String idFornecimento;
  final String idFabricacao;
  final String idBaia;
  final String data;
  final String horaInicio;
  final String? horaFim;
  final double pesoInicio;
  final double pesoFim;
  final double previsto;
  final double? realizado;
  final int flagSync;
  final int trato;
  final String idUsuario;
  final String? idDieta;

  factory FornecimentoRow.fromMap(Map<String, Object?> m) => FornecimentoRow(
        id: (m["ID"] ?? "").toString(),
        idFornecimento: (m["ID_FORNECIMENTO"] ?? "").toString(),
        idFabricacao: (m["ID_FABRICACAO"] ?? "").toString(),
        idBaia: (m["ID_BAIA"] ?? "").toString(),
        data: (m["DATA"] ?? "").toString(),
        horaInicio: (m["HORA_INICIO"] ?? "").toString(),
        horaFim: (m["HORA_FIM"] as String?),
        pesoInicio: (m["PESO_INICIO"] as num?)?.toDouble() ?? 0,
        pesoFim: (m["PESO_FIM"] as num?)?.toDouble() ?? 0,
        previsto: (m["PREVISTO"] as num?)?.toDouble() ?? 0,
        realizado: (m["REALIZADO"] as num?)?.toDouble(),
        flagSync: (m["FLAG_SYNC"] as num?)?.toInt() ?? 0,
        trato: (m["TRATO"] as num?)?.toInt() ?? 1,
        idUsuario: (m["ID_USUARIO"] ?? "").toString(),
        idDieta: (m["ID_DIETA"] as String?),
      );

  Map<String, Object?> toMap() => {
        "ID": id,
        "ID_FORNECIMENTO": idFornecimento,
        "ID_FABRICACAO": idFabricacao,
        "ID_BAIA": idBaia,
        "DATA": data,
        "HORA_INICIO": horaInicio,
        "HORA_FIM": horaFim,
        "PESO_INICIO": pesoInicio,
        "PESO_FIM": pesoFim,
        "PREVISTO": previsto,
        "REALIZADO": realizado,
        "FLAG_SYNC": flagSync,
        "TRATO": trato,
        "ID_USUARIO": idUsuario,
        "ID_DIETA": idDieta,
      };
}

class BaiaRow {
  BaiaRow({
    required this.id,
    required this.nomeLocal,
    this.linha,
    this.orderTrato,
    this.rfid,
    this.idLote,
    this.idFazenda,
  });

  final String id;
  final String nomeLocal;
  final String? linha;
  final int? orderTrato;
  final String? rfid;
  final String? idLote;
  final String? idFazenda;

  factory BaiaRow.fromMap(Map<String, Object?> m) => BaiaRow(
        id: (m["ID"] ?? "").toString(),
        nomeLocal: (m["NOME_LOCAL"] ?? "").toString(),
        linha: (m["LINHA"] as String?),
        orderTrato: (m["ORDER_TRATO"] as num?)?.toInt(),
        rfid: (m["RFID"] as String?),
        idLote: (m["ID_LOTE"] as String?),
        idFazenda: (m["ID_FAZENDA"] as String?),
      );

  Map<String, Object?> toMap() => {
        "ID": id,
        "NOME_LOCAL": nomeLocal,
        "LINHA": linha,
        "ORDER_TRATO": orderTrato,
        "RFID": rfid,
        "ID_LOTE": idLote,
        "ID_FAZENDA": idFazenda,
      };
}
