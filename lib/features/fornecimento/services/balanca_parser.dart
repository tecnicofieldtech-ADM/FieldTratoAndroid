// lib/features/fornecimento/services/balanca_parser.dart
import "../domain/fornecimento_models.dart";

class BalancaParser {
  /// Extrai string do peso (ex.: "1234.5") dependendo do modelo.
  /// Retorna "" se não conseguir.
  static String extraiPeso(String line, ModeloBalanca modelo) {
    final s = line.trim();
    if (s.isEmpty) return "";

    switch (modelo) {
      case ModeloBalanca.topcon:
        return _extractNumber(s);

      case ModeloBalanca.dinamica:
        return _extractNumber(s);

      case ModeloBalanca.alfa:
        return _extractNumber(s);

      // ✅ se você tiver mais modelos no enum (generale/hook/outro),
      // isso evita erro e mantém funcionando.
      default:
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

  /// Extrai o primeiro número com sinal opcional e decimal opcional.
  /// Aceita negativos.
  static String _extractNumber(String s) {
    final re = RegExp(r"[-+]?\d+(?:[.,]\d+)?");
    final m = re.firstMatch(s);
    if (m == null) return "";
    return m.group(0) ?? "";
  }
}
