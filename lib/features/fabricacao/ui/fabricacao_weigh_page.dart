// lib/features/fabricacao/ui/fabricacao_weigh_page.dart
import "dart:async";
import "package:flutter/material.dart";

import "../../../repo/config_repo.dart"; // ✅ novo (pra pegar tipoTrabalho e vagão)
import "../../fornecimento/data/fornecimento_repo.dart";
import "../domain/fabricacao_flow.dart";
import "../controller/fabricacao_controller.dart";
import "../data/fabricacao_repo.dart";
import "../domain/models.dart";
import "pre_pesado_dialog.dart";
import "ingredientes_modal.dart";
import "mistura_timer_page.dart";
import "fabricacao_list_page.dart";
import "../../../helpers/mirror_service.dart";
import "../../../widgets/scale_peso_highlight_card.dart";

class FabricacaoWeighPage extends StatefulWidget {
  const FabricacaoWeighPage({
    super.key,
    required this.repo,
    this.initialFabricacaoId,
  });

  final FabricacaoRepo repo;
  final String? initialFabricacaoId;

  @override
  State<FabricacaoWeighPage> createState() => _FabricacaoWeighPageState();
}

class _FabricacaoWeighPageState extends State<FabricacaoWeighPage> {
  late final FabricacaoController c;

  bool _booting = true;
  String? _bootError;

  Timer? _uiTicker;
  bool _reconnecting = false;

  String _prePesadoShownForDetId = "";
  bool _showingPrePesado = false;

  bool _finishing = false; // ✅ trava duplo clique no finalizar
  bool _readOnlyStation = false;
  FabricacaoFlowMode _flowMode = FabricacaoFlowMode.fullOnStation;
  int _tipoTrabalho = 0;

  final _cfgRepo = ConfigRepo(); // ✅ config pra criar carregamento
  final _fornRepo = FornecimentoRepo();

  bool get _recebendoAgora {
    final dt = c.lastPacketAt;
    if (dt == null) return false;
    return DateTime.now().difference(dt).inSeconds <= 2;
  }

  // ✅ troca withOpacity (deprecated) por withValues(alpha: ...)
  Color _alpha(Color color, double opacity) {
    final o = opacity.clamp(0.0, 1.0);
    return color.withValues(alpha: o);
  }

  String _fmtTime(DateTime? dt) {
    if (dt == null) return "--:--:--";
    final h = dt.hour.toString().padLeft(2, "0");
    final m = dt.minute.toString().padLeft(2, "0");
    final s = dt.second.toString().padLeft(2, "0");
    return "$h:$m:$s";
  }

  Widget _wrapPop(Widget child) {
    return PopScope(
      // bloqueia back enquanto finalizacao/timer estiver em andamento
      canPop: !_finishing,
      onPopInvokedWithResult: (didPop, result) async {
        if (_reconnecting) return;
        await c.shutdown();
      },
      child: child,
    );
  }

  @override
  void initState() {
    super.initState();
    c = FabricacaoController(widget.repo)..addListener(_onChange);
    c.onRemoteFinishRequested = () async {
      await _finalizarRemotoViaMirror();
    };
    _boot();

    _uiTicker = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _uiTicker?.cancel();
    c.removeListener(_onChange);
    c.onRemoteFinishRequested = null;

    // ignore: unawaited_futures
    unawaited(c.shutdown());

    c.dispose();
    super.dispose();
  }

  void _onChange() {
    if (!mounted) return;
    setState(() {});
    _maybeShowPrePesado();
  }

