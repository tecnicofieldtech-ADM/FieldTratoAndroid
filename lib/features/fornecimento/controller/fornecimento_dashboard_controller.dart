// lib/features/fornecimento/controller/fornecimento_dashboard_controller.dart
import "dart:async";
import "package:flutter/foundation.dart";

import "../../../helpers/scale_comm.dart";
import "../../../helpers/rfid_comm.dart";
import "../../../constants/config_options.dart";
import "../../../repo/config_repo.dart";
import "../data/fornecimento_repo.dart";
import "../domain/fornecimento_models.dart";
import "../domain/fornecimento_peso.dart";
import "../../../services/session_service.dart";
import "../../../services/rfid_tag_resolver.dart";
import "../../../utils/rfid_tag_utils.dart";

class FornecimentoHeaderVM {
  final int? trato;
  final DateTime data;
  final String? racaoId;
  final String? racaoNome;
  final String? carregamentoId;

  const FornecimentoHeaderVM({
    this.trato,
    required this.data,
    required this.racaoId,
    required this.racaoNome,
    required this.carregamentoId,
  });

  bool get tratoSelecionado => (trato ?? 0) > 0;
}

class CurralCardVM {
  final String idFornecimento;
  final String idBaia;
  final String curralNome;
  final String? linha;
  final int orderTrato;
  final double previstoKg;
  final double previstoOriginalKg;
  final double previstoRecalculadoKg;
  final bool isUltimoTrato;
  final bool previsaoDuplaFieldpec;
  final double realizadoKg;
  final String? epc;

  const CurralCardVM({
    required this.idFornecimento,
    required this.idBaia,
    required this.curralNome,
    required this.linha,
    required this.orderTrato,
    required this.previstoKg,
    required this.previstoOriginalKg,
    required this.previstoRecalculadoKg,
    this.isUltimoTrato = false,
    this.previsaoDuplaFieldpec = false,
    required this.realizadoKg,
    required this.epc,
  });

  bool get isUltimoTratoEfetivo {
    if (isUltimoTrato) return true;
    if (!previsaoDuplaFieldpec) return false;
    if (previstoOriginalKg > 0 &&
        previstoRecalculadoKg >= 0 &&
        (previstoOriginalKg - previstoRecalculadoKg).abs() > 0.01) {
      return true;
    }
    // Fallback: meta original maior que previsto cadastro da linha.
    return previstoOriginalKg > 0 &&
        previstoKg > 0 &&
        previstoOriginalKg > previstoKg + 0.01;
  }

  /// Meta fixa de previsto (nunca muda após fornecimento parcial).
  double get previstoFixoKg =>
      previstoOriginalKg > 0 ? previstoOriginalKg : previstoKg;

  double get diffKg => realizadoKg - previstoFixoKg;

  /// Previsto exibido no mapa/painel — sempre o valor original planejado.
  double get previstoExibicaoKg => previstoFixoKg;

  /// @deprecated Use [previstoFixoKg]. Mantido para compatibilidade interna.
  double get metaPrevistoUltimoTratoKg => previstoFixoKg;
}

class TotaisVM {
  final double totalPrevistoKg;
  final double totalRealizadoKg;

  const TotaisVM({
    required this.totalPrevistoKg,
    required this.totalRealizadoKg,
  });

  double get diffKg => totalRealizadoKg - totalPrevistoKg;
}

class UltimoFornecimentoVM {
  final String curralNome;
  final double fornecidoKg;

  const UltimoFornecimentoVM({
    required this.curralNome,
    required this.fornecidoKg,
  });
}

/// Controller do Dashboard (Mapa + Sessão + RFID AutoFlow)
class FornecimentoDashboardController extends ChangeNotifier {
  FornecimentoDashboardController({
    required FornecimentoRepo repo,
    required ScaleComm scale,
    required RfidComm rfid,
    ConfigRepo? configRepo,
    bool autoFlowRfid = true, // RFID comanda iniciar/salvar
  })  : _repo = repo,
        _scale = scale,
        _rfid = rfid,
        _cfg = configRepo ?? ConfigRepo(),
        _autoFlowRfid = autoFlowRfid;

  final FornecimentoRepo _repo;
  final ScaleComm _scale;
  final RfidComm _rfid;
  final ConfigRepo _cfg;
  final RfidTagResolver _rfidTagResolver = RfidTagResolver();

  final bool _autoFlowRfid;

  // ===========================
  // Estado básico
  // ===========================

  bool _loading = true;
  bool get loading => _loading;

  String? _error;
  String? get error => _error;

  FornecimentoHeaderVM? _header;
  FornecimentoHeaderVM? get header => _header;

  TotaisVM _totais = const TotaisVM(totalPrevistoKg: 0, totalRealizadoKg: 0);
  TotaisVM get totais => _totais;

  List<CurralCardVM> _curraisAll = const [];
  List<CurralCardVM> get currais => _curraisAll;

  CurralCardVM? _selected;
  CurralCardVM? get selected => _selected;

  UltimoFornecimentoVM? _ultimo;
  UltimoFornecimentoVM? get ultimo => _ultimo;

  // ===========================
  // UI Notice (banner/toast)
  // ===========================

  String? _uiNotice;
  String? get uiNotice => _uiNotice;

  String? _uiNoticeTitle;
  String? get uiNoticeTitle => _uiNoticeTitle;

  DateTime _lastNoticeAt = DateTime.fromMillisecondsSinceEpoch(0);
  String _lastNoticeKey = "";

