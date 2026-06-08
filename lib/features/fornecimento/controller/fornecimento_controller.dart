// lib/features/fornecimento/controller/fornecimento_controller.dart
import "dart:async";
import "package:flutter/foundation.dart";

import "../../../repo/config_repo.dart";
import "../data/fornecimento_repo.dart";
import "../domain/fornecimento_models.dart";
import "../domain/histerese_params.dart";

import "../services/scale_tcp_service.dart";
import "../services/rfid_tcp_service.dart";
import "../services/balanca_parser.dart";

class FornecimentoController extends ChangeNotifier {
  FornecimentoController({
    required this.repo,
    required this.scale,
    required this.rfid,
    required this.idUsuario,
  });

  final FornecimentoRepo repo;
  final ScaleTcpService scale;
  final RfidTcpService rfid;
  final String idUsuario;
  final _cfgRepo = ConfigRepo();

  // -----------------------
  // Estado / sessão
  // -----------------------
  String? _idFazenda;

  CarregamentoAberto? carregamento; // vem do repo
  int? tratoSelecionado;

  String? get idRacaoCarregada =>
      carregamento?.idDieta; // ✅ ID_DIETA == ID_RACAO

  List<CurralPrev> currais = const [];
  int indexAtual = 0;

  CurralPrev? get atual {
    if (currais.isEmpty) return null;
    final i = indexAtual.clamp(0, currais.length - 1);
    return currais[i];
  }

  // sessão por curral
  double? pesoInicio;
  DateTime? horaInicio;
  String? _idCadastroAberto;

  // config
  ModeloBalanca modeloBalanca = ModeloBalanca.topcon;
  HistereseParams histerese = HistereseParams.defaults;

  // peso
  double pesoAtual = 0;
  StreamSubscription<String>? _subScale;
  StreamSubscription<String>? _subRfid;

  String? lastEpc;

  bool _loading = false;
  bool get loading => _loading;

  String? _erro;
  String? get erro => _erro;

  bool _switching = false;
  int _origemMapa = 0; // 0=RFID, 1=Mapa

  // -----------------------
  // Helpers
  // -----------------------
  static String _pad2(int n) => n.toString().padLeft(2, "0");
  static String _ymd(DateTime d) =>
      "${d.year.toString().padLeft(4, "0")}-${_pad2(d.month)}-${_pad2(d.day)}";

  double _round3(double v) => (v * 1000).round() / 1000.0;

  double get realizadoParcial {
    final pi = pesoInicio;
    if (pi == null) return 0;
    // realizado = pesoInicio - pesoAtual (mantém lógica original)
    final v = pi - pesoAtual;
    return _round3(v < 0 ? 0 : v);
  }

  void _setLoading(bool v) {
    _loading = v;
    notifyListeners();
  }

  // -----------------------
  // Init
  // -----------------------
  Future<void> init({required String idFazenda}) async {
    _idFazenda = idFazenda;

    _setLoading(true);
    _erro = null;

    try {
      // params
      final p = await repo.getConnectionParams();
      modeloBalanca = p.modeloBalanca;
      if (p.histerese != null) histerese = p.histerese!;

      // conecta balança
      await scale.connect(p.hostBalanca, p.portaBalanca);
      await _subScale?.cancel();
      _subScale = scale.lines.listen((line) {
        final pesoStr = BalancaParser.extraiPeso(line, modeloBalanca);
        if (pesoStr.isEmpty) return;

        final w = BalancaParser.parseToDouble(pesoStr);
        if (w == null) return;

        pesoAtual = w;
        notifyListeners();
      });

      // conecta rfid (se tiver)
      await _subRfid?.cancel();
      if ((p.hostRfid ?? "").trim().isNotEmpty && (p.portaRfid ?? 0) > 0) {
        await rfid.connect(p.hostRfid!, p.portaRfid!);
        _subRfid = rfid.lines.listen((line) async {
          final epc = RfidTcpService.extractEpc(line);
          histerese = p.histerese ?? HistereseParams.defaults;

          lastEpc = epc;
          notifyListeners();

          await _onEpc(epc);
        });
      }

      // carregamento aberto (obrigatório)
      carregamento = await repo.getCarregamentoAberto();
      if (carregamento == null) {
        final tipo = await _cfgRepo.getTipoTrabalho();
        if (tipo == 2) {
          final ok = await repo.tryImportCarregamentoFromEstacionario();
          if (ok) {
            carregamento = await repo.getCarregamentoAberto();
          }
        }
      }
      if (carregamento == null || carregamento!.status != 0) {
        _erro =
            "Sem CARREGAMENTO em aberto (STATUS=0). Abra um carregamento antes de fornecer.";
        return;
      }

      // reset mapa/sessão
      currais = const [];
      indexAtual = 0;
      pesoInicio = null;
      horaInicio = null;
      _idCadastroAberto = null;
    } catch (e) {
      _erro = e.toString();
    } finally {
      _setLoading(false);
    }
  }

