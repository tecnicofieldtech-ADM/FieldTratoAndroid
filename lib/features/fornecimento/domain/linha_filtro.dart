/// Vazio = todas as linhas. Caso contrário, a linha precisa estar no conjunto.
bool linhaPassaFiltro(String? linha, Set<String> selecionadas) {
  if (selecionadas.isEmpty) return true;
  final l = (linha ?? "").trim().toUpperCase();
  if (l.isEmpty) return false;
  for (final s in selecionadas) {
    if (s.trim().toUpperCase() == l) return true;
  }
  return false;
}

Set<String> normalizarLinhas(Iterable<String> linhas) {
  final out = <String>{};
  for (final l in linhas) {
    final t = l.trim().toUpperCase();
    if (t.isNotEmpty) out.add(t);
  }
  return out;
}
