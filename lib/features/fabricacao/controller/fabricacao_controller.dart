// lib/features/fabricacao/controller/fabricacao_controller.dart
import "dart:async";
import "dart:math";
import "package:flutter/foundation.dart";

import "../../../db/app_db.dart";
import "../../../repo/config_repo.dart";
import "../../../helpers/scale_comm.dart";
import "../../../helpers/mirror_service.dart";

import "../data/fabricacao_repo.dart";
import "../domain/models.dart";

class FabricacaoController extends ChangeNotifier {
  FabricacaoController(this.repo);

  final FabricacaoRepo repo;

  bool _isDisposing = false;
  bool _isDisposed = false;

  void _safeNotify() {
    if (_isDisposed || _isDisposing) return;
    notifyListeners();
  }

  // =========================
  // ✅ CONFIG
  // =========================
  final _cfgRepo = ConfigRepo();

  /// ✅ TEMPO_MISTURA (MINUTOS). 0 = não abre timer
  int tempoMisturaMinValue = 0;

  /// ✅ TOLERANCIA_CARREGAMENTO (%). 0 = exige exato
  double toleranciaPct = 0.0;

  int get tempoMisturaMin =>
      tempoMisturaMinValue <= 0 ? 0 : tempoMisturaMinValue;

  /// ⚠️ compat: nome antigo "Kg" mas aqui agora significa "%"
  double get toleranciaKg => toleranciaPct;

  int get incrementoPeso => _incPeso;

  Future<void> loadConfigFabricacao() async {
    try {
      tempoMisturaMinValue = await _cfgRepo.getTempoMisturaMinutos();
    } catch (_) {
      tempoMisturaMinValue = 0;
    }

    try {
      toleranciaPct = await _cfgRepo.getToleranciaCarregamentoPct();
    } catch (_) {
      toleranciaPct = 0.0;
    }

    notifyListeners();
  }

  // =========================
  // Fabricação atual
  // =========================
  FabricacaoHeader? header;
  List<FabIngrediente> ingredientes = [];
  int idx = 0;

  FabIngrediente? get atual =>
      (ingredientes.isEmpty || idx < 0 || idx >= ingredientes.length)
          ? null
          : ingredientes[idx];

  // =========================================================
  // ✅ API pública para UI
  // =========================================================
  void setRealizadoLocalDoIngredienteAtual(int realizadoKg) {
    if (ingredientes.isEmpty || idx < 0 || idx >= ingredientes.length) return;
    final atualIng = ingredientes[idx];
    ingredientes[idx] = atualIng.copyWith(realizadoKg: realizadoKg);
    notifyListeners();
  }

  void setRealizadoLocalByDetId(String idDet, int realizadoKg) {
    final i = ingredientes.indexWhere((e) => e.idDet == idDet);
    if (i < 0) return;
    final atualIng = ingredientes[i];
    ingredientes[i] = atualIng.copyWith(realizadoKg: realizadoKg);
    notifyListeners();
  }

  // =========================
  // Balança (status)
  // =========================
  ScaleComm? _scale;

  StreamSubscription<ScaleEvent>? _stSub;
  StreamSubscription<ScaleWeightEvent>? _wSub;

  bool scaleConnected = false;
  bool scaleReceiving = false;
  bool scaleConnecting = false;

  DateTime? lastPacketAt;
  String lastRaw = "";
  double lastWeight = 0;

  int _incPeso = 1;

  bool get receivingNow {
    final dt = lastPacketAt;
    if (dt == null) return false;
    return DateTime.now().difference(dt).inSeconds <= 2;
  }

  String get scaleStatusLabel {
    if (scaleConnecting) return "Conectando…";
    if (!scaleConnected) return "Desconectada";
    if (scaleConnected && !receivingNow) return "Conectada, sem dados";
    return "OK ✅ Recebendo dados";
  }

  // =========================
  // ✅ ESPELHO
  // =========================
  bool get mirrorEnabled => MirrorService.instance.enabled;
  bool get mirrorConnected => MirrorService.instance.connected;

  String get mirrorLabel {
    if (!MirrorService.instance.enabled) return "Espelho: desligado";
    return MirrorService.instance.connected
        ? "Espelho: conectado (${MirrorService.instance.host}:${MirrorService.instance.port})"
        : "Espelho: tentando (${MirrorService.instance.host}:${MirrorService.instance.port})";
  }

