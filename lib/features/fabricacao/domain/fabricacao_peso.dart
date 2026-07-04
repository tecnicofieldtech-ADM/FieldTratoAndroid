// Regras de peso na fabricação (carregamento na balança).

/// No 1º insumo a balança pode estar abaixo de zero (ex.: -50 kg).
/// Nos demais insumos, baseline negativo é tratado como zero.
int capturaPesoInicialFabricacao({
  required int pesoAtual,
  required bool primeiroIngrediente,
}) {
  if (primeiroIngrediente) return pesoAtual;
  return pesoAtual < 0 ? 0 : pesoAtual;
}

/// Incremento desde o baseline; ignora oscilação para baixo.
int incrementoKgDesdeBaseline({
  required int pesoAtual,
  required int pesoInicial,
}) {
  final inc = pesoAtual - pesoInicial;
  return inc < 0 ? 0 : inc;
}
