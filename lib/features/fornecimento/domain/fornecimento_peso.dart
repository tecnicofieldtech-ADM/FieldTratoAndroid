/// Quanto foi fornecido (kg) no descarregamento.
///
/// Aceita leitura negativa na balança (abaixo do zero).
/// Ex.: início 500 kg, fim -100 kg → fornecido 600 kg.
double fornecidoKgSessao({
  required double pesoInicial,
  required double pesoAtual,
}) {
  final v = pesoInicial - pesoAtual;
  return v < 0 ? 0 : v;
}