  Future<void> startMirrorFromConfig() async {
    final ip = (await _cfgRepo.getIpEspelho()).trim();
    final port = await _cfgRepo.getPortaEspelho();

    await MirrorService.instance.configure(
      host: ip,
      port: port,
      onMessage: (msg) {
        final t = (msg["t"] ?? msg["cmd"] ?? "").toString();

        if (t == "next") {
          unawaited(() async {
            try {
              await next();
            } catch (_) {}
          }());
          return;
        }

        if (t == "prev") {
          unawaited(() async {
            try {
              await prev();
            } catch (_) {}
          }());
          return;
        }

        if (t == "ping") {
          MirrorService.instance.sendState({"t": "pong"}, force: true);
          return;
        }
      },
    );

    notifyListeners();
    _sendMirrorState(force: true);
  }

  Future<void> stopMirror() async {
    await MirrorService.instance.stop();
    notifyListeners();
  }

  // =========================
  // ✅ EVENTOS (pra Pá não “adivinhar”)
  // =========================
  void _sendMirrorEvent(String type, Map<String, dynamic> extra,
      {bool force = true}) {
    if (_closed) return;

    final h = header;
    MirrorService.instance.sendState({
      "t": "event",
      "stream": "fabricacao",
      "type": type,
      "fabId": h?.id ?? "",
      "trato": h?.trato ?? 0,
      "ts": DateTime.now().toIso8601String(),
      ...extra,
    }, force: force);
  }

  // =========================
  // ✅ STATE ENXUTO
  // =========================
  Map<String, dynamic>? _buildMirrorState() {
    final h = header;
    final a = atual;
    if (h == null || a == null) return null;

    FabIngrediente? prox;
    final i = idx + 1;
    if (i >= 0 && i < ingredientes.length) prox = ingredientes[i];

    final prev = a.previstoKg;
    final real = a.realizadoKg;

    final falta = (prev - real);
    final faltaClamp = falta < 0 ? 0 : falta;

    final autoOn = _autoTimer != null && _autoCountdown > 0;

    return {
      "t": "state",
      "stream": "fabricacao_resumo",
      "fabId": h.id,
      "trato": h.trato,
      "dieta": h.dietaNome,
      "finalizada": h.finalizada,
      "auto": {
        "enabled": autoOn ? 1 : 0,
        "countdown": autoOn ? _autoCountdown : 0,
        "fromPos": idx + 1,
        "toPos": (idx < ingredientes.length - 1) ? (idx + 2) : (idx + 1),
        "ts": DateTime.now().toIso8601String(),
      },
      "scale": {
        "connected": scaleConnected ? 1 : 0,
        "receiving": receivingNow ? 1 : 0,
        "weight": lastWeight.round(),
        "lastAt": lastPacketAt?.toIso8601String(),
        "raw": lastRaw,
      },
      "atual": {
        "nome": a.insumoNome,
        "prev": prev,
        "real": real,
        "falta": faltaClamp,
        "prePesado": a.isPrePesado ? 1 : 0,
        "pos": idx + 1,
        "total": ingredientes.length,
      },
      "prox": prox == null
          ? null
          : {
              "nome": prox.insumoNome,
              "prev": prox.previstoKg,
              "prePesado": prox.isPrePesado ? 1 : 0,
            },
      "ts": DateTime.now().toIso8601String(),
    };
  }

  bool _closed = false;

  void _sendMirrorState({bool force = false}) {
    if (_closed) return;
    final st = _buildMirrorState();
    if (st == null) return;
    MirrorService.instance.sendState(st, force: force);
  }

  // =========================
  // SHUTDOWN (sai da tela)
  // =========================
  Future<void> shutdown() async {
    if (_isDisposed || _isDisposing) return;

    _isDisposing = true;
    _closed = true;

    // cancela timers
    _cancelAutoPulo();

    // para mirror/scale (podem ter await)
    try {
      await stopMirror();
    } catch (_) {}
    try {
      await stopScale();
    } catch (_) {}

    // ✅ não chama notify se já foi disposed
    _isDisposing = false;
    _safeNotify();
  }

