// lib/features/fornecimento/domain/fornecimento_models.dart

import "../data/fornecimento_tables.dart";

enum ModeloBalanca { topcon, dinamica, alfa, generale, hook, outro }

// =========================================================
// Helpers locais de parse (robustos)
// =========================================================
String _s(dynamic v) => (v ?? "").toString().trim();

String? _sNull(dynamic v) {
  final t = _s(v);
  return t.isEmpty ? null : t;
}

/// double seguro:
/// aceita "99,00", "99.00", "1.234,56", "1,234.56"
double _toDouble(dynamic v) {
  if (v == null) return 0.0;
  if (v is num) return v.toDouble();

  var t = v.toString().trim();
  if (t.isEmpty || t.toLowerCase() == "null") return 0.0;

  final hasComma = t.contains(",");
  final hasDot = t.contains(".");

  if (hasComma && hasDot) {
    // assume BR: "1.234,56"
    t = t.replaceAll(".", "").replaceAll(",", ".");
  } else if (hasComma) {
    t = t.replaceAll(",", ".");
  }

  return double.tryParse(t) ?? 0.0;
}

int _toInt(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString().trim()) ?? 0;
}

int? _toIntNull(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString().trim());
}

bool _toBool(dynamic v) {
  if (v == null) return false;
  if (v is bool) return v;
  final s = v.toString().trim().toLowerCase();
  return s == "1" || s == "true" || s == "t" || s == "yes" || s == "sim";
}

double _clamp0(double v) => v < 0 ? 0 : v;

// =========================================================
// CURRAL PREV (card do curral / previsto do trato)
// =========================================================
class CurralPrev {
  CurralPrev({
    required this.idBaia,
    required this.trato,
    required this.dataIso, // YYYY-MM-DD
    required this.previstoKg,
    this.realizadoKg = 0,
    this.faltaKg = 0,
    this.concluido = false,
    this.rfid,
    this.idLote,
    this.nomeLocal,
    this.linha, // ✅ string
    this.ordemFornecimento,
    this.numero,
    this.idRacao,
    this.racao,
    this.idFornecimento,
    this.idDieta,
    this.qtdSessoes = 0,
  });

  final String idBaia;
  final int trato;
  final String dataIso;

  final double previstoKg;

  double realizadoKg;
  double faltaKg;
  bool concluido;

  final String? rfid;
  final String? idLote;

  final String? nomeLocal;

  /// ✅ LINHA agora é string (pode ser "", "A", "1"...)
  final String? linha;

  /// ✅ ORDER_TRATO do curral no trato
  final int? ordemFornecimento;

  /// ✅ número extraído do NOME_LOCAL (após "-")
  final String? numero;

  final String? idRacao;
  final String? racao;

  final String? idFornecimento;

  final String? idDieta;

  /// Quantidade de linhas em CADASTRO_FORNECIMENTO (realizado > 0) na chave.
  final int qtdSessoes;

  CurralPrev copyWith({
    double? realizadoKg,
    double? faltaKg,
    bool? concluido,
    String? idFornecimento,
    String? idRacao,
    String? racao,
    String? nomeLocal,
    String? linha,
    int? ordemFornecimento,
    String? numero,
    int? qtdSessoes,
  }) {
    return CurralPrev(
      idBaia: idBaia,
      trato: trato,
      dataIso: dataIso,
      previstoKg: previstoKg,
      realizadoKg: realizadoKg ?? this.realizadoKg,
      faltaKg: faltaKg ?? this.faltaKg,
      concluido: concluido ?? this.concluido,
      rfid: rfid,
      idLote: idLote,
      nomeLocal: nomeLocal ?? this.nomeLocal,
      linha: linha ?? this.linha,
      ordemFornecimento: ordemFornecimento ?? this.ordemFornecimento,
      numero: numero ?? this.numero,
      idRacao: idRacao ?? this.idRacao,
      racao: racao ?? this.racao,
      idFornecimento: idFornecimento ?? this.idFornecimento,
      idDieta: idDieta,
      qtdSessoes: qtdSessoes ?? this.qtdSessoes,
    );
  }

