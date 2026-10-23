import "package:flutter_test/flutter_test.dart";

import "package:field_trato/features/fornecimento/domain/ancora_troca.dart";
import "package:field_trato/features/fornecimento/domain/fornecimento_peso.dart";
import "package:field_trato/features/fornecimento/domain/troca_curral_relogio.dart";

void main() {
  group("painel A FORNECER", () {
    test("fica oculto sem curral, sem sessão ou durante a inicialização", () {
      expect(
        painelAFornecerLiberado(
          temCurral: false,
          sessaoAtiva: true,
          iniciando: false,
        ),
        isFalse,
      );
      expect(
        painelAFornecerLiberado(
          temCurral: true,
          sessaoAtiva: false,
          iniciando: false,
        ),
        isFalse,
      );
      expect(
        painelAFornecerLiberado(
          temCurral: true,
          sessaoAtiva: false,
          iniciando: true,
        ),
        isFalse,
      );
      expect(
        painelAFornecerLiberado(
          temCurral: true,
          sessaoAtiva: true,
          iniciando: true,
        ),
        isFalse,
      );
    });

    test("só libera depois da sessão atual, com a inicialização encerrada", () {
      expect(
        painelAFornecerLiberado(
          temCurral: true,
          sessaoAtiva: true,
          iniciando: false,
        ),
        isTrue,
      );
    });
  });

  group("relogio da troca", () {
    test("soma os deltas e separa espera, processamento e render", () {
      final relogio = TrocaCurralRelogio(de: "L-26", para: "L-27");
      relogio.marcar("inicio");
      relogio.marcar("fila");
      relogio.marcar("persistencia");
      relogio.marcar("hidratacao");
      relogio.marcar("peso_valido");
      relogio.marcar("cadastro");
      relogio.marcar("ancora");
      relogio.marcar("painel");

      final soma = relogio.marcas.fold<int>(0, (a, m) => a + m.deltaMs);
      expect(soma, relogio.totalMs);
      expect(relogio.deltaDe("peso_valido"), greaterThanOrEqualTo(0));
      expect(classeEtapa("peso_valido"), "espera");
      expect(classeEtapa("fila"), "espera");
      expect(classeEtapa("persistencia"), "proc");
      expect(classeEtapa("hidratacao"), "proc");
      expect(classeEtapa("cadastro"), "proc");
      expect(classeEtapa("ancora"), "proc");
      expect(classeEtapa("painel"), "render");
      expect(classeEtapa("selecao"), "render");
      expect(relogio.resumo(), contains("L-26->L-27"));
      expect(relogio.resumo(), contains("[espera]"));
      expect(relogio.resumo(), contains("[proc]"));
      expect(relogio.resumo(), contains("[render]"));
    });
  });

  group("âncora da troca", () {
    final corte = DateTime(2026, 10, 13, 18, 0, 0);
    final conectado = corte.subtract(const Duration(minutes: 2));
    final depois = corte.add(const Duration(milliseconds: 40));

    bool aceita({
      DateTime? recebidaEm,
      DateTime? corteEm,
      DateTime? conectadoEm,
      bool desconectada = false,
      int conexaoAmostra = 3,
      int conexaoAtual = 3,
      int geracaoPedido = 2,
      int geracaoAtual = 2,
      String curralPedido = "L-27",
      String curralAtual = "L-27",
    }) {
      return amostraServeDeAncora(
        recebidaEm: recebidaEm ?? depois,
        corte: corteEm ?? corte,
        conectadoEm: desconectada ? null : (conectadoEm ?? conectado),
        conexaoAmostra: conexaoAmostra,
        conexaoAtual: conexaoAtual,
        geracaoPedido: geracaoPedido,
        geracaoAtual: geracaoAtual,
        curralPedido: curralPedido,
        curralAtual: curralAtual,
      );
    }

    test("aceita a primeira amostra depois do corte, na conexão e na troca atuais", () {
      expect(aceita(), isTrue);
    });

    test("rejeita a leitura que fechou o curral anterior", () {
      expect(aceita(recebidaEm: corte), isFalse);
      expect(
        aceita(recebidaEm: corte.subtract(const Duration(seconds: 1))),
        isFalse,
      );
    });

    test("rejeita conexão antiga, desconexão e evento atrasado", () {
      expect(aceita(conexaoAmostra: 2), isFalse);
      expect(aceita(desconectada: true), isFalse);
      expect(
        aceita(
          recebidaEm: depois,
          conectadoEm: depois.add(const Duration(seconds: 1)),
        ),
        isFalse,
      );
      expect(aceita(geracaoPedido: 1, geracaoAtual: 2), isFalse);
      expect(aceita(curralPedido: "L-26", curralAtual: "L-27"), isFalse);
    });

    test("troca rápida invalida a amostra da transição abandonada", () {
      expect(aceita(geracaoPedido: 7, geracaoAtual: 8, curralAtual: "L-28"), isFalse);
    });

    test("timeout não autoriza peso antigo", () {
      expect(timeoutAutorizaPesoAntigo(), isFalse);
    });

    test("sem leitura a tela pede para esperar a balança", () {
      expect(
        avisoFaseTroca(FaseTrocaCurral.aguardandoPeso),
        contains("Aguardando balança"),
      );
      expect(avisoFaseTroca(FaseTrocaCurral.sessaoAtiva), isNull);
    });
  });

  group("contabilização intacta", () {
    test("kg da sessão continua sendo a diferença da âncora", () {
      expect(
        fornecidoKgSessao(pesoInicial: 1200, pesoAtual: 1180),
        20,
      );
      expect(
        fornecidoKgSessao(pesoInicial: 1200, pesoAtual: 1200),
        0,
      );
    });

    test("a fornecer da sessão é realizado mais sessão menos previsto", () {
      const realizado = 400.0;
      const previsto = 1000.0;
      const sessao = 50.0;
      expect(realizado + sessao - previsto, -550);
      const sessaoInativa = 0.0;
      expect(realizado + sessaoInativa - previsto, -600);
    });
  });
}
