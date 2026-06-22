/// MS percentual de dieta/fabricação: deve ser > 0 e <= 100.
class MsPercent {
  static bool isValid(double v) => v > 0 && v <= 100;

  static double? firstValid(Iterable<double?> values) {
    for (final v in values) {
      if (v != null && isValid(v)) return v;
    }
    return null;
  }

  /// Prioridade: fabricação → cadastro da dieta.
  static double resolve({double? msFabricacao, double? msDieta}) {
    return firstValid([msFabricacao, msDieta]) ?? 0;
  }
}
