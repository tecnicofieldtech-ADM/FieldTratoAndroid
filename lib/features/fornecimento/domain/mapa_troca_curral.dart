/// Geração do mapa de fornecimento.
///
/// Um reload só publica o resultado se nenhuma gravação local ocorreu
/// depois que a consulta começou. O SQL vigente substitui o patch otimista,
/// inclusive quando o realizado diminui (estorno).
class MapaReloadGate {
  int _epoch = 0;

  int get epoch => _epoch;

  int capture() => _epoch;

  void notarPatchLocal() {
    _epoch++;
  }

  bool vigente(int token) => token == _epoch;
}

/// Fila de cliques no mapa: um processamento por vez e o alvo mais recente
/// substitui os intermediários ainda não abertos.
class CliqueCurralFila {
  String? pendingId;
  bool busy = false;

  /// true = esta chamada deve rodar o loop. false = já há loop em andamento.
  bool oferecer(String idFornecimento) {
    pendingId = idFornecimento;
    if (busy) return false;
    busy = true;
    return true;
  }

  bool supera(String idFornecimento) =>
      pendingId != null && pendingId != idFornecimento;

  void descartarPendentes() {
    pendingId = null;
  }

  void liberar() {
    busy = false;
  }
}
