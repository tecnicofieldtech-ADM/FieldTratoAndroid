// lib/features/fornecimento/services/balanca_parser.dart
import "../../../helpers/scale_comm.dart";
import "../domain/fornecimento_models.dart";

class BalancaParser {
  /// Extrai peso em kg de uma linha TCP (aceita negativo).
  static double? parseKg(String line, ModeloBalanca modelo) {
    final s = line.trim();
    if (s.isEmpty) return null;

    final scaleModel = _toScaleModel(modelo);
    return parseScaleWeightKg(s, model: scaleModel);
  }

  /// Retorna string do peso ou "" se não conseguir (compat. legado).
  static String extraiPeso(String line, ModeloBalanca modelo) {
    final kg = parseKg(line, modelo);
    if (kg == null) return "";
    return kg.toString();
  }

  static double? parseToDouble(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    final norm = t.replaceAll(",", ".");
    return double.tryParse(norm);
  }

  static ScaleModel _toScaleModel(ModeloBalanca modelo) {
    switch (modelo) {
      case ModeloBalanca.dinamica:
        return ScaleModel.dg500;
      case ModeloBalanca.alfa:
        return ScaleModel.alfa;
      case ModeloBalanca.hook:
        return ScaleModel.hook;
      case ModeloBalanca.topcon:
        return ScaleModel.topcom;
      case ModeloBalanca.generale:
        return ScaleModel.dg500;
      case ModeloBalanca.outro:
        return ScaleModel.raw;
    }
  }
}
