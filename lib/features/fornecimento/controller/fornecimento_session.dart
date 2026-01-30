// lib/features/fornecimento/controller/fornecimento_session.dart
import "package:flutter/foundation.dart";

// ✅ Corrige o import: CurralPrev está em /data/fornecimento_models.dart
import "../data/fornecimento_models.dart";

/// Estado de sessão do fornecimento (Rotormix)
/// - não cria arquitetura nova: é só um "state holder" imutável com copyWith
@immutable
class FornecimentoSession {
  const FornecimentoSession({
    required this.idFazenda,
    required this.dataYmd,
    required this.idUsuario,
    this.idCarregamento,
    this.idDieta, // ✅ ID_DIETA == ID_RACAO
    this.trato,
    this.currais = const <CurralPrev>[],
    this.indexAtual = 0,
    this.pesoAtual = 0,
    this.pesoInicio,
    this.horaInicio,
    this.idCadastroAberto,
    this.lastEpc,
    this.warning,
    this.error,
  });

  /// contexto
  final String idFazenda;
  final String dataYmd; // "YYYY-MM-DD" (hoje localtime)
  final String idUsuario;

  /// carregamento aberto
  final String? idCarregamento;
  final String? idDieta; // ID_DIETA == ID_RACAO

  /// trato selecionado
  final int? trato;

  /// mapa de currais filtrado (hoje + trato + idDieta)
  final List<CurralPrev> currais;
  final int indexAtual;

  /// peso atual vindo da balança
  final double pesoAtual;

  /// sessão por curral
  final double? pesoInicio;
  final DateTime? horaInicio;
  final String? idCadastroAberto; // CADASTRO_FORNECIMENTO.ID (UUID nosso)

  /// RFID
  final String? lastEpc;

  /// mensagens (não travar quando EPC inválido)
  final String? warning;
  final String? error;

  CurralPrev? get atual =>
      currais.isEmpty ? null : currais[indexAtual.clamp(0, currais.length - 1)];

  bool get temMapa => currais.isNotEmpty;

  bool get iniciado => horaInicio != null;

  /// Realizado parcial = pesoInicio - pesoAtual (se iniciou curral)
  double get realizadoParcial {
    final pi = pesoInicio;
    if (pi == null) return 0;
    return _round3(pi - pesoAtual);
  }

  bool get carregamentoOk => (idCarregamento ?? "").trim().isNotEmpty;

  bool get tratoOk => (trato ?? 0) > 0;

  FornecimentoSession copyWith({
    String? idFazenda,
    String? dataYmd,
    String? idUsuario,
    String? idCarregamento,
    String? idDieta,
    int? trato,
    List<CurralPrev>? currais,
    int? indexAtual,
    double? pesoAtual,
    double? pesoInicio,
    DateTime? horaInicio,
    String? idCadastroAberto,
    String? lastEpc,
    String? warning,
    String? error,
    bool clearWarning = false,
    bool clearError = false,
    bool clearSessaoCurral = false,
  }) {
    return FornecimentoSession(
      idFazenda: idFazenda ?? this.idFazenda,
      dataYmd: dataYmd ?? this.dataYmd,
      idUsuario: idUsuario ?? this.idUsuario,
      idCarregamento: idCarregamento ?? this.idCarregamento,
      idDieta: idDieta ?? this.idDieta,
      trato: trato ?? this.trato,
      currais: currais ?? this.currais,
      indexAtual: indexAtual ?? this.indexAtual,
      pesoAtual: pesoAtual ?? this.pesoAtual,
      pesoInicio: clearSessaoCurral ? null : (pesoInicio ?? this.pesoInicio),
      horaInicio: clearSessaoCurral ? null : (horaInicio ?? this.horaInicio),
      idCadastroAberto:
          clearSessaoCurral ? null : (idCadastroAberto ?? this.idCadastroAberto),
      lastEpc: lastEpc ?? this.lastEpc,
      warning: clearWarning ? null : (warning ?? this.warning),
      error: clearError ? null : (error ?? this.error),
    );
  }

  static double _round3(double v) => (v * 1000).round() / 1000.0;
}