  static CurralPrev fromMap(Map<String, Object?> m) {
    Object? pickAny(List<String> keys) {
      for (final k in keys) {
        if (m.containsKey(k)) return m[k];
      }
      return null;
    }

    String? snAny(List<String> keys) => _sNull(pickAny(keys));

    int iAny(List<String> keys, {int def = 0}) {
      final v = pickAny(keys);
      return v == null ? def : _toInt(v);
    }

    int? iNullAny(List<String> keys) {
      final v = pickAny(keys);
      return _toIntNull(v);
    }

    double dAny(List<String> keys, {double def = 0}) {
      final v = pickAny(keys);
      return v == null ? def : _toDouble(v);
    }

    bool bAny(List<String> keys) {
      final v = pickAny(keys);
      return _toBool(v);
    }

    final idBaia = snAny(["idBaia", "idCurral", "id_baia", "ID_BAIA"]) ?? "";
    final dataIso = snAny(["dataIso", "data", "DATA", "data_iso"]) ?? "";
    final trato = iAny(["trato", "TRATO"], def: 0);

    final previsto = dAny(["previstoKg", "previsto", "PREVISTO_KG", "PREVISTO"]);
    final realizado =
        dAny(["realizadoKg", "realizado", "REALIZADO_KG", "REALIZADO"]);

    final linha = snAny(["linha", "LINHA", "linha_local"]);

    final ordemFornecimento = iNullAny([
      "ordemFornecimento",
      "ORDEM_FORNECIMENTO",
      "orderTrato",
      "ORDER_TRATO",
      "order_trato",
    ]);

    final numero = snAny(["numero", "NUMERO"]);

    final concluido = bAny(["concluido"]) ||
        (previsto > 0 ? (realizado >= previsto) : (realizado > 0));

    final falta = _clamp0(previsto - realizado);

    return CurralPrev(
      idBaia: idBaia,
      trato: trato,
      dataIso: dataIso,
      previstoKg: previsto,
      realizadoKg: realizado,
      faltaKg: falta,
      concluido: concluido,
      rfid: snAny(["rfid", "RFID"]),
      idLote: snAny(["idLote", "id_lote", "ID_LOTE"]),
      nomeLocal: snAny([
        "nomeLocal",
        "nome_local",
        "NOME_LOCAL",
        "nome",
        "nomeBaia",
      ]),
      linha: linha,
      ordemFornecimento: ordemFornecimento,
      numero: numero,
      idRacao: snAny(["idRacao", "id_racao", "ID_RACAO"]),
      racao: snAny(["racao", "racaoNome", "nomeRacao", "racao_nome"]),
      idFornecimento:
          snAny(["idFornecimento", "id_fornecimento", "ID_FORNECIMENTO"]),
      idDieta: snAny(["idDieta", "id_dieta", "ID_DIETA"]),
      qtdSessoes: iAny(["qtdSessoes", "qtd_sessoes", "QTD_SESSOES"], def: 0),
    );
  }
}

// =========================================================
// SNAPSHOT
// =========================================================
class CurralSnapshot {
  CurralSnapshot({
    required this.idBaia,
    required this.dataIso,
    required this.trato,
    required this.idDieta,
    required this.idFornecimento,
    required this.previstoKg,
    required this.realizadoKg,
  });

  final String idBaia;
  final String dataIso;
  final int trato;
  final String idDieta;
  final String idFornecimento;

  final double previstoKg;
  final double realizadoKg;
}

// =========================================================
// FORNECIMENTO ABERTO
// =========================================================
class FornecimentoAberto {
  FornecimentoAberto({
    required this.idFornecimento,
    required this.idBaia,
    required this.idDieta,
    required this.dataIso,
    required this.trato,
    this.idUsuario,
    this.idFabricacao,
    this.pesoInicio,
    this.horaInicio,
    this.previstoKg,
  });

  final String idFornecimento;
  final String idBaia;
  final String idDieta;
  final String dataIso;
  final int trato;

  final String? idUsuario;
  final String? idFabricacao;

  final double? pesoInicio;
  final String? horaInicio;
  final double? previstoKg;
}

// =========================================================
// FORNECIMENTO ABERTO MINI
// =========================================================
class FornecimentoAbertoMini {
  FornecimentoAbertoMini({
    required this.idCadastro,
    required this.idFornecimento,
    required this.idBaia,
  });

