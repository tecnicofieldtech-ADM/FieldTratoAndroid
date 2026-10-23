/// Marcas de uma troca de curral. Cada etapa guarda o tempo desde a
/// marca anterior e o total desde o início, em milissegundos.
class TrocaCurralMarca {
  const TrocaCurralMarca(this.etapa, this.deltaMs, this.totalMs);

  final String etapa;
  final int deltaMs;
  final int totalMs;
}

class TrocaCurralRelogio {
  TrocaCurralRelogio({this.de = "", this.para = ""});

  final String de;
  final String para;
  final Stopwatch _sw = Stopwatch()..start();
  final List<TrocaCurralMarca> marcas = [];
  int _ultimo = 0;

  void marcar(String etapa) {
    final total = _sw.elapsedMilliseconds;
    marcas.add(TrocaCurralMarca(etapa, total - _ultimo, total));
    _ultimo = total;
  }

  int deltaDe(String etapa) {
    for (final m in marcas) {
      if (m.etapa == etapa) return m.deltaMs;
    }
    return -1;
  }

  int get totalMs => _sw.elapsedMilliseconds;

  String resumo() {
    final partes = marcas
        .map((m) => "${m.etapa}=${m.deltaMs}ms[${classeEtapa(m.etapa)}]")
        .join(" ");
    final origem = de.isEmpty && para.isEmpty ? "" : "$de->$para ";
    return "[FORN_TROCA] $origem$partes total=${totalMs}ms";
  }
}

/// espera = poll ou fila; render = notify agendado (não é o tempo do frame);
/// proc = trabalho local (SQLite, cálculo, seleção).
String classeEtapa(String etapa) {
  switch (etapa) {
    case "fila":
    case "fila_abortada":
    case "peso_valido":
    case "peso_cancelado":
      return "espera";
    case "selecao":
    case "painel":
      return "render";
    default:
      return "proc";
  }
}

/// O número grande só aparece depois da âncora da sessão atual.
/// Enquanto a troca inicializa, a tela fica no estado transitório.
bool painelAFornecerLiberado({
  required bool temCurral,
  required bool sessaoAtiva,
  required bool iniciando,
}) {
  return temCurral && sessaoAtiva && !iniciando;
}