  // =========================
  // ✅ REGRA DO REALIZADO (IGUAL DELPHI)
  // =========================
  String _lastDetId = "";
  bool _baseDefinida = false;
  bool _baselinePending = false;
  int _pesoInicialPrimeiro = 0;
  int _realizadoAcumBanco = 0;

  int get pesoInicialIngrediente => _pesoInicialPrimeiro;

  // =========================
  // Auto pulo
  // =========================
  Timer? _autoTimer;
  int _autoCountdown = 0;
  int get autoCountdown => _autoCountdown;

  bool _jumping = false;
  bool _autoPuloDisparado = false;

  // =========================================================
  // BOOT / RESUME
  // =========================================================
  Future<bool> resumeOpenIfAny() async {
    final aberto = await repo.getFabricacaoEmAbertoHoje();
    if (aberto == null) return false;

    header = aberto;
    ingredientes = await repo.listIngredientesDaFabricacao(aberto.id);

    idx = 0;
    for (var i = 0; i < ingredientes.length; i++) {
      if (ingredientes[i].realizadoKg > 0) idx = i;
    }

    _cancelAutoPulo();
    _resetRealizadoStateForCurrent(baselinePending: true);

    notifyListeners();
    _sendMirrorState(force: true);

    return true;
  }

  Future<void> goToIndex(int index) async {
    if (ingredientes.isEmpty) return;
    if (index < 0 || index >= ingredientes.length) return;
    if (index == idx) return;
    if (_jumping) return;

    _jumping = true;
    try {
      _cancelAutoPulo();

      await salvarIngredienteAtual();
      await atualizaFabricacaoParcial();

      idx = index;
      _resetRealizadoStateForCurrent(baselinePending: true);

      _sendMirrorState(force: true);
      notifyListeners();
    } finally {
      _jumping = false;
    }
  }

  void _cancelAutoPulo() {
    final had = _autoTimer != null;

    _autoTimer?.cancel();
    _autoTimer = null;
    _autoCountdown = 0;

    if (had) {
      _sendMirrorEvent("auto_pulo_cancel", {
        "ts": DateTime.now().toIso8601String(),
      });
      _sendMirrorState(force: true);
    }
  }

  // =========================================================
  // BALANÇA
  // =========================================================
  Future<void> startScaleFromConfig() async {
    final host = (await _cfgRepo.getHostBalanca()).trim();
    final port = await _cfgRepo.getPortaBalanca();
    final modelInt = await _cfgRepo.getModeloBalanca();

    final inc = await _cfgRepo.getIncrementoPeso();
    _incPeso = inc.clamp(1, 10);

    if (host.isEmpty || port <= 0) {
      _setScaleDisconnected(notify: true);
      _sendMirrorState();
      return;
    }

    final model = _scaleModelFromInt(modelInt);

    await _stopScale();

    scaleConnecting = true;
    scaleConnected = false;
    scaleReceiving = false;
    notifyListeners();

    try {
      _scale = ScaleComm(
        host: host,
        port: port,
        model: model,
        allowNegative: true,
        autoReconnect: true,
        connectTimeout: const Duration(seconds: 3),
        reconnectDelay: const Duration(milliseconds: 800),
      );

      _scale!.setThrottle(minDelta: 1.0, minIntervalMs: 80);

      _stSub = _scale!.statusStream.listen((st) {
        switch (st.status) {
          case ScaleStatus.connecting:
            scaleConnecting = true;
            scaleConnected = false;
            scaleReceiving = false;
            break;
          case ScaleStatus.connected:
            scaleConnecting = false;
            scaleConnected = true;
            break;
          case ScaleStatus.disconnected:
            scaleConnecting = false;
            scaleConnected = false;
            scaleReceiving = false;
            break;
          case ScaleStatus.error:
            scaleConnecting = false;
            scaleConnected = false;
            scaleReceiving = false;
            if (st.message != null) lastRaw = st.message!;
            break;
        }
        _sendMirrorState();
        notifyListeners();
      });

      _wSub = _scale!.weightStream.listen((ev) {
        lastPacketAt = ev.readAt;
        lastRaw = ev.rawLine;

        lastWeight = _applyIncrement(ev.weight, _incPeso);

        scaleConnecting = false;
        scaleConnected = true;
        scaleReceiving = true;

        _processaPesoParaRealizado(lastWeight.round());

        _sendMirrorState();
        notifyListeners();
      });

      await _scale!.connect();

      scaleConnecting = false;
      _sendMirrorState(force: true);
      notifyListeners();
    } catch (e) {
      scaleConnecting = false;
      lastRaw = e.toString();
      _setScaleDisconnected(notify: true);
      _sendMirrorState();
    }
  }

