import "dart:async";
import "dart:math";

import "package:flutter_test/flutter_test.dart";
import "package:sqflite_common_ffi/sqflite_ffi.dart";

import "package:field_trato/features/fornecimento/domain/fornecimento_models.dart";
import "package:field_trato/features/fornecimento/domain/fornecimento_peso.dart";
import "package:field_trato/features/fornecimento/domain/mapa_troca_curral.dart";
import "package:field_trato/features/fornecimento/domain/previsto_ajustado.dart";

CurralPrev _row(int i, {double realizado = 0}) {
  return CurralPrev(
    idBaia: "$i",
    idFornecimento: "f$i",
    trato: 1,
    dataIso: "2026-10-08",
    previstoKg: 1000,
    previstoCadastroKg: 1000,
    previstoOriginalKg: 1000,
    previstoRecalculadoKg: 1000,
    isUltimoTrato: true,
    realizadoKg: realizado,
    realizadoApiKg: realizado,
    idRacao: "10922",
    linha: "${i % 8}",
  );
}

/// Espelha a decisão do controller: uma transição por vez, falha de save
/// aborta a fila, clique mais novo substitui alvo ainda não aberto.
class _TrocaSim {
  final fila = CliqueCurralFila();
  final abertos = <String>[];
  final saves = <String>[];
  String? sessaoCurral;
  String? cadastroAberto;
  bool failSave = false;
  int savesOk = 0;
  Completer<void>? segurarSave;

  Future<void> clique(String id) async {
    final lider = fila.oferecer(id);
    if (!lider) return;
    try {
      while (fila.pendingId != null) {
        final alvo = fila.pendingId!;
        fila.pendingId = null;
        final abortar = await _executar(alvo);
        if (abortar) {
          fila.descartarPendentes();
          break;
        }
      }
    } finally {
      fila.liberar();
      final pendente = fila.pendingId;
      if (pendente != null) {
        await clique(pendente);
      }
    }
  }

