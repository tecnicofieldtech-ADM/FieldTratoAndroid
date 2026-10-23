import "package:flutter_test/flutter_test.dart";

import "package:field_trato/features/fornecimento/domain/fornecimento_models.dart";
import "package:field_trato/features/fornecimento/domain/linha_filtro.dart";
import "package:field_trato/features/fornecimento/domain/previsto_ajustado.dart";

CurralPrev _c({
  required String idBaia,
  required int trato,
  required double cadastro,
  required double realizado,
  double? realizadoApi,
  double? recalculado,
  bool ultimo = false,
  String linha = "A",
  String? idLote,
  String idRacao = "10",
}) {
  return CurralPrev(
    idBaia: idBaia,
    trato: trato,
    dataIso: "2026-09-30",
    previstoKg: cadastro,
    previstoCadastroKg: cadastro,
    previstoOriginalKg: cadastro,
    previstoRecalculadoKg: recalculado ?? cadastro,
    isUltimoTrato: ultimo,
    realizadoKg: realizado,
    realizadoApiKg: realizadoApi,
    idRacao: idRacao,
    idLote: idLote,
    linha: linha,
  );
}

void main() {
  test("último trato usa o recalculado da API e só desconta extra local", () {
    // API já ajustou: 12335. Extra local nos anteriores: 280.
    // Meta correta: 12335 - 280 = 12055 (sem refazer o desconto da API).
    final rows = [
      _c(
        idBaia: "1",
        trato: 1,
        cadastro: 5000,
        realizado: 5400,
        realizadoApi: 5400,
      ),
      _c(
        idBaia: "1",
        trato: 2,
        cadastro: 5000,
        realizado: 5570,
        realizadoApi: 5290,
      ),
      _c(
        idBaia: "1",
        trato: 3,
        cadastro: 13025,
        realizado: 0,
        recalculado: 12335,
        ultimo: true,
      ),
    ];

    final idx = PrevistoAjustadoIndex.de(rows);
    final terceiro = rows.last;

    expect(idx.ehUltimo(terceiro), isTrue);
    expect(idx.de(terceiro), closeTo(12055, 0.01));
    expect(idx.de(rows[0]), 5000);
    expect(idx.de(rows[1]), 5000);
  });

  test("não desconta de novo quando a API já trouxe o ajustado", () {
    // Sem extra local: rodapé = PREVISTO_RECALCULADO da API.
    final rows = [
      _c(
        idBaia: "1",
        trato: 1,
        cadastro: 5000,
        realizado: 5400,
        realizadoApi: 5400,
      ),
      _c(
        idBaia: "1",
        trato: 2,
        cadastro: 5000,
        realizado: 5570,
        realizadoApi: 5570,
      ),
      _c(
        idBaia: "1",
        trato: 3,
        cadastro: 13025,
        realizado: 0,
        recalculado: 12055,
        ultimo: true,
      ),
    ];

    final idx = PrevistoAjustadoIndex.de(rows);
    expect(idx.de(rows.last), closeTo(12055, 0.01));
  });

  test("transição não ajusta o 2º trato da adaptação", () {
    final rows = [
      _c(
        idBaia: "1",
        trato: 1,
        cadastro: 4000,
        realizado: 4300,
        realizadoApi: 4300,
        idRacao: "ADAPT",
      ),
      _c(
        idBaia: "1",
        trato: 2,
        cadastro: 4000,
        realizado: 4670,
        realizadoApi: 4670,
        idRacao: "ADAPT",
      ),
      _c(
        idBaia: "1",
        trato: 3,
        cadastro: 13025,
        realizado: 0,
        recalculado: 12055,
        idRacao: "TERM",
        ultimo: true,
      ),
    ];
    final idx = PrevistoAjustadoIndex.de(rows);
    expect(idx.ehUltimo(rows[1]), isFalse);
    expect(idx.de(rows[1]), 4000);
    expect(idx.ehUltimo(rows[2]), isTrue);
    expect(idx.de(rows[2]), closeTo(12055, 0.01));
  });

  test("ajuste de uma baia não entra na outra", () {
    final rows = [
      _c(
        idBaia: "1",
        trato: 1,
        cadastro: 1000,
        realizado: 1100,
        realizadoApi: 1100,
      ),
      _c(
        idBaia: "1",
        trato: 2,
        cadastro: 1000,
        realizado: 0,
        recalculado: 900,
        ultimo: true,
      ),
      _c(
        idBaia: "2",
        trato: 1,
        cadastro: 800,
        realizado: 800,
        realizadoApi: 800,
      ),
      _c(
        idBaia: "2",
        trato: 2,
        cadastro: 800,
        realizado: 0,
        recalculado: 800,
        ultimo: true,
      ),
    ];
    final idx = PrevistoAjustadoIndex.de(rows);
    expect(idx.de(rows[1]), closeTo(900, 0.01));
    expect(idx.de(rows[3]), closeTo(800, 0.01));
  });

  test("sem recalculado no último trato cai no mapa/cadastro sem desconto duplo", () {
    final ultimo = CurralPrev(
      idBaia: "1",
      trato: 3,
      dataIso: "2026-09-30",
      previstoKg: 12335,
      previstoOriginalKg: 12335,
      previstoRecalculadoKg: 12335,
      isUltimoTrato: true,
      realizadoKg: 0,
      idRacao: "10",
    );
    final idx = PrevistoAjustadoIndex.de([
      _c(
        idBaia: "1",
        trato: 1,
        cadastro: 5000,
        realizado: 5400,
        realizadoApi: 5400,
      ),
      ultimo,
    ]);
    expect(idx.de(ultimo), closeTo(12335, 0.01));
  });

  test("filtro de linhas vazio aceita todas e a seleção soma só as marcadas", () {
    expect(linhaPassaFiltro("A", {}), isTrue);
    expect(linhaPassaFiltro("B", {"A", "C"}), isFalse);
    expect(linhaPassaFiltro("c", {"A", "C"}), isTrue);

    final rows = [
      _c(idBaia: "1", trato: 3, cadastro: 100, realizado: 0, linha: "A"),
      _c(idBaia: "2", trato: 3, cadastro: 40, realizado: 0, linha: "B"),
      _c(idBaia: "3", trato: 3, cadastro: 25, realizado: 0, linha: "C"),
    ];
    final idx = PrevistoAjustadoIndex.de(rows);
    const filtro = {"A", "C"};
    final total = rows
        .where((r) => linhaPassaFiltro(r.linha, filtro))
        .fold<double>(0, (a, r) => a + idx.de(r));
    expect(total, closeTo(125, 0.01));
  });
}
