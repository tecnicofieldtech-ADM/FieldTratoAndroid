// lib/features/fornecimento/controller/fornecimento_controller.dart
import "dart:async";
import "package:flutter/foundation.dart";

import "../data/fornecimento_repo.dart";
import "../domain/fornecimento_models.dart";
import "../domain/histerese_params.dart";

import "../services/scale_tcp_service.dart";
import "../services/rfid_tcp_service.dart";

// ✅ evita conflito de enum duplicado
import "../services/balanca_parser.dart" hide ModeloBalanca;

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

  // estado
  List<CurralPrev> currais = const [];
  int indexAtual = 0;

  CurralPrev? get atual => (currais.isEmpty) ? null : currais[indexAtual];

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

  // lib/features/fornecimento/controller/fornecimento_controller.dart
// ✅ ADICIONE dentro da classe FornecimentoController

  /// Posiciona o "atual" pelo ID_FORNECIMENTO (string).
  /// Se não achar, mantém o atual como está.
  Future<void> goToFornecimento(String? idFornecimento) async {
    final id = (idFornecimento ?? "").toString().trim();
    if (id.isEmpty) return;

    final i = currais.indexWhere((c) => c.idFornecimento == id);
    if (i >= 0) {
      int _idx  = i; // ou o nome da sua variável de índice atual
      notifyListeners();
    }
  }


  Future<void> init({required String idFazenda}) async {
    _loading = true;
    notifyListeners();

    final p = await repo.getConnectionParams();
    modeloBalanca = p.modeloBalanca;
    if (p.histerese != null) histerese = p.histerese!;

    // conecta scale
    await scale.connect(p.hostBalanca, p.portaBalanca);
    await _subScale?.cancel();
    _subScale = scale.lines.listen((line) {
      // ✅ usa os métodos que EXISTEM no seu parser
      final pesoStr = BalancaParser.extraiPeso(line, modeloBalanca);
      if (pesoStr.isEmpty) return;

      final w = BalancaParser.parseToDouble(pesoStr);
      if (w == null) return;

      pesoAtual = w;
      notifyListeners();
    });

    // conecta rfid (se tiver)
    if ((p.hostRfid ?? "").trim().isNotEmpty && (p.portaRfid ?? 0) > 0) {
      await rfid.connect(p.hostRfid!, p.portaRfid!);
      await _subRfid?.cancel();
      _subRfid = rfid.lines.listen((line) {
        final epc = RfidTcpService.extractEpc(line);
        if (epc != null && epc.isNotEmpty) {
          lastEpc = epc;
          notifyListeners();
        }
      });
    }

    // lista currais (trato atual)
    currais = await repo.listCurraisPrevistosHoje(idFazenda: idFazenda);

    indexAtual = 0;
    _loading = false;
    notifyListeners();
  }

  void next() {
    if (currais.isEmpty) return;
    if (indexAtual < currais.length - 1) {
      indexAtual++;
      notifyListeners();
    }
  }

  void prev() {
    if (currais.isEmpty) return;
    if (indexAtual > 0) {
      indexAtual--;
      notifyListeners();
    }
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