  // -----------------------
  // Montar mapa (hoje + ração carregada + trato)
  // -----------------------
  Future<void> selecionarTrato({
    required String idFazenda,
    required int trato,
  }) async {
    tratoSelecionado = trato;
    await montarMapaCurrais(idFazenda: idFazenda);
  }

  Future<void> montarMapaCurrais({required String idFazenda}) async {
    _erro = null;

    if (carregamento == null || carregamento!.status != 0) {
      _erro = "Sem CARREGAMENTO em aberto (STATUS=0).";
      notifyListeners();
      return;
    }

    if (tratoSelecionado == null) {
      _erro = "Selecione o TRATO.";
      notifyListeners();
      return;
    }

    final idRacao = (idRacaoCarregada ?? "").trim();
    if (idRacao.isEmpty) {
      _erro = "Carregamento sem ID_DIETA (ID_RACAO) para filtrar.";
      notifyListeners();
      return;
    }

    _setLoading(true);
    try {
      currais = await repo.listCurraisPrevistosHoje(
        idFazenda: idFazenda,
        trato: tratoSelecionado!,
        idRacao: idRacao,
      );

      indexAtual = 0;
      pesoInicio = null;
      horaInicio = null;
      _idCadastroAberto = null;
    } catch (e) {
      _erro = e.toString();
    } finally {
      _setLoading(false);
    }
  }

  // -----------------------
  // Navegação UI (o WEIGH_PAGE chama isso)
  // -----------------------
  Future<void> next() async {
    if (currais.isEmpty) return;
    if (indexAtual < currais.length - 1) {
      await _trocarParaIndex(indexAtual + 1);
    }
  }

  Future<void> prev() async {
    if (currais.isEmpty) return;
    if (indexAtual > 0) {
      await _trocarParaIndex(indexAtual - 1);
    }
  }

  /// opcional: usado na weigh_page para "posicionar" no curral vindo da tela anterior
  Future<void> goToFornecimento(String idFornecimento) async {
    if (currais.isEmpty) return;

    // tenta localizar por idFornecimento (se o model tiver)
    final i = currais.indexWhere((x) => x.idFornecimento == idFornecimento);
    if (i >= 0) {
      await _trocarParaIndex(i);
    }
  }

  Future<void> iniciarPorClique(int index) async {
    if (index < 0 || index >= currais.length) return;
    _origemMapa = 1;
    await _trocarParaIndex(index);
  }

  // -----------------------
  // RFID (troca automática)
  // -----------------------
  Future<void> _onEpc(String epc) async {
    if (currais.isEmpty) return;
    if (_switching) return;

    _switching = true;
    try {
      _origemMapa = 0;
      final target = epc.trim();
      final i = currais.indexWhere(
        (c) => (c.rfid ?? "").trim() == target,
      );

      if (i < 0) return; // curral fora do mapa
      await _trocarParaIndex(i);
    } finally {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      _switching = false;
    }
  }

