import "fornecimento_models.dart";

/// Cadastro do trato (sem o saldo do último). Null se o último trato
/// não tiver o cadastro gravado — nesse caso não dá para recompor a meta.
double? cadastroPrevistoKg(CurralPrev c) {
  final cad = c.previstoCadastroKg ?? 0;
  if (cad > 0) return cad;
  if (c.isUltimoTrato) return null;
  final orig = c.previstoOriginalKg ?? 0;
  if (orig > 0) return orig;
  if (c.previstoKg > 0) return c.previstoKg;
  return null;
}

/// Extra local (não sincronizado) = realizado total − realizado da API.
double realizadoLocalExtraKg(CurralPrev c) {
  final api = c.realizadoApiKg;
  final baseApi = api == null ? c.realizadoKg : (api < 0 ? 0.0 : api);
  final extra = c.realizadoKg - baseApi;
  return extra > 0 ? extra : 0.0;
}

/// Base do último trato = PREVISTO_RECALCULADO da API (já ajustado).
/// Só desconta a mais o realizado local ainda não sincronizado dos
/// tratos anteriores. Não refaz soma(cadastro) − realizado (isso
/// descontava duas vezes). Transição: último = maior trato da baia
/// no dia, qualquer ração.
class PrevistoAjustadoIndex {
  PrevistoAjustadoIndex._(this._kg, this._ultimo);

  final Map<CurralPrev, double> _kg;
  final Map<CurralPrev, bool> _ultimo;

  factory PrevistoAjustadoIndex.de(Iterable<CurralPrev> rows) {
    final groups = <String, List<CurralPrev>>{};
    for (final r in rows) {
      groups.putIfAbsent(_grupo(r), () => <CurralPrev>[]).add(r);
    }

    final kg = Map<CurralPrev, double>.identity();
    final ultimo = Map<CurralPrev, bool>.identity();

    for (final list in groups.values) {
      var maxTrato = 0;
      for (final r in list) {
        if (r.trato > maxTrato) maxTrato = r.trato;
      }

      var localExtraAnterior = 0.0;
      final doUltimo = <CurralPrev>[];
      for (final r in list) {
        if (r.trato < maxTrato) {
          localExtraAnterior += realizadoLocalExtraKg(r);
        } else if (r.trato == maxTrato && maxTrato > 0) {
          doUltimo.add(r);
        }
      }

      var baseUltimo = 0.0;
      for (final r in doUltimo) {
        baseUltimo += _baseApiUltimo(r);
      }
      final meta = (baseUltimo - localExtraAnterior) < 0
          ? 0.0
          : (baseUltimo - localExtraAnterior);

      for (final r in list) {
        if (r.trato != maxTrato || maxTrato <= 0) {
          kg[r] = cadastroPrevistoKg(r) ?? r.previstoMapaKg;
          ultimo[r] = false;
          continue;
        }

        final base = _baseApiUltimo(r);
        final share = baseUltimo > 0
            ? base / baseUltimo
            : (doUltimo.isEmpty ? 1.0 : 1.0 / doUltimo.length);
        kg[r] = meta * share;
        ultimo[r] = true;
      }
    }

    return PrevistoAjustadoIndex._(kg, ultimo);
  }

  static double _baseApiUltimo(CurralPrev r) {
    final rec = r.previstoRecalculadoKg ?? 0;
    if (rec > 0) return rec;
    final mapa = r.previstoMapaKg;
    if (mapa > 0) return mapa;
    return cadastroPrevistoKg(r) ?? 0;
  }

  static String _grupo(CurralPrev c) {
    final lote = (c.idLote ?? "").trim();
    return "${c.dataIso}|${c.idBaia.trim()}|$lote";
  }

  double de(CurralPrev c) => _kg[c] ?? c.previstoMapaKg;

  bool ehUltimo(CurralPrev c) => _ultimo[c] ?? c.isUltimoTrato;
}