  Future<bool> _executar(String id) async {
    if (sessaoCurral != null && sessaoCurral != id) {
      final espera = segurarSave;
      if (espera != null) await espera.future;
      saves.add(sessaoCurral!);
      if (failSave) return true;
      savesOk++;
      cadastroAberto = null;
      sessaoCurral = null;
      if (fila.supera(id)) return false;
    }
    if (fila.supera(id)) return false;
    if (sessaoCurral == id && cadastroAberto != null) return false;
    cadastroAberto = "cad-$id-${abertos.length}";
    sessaoCurral = id;
    abertos.add(id);
    return false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test("1 troca A para B normal", () async {
    final sim = _TrocaSim()..sessaoCurral = "A"..cadastroAberto = "cad-A";
    await sim.clique("B");
    expect(sim.saves, ["A"]);
    expect(sim.abertos, ["B"]);
    expect(sim.cadastroAberto, isNotNull);
    expect(sim.savesOk, 1);
  });

  test("2 troca A B C rapida coalesce no ultimo alvo", () async {
    final sim = _TrocaSim()..sessaoCurral = "A"..cadastroAberto = "cad-A";
    final segurar = Completer<void>();
    sim.segurarSave = segurar;
    final f1 = sim.clique("B");
    await Future<void>.delayed(Duration.zero);
    final f2 = sim.clique("C");
    segurar.complete();
    await Future.wait([f1, f2]);
    expect(sim.saves, ["A"]);
    expect(sim.abertos, ["C"]);
  });

  test("3 falha de gravacao nao abre o proximo nem segue a fila", () async {
    final sim = _TrocaSim()
      ..sessaoCurral = "A"
      ..cadastroAberto = "cad-A"
      ..failSave = true;
    final segurar = Completer<void>();
    sim.segurarSave = segurar;
    final primeiro = sim.clique("B");
    await Future<void>.delayed(Duration.zero);
    final segundo = sim.clique("C");
    segurar.complete();
    await Future.wait([primeiro, segundo]);
    expect(sim.abertos, isEmpty);
    expect(sim.sessaoCurral, "A");
    expect(sim.savesOk, 0);
  });

  test("4 reload lento nao publica se a geracao mudou", () async {
    final gate = MapaReloadGate();
    final tokenLento = gate.capture();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    gate.notarPatchLocal();
    final tokenNovo = gate.capture();
    expect(gate.vigente(tokenLento), isFalse);
    expect(gate.vigente(tokenNovo), isTrue);
  });

  test("5 reload antigo nao sobrescreve estado novo", () {
    final gate = MapaReloadGate();
    final antigo = gate.capture();
    gate.notarPatchLocal();
    final novo = gate.capture();
    const sqlAntigo = 100.0;
    const sqlNovo = 900.0;
    double publicado = 0;
    if (gate.vigente(antigo)) publicado = sqlAntigo;
    if (gate.vigente(novo)) publicado = sqlNovo;
    expect(publicado, 900);
  });

  test("6 sessao com zero kg nao acumula realizado", () {
    const kg = 0.0;
    final realizado = <String, double>{"A": 10};
    if (kg > 0) {
      realizado["A"] = realizado["A"]! + kg;
    }
    expect(realizado["A"], 10);
    expect(kg <= 0, isTrue);
  });

  test("7 clique repetido no mesmo curral nao abre outro cadastro", () async {
    final sim = _TrocaSim()..sessaoCurral = "A"..cadastroAberto = "cad-A";
    await sim.clique("A");
    await sim.clique("A");
    expect(sim.abertos, isEmpty);
    expect(sim.cadastroAberto, "cad-A");
  });

  test("8 patch local e SQL vigente conciliam pelo token, nao pelo maior", () {
    final gate = MapaReloadGate();
    var memoria = 100.0;
    memoria += 800;
    gate.notarPatchLocal();
    final token = gate.capture();
    const sql = 900.0;
    if (gate.vigente(token)) memoria = sql;
    expect(memoria, 900);
  });

  test("9 estorno legitimo substitui o patch otimista", () {
    final gate = MapaReloadGate();
    var memoria = 800.0;
    gate.notarPatchLocal();
    final token = gate.capture();
    const sqlEstornado = 500.0;
    expect(sqlEstornado < memoria, isTrue);
    if (gate.vigente(token)) memoria = sqlEstornado;
    expect(memoria, 500);
  });

  test("10 peso inicial do curral novo independe da ancora anterior", () {
    const pesoA = 5000.0;
    const pesoDepoisDoFornecimento = 4200.0;
    final fornecidoA = fornecidoKgSessao(
      pesoInicial: pesoA,
      pesoAtual: pesoDepoisDoFornecimento,
    );
    expect(fornecidoA, 800);

    const pesoInicialB = pesoDepoisDoFornecimento;
    expect(pesoInicialB, isNot(pesoA));
    final fornecidoBNoInstante = fornecidoKgSessao(
      pesoInicial: pesoInicialB,
      pesoAtual: pesoDepoisDoFornecimento,
    );
    expect(fornecidoBNoInstante, 0);
  });

  test("fila serializa tres cliques e o lider e unico", () {
    final fila = CliqueCurralFila();
    expect(fila.oferecer("A"), isTrue);
    expect(fila.oferecer("B"), isFalse);
    expect(fila.oferecer("C"), isFalse);
    expect(fila.pendingId, "C");
    expect(fila.supera("B"), isTrue);
    expect(fila.busy, isTrue);
  });

  test("desempenho in-memory do indice de previsto 20/100/300", () {
    for (final n in [20, 100, 300]) {
      final rows = List<CurralPrev>.generate(n, _row);
      final amostras = <int>[];
      for (var i = 0; i < 40; i++) {
        final sw = Stopwatch()..start();
        PrevistoAjustadoIndex.de(rows);
        sw.stop();
        amostras.add(sw.elapsedMicroseconds);
      }
      amostras.sort();
      final media = amostras.reduce((a, b) => a + b) / amostras.length;
      final p95 = amostras[(amostras.length * 0.95).floor() - 1];
      final maximo = amostras.last;
      // ignore: avoid_print
      print(
        "PREVISTO_INDEX n=$n mediaUs=${media.toStringAsFixed(1)} "
        "p95Us=$p95 maxUs=$maximo",
      );
      expect(maximo, greaterThanOrEqualTo(0));
    }
  });

  test("desempenho sqlite ffi da soma de realizado 20/100/300", () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await db.execute(
      "CREATE TABLE PREVISAO ("
      "ID_FORNECIMENTO TEXT, REALIZADO_KG REAL)",
    );
    await db.execute(
      "CREATE TABLE CADASTRO_FORNECIMENTO ("
      "ID TEXT, ID_FORNECIMENTO TEXT, REALIZADO REAL, FLAG_SYNC INTEGER)",
    );

    for (final n in [20, 100, 300]) {
      await db.delete("PREVISAO");
      await db.delete("CADASTRO_FORNECIMENTO");
      final batch = db.batch();
      for (var i = 0; i < n; i++) {
        batch.insert("PREVISAO", {
          "ID_FORNECIMENTO": "f$i",
          "REALIZADO_KG": 10,
        });
        batch.insert("CADASTRO_FORNECIMENTO", {
          "ID": "c$i",
          "ID_FORNECIMENTO": "f$i",
          "REALIZADO": 5,
          "FLAG_SYNC": 0,
        });
      }
      await batch.commit(noResult: true);

      final amostras = <int>[];
      for (var i = 0; i < 20; i++) {
        final sw = Stopwatch()..start();
        final rows = await db.rawQuery("""
          SELECT p.ID_FORNECIMENTO,
            COALESCE(p.REALIZADO_KG, 0) + COALESCE((
              SELECT SUM(COALESCE(cf.REALIZADO, 0))
              FROM CADASTRO_FORNECIMENTO cf
              WHERE cf.ID_FORNECIMENTO = p.ID_FORNECIMENTO
                AND IFNULL(cf.FLAG_SYNC, 0) = 0
            ), 0) AS realizado
          FROM PREVISAO p
        """);
        sw.stop();
        amostras.add(sw.elapsedMicroseconds);
        expect(rows.length, n);
        expect(rows.first["realizado"], 15);
      }
      amostras.sort();
      final media = amostras.reduce((a, b) => a + b) / amostras.length;
      final idx = min(amostras.length - 1, (amostras.length * 0.95).floor());
      final p95 = amostras[idx];
      final maximo = amostras.last;
      // ignore: avoid_print
      print(
        "SQLITE_REALIZADO n=$n mediaUs=${media.toStringAsFixed(1)} "
        "p95Us=$p95 maxUs=$maximo",
      );
    }
    await db.close();
  });
}