  void clearNotice() {
    if (_uiNotice == null && _uiNoticeTitle == null) return;
    _uiNotice = null;
    _uiNoticeTitle = null;
    notifyListeners();
  }

  void _setNotice(
    String msg, {
    String key = "",
    String? title,
    int cooldownMs = 1200,
  }) {
    final now = DateTime.now();
    if (key.isNotEmpty &&
        key == _lastNoticeKey &&
        now.difference(_lastNoticeAt).inMilliseconds < cooldownMs) {
      return;
    }
    _uiNotice = msg;
    _uiNoticeTitle = title ?? _defaultNoticeTitle(key);
    _lastNoticeAt = now;
    _lastNoticeKey = key;
    notifyListeners();
  }

  String _defaultNoticeTitle(String key) {
    if (key.startsWith("rfid_sem_previsto")) return "Curral sem previsto";
    if (key.startsWith("rfid_pause")) return "RFID pausado";
    if (key.startsWith("rfid_autosave") || key.startsWith("rfid_autostart")) {
      return "Fornecimento";
    }
    if (key.startsWith("rfid_flow")) return "RFID";
    return "Aviso";
  }

  void _cancelPendingRfid() {
    _pendingEpcTimer?.cancel();
    _pendingEpcTimer = null;
    _pendingEpcBoot = null;
  }

  // ===========================
  // Status (Balança / RFID)
  // ===========================

  ScaleStatus _scaleStatus = ScaleStatus.disconnected;
  ScaleStatus get scaleStatus => _scaleStatus;

  String? _scaleMsg;
  String? get scaleMsg => _scaleMsg;

  RfidStatus _rfidStatus = RfidStatus.disconnected;
  RfidStatus get rfidStatus => _rfidStatus;

  String? _rfidMsg;
  String? get rfidMsg => _rfidMsg;

  StreamSubscription<ScaleEvent>? _scaleStatusSub;
  StreamSubscription<RfidStatusEvent>? _rfidStatusSub;

  // ===========================
  // Balança (tempo real)
  // ===========================

  double _pesoAtual = 0;
  double get pesoAtual => _pesoAtual;
  String lastScaleRaw = "";

  StreamSubscription<ScaleWeightEvent>? _scaleSub;

  // ===========================
  // RFID
  // ===========================

  bool _rfidPausado = false;
  bool get rfidPausado => _rfidPausado;

  StreamSubscription<RfidTagEvent>? _rfidSub;

  bool _rfidProcessing = false;
  bool _rfidPauseToggleBusy = false;

  String _lastRfidHandled = "";
  DateTime _lastRfidHandledAt = DateTime.fromMillisecondsSinceEpoch(0);
  String? _pendingEpcBoot;
  Timer? _pendingEpcTimer;

  // ===========================
  // Sessão
  // ===========================

  bool _sessaoAtiva = false;
  bool get sessaoAtiva => _sessaoAtiva;
  bool get aguardandoInicioSessao => _selected != null && !_sessaoAtiva;

  double? _pesoInicial;
  double? get pesoInicial => _pesoInicial;

  /// ✅ ID do CADASTRO_FORNECIMENTO em aberto (SQLite)
  String? _idCadastroAberto;

  String _idFazenda = "";
  bool _isFieldpec = false;

  int _origemMapa = 0; // 0 = RFID, 1 = Mapa

  // Proteção double-start
  bool _startingSessao = false;
  DateTime _lastStartAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime? _sessaoIniciadaEm;
  bool _rebasePesoInicialFeito = false;

  // ===========================
  // “tempo real” no painel
  // ===========================

  double get fornecidoSessaoKg {
    if (!_sessaoAtiva) return 0;
    final ini = _pesoInicial ?? 0;
    return fornecidoKgSessao(pesoInicial: ini, pesoAtual: _pesoAtual);
  }

  /// Realizado (est.) − previsto fixo (mesma base do Dif).
  /// Exibição A FORNECER: falta → valor positivo sem sinal; excedeu → +valor.
  double get aFornecerEstimadoKg {
    final s = _selected;
    if (s == null) return 0;

    final previsto = s.previstoFixoKg;
    final realizadoEst = s.realizadoKg + fornecidoSessaoKg;
    return realizadoEst - previsto;
  }

  double get previstoPainelKg {
    final s = _selected;
    if (s == null) return 0;
    return s.previstoFixoKg;
  }

  bool get isFieldpecUltimoTratoSelecionado {
    final s = _selected;
    return _isFieldpec &&
        s != null &&
        s.previsaoDuplaFieldpec &&
        s.isUltimoTratoEfetivo;
  }

  double get realizadoEstimadoKg {
    final s = _selected;
    if (s == null) return 0;
    return s.realizadoKg + fornecidoSessaoKg;
  }

  // ===========================
  // Filtro por Linha
  // ===========================

  String? _linhaFiltro;
  String? get linhaFiltro => _linhaFiltro;

  List<String> get linhasDisponiveis {
    final set = <String>{};
    for (final c in _curraisAll) {
      final l = (c.linha ?? "").trim();
      if (l.isNotEmpty) set.add(l);
    }
    final list = set.toList()
      ..sort((a, b) {
        final ia = int.tryParse(a);
        final ib = int.tryParse(b);
        if (ia != null && ib != null) return ia.compareTo(ib);
        if (ia != null && ib == null) return -1;
        if (ia == null && ib != null) return 1;
        return a.compareTo(b);
      });
    return list;
  }