  // -----------------------
  // Troca de curral (fecha atual e inicia novo)
  // -----------------------
  Future<void> _trocarParaIndex(int novoIndex) async {
    if (currais.isEmpty) return;

    if (novoIndex == indexAtual && atual != null) return;

    // fecha atual se estava iniciado
    if (atual != null && horaInicio != null) {
      await fecharCurralAtual();
    }

    indexAtual = novoIndex;

    final c = atual;
    if (c == null) return;

    pesoInicio = pesoAtual;
    horaInicio = DateTime.now();

    final idRacao = (idRacaoCarregada ?? "").trim();
    final dataRef = _parseDataIso(c.dataIso);
    final idFornecimento = (c.idFornecimento ?? "").trim().isNotEmpty
        ? (c.idFornecimento ?? "").trim()
        : (idRacao.isEmpty
            ? ""
            : FornecimentoRepo.comboKey(
                idBaia: c.idBaia,
                idRacao: idRacao,
                dataYmd: _ymd(dataRef),
                trato: c.trato,
              ));

    if (idFornecimento.isNotEmpty) {
      try {
        _idCadastroAberto = await repo.iniciarCadastroFornecimento(
          idFornecimento: idFornecimento,
          idCurral: c.idBaia,
          data: dataRef,
          trato: c.trato,
          previstoKg: c.previstoKg,
          pesoInicio: pesoInicio!,
          idUsuario: idUsuario,
        );
      } catch (e) {
        _erro = e.toString();
        pesoInicio = null;
        horaInicio = null;
        _idCadastroAberto = null;
      }
    }

    notifyListeners();
  }

  static DateTime _parseDataIso(String iso) {
    final base = iso.length >= 10 ? iso.substring(0, 10) : iso;
    return DateTime.tryParse(base) ?? DateTime.now();
  }

  // -----------------------
  // Fechar (grava CADASTRO_FORNECIMENTO e atualiza PREVISAO)
  // -----------------------
  Future<void> fecharCurralAtual() async {
    final c = atual;
    if (c == null) return;

    final inicio = horaInicio;
    if (inicio == null) return; // não iniciou

    final idFaz = (_idFazenda ?? "").trim();
    if (idFaz.isEmpty) {
      _erro = "idFazenda não definido no controller.";
      notifyListeners();
      return;
    }

    final idRacao = (idRacaoCarregada ?? "").trim();
    if (idRacao.isEmpty) {
      _erro = "Carregamento sem ID_DIETA (ID_RACAO).";
      notifyListeners();
      return;
    }

    final data = DateTime.now();
    final ymd = _ymd(data);
    final trato = c.trato;

    final idFornecimento = (c.idFornecimento ?? "").trim().isNotEmpty
        ? (c.idFornecimento ?? "").trim()
        : FornecimentoRepo.comboKey(
            idBaia: c.idBaia,
            idRacao: idRacao,
            dataYmd: ymd,
            trato: trato,
          );

    final realizado = realizadoParcial;

    try {
      // Grava 1 linha em CADASTRO_FORNECIMENTO; acumulado na API na sync.
      await repo.salvarCadastroFinalizado(
        idFornecimento: idFornecimento,
        idCurral: c.idBaia,
        data: data,
        trato: trato,
        previstoKg: c.previstoKg,
        pesoFim: pesoAtual,
        realizadoKg: realizado,
        idUsuario: idUsuario,
        origemMapa: _origemMapa,
        idCadastroAberto: _idCadastroAberto,
      );

      // limpa sessão
      pesoInicio = null;
      horaInicio = null;
      _idCadastroAberto = null;

      // recarrega mapa para refletir realizado/falta
      await montarMapaCurrais(idFazenda: idFaz);
    } catch (e) {
      _erro = e.toString();
    }

    notifyListeners();
  }

  @override
  void dispose() {
    _subScale?.cancel();
    _subRfid?.cancel();
    scale.dispose();
    rfid.dispose();
    super.dispose();
  }
}
