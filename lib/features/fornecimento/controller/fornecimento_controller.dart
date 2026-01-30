// lib/features/fornecimento/controller/fornecimento_controller.dart
import "dart:async";
import "package:flutter/foundation.dart";

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
    return _round3(pi - pesoAtual);
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

    // inicia sessão do novo
    pesoInicio = pesoAtual;
    horaInicio = DateTime.now();

    notifyListeners();
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

    // ✅ chave estável (idBaia|idRacao|data|trato)
    final key = FornecimentoRepo.comboKey(
      idBaia: c.idBaia,
      idRacao: idRacao,
      dataYmd: ymd,
      trato: trato,
    );

    final realizado = realizadoParcial;

    try {
      // 1) garante/abre registro em CADASTRO_FORNECIMENTO (ou pega o aberto)
      final idCadastro = await repo.iniciarCadastroFornecimento(
        idFornecimento: key, // ✅ agora é a comboKey
        idCurral: c.idBaia,
        data: data,
        trato: trato,
        previstoKg: c.previstoKg,
        pesoInicio: pesoInicio ?? pesoAtual,
      );

      // 2) finaliza CADASTRO_FORNECIMENTO
      await repo.finalizarCadastroFornecimento(
        idCadastro: idCadastro,
        pesoFim: pesoAtual,
        realizadoKg: realizado,
      );

      // 3) soma com acumulado e atualiza PREVISAO (por data+trato+baia)
      final acumulado = await repo.getRealizadoAcumuladoDoCurral(
        idFornecimento: key,
        idCurral: c.idBaia,
        data: data,
        trato: trato,
      );

      final novoRealizado = _round3(acumulado + realizado);

      await repo.setPrevRealizado(
        idFornecimento: key,
        idCurral: c.idBaia,
        data: data,
        trato: trato,
        realizadoKg: novoRealizado,
      );

      // limpa sessão
      pesoInicio = null;
      horaInicio = null;

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