  double _applyIncrement(double w, int inc) {
    if (inc <= 1) return w;
    final v = (w / inc).round() * inc;
    return v.toDouble();
  }

  Future<void> reconnectScale() async {
    await startScaleFromConfig();
  }

  Future<void> _stopScale() async {
    try {
      await _stSub?.cancel();
    } catch (_) {}
    try {
      await _wSub?.cancel();
    } catch (_) {}
    _stSub = null;
    _wSub = null;

    try {
      await _scale?.dispose();
    } catch (_) {}
    _scale = null;
  }

  Future<void> stopScale() async {
    try {
      await _stSub?.cancel();
    } catch (_) {}
    try {
      await _wSub?.cancel();
    } catch (_) {}
    _stSub = null;
    _wSub = null;

    final s = _scale;
    _scale = null;

    if (s != null) {
      s.stopNow();
      try {
        await s.dispose();
      } catch (_) {}
    }

    _setScaleDisconnected(notify: true);
  }

  void _setScaleDisconnected({bool notify = false}) {
    scaleConnecting = false;
    scaleConnected = false;
    scaleReceiving = false;
    lastPacketAt = null;
    if (notify) notifyListeners();
  }

  ScaleModel _scaleModelFromInt(int v) {
    switch (v) {
      case 0:
        return ScaleModel.topcom;
      case 1:
        return ScaleModel.dg500;
      case 2:
        return ScaleModel.alfa;
      default:
        return ScaleModel.raw;
    }
  }

  // =========================================================
  // REALIZADO
  // =========================================================
  void _resetRealizadoStateForCurrent({required bool baselinePending}) {
    final ing = atual;
    if (ing == null) return;

    _lastDetId = ing.idDet;
    _realizadoAcumBanco = ing.realizadoKg;

    _baseDefinida = false;
    _baselinePending = baselinePending;
    _pesoInicialPrimeiro = 0;

    _autoPuloDisparado = false;
  }

  void _ensureIngredienteState() {
    final ing = atual;
    if (ing == null) return;

    final detId = ing.idDet;
    if (detId.isNotEmpty && detId != _lastDetId) {
      _resetRealizadoStateForCurrent(baselinePending: true);
      _cancelAutoPulo();
    }
  }

  void _processaPesoParaRealizado(int pesoAtualInt) {
    final ing = atual;
    if (ing == null) return;
    if (ing.isPrePesado) return;

    _ensureIngredienteState();

    if (_baselinePending) {
      _pesoInicialPrimeiro = pesoAtualInt;
      _baseDefinida = true;
      _baselinePending = false;
      return;
    }

    if (!_baseDefinida) {
      _pesoInicialPrimeiro = pesoAtualInt;
      _baseDefinida = true;
      return;
    }

    int incremento = pesoAtualInt - _pesoInicialPrimeiro;
    if (incremento < 0) incremento = 0;

    final realizado = _realizadoAcumBanco + incremento;

    if (realizado != ing.realizadoKg) {
      ingredientes[idx] = ing.copyWith(realizadoKg: realizado);
    }

    if (realizado > _realizadoAcumBanco) {
      _applyAutoPuloIfNeeded();
    }
  }

  // =========================================================
  // TOLERÂNCIA
  // =========================================================
  double _tolKgParaPrevisto(int previstoKg) {
    if (previstoKg <= 0) return 0.0;
    if (toleranciaPct <= 0) return 0.0;
    return previstoKg.toDouble() * (toleranciaPct / 100.0);
  }

  bool _dentroTolerancia(int previstoKg, int realizadoKg) {
    if (previstoKg <= 0) return false;

    final dif = (realizadoKg - previstoKg).abs().toDouble();

    if (toleranciaPct <= 0) return dif == 0.0;

    final tolKg = _tolKgParaPrevisto(previstoKg);
    return dif <= tolKg;
  }