  void _showParabensIfDentroTol({
    required int prev,
    required int real,
    required double tolPct,
  }) {
    if (!mounted) return;
    if (prev <= 0) return;

    final dif = (real - prev).abs().toDouble();
    final tolKg = prev.toDouble() * (tolPct / 100.0);

    final dentro = (tolPct <= 0) ? (dif == 0.0) : (dif <= tolKg);
    if (!dentro) return;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        content: Row(
          children: const [
            Icon(Icons.celebration, color: Colors.white),
            SizedBox(width: 10),
            Expanded(child: Text("Parabéns! Ingrediente no alvo ✅")),
          ],
        ),
      ),
    );
  }

  // =========================================================
  // BOOT
  // =========================================================
  Future<void> _boot() async {
    setState(() {
      _booting = true;
      _bootError = null;
    });

    try {
      final ok = await c.bootTruckSide(
        initialFabricacaoId: widget.initialFabricacaoId,
      );
      if (!ok) {
        setState(() {
          _bootError = (widget.initialFabricacaoId ?? "").trim().isNotEmpty
              ? "Fabricação selecionada não encontrada."
              : "Nenhuma fabricação em aberto para hoje.";
          _booting = false;
        });
        return;
      }

      if (!mounted) return;
      final tipo = await _cfgRepo.getTipoTrabalho();
      final flowMode = await _cfgRepo.getFabricacaoFlowMode();
      final h = c.header;
      if (tipo == 1 && h != null && h.status == FabricacaoStatus.pendenteCaminhao) {
        setState(() {
          _readOnlyStation = true;
        });
      }
      setState(() {
        _tipoTrabalho = tipo;
        _flowMode = flowMode;
        _booting = false;
      });

      _maybeShowPrePesado();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _bootError = e.toString();
        _booting = false;
      });
    }
  }

  Future<void> _reconnectAll() async {
    if (_reconnecting) return;

    try {
      setState(() {
        _reconnecting = true;
        _bootError = null;
      });

      try {
        await c.startMirrorFromConfig();
      } catch (_) {}

      await c.reconnectScale();

      if (!mounted) return;
      setState(() => _reconnecting = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _reconnecting = false;
        _bootError = "Erro ao reconectar: $e";
      });
    }
  }

  // =========================================================
  // ✅ CARREGAMENTO ABERTO (STATUS=0) após finalizar
  // =========================================================
  Future<void> _criarCarregamentoParaFabricacaoAtual() async {
    final h = c.header;
    if (h == null) return;

    int tipoTrabalho = 0;
    try {
      tipoTrabalho = await _cfgRepo.getTipoTrabalho();
    } catch (_) {
      tipoTrabalho = 0;
    }

    String idVagao = "";
    try {
      idVagao = await _cfgRepo.getIdVagao();
    } catch (_) {
      idVagao = "";
    }
    if (idVagao.isEmpty) {
      try {
        idVagao = (await widget.repo.getIdVagaoByFabricacaoId(h.id)).trim();
      } catch (_) {
        idVagao = "";
      }
    }

    await widget.repo.criarCarregamentoParaFabricacao(
      idFabricacao: h.id,
      idVagaoOverride: idVagao.isEmpty ? null : idVagao,
      tipoTrabalho: tipoTrabalho,
    );
  }

  Future<bool> _dialogErroCarregamento(Object e, {bool permiteRetry = true}) async {
    if (!mounted) return false;
    final retry = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text("Erro ao gerar carregamento"),
        content: Text(
          "$e\n\n"
          "A fabricação não foi finalizada. Corrija o problema e tente novamente.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text("Fechar"),
          ),
          if (permiteRetry)
            FilledButton(
              onPressed: () => Navigator.of(dialogCtx).pop(true),
              child: const Text("Tentar novamente"),
            ),
        ],
      ),
    );
    return retry == true;
  }

  Future<void> _dialogErroFinalizacao(Object e) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text("Erro ao finalizar fabricação"),
        content: Text("$e"),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text("OK"),
          ),
        ],
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text("Erro ao finalizar: $e"),
      ),
    );
  }

  Future<bool> _criarCarregamentoComRetry() async {
    while (mounted) {
      try {
        await _criarCarregamentoParaFabricacaoAtual();
        return true;
      } catch (e) {
        final retry = await _dialogErroCarregamento(e);
        if (!retry) return false;
      }
    }
    return false;
  }

  Future<void> _goFabricacaoList() async {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => FabricacaoListPage(repo: widget.repo),
      ),
    );
  }

  Future<FabricacaoFlowMode> _getFlowMode() async {
    return _cfgRepo.getFabricacaoFlowMode();
  }

  bool get _mostrarFinalizarParcialEstacionario =>
      _tipoTrabalho == 1 &&
      _flowMode == FabricacaoFlowMode.startStationFinishTruck &&
      !_readOnlyStation;

  /// Finish enviado pela Pá via mirror.
  Future<void> _finalizarRemotoViaMirror() async {
    if (!mounted) return;
    if (_finishing || _readOnlyStation) return;

    final flowMode = await _getFlowMode();
    final tipoTrabalho = await _cfgRepo.getTipoTrabalho();

    if (tipoTrabalho == 1 &&
        flowMode == FabricacaoFlowMode.startStationFinishTruck) {
      await _finalizarParcialEstacionario(confirmar: false);
      return;
    }

    await _finalizarFluxoCompleto(confirmar: false, navegarAposFinalizar: true);
  }

  static const Color _finalizarParcialAmareloEscuro = Color(0xFFB45309);

  Future<void> _finalizarParcialEstacionario({bool confirmar = true}) async {
    final h = c.header;
    if (h == null) return;

    if (confirmar) {
      final ok = await showDialog<bool>(
            context: context,
            builder: (dialogCtx) => AlertDialog(
              title: const Text("Finalizar parcialmente"),
              content: const Text(
                "Finalizar parcialmente vai gerar um carregamento para o caminhão completar.\n"
                "Após isso, esta fabricação ficará PENDENTE e este tablet NÃO enviará essa fabricação ao servidor.\n"
                "Deseja continuar?",
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(false),
                  child: const Text("Não"),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(true),
                  child: const Text("Sim"),
                ),
              ],
            ),
          ) ??
          false;

      if (!ok) return;
    }

    await c.salvarIngredienteAtual();
    await c.atualizaFabricacaoParcial();
    await widget.repo.marcarPendenteCaminhao(h.id);

    await c.finalizeMirrorAndStop(
      msg: "Carregamento enviado para o caminhão completar",
      parcial: true,
    );

    if (!mounted) return;
    setState(() => _readOnlyStation = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          confirmar
              ? "Fabricação marcada como pendente do caminhão."
              : "Finalização parcial (Pá): carregamento enviado para o caminhão completar.",
        ),
      ),
    );
    await _goFabricacaoList();
  }

  Future<void> _perguntarIrParaFornecimento({
    required int trato,
  }) async {
    final tipoTrabalho = await _cfgRepo.getTipoTrabalho();
    if (tipoTrabalho == 1) {
      await _goFabricacaoList();
      return;
    }

    if (!mounted) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text("Fornecimento"),
        content: const Text("Deseja fornecer essa ração agora?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text("Não"),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text("Sim"),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (go != true) {
      await _goFabricacaoList();
      return;
    }

    final idFazenda = (await _cfgRepo.getIdFazendaSelecionada()).trim();
    if (!mounted) return;
    if (idFazenda.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text("Nenhuma fazenda selecionada na configuração."),
        ),
      );
      await _goFabricacaoList();
      return;
    }

    try {
      await _fornRepo.prefetchMapaDoDia(idFazenda: idFazenda);
    } catch (_) {}

    if (!mounted) return;

    Navigator.of(context).pushReplacementNamed(
      "/fornecimento",
      arguments: {
        "idFazenda": idFazenda,
        "autoOpenNovoFornecimento": true,
        "tratoSugerido": trato,
      },
    );
  }

  // =========================================================
  // PRÉ-PESADO
  // =========================================================
  void _maybeShowPrePesado() {
    if (!mounted) return;
    if (_booting) return;
    if (_bootError != null) return;

    final ing = c.atual;
    if (ing == null) return;
    if (!ing.isPrePesado) return;

    if (_prePesadoShownForDetId == ing.idDet) return;
    if (_showingPrePesado) return;

    _prePesadoShownForDetId = ing.idDet;
    _showingPrePesado = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      await showPrePesadoDialog(
        context: context,
        controller: c,
        idDet: ing.idDet,
        nome: ing.insumoNome,
        previstoKg: ing.previstoKg,
        onConfirm: (realizado) async {
          final atualIng = c.ingredientes.firstWhere(
            (e) => e.idDet == ing.idDet,
            orElse: () => ing,
          );
          if (atualIng.realizadoKg > 0) return;

          try {
            await c.confirmarIngredientePrePesadoById(ing.idDet, realizado);
          } catch (e) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("Erro ao confirmar ingrediente: $e")),
            );
            final isLast = c.idx == c.ingredientes.length - 1;
            if (!isLast) await c.next();
          }
        },
      );

      _showingPrePesado = false;
    });
  }

  // =========================================================
  // Ingredientes modal
  // =========================================================
  void _openIngredientesModal() async {
    final h = c.header;
    if (h == null) return;

    final selectedIndex = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => IngredientesModal(
        repo: widget.repo,
        fabId: h.id,
      ),
    );

    if (!mounted) return;
    if (selectedIndex == null) return;

    try {
      await c.goToIndex(selectedIndex);
      _maybeShowPrePesado();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Não foi possível navegar: $e")),
      );
    }
  }

  Future<void> _tentarDestravarNavegacao() async {
    try {
      await c.tentarDestravarNavegacao();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Gravação concluída. Navegação liberada.")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Falha ao gravar novamente: $e")),
      );
    }
  }

  Future<void> _finalizarFluxoCompleto({
    required bool confirmar,
    bool navegarAposFinalizar = true,
  }) async {
    if (!mounted) return;
    if (_finishing || _readOnlyStation) return;

    final flowMode = await _getFlowMode();
    final tipoTrabalho = await _cfgRepo.getTipoTrabalho();

    if (confirmar) {
      if (flowMode == FabricacaoFlowMode.startStationFinishTruck &&
          tipoTrabalho == 1) {
        final acao = await showModalBottomSheet<String>(
          context: context,
          builder: (sheetCtx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.outbox),
                  title: const Text("Finalizar Parcial (Gerar Carregamento)"),
                  onTap: () => Navigator.of(sheetCtx).pop("PARCIAL"),
                ),
                ListTile(
                  leading: const Icon(Icons.check_circle),
                  title: const Text("Finalizar Completa"),
                  onTap: () => Navigator.of(sheetCtx).pop("COMPLETA"),
                ),
              ],
            ),
          ),
        );
        if (acao == "PARCIAL") {
          await _finalizarParcialEstacionario();
          return;
        }
        if (acao != "COMPLETA") return;
      } else {
        final ok = await showDialog<bool>(
          context: context,
          builder: (dialogCtx) => AlertDialog(
            title: const Text("Finalizar fabricação"),
            content: const Text("Deseja finalizar a fabricação?"),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(false),
                child: const Text("Não"),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogCtx).pop(true),
                child: const Text("Sim"),
              ),
            ],
          ),
        );
        if (ok != true) return;
      }
    }

    if (!mounted) return;
    setState(() => _finishing = true);
    try {
      await c.prepararFinalizacao();

      final carregOk = await _criarCarregamentoComRetry();
      if (!carregOk) return;

      final minutos = await c.concluirFinalizacaoSemSalvar();
      final h = c.header;
      if (h != null) {
        await widget.repo.marcarFinalizadaComOrigem(
          h.id,
          tipoTrabalho == 2 ? "CAMINHAO" : "ESTACIONARIO",
        );
      }
      if (!mounted) return;

      if (!navegarAposFinalizar) {
        await _goFabricacaoList();
        return;
      }

      await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => MisturaTimerPage(
            minutos: minutos,
            segundosQuandoMinutosZero: 10,
            repo: widget.repo,
            fabricacaoId: c.header?.id,
            titulo: minutos > 0 ? "Mistura" : "Finalizando fabricação",
            onDonePopToRoot: false,
          ),
        ),
      );
      if (!mounted) return;
      await _perguntarIrParaFornecimento(
        trato: c.header?.trato ?? 0,
      );
    } catch (e) {
      await _dialogErroFinalizacao(e);
    } finally {
      if (mounted) setState(() => _finishing = false);
    }
  }

  FabIngrediente? get _prox {
    final i = c.idx + 1;
    if (i < 0 || i >= c.ingredientes.length) return null;
    return c.ingredientes[i];
  }

  // =========================================================
  // Helpers de tolerância (%)
  // =========================================================
  double _tolKgDoIngrediente(int previstoKg, double toleranciaPct) {
    if (previstoKg <= 0) return 0.0;
    if (toleranciaPct <= 0) return 0.0;
    return previstoKg.toDouble() * (toleranciaPct / 100.0);
  }

  bool _dentroTolPct({
    required int previstoKg,
    required int realizadoKg,
    required double toleranciaPct,
  }) {
    if (previstoKg <= 0) return false;

    final dif = (realizadoKg - previstoKg).abs().toDouble();

    if (toleranciaPct <= 0) return dif == 0.0;

    final tolKg = _tolKgDoIngrediente(previstoKg, toleranciaPct);
    return dif <= tolKg;
  }

  // =========================
  // UI
  // =========================
  @override
  Widget build(BuildContext context) {
    if (_booting) {
      return const Scaffold(
        appBar: _TopAppBar(title: "Fabricação"),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_bootError != null) {
      return Scaffold(
        appBar: const _TopAppBar(title: "Fabricação"),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _bootError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: _boot,
                  child: const Text("Tentar novamente"),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text("Voltar"),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final header = c.header!;
    final ing = c.atual!;
    final nextIng = _prox;
    final isLast = c.idx == c.ingredientes.length - 1;

    final prev = ing.previstoKg;
    final real = ing.realizadoKg;

    final difAbs = (real - prev).abs();

    final tolPct = c.toleranciaPct;
    final tolKg = _tolKgDoIngrediente(prev, tolPct);

    final dentroTol = _dentroTolPct(
      previstoKg: prev,
      realizadoKg: real,
      toleranciaPct: tolPct,
    );

    final difColor = prev <= 0
        ? Colors.blueGrey
        : (dentroTol
            ? Colors.blueGrey
            : (real > prev ? Colors.red : Colors.green));

    return _wrapPop(
      Scaffold(
        appBar: _TopAppBar(
          title: "Fabricação",
          subtitle: "Trato ${header.trato} • ${header.dietaNome}",
          actions: [
            IconButton(
              tooltip: "Ingredientes",
              onPressed: _openIngredientesModal,
              icon: const Icon(Icons.list_alt),
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _cardBalancaTopCompact(
                totalPrevistoFabricacaoKg: header.qtdPrevista,
                previstoIngredienteKg: prev,
                tolPct: tolPct,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: _cardIngredienteTop(ing: ing, nextIng: nextIng),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: _cardDiferencaPrincipalFill(
                  prev: prev,
                  real: real,
                  difAbs: difAbs,
                  difColor: difColor,
                  dentroTol: dentroTol,
                  tolPct: tolPct,
                  tolKg: tolKg,
                ),
              ),
            ),
            if (c.navLockedBySaveError)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Card(
                  color: Colors.red.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            c.navLockReason.isEmpty
                                ? "Navegação travada por falha de gravação."
                                : c.navLockReason,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Colors.red,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: _tentarDestravarNavegacao,
                          child: const Text("Tentar gravar"),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (_readOnlyStation)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Card(
                  color: Colors.blue.shade50,
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Icon(Icons.lock_outline, color: Colors.blue),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            "Fabricacao pendente do caminhao. Edicao bloqueada neste tablet.",
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Colors.blue,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: _bottomListaBar(),
            ),
            if (_mostrarFinalizarParcialEstacionario)
              SafeArea(
                top: false,
                minimum: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Card(
                  elevation: 2,
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          "Estacionário",
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            color: Colors.grey.shade800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "Gera carregamento para o caminhão completar a fabricação.",
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: _finalizarParcialAmareloEscuro,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: (_finishing || c.navLockedBySaveError)
                              ? null
                              : () async => _finalizarParcialEstacionario(),
                          icon: const Icon(Icons.outbox),
                          label: const Text(
                            "Finalizar parcial",
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            _bottomNav(
              isLast: isLast,
              highlightFinalize: dentroTol,
            ),
          ],
        ),
      ),
    );
  }

  // =========================
  // Card Balança (TOP compacto)
  // =========================
  Widget _cardBalancaTopCompact({
    required double totalPrevistoFabricacaoKg,
    required int previstoIngredienteKg,
    required double tolPct,
  }) {
    final connected = c.scaleConnected;
    final connecting = c.scaleConnecting;
    final recebendo = _recebendoAgora;
    final pausado = c.pesoPausado;

    final mirrorOn = c.mirrorEnabled;
    final mirrorOk = c.mirrorConnected;

    Color color;
    IconData icon;
    String text;

    if (connecting) {
      color = Colors.blueGrey;
      icon = Icons.wifi_tethering;
      text = "Conectando...";
    } else if (!connected) {
      color = Colors.red;
      icon = Icons.portable_wifi_off;
      text = "Desconectada";
    } else if (!recebendo) {
      color = Colors.orange;
      icon = Icons.sync_problem;
      text = "Sem dados";
    } else {
      color = Colors.green;
      icon = Icons.check_circle;
      text = "OK";
    }

    final lastAtTxt = _fmtTime(c.lastPacketAt);
    final canReconnect = !_reconnecting && !connecting;

    final subIng = previstoIngredienteKg > 0
        ? "Insumo atual: ${previstoIngredienteKg.toStringAsFixed(0)} kg"
            "${tolPct > 0 ? " · tol ${tolPct.toStringAsFixed(0)}%" : ""}"
        : null;

    final balancaDetail = "$text · $lastAtTxt${pausado ? " · PAUSADA" : ""}";

    Color mirrorColor;
    IconData mirrorIcon;
    String mirrorDetail;
    if (!mirrorOn) {
      mirrorColor = Colors.grey;
      mirrorIcon = Icons.cast_outlined;
      mirrorDetail = "Desligado";
    } else if (mirrorOk) {
      mirrorColor = Colors.green;
      mirrorIcon = Icons.cast_connected;
      mirrorDetail = "Conectado";
    } else {
      mirrorColor = Colors.orange;
      mirrorIcon = Icons.cast;
      mirrorDetail = "Conectando…";
    }
    if (mirrorOn) {
      final host = MirrorService.instance.host.trim();
      final port = MirrorService.instance.port;
      if (host.isNotEmpty) {
        mirrorDetail = "$mirrorDetail · $host:$port";
      }
    }

    return ScalePesoHighlightCard(
      pesoKg: c.lastWeight,
      pesoLabel: "Balança",
      secondaryLabel: "Previsto total (fabricação)",
      secondaryKg: totalPrevistoFabricacaoKg,
      secondarySubtitle: subIng,
      pesoInlineActions: FilledButton.icon(
        onPressed: connecting ? null : c.togglePausaPesagem,
        icon: Icon(pausado ? Icons.play_arrow : Icons.pause, size: 18),
        label: Text(pausado ? "Retomar" : "Pausar"),
        style: FilledButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
      ),
      connectionSlots: [
        ScaleConnectionStatusChip(
          title: "Balança",
          detail: balancaDetail,
          icon: icon,
          color: color,
        ),
        ScaleConnectionStatusChip(
          title: "Espelho",
          detail: mirrorDetail,
          icon: mirrorIcon,
          color: mirrorColor,
        ),
      ],
      footer: Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: canReconnect ? _reconnectAll : null,
          icon: _reconnecting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh, size: 18),
          label: Text(_reconnecting ? "..." : "Reconectar"),
          style: OutlinedButton.styleFrom(
            visualDensity: VisualDensity.compact,
          ),
        ),
      ),
    );
  }

  Widget _cardIngredienteTop({
    required FabIngrediente ing,
    required FabIngrediente? nextIng,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.inventory_2_outlined, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    ing.insumoNome.isEmpty ? "(Sem nome)" : ing.insumoNome,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 22,
                      height: 1.05,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (ing.isPrePesado) ...[
                  const SizedBox(width: 8),
                  _chip(icon: Icons.verified, label: "Pré-pesado"),
                ],
              ],
            ),
            if (nextIng != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.grey.shade100,
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.next_plan, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        "Próximo: ${nextIng.insumoNome}",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      "${nextIng.previstoKg} kg",
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    if (nextIng.isPrePesado) ...[
                      const SizedBox(width: 10),
                      const Icon(Icons.verified, size: 18),
                    ]
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _cardDiferencaPrincipalFill({
    required int prev,
    required int real,
    required int difAbs,
    required Color difColor,
    required bool dentroTol,
    required double tolPct,
    required double tolKg,
  }) {
    String status;
    if (prev <= 0) {
      status = "Sem previsto";
    } else if (dentroTol) {
      status = tolPct > 0 ? "No alvo ✅" : "No alvo ✅ (exato)";
    } else if (real < prev) {
      status = "Faltando $difAbs kg";
    } else {
      status = "Passou $difAbs kg";
    }

    final percent = (prev > 0) ? (real * 100 / prev) : 0.0;
    final pctLabel = prev > 0 ? "${percent.toStringAsFixed(0)}%" : "--";
    final barValue = prev > 0 ? (real / prev).clamp(0.0, 1.0) : 0.0;

    final faltando = prev > 0 ? (prev - real) : 0;
    final difText = (prev > 0 && real > prev) ? "+${real - prev}" : "$faltando";

    Color bg;
    if (prev <= 0) {
      bg = Colors.blueGrey.shade700;
    } else if (dentroTol) {
      bg = Colors.green.shade700;
    } else if (real > prev) {
      bg = Colors.deepOrange.shade700;
    } else {
      bg = Colors.black;
    }

    return Container(
      width: double.infinity,
      height: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        color: bg,
        boxShadow: [
          BoxShadow(
            blurRadius: 22,
            spreadRadius: 0,
            offset: const Offset(0, 12),
            color: Colors.black.withValues(alpha: 0.22),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    const Icon(Icons.scale, color: Colors.white, size: 28),
                    const SizedBox(width: 10),
                    const Flexible(
                      child: Text(
                        "A FABRICAR (kg)",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 26,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 132),
                    child: _PulseChip(
                      icon: Icons.timer,
                      active: c.autoCountdown > 0,
                      label: c.autoCountdown > 0
                          ? "Pulo: ${c.autoCountdown}s"
                          : "Pulo: pronto",
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  difText,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 200,
                    height: 0.90,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Stack(
            alignment: Alignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  minHeight: 18,
                  value: barValue,
                ),
              ),
              Text(
                pctLabel,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _midKvCenteredCompact("Previsto", "$prev kg")),
              const SizedBox(width: 10),
              Expanded(child: _midKvCenteredCompact("Realizado", "$real kg")),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: Colors.white.withValues(alpha: 0.16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
            ),
            child: Row(
              children: [
                Icon(
                  dentroTol
                      ? Icons.verified
                      : (prev <= 0
                          ? Icons.help_outline
                          : (real < prev
                              ? Icons.warning_amber
                              : Icons.error_outline)),
                  size: 18,
                  color: Colors.white,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    status,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                      color: Colors.white,
                    ),
                  ),
                ),
                if (prev > 0 && tolPct > 0)
                  Text(
                    "±${tolPct.toStringAsFixed(1)}% (±${tolKg.toStringAsFixed(0)}kg)",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomListaBar() {
    final total = c.ingredientes.length;
    final pos = (c.idx + 1).clamp(1, total);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                "Progresso $pos/$total",
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            TextButton.icon(
              onPressed: _openIngredientesModal,
              icon: const Icon(Icons.list_alt, size: 18),
              label: const Text("Ver lista"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _midKvCenteredCompact(String k, String v) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade300),
        color: _alpha(Colors.white, 0.70),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            k,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w800,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              v,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22,
                height: 1.0,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomNav({
    required bool isLast,
    required bool highlightFinalize,
  }) {
    final pulse = (DateTime.now().millisecond < 500);
    final destacar = isLast && highlightFinalize && !_finishing;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey.shade200)),
        ),
        child: Row(
          children: [
            IconButton(
              onPressed: (c.idx == 0 || c.navLockedBySaveError || _readOnlyStation)
                  ? null
                  : () async {
                      try {
                        await c.prev();
                      } catch (e) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text("Não foi possível voltar: $e")),
                        );
                      }
                    },
              icon: const Icon(Icons.arrow_back),
              tooltip: "Anterior",
            ),
            const SizedBox(width: 6),
            Expanded(
              child: AnimatedScale(
                scale: destacar ? (pulse ? 1.03 : 1.0) : 1.0,
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeInOut,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: destacar
                        ? [
                            BoxShadow(
                              color: Colors.green.withValues(alpha: 0.35),
                              blurRadius: pulse ? 18 : 10,
                              spreadRadius: pulse ? 1.5 : 0.2,
                            ),
                          ]
                        : null,
                  ),
                  child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: destacar ? Colors.green.shade700 : null,
                ),
                onPressed: (_finishing || _readOnlyStation || (!isLast && c.navLockedBySaveError))
                    ? null
                    : () async {
                        if (!isLast) {
                          final ingAntes = c.atual;

                          final prevAntes = ingAntes?.previstoKg ?? 0;
                          final realAntes = ingAntes?.realizadoKg ?? 0;
                          final tolPct = c.toleranciaPct;

                          try {
                            await c.next();
                          } catch (e) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  "Não foi possível avançar: $e",
                                ),
                              ),
                            );
                            return;
                          }

                          if (!mounted) return;

                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            _showParabensIfDentroTol(
                              prev: prevAntes,
                              real: realAntes,
                              tolPct: tolPct,
                            );
                          });

                          return;
                        }

                        try {
                          await _finalizarFluxoCompleto(confirmar: true);
                        } catch (e) {
                          if (!mounted) return;
                          await _dialogErroFinalizacao(e);
                        }
                      },
                    icon: Icon(isLast ? Icons.check : Icons.arrow_forward),
                    label: Text(isLast ? "Finalizar" : "Próximo"),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PulseChip extends StatefulWidget {
  const _PulseChip({
    required this.icon,
    required this.label,
    required this.active,
  });

  final IconData icon;
  final String label;
  final bool active;

  @override
  State<_PulseChip> createState() => _PulseChipState();
}

class _PulseChipState extends State<_PulseChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ac = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  )..repeat(reverse: true);

  Color _alpha(Color color, double opacity) {
    final o = opacity.clamp(0.0, 1.0);
    return color.withValues(alpha: o);
  }

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) {
      return _chipBase(
        icon: widget.icon,
        label: widget.label,
        color: Colors.grey.shade100,
        border: Colors.grey.shade300,
        iconColor: Colors.black87,
        textColor: Colors.black87,
      );
    }

    return AnimatedBuilder(
      animation: _ac,
      builder: (_, __) {
        final t = _ac.value;
        final scale = 1.0 + (t * 0.06);
        final glow = 0.10 + (t * 0.20);

        return Transform.scale(
          scale: scale,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              boxShadow: [
                BoxShadow(
                  color: _alpha(Colors.orange, glow),
                  blurRadius: 18,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: _chipBase(
              icon: widget.icon,
              label: widget.label,
              color: Colors.white.withValues(alpha: 0.92),
              border: _alpha(Colors.orange, 0.60),
              iconColor: Colors.deepOrange,
              textColor: Colors.black87,
            ),
          ),
        );
      },
    );
  }

  Widget _chipBase({
    required IconData icon,
    required String label,
    required Color color,
    required Color border,
    required Color iconColor,
    required Color textColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _TopAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _TopAppBar({required this.title, this.subtitle, this.actions});

  final String title;
  final String? subtitle;
  final List<Widget>? actions;

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      titleSpacing: 12,
      actions: actions,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title),
          if (subtitle != null)
            Text(
              subtitle!,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
            ),
        ],
      ),
    );
  }
}



