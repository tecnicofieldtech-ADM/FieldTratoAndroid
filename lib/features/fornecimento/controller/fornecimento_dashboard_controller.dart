// lib/features/fornecimento/controller/fornecimento_dashboard_controller.dart
import "dart:async";
import "package:flutter/foundation.dart";

import "../../../helpers/scale_comm.dart";
import "../../../helpers/rfid_comm.dart";
import "../data/fornecimento_repo.dart";
import "../../../services/session_service.dart";

class FornecimentoHeaderVM {
  final int trato;
  final DateTime data;
  final String? racaoId;
  final String? racaoNome;
  final String? carregamentoId;

  const FornecimentoHeaderVM({
    required this.trato,
    required this.data,
    required this.racaoId,
    required this.racaoNome,
    required this.carregamentoId,
  });
}

class CurralCardVM {
  final String idFornecimento;
  final String idBaia;
  final String curralNome;
  final String? linha;
  final int orderTrato;
  final double previstoKg;
  final double realizadoKg;
  final String? epc;

  const CurralCardVM({
    required this.idFornecimento,
    required this.idBaia,
    required this.curralNome,
    required this.linha,
    required this.orderTrato,
    required this.previstoKg,
    required this.realizadoKg,
    required this.epc,
  });

  double get diffKg => realizadoKg - previstoKg;
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
    bool autoFlowRfid = true, // RFID comanda iniciar/salvar
  })  : _repo = repo,
        _scale = scale,
        _rfid = rfid,
        _autoFlowRfid = autoFlowRfid;

  final FornecimentoRepo _repo;
  final ScaleComm _scale;
  final RfidComm _rfid;

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

  DateTime _lastNoticeAt = DateTime.fromMillisecondsSinceEpoch(0);
  String _lastNoticeKey = "";

  void clearNotice() {
    if (_uiNotice == null) return;
    _uiNotice = null;
    notifyListeners();
  }

  void _setNotice(String msg, {String key = "", int cooldownMs = 1200}) {
    final now = DateTime.now();
    if (key.isNotEmpty &&
        key == _lastNoticeKey &&
        now.difference(_lastNoticeAt).inMilliseconds < cooldownMs) {
      return;
    }
    _uiNotice = msg;
    _lastNoticeAt = now;
    _lastNoticeKey = key;
    notifyListeners();
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

  double? _pesoInicial;
  double? get pesoInicial => _pesoInicial;

  /// ✅ ID do CADASTRO_FORNECIMENTO em aberto (SQLite)
  String? _idCadastroAberto;

  String _idFazenda = "";

  int _origemMapa = 0; // 0 = RFID, 1 = Mapa

  // Proteção double-start
  bool _startingSessao = false;
  DateTime _lastStartAt = DateTime.fromMillisecondsSinceEpoch(0);

  // ===========================
  // “tempo real” no painel
  // ===========================

  double get fornecidoSessaoKg {
    if (!_sessaoAtiva) return 0;
    final ini = _pesoInicial ?? 0;
    final atual = _pesoAtual;
    final v = ini - atual;
    return v < 0 ? 0 : v;
  }

  double get aFornecerEstimadoKg {
    final s = _selected;
    if (s == null) return 0;
    final previsto = s.previstoKg;
    final realizadoEst = s.realizadoKg + fornecidoSessaoKg;
    if (realizadoEst <= previsto) {
      return previsto - realizadoEst;
    }
    return realizadoEst - previsto;
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

  String? _toLinhaStr(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

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
    final lf = (_linhaFiltro ?? "").trim();
    if (lf.isEmpty) return _curraisAll;
    return _curraisAll.where((c) => (c.linha ?? "").trim() == lf).toList();
  }

  void setLinhaFiltro(String? linha) {
    final v = (linha ?? "").trim();
    final next = v.isEmpty ? null : v;
    if (_linhaFiltro == next) return;
    _linhaFiltro = next;
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
    _error = msg;
    _loading = false;
    notifyListeners();
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

  bool _equalsIgnoreCase(String a, String b) =>
      a.toLowerCase() == b.toLowerCase();

  String _normalizeEpc(String s) {
    var t = s.trim();
    final up = t.toUpperCase();

    final idx = up.indexOf("EPC:");
    if (idx >= 0) t = t.substring(idx + 4).trim();
    if (t.startsWith(";")) t = t.substring(1).trim();

    t = t.replaceAll(" ", "").replaceAll("\n", "").replaceAll("\r", "");
    return t;
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
    required int trato,
    required String idFazenda,
    String? idRacaoFiltro,
  }) async {
    _setLoading(true);
    _error = null;

    _idFazenda = idFazenda.trim();

    // garante listeners 1 vez
    _startScaleListener();
    _startRfidListener();
    _startStatusListeners();

    // RFID ativo ao entrar
    _rfidPausado = false;
    _rfid.setLeituraAtiva(true);

    try {
      _repo.setTrato(trato);

      final car = await _repo.getCarregamentoAberto(data: data);
      if (car == null || car.id.trim().isEmpty) {
        throw Exception(
          "Não existe carregamento em aberto para hoje. "
          "Finalize uma fabricação para gerar o carregamento (STATUS=0).",
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

      final racaoNome = await _repo.getDietaNomeById(racaoFinal);

      _header = FornecimentoHeaderVM(
        trato: trato,
        data: data,
        racaoId: racaoFinal,
        racaoNome:
            (racaoNome ?? "").trim().isNotEmpty ? racaoNome!.trim() : null,
        carregamentoId: car.id,
      );

      await _reloadMapa(idFazenda: idFazenda);

      // limpa seleção/sessão caso a lista venha vazia
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

    _scaleStatusSub = _scale.statusStream.listen((ev) {
      _scaleStatus = ev.status;
      _scaleMsg =
          (ev.message ?? "").trim().isNotEmpty ? ev.message!.trim() : null;
      notifyListeners();
    }, onError: (_) {});

    _rfidStatusSub = _rfid.statusStream.listen((ev) {
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
    _scaleSub = _scale.weightStream.listen((ev) {
      _pesoAtual = ev.weight;
      notifyListeners();
    }, onError: (_) {});
  }

  void _startRfidListener() {
    _rfidSub?.cancel();

    _rfidSub = _rfid.tagStream.listen((ev) async {
      if (_rfidPausado) return;

      // garante ativo (caso alguém desligue em outro ponto)
      if (!_rfid.leituraAtiva) _rfid.setLeituraAtiva(true);

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
      final currentEpc = _normalizeEpc(currentSessao?.epc ?? "").toUpperCase();
      final lidoEpc = _normalizeEpc(epc).toUpperCase();
      final tagDiferenteDaSessaoAtual =
          currentEpc.isEmpty || currentEpc != lidoEpc;

      final target = await _findCurralByEpc(epc);

      if (target == null) {
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

      // se já está no mesmo, não faz nada
      if (current != null && current.idFornecimento == target.idFornecimento) {
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
    final epcNorm = _normalizeEpc(epc).toUpperCase();

    // tenta no mapa já carregado
    for (final c in _curraisAll) {
      final ce = c.epc == null ? "" : _normalizeEpc(c.epc!).toUpperCase();
      if (ce == epcNorm) return c;
    }

    final h = _header;
    if (h == null) return null;

    // fallback: pergunta pro repo
    final idFornecimento = await _repo.findIdFornecimentoByRfid(
      epc: epcNorm,
      trato: h.trato,
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

  Future<void> _reloadMapa({required String idFazenda}) async {
    final h = _header;
    if (h == null) return;

    final idRacao = (h.racaoId ?? "").trim();

    final rows = await _repo.listCurraisPrevistosHoje(
      data: h.data,
      trato: h.trato,
      idFazenda: idFazenda,
      idRacao: idRacao.isNotEmpty ? idRacao : null,
    );

    final cards = rows.map((r) {
      final idForne = (r.idFornecimento ?? "").toString().trim();
      final idBaia = r.idBaia.trim();

      final nome = (r.nomeLocal ?? "").toString().trim();

      // normaliza EPC do mapa também
      final rfidRaw = (r.rfid ?? "").toString().trim();
      final rfid = rfidRaw.isEmpty ? null : _normalizeEpc(rfidRaw);

      final linha = _toLinhaStr(r.linha);

      return CurralCardVM(
        idFornecimento: idForne.isEmpty ? "?" : idForne,
        idBaia: idBaia.isEmpty ? "?" : idBaia,
        curralNome: nome.isEmpty ? "(sem nome)" : nome,
        linha: linha,
        orderTrato: r.ordemFornecimento ?? 0,
        previstoKg: _toD(r.previstoKg),
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

    // se filtro linha não existe mais, limpa
    if (_linhaFiltro != null && !linhasDisponiveis.contains(_linhaFiltro)) {
      _linhaFiltro = null;
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

      // Ao pausar, precisa persistir a sessão aberta antes de desligar leitura.
      if (vaiPausar && _sessaoAtiva && _selected != null) {
        await salvarFornecimento(idFazenda: _idFazenda);

        final hadError = (_error ?? "").trim().isNotEmpty;
        if (hadError) {
          _setNotice(
            "Falha ao pausar RFID: não foi possível salvar a sessão aberta.",
            key: "rfid_pause_save_error",
            cooldownMs: 1200,
          );
          return;
        }
      }

      _rfidPausado = vaiPausar;
      _rfid.setLeituraAtiva(!_rfidPausado);
      notifyListeners();

      if (_rfidPausado) {
        _setNotice(
          "RFID pausado. Sessão aberta salva no banco.",
          key: "rfid_pause_saved",
          cooldownMs: 1200,
        );
      }
    } finally {
      _rfidPauseToggleBusy = false;
    }
  }

  void setLeituraRfid(bool on) {
    _rfidPausado = !on;
    _rfid.setLeituraAtiva(on);
    notifyListeners();
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

    if (_autoFlowRfid) {
      await iniciarCarregamento();
    }
  }

  Future<void> selecionarCurralPorEpc(String epc) async {
    final target = await _findCurralByEpc(epc);
    if (target == null) {
      _setNotice(
        "RFID lido, mas não existe previsto para este curral/ração.\nEPC: $epc",
        key: "rfid_sem_previsto_$epc",
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

  // ===========================
  // SESSÃO
  // ===========================

  Future<void> iniciarCarregamento() async {
    final h = _header;
    final s = _selected;
    if (h == null || s == null) return;

    // se já está ativo, não reinicia
    if (_sessaoAtiva &&
        _pesoInicial != null &&
        (_idCadastroAberto ?? "").trim().isNotEmpty) {
      return;
    }

    final now = DateTime.now();

    // evita double-start por spam / concorrência
    if (_startingSessao) return;
    if (now.difference(_lastStartAt).inMilliseconds < 350) return;

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

      // ✅ abre/recupera CADASTRO_FORNECIMENTO e guarda o idCadastro
      final idCad = await _repo.iniciarCadastroFornecimento(
        idFornecimento: s.idFornecimento,
        idCurral: s.idBaia,
        data: h.data,
        trato: h.trato,
        previstoKg: s.previstoKg,
        pesoInicio: _pesoAtual,
        idUsuario: idUsuario,
      );

      _idCadastroAberto = idCad;

      _sessaoAtiva = true;
      _pesoInicial = _pesoAtual;

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
    notifyListeners();
  }

  Future<void> salvarFornecimento({required String idFazenda}) async {
    final h = _header;
    final s = _selected;
    if (h == null || s == null) return;

    if (!_sessaoAtiva || _pesoInicial == null) return;

    final fornecidoKg = fornecidoSessaoKg;

    // ✅ se não forneceu nada: encerra/cancela o cadastro aberto pra não virar pendência fantasma
    if (fornecidoKg <= 0) {
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

      // ✅ 1) SALVA FINALIZADO (SQLite) - novo fluxo
      await _repo.salvarCadastroFinalizado(
        idFornecimento: s.idFornecimento,
        idCurral: s.idBaia,
        data: h.data,
        trato: h.trato,
        previstoKg: s.previstoKg,
        pesoFim: _pesoAtual,
        realizadoKg: fornecidoKg,
        idUsuario: idUsuario,
        origemMapa: _origemMapa,
      );

      // ✅ 2) Atualiza PREVISAO (mapa) somando no realizado
      final atual = await _repo.getRealizadoAcumuladoDoCurral(
        idFornecimento: s.idFornecimento,
        idCurral: s.idBaia,
        data: h.data,
        trato: h.trato,
      );

      final novo = atual + fornecidoKg;

      await _repo.setPrevRealizado(
        idFornecimento: s.idFornecimento,
        idCurral: s.idBaia,
        data: h.data,
        trato: h.trato,
        realizadoKg: novo,
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
