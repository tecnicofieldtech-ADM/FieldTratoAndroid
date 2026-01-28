// lib/features/fornecimento/services/balanca_parser.dart
//
// ✅ IMPORTA O ENUM ÚNICO DO DOMÍNIO
import "../domain/fornecimento_models.dart";

class BalancaParser {
  /// Extrai string do peso (ex.: "1234.5") dependendo do modelo.
  /// Retorna "" se não conseguir.
  static String extraiPeso(String line, ModeloBalanca modelo) {
    final s = line.trim();
    if (s.isEmpty) return "";

    switch (modelo) {
      case ModeloBalanca.topcon:
        // exemplos comuns: "  1234.50 kg", "W:1234.5", etc
        return _extractNumber(s);

      case ModeloBalanca.dinamica:
        // exemplos: "ST,GS,  1234.50kg", "1234.50"
        return _extractNumber(s);

      case ModeloBalanca.alfa:
        // exemplos: "N 001234.50", "001234.50"
        return _extractNumber(s);
    }
  }

  /// Converte a string num double (aceita "," e ".")
  static double? parseToDouble(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    final norm = t.replaceAll(",", ".");
    return double.tryParse(norm);
  }

  // =========================================================
  // helpers internos
  // =========================================================

  /// Extrai o primeiro número com sinal opcional e decimal opcional.
  /// Aceita negativos.
  static String _extractNumber(String s) {
    // pega tipo: -1234.56 ou 1234,56 ou 1234
    final re = RegExp(r"[-+]?\d+(?:[.,]\d+)?");
    final m = re.firstMatch(s);
    if (m == null) return "";
    return m.group(0) ?? "";
  }
}