  List<CurralCardVM> get curraisFiltrados {
    if (!tratoSelecionado) return const [];
    final lf = (_linhaFiltro ?? "").trim();
    if (lf.isEmpty) return _curraisAll;
    final lfUp = lf.toUpperCase();
    return _curraisAll
        .where((c) => (c.linha ?? "").trim().toUpperCase() == lfUp)
        .toList();
  }

  void setLinhaFiltro(String? linha) {
    final v = (linha ?? "").trim();
    final next = v.isEmpty ? null : v;
    if (_linhaFiltro == next) return;
    _linhaFiltro = next;
    notifyListeners();
  }

  /// Recarrega currais do SQLite (após atualizar previsão na API).
  Future<void> reloadMapa() async {
    if (_header?.tratoSelecionado ?? false) {
      await _reloadMapa(idFazenda: _idFazenda);
    } else {
      await carregarPrevisaoPorRacao();
    }
  }

  /// Baixa/valida previsão filtrada só pelo ID da ração (sem trato, sem exibir mapa).
  Future<void> carregarPrevisaoPorRacao() async {
    final h = _header;
    if (h == null) return;

    final racaoId = (h.racaoId ?? "").trim();
    if (racaoId.isEmpty) return;

    final rows = await _repo.listCurraisPrevistosHoje(
      data: h.data,
      idFazenda: _idFazenda.trim().isEmpty ? null : _idFazenda,
      idRacao: racaoId,
      strictRacaoFilter: true,
      omitirFiltroTrato: true,
    );

    _previsaoRacaoOk = rows.isNotEmpty;

    if (rows.isNotEmpty) {
      final tratos = <int>{};
      for (final r in rows) {
        if (r.trato > 0) tratos.add(r.trato);
      }
      if (tratos.isNotEmpty) {
        _tratosDisponiveis = tratos.toList()..sort();
      }
      clearNotice();
    } else {
      _setNotice(
        "Nenhum curral na previsão local com:\n"
        "Data: ${_ymd(h.data)}\n"
        "ID ração: $racaoId\n"
        "Selecione o trato após sincronizar a previsão.",
        key: "mapa_vazio_racao",
        cooldownMs: 3000,
      );
    }

    _curraisAll = const [];
    _selected = null;
    limparSessao();
    _totais = const TotaisVM(totalPrevistoKg: 0, totalRealizadoKg: 0);
    notifyListeners();
  }

  List<int> _tratosDisponiveis = const [1, 2, 3, 4, 5, 6];
  List<int> get tratosDisponiveis => _tratosDisponiveis;

  bool _previsaoRacaoOk = false;
  bool get previsaoRacaoOk => _previsaoRacaoOk;

  bool get tratoSelecionado => _header?.tratoSelecionado ?? false;

  Future<void> _loadTratosDisponiveis() async {
    final h = _header;
    if (h == null) return;
    final racao = (h.racaoId ?? "").trim();
    if (racao.isEmpty) return;

    final list = await _repo.listTratosPrevisao(
      data: h.data,
      idRacao: racao,
      idFazenda: _idFazenda.trim().isEmpty ? null : _idFazenda,
    );
    if (list.isNotEmpty) {
      _tratosDisponiveis = list;
    }
  }

  Future<void> selecionarTrato(int trato) async {
    final h = _header;
    if (h == null) return;

    final t = trato <= 0 ? null : trato;
    _header = FornecimentoHeaderVM(
      trato: t,
      data: h.data,
      racaoId: h.racaoId,
      racaoNome: h.racaoNome,
      carregamentoId: h.carregamentoId,
    );

    if (t != null) {
      _repo.setTrato(t);
    }

    limparSessao();
    _selected = null;
    _linhaFiltro = null;

    await _reloadMapa(idFazenda: _idFazenda);
    notifyListeners();
  }

  // ===========================
  // Helpers gerais
  // ===========================

  void _setLoading(bool v) {
    if (_loading == v) return;
    _loading = v;
    notifyListeners();
  }

  void setError(String? msg) {
    _error = (msg ?? "").trim().isEmpty ? null : msg!.trim();
    _loading = false;
    notifyListeners();
  }

  void beginBoot() {
    _error = null;
    _setLoading(true);
  }

  bool _consumeBlockingErrorAsNotice({
    required String title,
    required String key,
  }) {
    final msg = (_error ?? "").trim();
    if (msg.isEmpty) return false;

    _error = null;
    _loading = false;
    _setNotice(
      "$title\n$msg",
      key: key,
      cooldownMs: 1500,
    );
    return true;
  }