  final String idCadastro;
  final String idFornecimento;
  final String idBaia;
}

// =========================================================
// ROWS (DAO)
// =========================================================
class FornecimentoRow {
  FornecimentoRow({
    required this.id,
    required this.idFornecimento,
    required this.idBaia,
    required this.idDieta,
    required this.dataIso,
    required this.trato,
    required this.previstoKg,
    required this.realizadoKg,
  });

  final String id;
  final String idFornecimento;
  final String idBaia;
  final String idDieta;
  final String dataIso;
  final int trato;
  final double previstoKg;
  final double realizadoKg;

  static FornecimentoRow fromMap(Map<String, Object?> m) {
    Object? pick(List<String> keys) {
      for (final k in keys) {
        if (m.containsKey(k)) return m[k];
      }
      return null;
    }

    String sKeys(List<String> keys) => _s(pick(keys));
    int iKeys(List<String> keys) => _toInt(pick(keys));
    double dKeys(List<String> keys) => _toDouble(pick(keys));

    return FornecimentoRow(
      id: sKeys(["id", "ID"]),
      idFornecimento:
          sKeys(["idFornecimento", "ID_FORNECIMENTO", "id_fornecimento"]),
      idBaia: sKeys(["idBaia", "ID_BAIA", "id_baia"]),
      idDieta: sKeys(["idDieta", "ID_DIETA", "id_dieta"]),
      dataIso: sKeys(["dataIso", "DATA", "data"]),
      trato: iKeys(["trato", "TRATO"]),
      previstoKg: dKeys(["previstoKg", "PREVISTO", "PREVISTO_KG", "previsto"]),
      realizadoKg:
          dKeys(["realizadoKg", "REALIZADO", "REALIZADO_KG", "realizado"]),
    );
  }

  // ⚠️ Mantido como "map genérico" (se você usa em UI/testes/etc.)
  Map<String, Object?> toMap() => {
        "id": id,
        "idFornecimento": idFornecimento,
        "idBaia": idBaia,
        "idDieta": idDieta,
        "dataIso": dataIso,
        "trato": trato,
        "previstoKg": previstoKg,
        "realizadoKg": realizadoKg,
      };

  // ✅ Map certo para INSERT/UPDATE direto no CADASTRO_FORNECIMENTO (SQLite real)
  Map<String, Object?> toDbMap() => {
        FornTables.cfId: id,
        FornTables.cfIdFornecimento: idFornecimento,
        FornTables.cfIdBaia: idBaia,
        FornTables.cfIdDieta: idDieta,
        FornTables.cfData: dataIso,
        FornTables.cfTrato: trato,
        FornTables.cfPrevisto: previstoKg,
        FornTables.cfRealizado: realizadoKg,
      };
}

// =========================================================
// LINHA LOCAL (CADASTRO_FORNECIMENTO no tablet)
// =========================================================
class FornecimentoLocalRow {
  FornecimentoLocalRow({
    required this.id,
    required this.dataIso,
    required this.horaInicio,
    required this.horaFim,
    required this.idBaia,
    this.nomeBaia,
    this.linha,
    required this.trato,
    required this.idDieta,
    this.racaoNome,
    required this.previstoKg,
    required this.realizadoKg,
    required this.syncOk,
  });

  final String id;
  final String dataIso;
  final String horaInicio;
  final String horaFim;
  final String idBaia;
  final String? nomeBaia;
  final String? linha;
  final int trato;
  final String idDieta;
  final String? racaoNome;
  final double previstoKg;
  final double realizadoKg;
  final bool syncOk;

  String get racaoDisplay {
    final nome = (racaoNome ?? "").trim();
    if (nome.isNotEmpty) return nome;
    final id = idDieta.trim();
    return id.isEmpty ? "-" : id;
  }

  String get baiaDisplay {
    final nome = (nomeBaia ?? "").trim();
    if (nome.isNotEmpty) return nome;
    final id = idBaia.trim();
    return id.isEmpty ? "-" : id;
  }

