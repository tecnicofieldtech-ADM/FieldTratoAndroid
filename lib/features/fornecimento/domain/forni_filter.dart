import 'dart:math';
import 'histerese_params.dart';

class ForniFilterState {
  double w0 = 0;          // baseline do curral
  double wEma = 0;
  double wMono = 0;
  double wConfirm = 0;

  // mediana curta
  final List<double> buf = List.filled(5, 0);
  int bufIdx = 0;
  int bufCount = 0;

  // gates
  DateTime? gateUpStart;

  // params
  late HistereseParams p;

  // limites
  double wNegMax = 3000.0;

  // base do realizado no banco quando entra no curral
  double realizadoBase = 0;

  DateTime lastTick = DateTime.now();
}

class ForniFilter {
  final ForniFilterState s = ForniFilterState();

  void startBaseline({
    required double pesoAtual,
    required HistereseParams params,
    required double realizadoBase,
  }) {
    s.p = params;
    s.w0 = pesoAtual;
    s.wEma = pesoAtual;
    s.wMono = pesoAtual;
    s.wConfirm = pesoAtual;
    s.bufIdx = 0;
    s.bufCount = 0;
    s.gateUpStart = null;
    s.realizadoBase = realizadoBase;
    s.lastTick = DateTime.now();
  }

  double _clamp(double v, double a, double b) => v < a ? a : (v > b ? b : v);

  double _median(List<double> arr, int count) {
    final t = arr.take(count).toList()..sort();
    return t[count ~/ 2];
  }

  /// Retorna null quando leitura inválida (fora bounds).
  double? update(double w) {
    final now = DateTime.now();
    var dt = now.difference(s.lastTick).inMilliseconds / 1000.0;
    if (dt <= 0) dt = 0.1;
    s.lastTick = now;

    // bootstrap failsafe
    if (s.w0 <= 0) {
      s.w0 = w;
      s.wEma = w;
      s.wMono = w;
      s.wConfirm = w;
      s.gateUpStart = null;
      return s.wConfirm;
    }

    final minBound = -s.wNegMax.abs();
    var maxBound = s.w0 * 1.02 + 30.0;

    if (w > maxBound && (w - s.w0).abs() <= 2000) {
      maxBound = w + 100;
    }

    if (w < minBound || w > maxBound) {
      return null; // inválida
    }

    // SMax: amansa salto
    final lastConfirm = s.wConfirm;
    double wInp;
    if ((w - lastConfirm).abs() > s.p.sMax) {
      wInp = w > lastConfirm ? (lastConfirm + s.p.sMax) : (lastConfirm - s.p.sMax);
    } else {
      wInp = w;
    }

    // mediana curta
    s.buf[s.bufIdx] = wInp;
    if (s.bufCount < s.buf.length) s.bufCount++;
    s.bufIdx = (s.bufIdx + 1) % s.buf.length;
    final wMed = _median(s.buf, s.bufCount);

    // EMA
    final wEma = s.p.alpha * wMed + (1 - s.p.alpha) * s.wEma;
    s.wEma = wEma;

    // monotônico com vazamento pra cima limitado
    final maxUpMono = s.p.rup * dt;
    var wMonoCand = min(wEma, s.wMono + maxUpMono);
    wMonoCand = _clamp(wMonoCand, minBound, s.w0);

    // === CONFIRMAÇÃO (fornecimento descarrega) ===
    if (wMonoCand < lastConfirm) {
      // descida livre
      s.wConfirm = wMonoCand;
      s.gateUpStart = null;
    } else {
      // subida amortecida (ruído)
      if (wMonoCand >= lastConfirm + s.p.dBack) {
        s.gateUpStart ??= now;
        final upElapsed = now.difference(s.gateUpStart!).inMilliseconds / 1000.0;
        if (upElapsed >= (s.p.tBackMs / 1000.0)) {
          final upStep = s.p.rUpBack * dt;
          s.wConfirm = min(wMonoCand, lastConfirm + upStep);
          s.gateUpStart = null;
        }
      } else {
        s.gateUpStart = null;
      }
    }

    s.wMono = wMonoCand;
    s.wConfirm = _clamp(s.wConfirm, minBound, s.w0);
    return s.wConfirm;
  }

  double calcRealizado(double wConfirm) {
    // base + max(0, w0 - wConfirm)
    return s.realizadoBase + max(0, s.w0 - wConfirm);
  }
}