  double _toD(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().replaceAll(",", ".")) ?? 0;
  }

  static String _ymd(DateTime d) {
    final y = d.year.toString().padLeft(4, "0");
    final m = d.month.toString().padLeft(2, "0");
    final dd = d.day.toString().padLeft(2, "0");
    return "$y-$m-$dd";
  }

  bool _equalsIgnoreCase(String a, String b) =>
      a.toLowerCase() == b.toLowerCase();

  String _normalizeEpc(String s) => RfidTagUtils.normalizeRawEpc(s);

  Future<bool> _sameRfidTag(String a, String b) async {
    final x = _normalizeEpc(a);
    final y = _normalizeEpc(b);
    if (x.isEmpty || y.isEmpty) return false;
    if (x == y) return true;
    return _rfidTagResolver.matches(a, b);
  }

  String _currentUserId() {
    final s = (SessionService.instance.userId ?? "").trim();
    return s;
  }

  // ===========================
  // INIT / DISPOSE
  // ===========================

  Future<void> init({
    required DateTime data,
    required String idFazenda,
    String? idRacaoFiltro,
  }) async {
    _setLoading(true);
    _error = null;

    _idFazenda = idFazenda.trim();
    _isFieldpec = ConfigOptions.isFieldPecBackend(await _cfg.getBackend());

    // garante listeners 1 vez
    _startScaleListener();
    _startRfidListener();
    _startStatusListeners();

    // RFID ativo ao entrar
    _rfidPausado = false;
    _rfid.setLeituraAtiva(true);

    try {
      final car = await _repo.getCarregamentoAberto(data: data);
      if (car == null || car.id.trim().isEmpty) {
        throw Exception(
          "Não há carregamento aberto hoje. "
          "Realize o carregamento da ração antes de fornecer.",
        );
      }

      final carRacao = (car.idDieta ?? "").toString().trim();
      final filtro = (idRacaoFiltro ?? "").trim();

      final racaoFinal = filtro.isNotEmpty
          ? filtro
          : (carRacao.isNotEmpty
              ? carRacao
              : (_repo.idRacaoAtual ?? "").trim());

      if (racaoFinal.isEmpty) {
        throw Exception("Carregamento em aberto sem ID_DIETA (ração).");
      }

      await _repo.assertFabricacaoParaFornecimento(data: data);

      final racaoNome = await _repo.getDietaNomeById(racaoFinal);

      _header = FornecimentoHeaderVM(
        trato: null,
        data: data,
        racaoId: racaoFinal,
        racaoNome:
            (racaoNome ?? "").trim().isNotEmpty ? racaoNome!.trim() : null,
        carregamentoId: car.id,
      );

      _repo.setIdRacaoAtual(racaoFinal);
      await _loadTratosDisponiveis();

      await carregarPrevisaoPorRacao();

      if (_curraisAll.isEmpty) {
        limparSessao();
        _selected = null;
      }

      _setLoading(false);
    } catch (e) {
      setError(e.toString());
    }
  }

  @override
  void dispose() {
    // desliga leitura no hardware ao sair da tela
    _rfid.setLeituraAtiva(false);

    _scaleSub?.cancel();
    _rfidSub?.cancel();
    _scaleStatusSub?.cancel();
    _rfidStatusSub?.cancel();
    _pendingEpcTimer?.cancel();
    _pendingEpcTimer = null;
    super.dispose();
  }

  void _startStatusListeners() {
    _scaleStatusSub?.cancel();
    _rfidStatusSub?.cancel();

    _scaleStatus = _scale.lastStatus;
    _rfidStatus = _rfid.lastStatus;

    _scaleStatusSub = _scale.statusStream.listen((ev) {
      _scaleStatus = ev.status;
      _scaleMsg =
          (ev.message ?? "").trim().isNotEmpty ? ev.message!.trim() : null;
      notifyListeners();
    }, onError: (_) {});

    _rfidStatusSub = _rfid.statusStream.listen((ev) {
      if (_rfidPausado) return;
      _rfidStatus = ev.status;
      _rfidMsg =
          (ev.message ?? "").trim().isNotEmpty ? ev.message!.trim() : null;
      notifyListeners();
    }, onError: (_) {});
  }

  // ===========================
  // LISTENERS
  // ===========================

  void _startScaleListener() {
    _scaleSub?.cancel();
    _primePesoFromScale();
    _scaleSub = _scale.weightStream.listen((ev) {
      _pesoAtual = ev.weight;
      lastScaleRaw = ev.rawLine;
      if (_scaleStatus != ScaleStatus.connected) {
        _scaleStatus = ScaleStatus.connected;
        _scaleMsg = null;
      }
      unawaited(_maybeAutoRebasePesoInicial(ev.weight));
      notifyListeners();
    }, onError: (_) {});
  }

  void _primePesoFromScale() {
    final w = _scale.lastWeight;
    final at = _scale.lastReadAt;
    if (w == null || at == null) return;
    if (DateTime.now().difference(at).inSeconds > 8) return;
    _pesoAtual = w;
  }

  /// Aguarda leitura recente da balança antes de gravar o peso inicial da sessão.
  Future<double> _awaitPesoBalanca({
    Duration timeout = const Duration(milliseconds: 1500),
  }) async {
    final deadline = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(deadline)) {
      final last = _scale.lastWeight;
      final lastAt = _scale.lastReadAt;
      if (last != null && lastAt != null) {
        final ageMs = DateTime.now().difference(lastAt).inMilliseconds;
        if (ageMs <= 5000) {
          _pesoAtual = last;
          return last;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }

    final fallback = _scale.lastWeight ?? _pesoAtual;
    _pesoAtual = fallback;
    return fallback;
  }

  /// Ancora o peso inicial na primeira leitura estável (evita sessão com peso 0).
  Future<void> _maybeAutoRebasePesoInicial(double pesoAtual) async {
    if (!_sessaoAtiva || _selected == null) return;
    if (_rebasePesoInicialFeito) return;

    final ini = _sessaoIniciadaEm;
    if (ini == null) return;
    if (DateTime.now().difference(ini).inSeconds > 12) return;

    final pesoIni = _pesoInicial ?? 0;
    final fornecido = fornecidoKgSessao(
      pesoInicial: pesoIni,
      pesoAtual: pesoAtual,
    );
    if (fornecido > 0.5) {
      _rebasePesoInicialFeito = true;
      return;
    }

    final diffIni = (pesoIni - pesoAtual).abs();
    if (pesoIni > 0 && diffIni > 0.5) return;

    _pesoInicial = pesoAtual;
    _rebasePesoInicialFeito = true;

    final idCad = (_idCadastroAberto ?? "").trim();
    if (idCad.isNotEmpty) {
      try {
        await _repo.rebasePesoInicioCadastroAberto(
          idCadastro: idCad,
          pesoInicio: pesoAtual,
        );
      } catch (e) {
        if (kDebugMode) {
          debugPrint("autoRebasePesoInicial: falha ao persistir: $e");
        }
      }
    }
    notifyListeners();
  }

  void _startRfidListener() {
    _rfidSub?.cancel();

    _rfidSub = _rfid.tagStream.listen((ev) async {
      if (_rfidPausado) return;

      final epc = _normalizeEpc(ev.epc);
      if (epc.isEmpty) return;

      if (kDebugMode) debugPrint("RFID EPC => $epc");

      // Evita falso "sem previsto" quando a tag chega antes do mapa carregar.
      if (_loading || _header == null || _curraisAll.isEmpty) {
        _queuePendingBootEpc(epc);
        return;
      }

      if (_autoFlowRfid) {
        await _handleRfidAutoFlow(epc);
      } else {
        await selecionarCurralPorEpc(epc);
      }
    }, onError: (_) {});
  }

  void _queuePendingBootEpc(String epc) {
    _pendingEpcBoot = _normalizeEpc(epc);
    if (_pendingEpcBoot == null || _pendingEpcBoot!.isEmpty) return;
    if (_pendingEpcTimer?.isActive == true) return;

    _pendingEpcTimer = Timer(const Duration(milliseconds: 700), () {
      _pendingEpcTimer = null;
      _flushPendingBootEpc();
    });
  }

  void _flushPendingBootEpc() {
    if (_rfidPausado) return;

    final epc = (_pendingEpcBoot ?? "").trim();
    if (epc.isEmpty) return;

    if (_loading || _header == null || _curraisAll.isEmpty) {
      _queuePendingBootEpc(epc);
      return;
    }

    _pendingEpcBoot = null;

    if (_autoFlowRfid) {
      unawaited(_handleRfidAutoFlow(epc));
    } else {
      unawaited(selecionarCurralPorEpc(epc));
    }
  }

  // ===========================
  // RFID FLOW (AUTO SAVE + AUTO START)
  // ===========================

  Future<void> _handleRfidAutoFlow(String epc) async {
    if (_rfidProcessing) return;

    final now = DateTime.now();

    // debounce ANTES de qualquer coisa
    if (_equalsIgnoreCase(epc, _lastRfidHandled) &&
        now.difference(_lastRfidHandledAt).inMilliseconds < 800) {
      return;
    }

    _rfidProcessing = true;
    try {
      final currentSessao = _selected;
      final currentEpc = _normalizeEpc(currentSessao?.epc ?? "");
      final lidoEpc = _normalizeEpc(epc);
      final tagDiferenteDaSessaoAtual = currentEpc.isEmpty ||
          !await _sameRfidTag(currentSessao?.epc ?? "", epc);

      final target = await _findCurralByEpc(epc);

      if (target == null) {
        if (lidoEpc.isEmpty) return;

        // Se leu outra tag e havia sessao ativa, persiste igual ao botao Salvar.
        if (_sessaoAtiva &&
            currentSessao != null &&
            tagDiferenteDaSessaoAtual) {
          await salvarFornecimento(idFazenda: _idFazenda);
          if (_consumeBlockingErrorAsNotice(
            title: "Falha ao salvar a sessao atual ao trocar de tag.",
            key: "rfid_autosave_error",
          )) {
            return;
          }
        }

        final h = _header;
        final racaoNome = (h?.racaoNome ?? "").trim();
        final racaoTxt = racaoNome.isNotEmpty ? racaoNome : (h?.racaoId ?? "-");

        _setNotice(
          "RFID lido, mas este curral NÃO tem previsto para a ração carregada.\n"
          "EPC: $epc\n"
          "Ração: $racaoTxt",
          key: "rfid_sem_previsto_$epc",
          cooldownMs: 1500,
        );

        _lastRfidHandled = epc;
        _lastRfidHandledAt = now;
        return;
      }

      final current = _selected;

      // Se já está no mesmo curral:
      // - com sessão ativa: ignora leitura repetida
      // - sem sessão ativa: reabre sessão (evita precisar sair/voltar da tela)
      if (current != null && current.idFornecimento == target.idFornecimento) {
        if (_sessaoAtiva &&
            _pesoInicial != null &&
            (_idCadastroAberto ?? "").trim().isNotEmpty) {
          // Rebase se travou em 0 (balança oscilando acima do peso inicial).
          if (fornecidoSessaoKg <= 0) {
            await rebaseSessaoPeso();
          }
          _lastRfidHandled = epc;
          _lastRfidHandledAt = now;
          return;
        }

        await iniciarCarregamento();
        if (_consumeBlockingErrorAsNotice(
          title: "Falha ao iniciar sessao para a tag lida.",
          key: "rfid_autostart_error",
        )) {
          return;
        }

        _lastRfidHandled = epc;
        _lastRfidHandledAt = now;
        return;
      }

      // se tinha sessão ativa em outro curral, salva (sem explodir UI)
      if (_sessaoAtiva && current != null) {
        await salvarFornecimento(idFazenda: _idFazenda);
        if (_consumeBlockingErrorAsNotice(
          title: "Falha ao salvar a sessao anterior antes de iniciar outra.",
          key: "rfid_autosave_error",
        )) {
          return;
        }
      }

      _selected = target;
      _origemMapa = 0;
      clearNotice();
      notifyListeners();

      await iniciarCarregamento();
      if (_consumeBlockingErrorAsNotice(
        title: "Falha ao iniciar sessao para a tag lida.",
        key: "rfid_autostart_error",
      )) {
        return;
      }

      _lastRfidHandled = epc;
      _lastRfidHandledAt = now;
    } catch (e) {
      _setNotice(
        "Falha ao processar leitura RFID.\n$e",
        key: "rfid_flow_exception",
        cooldownMs: 1500,
      );
    } finally {
      _rfidProcessing = false;
    }
  }

  Future<CurralCardVM?> _findCurralByEpc(String epc) async {
    final epcNorm = _normalizeEpc(epc);
    if (epcNorm.isEmpty) return null;

    for (final c in _curraisAll) {
      final ce = c.epc;
      if (ce == null || ce.trim().isEmpty) continue;
      if (await _rfidTagResolver.matches(epc, ce)) return c;
    }

    final h = _header;
    if (h == null) return null;

    // fallback: pergunta pro repo
    final idFornecimento = await _repo.findIdFornecimentoByRfid(
      epc: epcNorm,
      trato: h.tratoSelecionado ? h.trato! : _repo.tratoAtual,
      idRacao: h.racaoId,
      data: h.data,
    );

    if (idFornecimento == null || idFornecimento.trim().isEmpty) return null;

    for (final c in _curraisAll) {
      if (c.idFornecimento == idFornecimento) return c;
    }

    if (_idFazenda.trim().isNotEmpty) {
      await _reloadMapa(idFazenda: _idFazenda);
      for (final c in _curraisAll) {
        if (c.idFornecimento == idFornecimento) return c;
      }
    }

    return null;
  }

  // ===========================
  // LOAD MAPA / TOTAIS
  // ===========================

  Future<void> _reloadMapa({
    required String idFazenda,
  }) async {
    final h = _header;
    if (h == null) return;
    if (!h.tratoSelecionado || h.trato == null) return;

    final racaoId = (h.racaoId ?? "").trim();
    if (racaoId.isEmpty) return;

    final tratoFiltro = h.trato!;

    var rows = await _repo.listCurraisPrevistosHoje(
      data: h.data,
      trato: tratoFiltro,
      idFazenda: idFazenda,
      idRacao: racaoId,
      strictRacaoFilter: true,
      omitirFiltroTrato: false,
    );

    if (rows.isEmpty) {
      _setNotice(
        "Nenhum curral na previsão local com:\n"
        "Data: ${_ymd(h.data)}\n"
        "ID ração: $racaoId\n"
        "Trato: $tratoFiltro",
        key: "mapa_vazio_filtro",
        cooldownMs: 3000,
      );
    } else {
      clearNotice();
    }

    final cards = rows.map((r) {
      final idForne = (r.idFornecimento ?? "").toString().trim();
      final idBaia = r.idBaia.trim();

      final nome = (r.nomeLocal ?? "").toString().trim();
      final idBaiaTxt = idBaia.isEmpty ? "?" : idBaia;

      // normaliza EPC do mapa também
      final rfidRaw = (r.rfid ?? "").toString().trim();
      final rfid = rfidRaw.isEmpty ? null : _normalizeEpc(rfidRaw);

      final linhaRaw = resolveLinhaCurral(
        linhaDb: r.linha,
        nomeLocal: nome.isEmpty ? r.nomeLocal : nome,
      );
      final linha = linhaRaw.isEmpty ? null : linhaRaw;

      final orig = r.previstoOriginalKg ?? 0;
      final recalc = r.previstoRecalculadoKg ?? r.previstoKg;
      final previstoFixo = orig > 0 ? orig : r.previstoKg;
      final ultimo = r.isUltimoTrato ||
          (_isFieldpec &&
              previstoFixo > 0 &&
              recalc > 0 &&
              (previstoFixo - recalc).abs() > 0.01);

      return CurralCardVM(
        idFornecimento: idForne.isEmpty ? "?" : idForne,
        idBaia: idBaia.isEmpty ? "?" : idBaia,
        curralNome: nome.isEmpty ? "Baia $idBaiaTxt" : nome,
        linha: linha,
        orderTrato: r.ordemFornecimento ?? 0,
        previstoKg: previstoFixo,
        previstoOriginalKg: previstoFixo,
        previstoRecalculadoKg: recalc,
        isUltimoTrato: ultimo,
        previsaoDuplaFieldpec: _isFieldpec,
        realizadoKg: _toD(r.realizadoKg),
        epc: rfid,
      );
    }).toList();

    double tp = 0;
    double tr = 0;
    for (final c in cards) {
      tp += c.previstoKg;
      tr += c.realizadoKg;
    }

    int lineRank(String? s) {
      final t = (s ?? "").trim();
      if (t.isEmpty) return 999999999;
      final n = int.tryParse(t);
      return n ?? 999999998;
    }

    cards.sort((a, b) {
      final c0 = a.orderTrato.compareTo(b.orderTrato);
      if (c0 != 0) return c0;

      final ra = lineRank(a.linha);
      final rb = lineRank(b.linha);
      final c1 = ra.compareTo(rb);
      if (c1 != 0) return c1;

      final la = (a.linha ?? "").trim();
      final lb = (b.linha ?? "").trim();
      final c2 = la.compareTo(lb);
      if (c2 != 0) return c2;

      return a.curralNome.compareTo(b.curralNome);
    });

    _curraisAll = cards;

    // se filtro linha não existe mais, limpa (comparação case-insensitive)
    if (_linhaFiltro != null) {
      final lfUp = _linhaFiltro!.trim().toUpperCase();
      final ok = linhasDisponiveis
          .any((l) => l.trim().toUpperCase() == lfUp);
      if (!ok) _linhaFiltro = null;
    }

    // mantém seleção se existir
    if (_selected != null) {
      final id = _selected!.idFornecimento;
      CurralCardVM? found;
      for (final c in _curraisAll) {
        if (c.idFornecimento == id) {
          found = c;
          break;
        }
      }
      _selected = found;
      if (_selected == null) limparSessao();
    }

    _totais = TotaisVM(totalPrevistoKg: tp, totalRealizadoKg: tr);

    notifyListeners();
    _flushPendingBootEpc();
  }

  // ===========================
  // UI ACTIONS
  // ===========================

  void toggleRfidPausado() {
    unawaited(_toggleRfidPausadoAsync());
  }

  Future<void> _toggleRfidPausadoAsync() async {
    if (_rfidPauseToggleBusy) return;
    _rfidPauseToggleBusy = true;
    try {
      final vaiPausar = !_rfidPausado;

      if (vaiPausar) {
        _rfidPausado = true;
        _cancelPendingRfid();
      }

      // Ao pausar, precisa persistir a sessão aberta antes de desligar leitura.
      if (vaiPausar && _sessaoAtiva && _selected != null) {
        await salvarFornecimento(idFazenda: _idFazenda);

        final hadError = (_error ?? "").trim().isNotEmpty;
        if (hadError) {
          _rfidPausado = false;
          _setNotice(
            "Falha ao pausar RFID: não foi possível salvar a sessão aberta.",
            key: "rfid_pause_save_error",
            title: "RFID pausado",
            cooldownMs: 1200,
          );
          return;
        }
      }

      if (vaiPausar) {
        await _pauseRfidAntena();
        clearNotice();
        _setNotice(
          _sessaoAtiva && _selected != null
              ? "Leitura pausada. Sessão em aberto foi salva."
              : "Leitura pausada pelo operador.",
          key: "rfid_pause_saved",
          title: "RFID pausado",
          cooldownMs: 1200,
        );
      } else {
        clearNotice();
        await _resumeRfidAntena();
      }
    } finally {
      _rfidPauseToggleBusy = false;
    }
  }

  Future<void> _pauseRfidAntena() async {
    _rfidPausado = true;
    _rfid.setLeituraAtiva(false);
    try {
      await _rfid.disconnect();
    } catch (_) {}
    _rfidStatus = RfidStatus.disconnected;
    _rfidMsg = null;
    notifyListeners();
  }

  Future<void> _resumeRfidAntena() async {
    _rfidPausado = false;
    _rfid.setLeituraAtiva(true);
    try {
      await _rfid.connect();
    } catch (_) {}
    notifyListeners();
  }

  void setLeituraRfid(bool on) {
    if (on) {
      unawaited(_resumeRfidAntena());
    } else {
      unawaited(_pauseRfidAntena());
    }
  }

  /// ✅ ao clicar manualmente, aplica a mesma regra do RFID:
  /// - se tinha sessão ativa em outro curral, salva
  /// - seleciona o curral
  /// - inicia carregamento
  Future<void> selecionarCurralPorClique(CurralCardVM c) async {
    final current = _selected;

    if (_sessaoAtiva &&
        current != null &&
        current.idFornecimento != c.idFornecimento) {
      await salvarFornecimento(idFazenda: _idFazenda);
    }

    _selected = c;
    _origemMapa = 1;
    clearNotice();
    notifyListeners();

    await iniciarCarregamento();
  }

  Future<void> selecionarCurralPorEpc(String epc) async {
    final epcNorm = _normalizeEpc(epc);
    if (epcNorm.isEmpty) return;

    final target = await _findCurralByEpc(epc);
    if (target == null) {
      _setNotice(
        "RFID lido, mas não existe previsto para este curral/ração.\nEPC: $epcNorm",
        key: "rfid_sem_previsto_$epcNorm",
        cooldownMs: 1500,
      );

      _lastRfidHandled = epc;
      _lastRfidHandledAt = DateTime.now();
      return;
    }

    _selected = target;
    _origemMapa = 0;
    clearNotice();
    notifyListeners();
  }

  void restaurarSelecaoPorIdFornecimento(String idFornecimento) {
    final id = idFornecimento.trim();
    if (id.isEmpty) return;

    CurralCardVM? found;
    for (final c in _curraisAll) {
      if (c.idFornecimento == id) {
        found = c;
        break;
      }
    }
    if (found == null) return;

    _selected = found;
    _origemMapa = 1;
    clearNotice();
    notifyListeners();
  }

  /// Restaura curral salvo e tenta abrir/recuperar sessão de pesagem.
  Future<void> recuperarSelecaoAposBoot(String idFornecimento) async {
    restaurarSelecaoPorIdFornecimento(idFornecimento);
    if (_selected == null || _header == null) return;
    if (_sessaoAtiva) return;
    await iniciarCarregamento();
  }

  // ===========================
  // SESSÃO
  // ===========================

  /// Redefine o peso inicial da sessão para o peso atual da balança.
  Future<void> rebaseSessaoPeso() async {
    if (!_sessaoAtiva || _selected == null) return;

    _pesoInicial = _pesoAtual;
    final idCad = (_idCadastroAberto ?? "").trim();
    if (idCad.isNotEmpty) {
      try {
        await _repo.rebasePesoInicioCadastroAberto(
          idCadastro: idCad,
          pesoInicio: _pesoAtual,
        );
      } catch (e) {
        if (kDebugMode) {
          debugPrint("rebaseSessaoPeso: falha ao persistir peso inicial: $e");
        }
      }
    }
    notifyListeners();
  }

  Future<void> iniciarCarregamento() async {
    final h = _header;
    final s = _selected;
    if (h == null || s == null) return;

    if (!h.tratoSelecionado) {
      setError("Selecione o trato antes de iniciar o fornecimento.");
      return;
    }

    final trato = h.trato!;

    // se já está ativo no mesmo curral, não reinicia
    if (_sessaoAtiva &&
        _pesoInicial != null &&
        (_idCadastroAberto ?? "").trim().isNotEmpty &&
        _selected?.idFornecimento == s.idFornecimento) {
      return;
    }

    // evita double-start por spam / concorrência (aguarda em vez de abortar)
    while (_startingSessao) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    final now = DateTime.now();
    if (now.difference(_lastStartAt).inMilliseconds < 350) {
      await Future<void>.delayed(
        Duration(
          milliseconds: 350 - now.difference(_lastStartAt).inMilliseconds,
        ),
      );
    }

    final idUsuario = _currentUserId();
    if (idUsuario.isEmpty) {
      setError("Exception: Usuário não definido. Faça login novamente.");
      return;
    }

    _startingSessao = true;
    _lastStartAt = now;

    try {
      _setLoading(true);
      _error = null;

      final pesoRef = await _awaitPesoBalanca();

      // ✅ abre/recupera CADASTRO_FORNECIMENTO e guarda o idCadastro
      final idCad = await _repo.iniciarCadastroFornecimento(
        idFornecimento: s.idFornecimento,
        idCurral: s.idBaia,
        data: h.data,
        trato: trato,
        previstoKg: s.previstoFixoKg,
        pesoInicio: pesoRef,
        idUsuario: idUsuario,
      );

      _idCadastroAberto = idCad;

      _sessaoAtiva = true;
      _sessaoIniciadaEm = DateTime.now();
      _rebasePesoInicialFeito = false;

      // Sempre ancora na leitura atual da balança (cadastro reutilizado pode ter peso antigo).
      _pesoInicial = pesoRef;
      if (idCad.trim().isNotEmpty) {
        await _repo.rebasePesoInicioCadastroAberto(
          idCadastro: idCad,
          pesoInicio: pesoRef,
        );
      }

      if (kDebugMode) {
        debugPrint(
          "[FORN_SESSAO] curral=${s.curralNome} pesoIni=$pesoRef pesoAtual=$_pesoAtual",
        );
      }

      _setLoading(false);
    } catch (e) {
      setError(e.toString());
    } finally {
      _startingSessao = false;
    }
  }

  void limparSessao() {
    _sessaoAtiva = false;
    _pesoInicial = null;
    _idCadastroAberto = null;
    _sessaoIniciadaEm = null;
    _rebasePesoInicialFeito = false;
    notifyListeners();
  }

  Future<void> salvarFornecimento({required String idFazenda}) async {
    final h = _header;
    final s = _selected;
    if (h == null || s == null) return;
    if (!h.tratoSelecionado) return;

    if (!_sessaoAtiva || _pesoInicial == null) return;

    final trato = h.trato!;

    final fornecidoKg = fornecidoSessaoKg;

    // se não forneceu nada: cancela cadastro aberto (sem pendência fantasma)
    if (fornecidoKg <= 0) {
      final idCad = (_idCadastroAberto ?? "").trim();
      if (idCad.isNotEmpty) {
        try {
          await _repo.cancelarCadastroFornecimentoAberto(idCadastro: idCad);
        } catch (_) {}
      }
      limparSessao();
      _selected = null;
      clearNotice();
      notifyListeners();
      return;
    }

    try {
      _setLoading(true);
      _error = null;

      final idUsuario = _currentUserId();
      if (idUsuario.isEmpty) {
        setError("Exception: Usuário não definido. Faça login novamente.");
        return;
      }

      // ✅ Grava 1 linha em CADASTRO_FORNECIMENTO (kg da sessão).
      // Acumulado fica na API; mapa local = soma das linhas + PREVISAO da API.
      await _repo.salvarCadastroFinalizado(
        idFornecimento: s.idFornecimento,
        idCurral: s.idBaia,
        data: h.data,
        trato: trato,
        previstoKg: s.previstoFixoKg,
        pesoFim: _pesoAtual,
        realizadoKg: fornecidoKg,
        idUsuario: idUsuario,
        idCadastroAberto: _idCadastroAberto,
      );

      _ultimo = UltimoFornecimentoVM(
        curralNome: s.curralNome,
        fornecidoKg: fornecidoKg,
      );

      await _reloadMapa(idFazenda: idFazenda);

      // ✅ encerra sessão + limpa seleção
      limparSessao();
      _selected = null;
      clearNotice();

      _setLoading(false);
    } catch (e) {
      setError(e.toString());
    }
  }
}