  // =========================================================
  // SALVAR ingrediente atual
  // =========================================================
  Future<void> salvarIngredienteAtual() async {
    final ing = atual;
    if (ing == null) return;
    if (ing.isPrePesado) return;

    final prev = ing.previstoKg;
    final newReal = ing.realizadoKg;
    final oldReal = _realizadoAcumBanco;

    if ((newReal - oldReal).abs() < 1) return;

    final agora = _fmtHHmmss(DateTime.now());

    final oldIni = await repo.getHoraInicioByDetId(ing.idDet);
    final oldFim = await repo.getHoraFimByDetId(ing.idDet);

    final newIni = (oldIni.trim().isEmpty && newReal > 0) ? agora : oldIni;

    final dentro = _dentroTolerancia(prev, newReal);
    final newFim = (dentro && oldFim.trim().isEmpty) ? agora : oldFim;

    await repo.updateIngredienteFabricacao(
      idDet: ing.idDet,
      qtdRealizada: newReal.toDouble(),
      horaInicio: newIni,
      horaFim: newFim,
    );

    _realizadoAcumBanco = newReal;
    _sendMirrorState();
  }

  String _fmtHHmmss(DateTime d) {
    String dd(int v) => v.toString().padLeft(2, "0");
    return "${dd(d.hour)}:${dd(d.minute)}:${dd(d.second)}";
  }

  Future<void> atualizaFabricacaoParcial() async {
    final h = header;
    if (h == null) return;

    await repo.updateFabricacaoParcial(h.id);
    _sendMirrorState();
  }

  // =========================================================
  // PRÉ-PESADO
  // =========================================================
  Future<void> confirmarIngredientePrePesado(int realizadoKg) async {
    final ing = atual;
    final head = header;
    if (ing == null || head == null) return;

    final agora = DateTime.now();
    String fmt(DateTime d) =>
        "${d.hour.toString().padLeft(2, "0")}:${d.minute.toString().padLeft(2, "0")}:${d.second.toString().padLeft(2, "0")}";
    final hora = fmt(agora);

    await repo.updateIngredienteFabricacao(
      idDet: ing.idDet,
      qtdRealizada: realizadoKg.toDouble(),
      horaInicio: hora,
      horaFim: hora,
    );

    await repo.updateFabricacaoParcial(head.id);

    ingredientes[idx] = ing.copyWith(realizadoKg: realizadoKg);

    _sendMirrorState(force: true);

    final isLast = idx == ingredientes.length - 1;
    if (!isLast) {
      await next();
    } else {
      notifyListeners();
    }
  }

  // =========================================================
  // ✅ AUTO PULO + EVENTO
  // =========================================================
  void _applyAutoPuloIfNeeded() {
    if (_jumping) return;
    if (_autoPuloDisparado) return;

    final ing = atual;
    if (ing == null) return;
    if (ing.isPrePesado) return;

    final prevInt = ing.previstoKg;
    if (prevInt <= 0) return;

    final realInt = ing.realizadoKg;

    final tolKg = _tolKgParaPrevisto(prevInt);
    final minAceitavel = (tolKg > 0) ? (prevInt - tolKg) : prevInt;

    final atingiu = realInt >= minAceitavel;
    if (!atingiu) return;

    _autoPuloDisparado = true;
    _startAutoCountdown();
  }

