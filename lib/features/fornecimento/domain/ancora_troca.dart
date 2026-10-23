enum FaseTrocaCurral {
  transicao,
  aguardandoPeso,
  sessaoAtiva,
  erroPeso,
}

class AmostraCandidata {
  const AmostraCandidata({
    required this.peso,
    required this.recebidaEm,
    required this.conexaoId,
  });

  final double peso;
  final DateTime recebidaEm;
  final int conexaoId;
}

/// Amostra do início do curral novo: chegou depois do corte do curral
/// anterior, nesta conexão, nesta troca e neste curral.
bool amostraServeDeAncora({
  required DateTime recebidaEm,
  required DateTime corte,
  required DateTime? conectadoEm,
  required int conexaoAmostra,
  required int conexaoAtual,
  required int geracaoPedido,
  required int geracaoAtual,
  required String curralPedido,
  required String curralAtual,
}) {
  if (geracaoPedido != geracaoAtual) return false;
  if (curralPedido != curralAtual) return false;
  if (conexaoAmostra != conexaoAtual) return false;
  if (conectadoEm == null) return false;
  if (recebidaEm.isBefore(conectadoEm)) return false;
  return recebidaEm.isAfter(corte);
}

/// O timeout não autoriza peso antigo nem cache da sessão encerrada.
bool timeoutAutorizaPesoAntigo() => false;

String? avisoFaseTroca(FaseTrocaCurral fase) {
  switch (fase) {
    case FaseTrocaCurral.transicao:
      return "Gravando o curral anterior...";
    case FaseTrocaCurral.aguardandoPeso:
      return "Aguardando balança. Não inicie a descarga antes da pesagem ficar ativa.";
    case FaseTrocaCurral.erroPeso:
      return "Não foi possível abrir a pesagem deste curral.";
    case FaseTrocaCurral.sessaoAtiva:
      return null;
  }
}
