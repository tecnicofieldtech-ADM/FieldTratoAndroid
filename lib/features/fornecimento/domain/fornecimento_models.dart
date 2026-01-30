// lib/features/fornecimento/domain/fornecimento_models.dart

enum ModeloBalanca { topcon, dinamica, alfa, generale, hook, outro }

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
    this.linha,
    this.idRacao,
    this.racao,
    this.idFornecimento,
    this.idDieta,
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

  // ✅ usados na UI
  final String? nomeLocal; // ou nomeBaia
  final int? linha;

  // ✅ usados na UI/DAO
  final String? idRacao;
  final String? racao;

  // ✅ usado no fluxo do fornecimento aberto
  final String? idFornecimento;

  // ✅ se você já tiver dieta no select/join
  final String? idDieta;

  CurralPrev copyWith({
    double? realizadoKg,
    double? faltaKg,
    bool? concluido,
    String? idFornecimento,
    String? idRacao,
    String? racao,
    String? nomeLocal,
    int? linha,
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
      idRacao: idRacao ?? this.idRacao,
      racao: racao ?? this.racao,
      idFornecimento: idFornecimento ?? this.idFornecimento,
      idDieta: idDieta,
    );
  }

  // ✅ o repo está cobrando
  static CurralPrev fromMap(Map<String, Object?> m) {
    String _s(String k) => (m[k] ?? "").toString();
    String? _sn(String k) {
      final v = m[k];
      if (v == null) return null;
      final t = v.toString().trim();
      return t.isEmpty ? null : t;
    }

    int _i(String k) {
      final v = m[k];
      if (v == null) return 0;
      if (v is int) return v;
      return int.tryParse(v.toString()) ?? 0;
    }

    int? _in(String k) {
      final v = m[k];
      if (v == null) return null;
      if (v is int) return v;
      return int.tryParse(v.toString());
    }

    double _d(String k) {
      final v = m[k];
      if (v == null) return 0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString().replaceAll(",", ".")) ?? 0;
    }

    bool _b(String k) {
      final v = m[k];
      if (v == null) return false;
      if (v is bool) return v;
      final s = v.toString();
      return s == "1" || s.toLowerCase() == "true";
    }

    // ✅ aceita nomes antigos/novos
    final idBaia = _sn("idBaia") ?? _sn("idCurral") ?? _s("id_baia");
    final dataIso = _sn("dataIso") ?? _sn("data") ?? _s("data_iso");
    final trato = _i("trato");

    return CurralPrev(
      idBaia: idBaia,
      trato: trato,
      dataIso: dataIso,
      previstoKg: _d("previstoKg") != 0 ? _d("previstoKg") : _d("previsto"),
      realizadoKg: _d("realizadoKg") != 0 ? _d("realizadoKg") : _d("realizado"),
      faltaKg: _d("faltaKg"),
      concluido: _b("concluido"),
      rfid: _sn("rfid"),
      idLote: _sn("idLote"),
      nomeLocal: _sn("nomeLocal") ?? _sn("nome") ?? _sn("nomeBaia"),
      linha: _in("linha"),
      idRacao: _sn("idRacao"),
      racao: _sn("racao"),
      idFornecimento: _sn("idFornecimento"),
      idDieta: _sn("idDieta"),
    );
  }
}

// =========================================================
// SNAPSHOT (seu DAO usa como “estado do curral”)
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
// FORNECIMENTO ABERTO MINI (repo espera idCadastro)
// =========================================================
class FornecimentoAbertoMini {
  FornecimentoAbertoMini({
    required this.idFornecimento,
    required this.idBaia,
  });

  final String idFornecimento;
  final String idBaia;

  // ✅ compatibilidade com código antigo
  String get idCadastro => idFornecimento;
}

// =========================================================
// ROWS (DAO pede toMap/fromMap)
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
    String s(String k) => (m[k] ?? "").toString();
    int i(String k) => int.tryParse((m[k] ?? "0").toString()) ?? 0;
    double d(String k) {
      final v = m[k];
      if (v == null) return 0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString().replaceAll(",", ".")) ?? 0;
    }

    return FornecimentoRow(
      id: s("id"),
      idFornecimento: s("idFornecimento"),
      idBaia: s("idBaia"),
      idDieta: s("idDieta"),
      dataIso: s("dataIso"),
      trato: i("trato"),
      previstoKg: d("previstoKg"),
      realizadoKg: d("realizadoKg"),
    );
  }

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
}

class BaiaRow {
  BaiaRow({
    required this.id,
    required this.nomeLocal,
    this.linha,
    this.orderTrato,
    this.rfid,
    this.idLote,
  });

  final String id;
  final String nomeLocal;
  final int? linha;
  final int? orderTrato;
  final String? rfid;
  final String? idLote;

  static BaiaRow fromMap(Map<String, Object?> m) {
    String s(String k) => (m[k] ?? "").toString();
    int? inull(String k) => m[k] == null ? null : int.tryParse(m[k].toString());

    String? snull(String k) {
      final v = m[k];
      if (v == null) return null;
      final t = v.toString().trim();
      return t.isEmpty ? null : t;
    }

    return BaiaRow(
      id: s("id"),
      nomeLocal: s("nomeLocal"),
      linha: inull("linha"),
      orderTrato: inull("orderTrato"),
      rfid: snull("rfid"),
      idLote: snull("idLote"),
    );
  }

  Map<String, Object?> toMap() => {
        "id": id,
        "nomeLocal": nomeLocal,
        "linha": linha,
        "orderTrato": orderTrato,
        "rfid": rfid,
        "idLote": idLote,
      };
}