  Future<void> _startAutoCountdown() async {
    if (_autoTimer != null) return;

    final puloAuto = await _cfgRepo.getPuloAutomatico();
    final secs = await _cfgRepo.getTempoPuloSegundos();

    if (puloAuto != 1) {
      _cancelAutoPulo();
      return;
    }

    final s = secs <= 0 ? 1 : secs;

    _autoCountdown = s;
    notifyListeners();

    _sendMirrorEvent("auto_pulo", {
      "seconds": s,
      "fromPos": idx + 1,
      "toPos": (idx < ingredientes.length - 1) ? (idx + 2) : (idx + 1),
      "atual": (atual?.insumoNome ?? ""),
      "prox": (idx < ingredientes.length - 1)
          ? (ingredientes[idx + 1].insumoNome)
          : "",
      "ts": DateTime.now().toIso8601String(),
    });

    _sendMirrorState(force: true);

    _autoTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      _autoCountdown--;
      if (_autoCountdown < 0) _autoCountdown = 0;

      notifyListeners();
      _sendMirrorState(force: true);

      if (_autoCountdown <= 0) {
        _autoCountdown = 0;
        t.cancel();
        _autoTimer = null;

        _sendMirrorEvent("auto_pulo_end", {
          "fromPos": idx + 1,
          "toPos": (idx < ingredientes.length - 1) ? (idx + 2) : (idx + 1),
          "ts": DateTime.now().toIso8601String(),
        });

        _sendMirrorState(force: true);

        unawaited(() async {
          try {
            await next();
          } catch (_) {}
        }());
      }
    });
  }

  // =========================================================
  // Navegação ingredientes
  // =========================================================
  Future<void> next() async {
    if (_jumping) return;

    _jumping = true;
    try {
      _cancelAutoPulo();

      await salvarIngredienteAtual();
      await atualizaFabricacaoParcial();

      if (idx < ingredientes.length - 1) {
        idx++;

        _autoPuloDisparado = false;
        _resetRealizadoStateForCurrent(baselinePending: true);

        _sendMirrorState(force: true);
        notifyListeners();
      }
    } finally {
      _jumping = false;
    }
  }

  Future<void> prev() async {
    if (_jumping) return;

    _jumping = true;
    try {
      _cancelAutoPulo();

      if (idx > 0) {
        idx--;

        _autoPuloDisparado = false;
        _resetRealizadoStateForCurrent(baselinePending: true);

        _sendMirrorState(force: true);
        notifyListeners();
      }
    } finally {
      _jumping = false;
    }
  }

  // =========================================================
  // FINALIZAÇÃO (antes do timer)
  // =========================================================
  Future<int> finalizarFabricacaoAntesDoTimer() async {
    final h = header;
    if (h == null) return 0;

    await salvarIngredienteAtual();
    await atualizaFabricacaoParcial();

    final agora = _fmtHHmmss(DateTime.now());
    final total = await repo.getTotalRealizadoFabricacao(h.id);

    await repo.finalizaFabricacao(
      idFabricacao: h.id,
      qtdRealizada: total,
      horaFim: agora,
      finalizada: 1,
    );

    header = h.copyWith(
      finalizada: 1,
      qtdRealizada: total,
    );

    notifyListeners();

    _sendMirrorEvent("finalizada", {"msg": "Fabricação finalizada ✅"});
    _sendMirrorState(force: true);

    try {
      final min = await _cfgRepo.getTempoMisturaMinutos();
      if (min <= 0) return 0;
      return min;
    } catch (_) {
      return 0;
    }
  }

  // =========================================================
  // Finalização completa
  // =========================================================
  Future<void> finalizarFabricacao() async {
    final h = header;
    if (h == null) return;

    await salvarIngredienteAtual();
    await repo.updateFabricacaoParcial(h.id);

    final db = await AppDb.instance.db;

    const det = "DETALHES_FABRICA_RACAO";
    const head = "CADASTRO_FABRICA_RACAO";
    const carreg = "CARREGAMENTO";

    String pickDetRealCol(List<Map<String, Object?>> info) {
      final cols =
          info.map((e) => (e["name"] ?? "").toString().toLowerCase()).toSet();
      if (cols.contains("qtd_realizada")) return "QTD_REALIZADA";
      if (cols.contains("realizadokg")) return "REALIZADOKG";
      if (cols.contains("realizado_kg")) return "REALIZADO_KG";
      return "QTD_REALIZADA";
    }

    String pickDetIdFabCol(List<Map<String, Object?>> info) {
      final cols =
          info.map((e) => (e["name"] ?? "").toString().toLowerCase()).toSet();
      if (cols.contains("id_fabricacao")) return "ID_FABRICACAO";
      if (cols.contains("idfabricacao")) return "IDFABRICACAO";
      if (cols.contains("id_cabecalho")) return "ID_CABECALHO";
      if (cols.contains("id_header")) return "ID_HEADER";
      return "ID_FABRICACAO";
    }

    final detInfo = await db.rawQuery("PRAGMA table_info($det)");
    final detRealCol = pickDetRealCol(detInfo);
    final detIdFabCol = pickDetIdFabCol(detInfo);

    final sumRow = await db.rawQuery(
      "SELECT COALESCE(SUM(COALESCE($detRealCol,0)),0) AS s FROM $det WHERE $detIdFabCol = ?",
      [h.id],
    );

    final totalReal =
        (sumRow.isNotEmpty ? (sumRow.first["s"] as num?)?.toDouble() : 0.0) ??
            0.0;

    double msReal = 0.0;
    try {
      final r = await db.rawQuery(
        "SELECT COALESCE(MS_REALIZADA,0) AS ms FROM $head WHERE ID = ? LIMIT 1",
        [h.id],
      );
      msReal =
          (r.isNotEmpty ? (r.first["ms"] as num?)?.toDouble() : 0.0) ?? 0.0;
    } catch (_) {
      msReal = 0.0;
    }

    final horaFim = _fmtHHmmss(DateTime.now());

    try {
      await db.rawUpdate(
        """
        UPDATE $head
        SET
          QTD_REALIZADA = ?,
          HORA_FIM = ?,
          FINALIZADA = 1,
          MS_REALIZADA = ?
        WHERE ID = ?
        """,
        [totalReal, horaFim, msReal, h.id],
      );
    } catch (_) {
      await db.rawUpdate(
        """
        UPDATE $head
        SET
          QTD_REALIZADA = ?,
          HORA_FIM = ?,
          FINALIZADA = 1
        WHERE ID = ?
        """,
        [totalReal, horaFim, h.id],
      );
    }

    header = h.copyWith(finalizada: 1, qtdRealizada: totalReal);
    notifyListeners();

    int tipoTrabalho = 0;
    String idVagao = "";
    try {
      tipoTrabalho = await _cfgRepo.getTipoTrabalho();
    } catch (_) {
      tipoTrabalho = 0;
    }
    try {
      idVagao = (await _cfgRepo.getIdVagao()).toString().trim();
    } catch (_) {
      idVagao = "";
    }

    final pesoFabricado = totalReal;
    final pesoCarregado = (tipoTrabalho == 0) ? totalReal : 0.0;

    final idDieta = (h.idDieta).toString();
    final uid = _genIdUnico();

    final dataRegistro = DateTime.now().toIso8601String();

    final vagaoIdInt = int.tryParse(idVagao) ?? 0;
    if (vagaoIdInt <= 0) {
      throw Exception(
          "Vagão não configurado. Selecione um vagão nas configurações.");
    }

    await db.execute(
      """
      INSERT INTO $carreg(
        ID,
        DATA_REGISTRO,
        STATUS,
        ID_FABRICACAO,
        ID_DIETA,
        PESO_FABRICADO,
        PESO_CARREGADO,
        ID_VAGAO
      ) VALUES(?,?,?,?,?,?,?,?)
      """,
      [
        uid,
        dataRegistro,
        1, // ✅ ABERTO
        h.id,
        idDieta,
        pesoFabricado,
        pesoCarregado,
        vagaoIdInt,
      ],
    );

    _sendMirrorEvent("finalizada", {"msg": "Fabricação finalizada ✅"});
    _sendMirrorState(force: true);
  }

  String _genIdUnico() {
    final r = Random.secure();
    String h(int v) => v.toRadixString(16).padLeft(2, "0");
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final s = b.map(h).join();
    return "${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}";
  }

  // =========================================================
  // BOOT helper
  // =========================================================
  Future<bool> bootTruckSide() async {
    final ok = await resumeOpenIfAny();
    if (!ok) return false;

    _closed = false;

    await loadConfigFabricacao();
    await startMirrorFromConfig();
    await startScaleFromConfig();

    _sendMirrorState(force: true);
    return true;
  }

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposing = true;
    _isDisposed = true;
    _closed = true;

    // cancela timers
    _cancelAutoPulo();

    // ✅ cancela streams imediatamente (sem notify)
    try {
      _stSub?.cancel();
    } catch (_) {}
    try {
      _wSub?.cancel();
    } catch (_) {}
    _stSub = null;
    _wSub = null;

    // ✅ mata scale sem await
    try {
      _scale?.stopNow();
    } catch (_) {}
    _scale = null;

    // ✅ mata mirror sem await
    try {
      MirrorService.instance.stop();
    } catch (_) {}

    super.dispose();
  }
}