  static FornecimentoLocalRow fromMap(Map<String, Object?> m) {
    Object? pick(List<String> keys) {
      for (final k in keys) {
        if (m.containsKey(k)) return m[k];
      }
      return null;
    }

    String sKeys(List<String> keys) => _s(pick(keys));
    int iKeys(List<String> keys) => _toInt(pick(keys));
    double dKeys(List<String> keys) => _toDouble(pick(keys));

    final flagSync = iKeys(["flag_sync", "FLAG_SYNC", "flagSync"]);
    final dataRaw = sKeys(["dataIso", "data_iso", "DATA", "data"]);
    final dataIso = dataRaw.length >= 10 ? dataRaw.substring(0, 10) : dataRaw;

    return FornecimentoLocalRow(
      id: sKeys(["id", "ID"]),
      dataIso: dataIso,
      horaInicio: sKeys(["horaInicio", "hora_inicio", "HORA_INICIO"]),
      horaFim: sKeys(["horaFim", "hora_fim", "HORA_FIM"]),
      idBaia: sKeys(["idBaia", "id_baia", "ID_BAIA"]),
      nomeBaia: sKeys(["nomeBaia", "nome_baia", "nome_local", "NOME_LOCAL"]),
      linha: sKeys(["linha", "LINHA"]),
      trato: iKeys(["trato", "TRATO"]),
      idDieta: sKeys(["idDieta", "id_dieta", "ID_DIETA"]),
      racaoNome: sKeys(["racaoNome", "racao_nome", "NOME_RACAO"]),
      previstoKg: dKeys(["previstoKg", "previsto", "PREVISTO"]),
      realizadoKg: dKeys(["realizadoKg", "realizado", "REALIZADO"]),
      syncOk: flagSync == 1,
    );
  }
}

// =========================================================
// BAIA ROW
// =========================================================
class BaiaRow {
  BaiaRow({
    required this.id,
    required this.nomeLocal,
    this.linha,
    this.orderTrato,
    this.rfid,
    this.idLote,
    this.idFazenda, // ✅ adiciono aqui porque você tem coluna no SQLite
  });

  final String id;
  final String nomeLocal;

  /// ✅ no seu SQLite a coluna LINHA é TEXT.
  final String? linha;

  final int? orderTrato;
  final String? rfid;
  final String? idLote;

  final String? idFazenda;

  static BaiaRow fromMap(Map<String, Object?> m) {
    Object? pick(List<String> keys) {
      for (final k in keys) {
        if (m.containsKey(k)) return m[k];
      }
      return null;
    }

    String sKeys(List<String> keys) => _s(pick(keys));
    int? iNullKeys(List<String> keys) => _toIntNull(pick(keys));
    String? sNullKeys(List<String> keys) => _sNull(pick(keys));

    String? linhaStr(List<String> keys) {
      final v = pick(keys);
      if (v == null) return null;
      final t = v.toString().trim();
      return t.isEmpty ? null : t;
    }

    return BaiaRow(
      id: sKeys(["id", "ID"]),
      nomeLocal: sKeys(["nomeLocal", "NOME_LOCAL", "nome_local"]),
      linha: linhaStr(["linha", "LINHA"]),
      orderTrato: iNullKeys(["orderTrato", "ORDER_TRATO", "order_trato"]),
      rfid: sNullKeys(["rfid", "RFID"]),
      idLote: sNullKeys(["idLote", "ID_LOTE", "id_lote"]),
      idFazenda: sNullKeys(["idFazenda", "ID_FAZENDA", "id_fazenda"]),
    );
  }

  // ⚠️ Mantido como map genérico.
  Map<String, Object?> toMap() => {
        "id": id,
        "nomeLocal": nomeLocal,
        "linha": linha,
        "orderTrato": orderTrato,
        "rfid": rfid,
        "idLote": idLote,
        "idFazenda": idFazenda,
      };

  // ✅ Map certo para INSERT/UPDATE direto no DETALHES_BAIAS (SQLite real)
  Map<String, Object?> toDbMap({String? overrideIdFazenda}) {
    final faz = (overrideIdFazenda ?? idFazenda ?? "").trim();
    return {
      FornTables.dbId: id,
      FornTables.dbNomeLocal: nomeLocal,
      FornTables.dbLinha: linha,
      FornTables.dbOrderTrato: orderTrato,
      FornTables.dbRfid: rfid,
      FornTables.dbIdLote: idLote,
      if (faz.isNotEmpty) FornTables.dbIdFazenda: faz,
    };
  }
}


