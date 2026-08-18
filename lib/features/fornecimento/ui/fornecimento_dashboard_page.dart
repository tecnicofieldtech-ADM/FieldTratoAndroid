// lib/features/fornecimento/ui/fornecimento_dashboard_page.dart
import "dart:async";

import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:shared_preferences/shared_preferences.dart";

import "../../../helpers/scale_comm.dart";
import "../../../helpers/scale_model_config.dart";
import "../../../helpers/rfid_comm.dart";

import "../controller/fornecimento_dashboard_controller.dart";
import "../data/fornecimento_repo.dart";
import "../../../services/session_service.dart";
import "../../../repo/config_repo.dart";
import "../../../repo/fazenda_repo.dart";
import "../../../repo/user_repo.dart";
import "../../../repo/vagao_repo.dart";
import "../../../services/bootstrap_sync.dart";
import "../../../widgets/scale_peso_highlight_card.dart";

class FornecimentoDashboardPage extends StatefulWidget {
  const FornecimentoDashboardPage({
    super.key,
    required this.idFazenda,
    required this.idUsuario,
    this.trato,
    required this.repo,
    required this.scale,
    required this.rfid,
    this.data,
    this.idRacaoFiltro,
    this.startCleared = false,
  });

  final String idFazenda;
  final String idUsuario;
  final int? trato;

  final DateTime? data;
  final String? idRacaoFiltro;
  final bool startCleared;

  final FornecimentoRepo repo;
  final ScaleComm scale;
  final RfidComm rfid;

  @override
  State<FornecimentoDashboardPage> createState() =>
      _FornecimentoDashboardPageState();
}

class _FornecimentoDashboardPageState extends State<FornecimentoDashboardPage> {
  late final FornecimentoDashboardController _ctrl;

  final _cfgRepo = ConfigRepo();
  final _vagaoRepo = VagaoRepo();
  final _fazendaRepo = FazendaRepo();
  final _userRepo = UserRepo();

  late final BootstrapSync _bootstrap = BootstrapSync(
    cfgRepo: _cfgRepo,
    vagaoRepo: _vagaoRepo,
    fazendaRepo: _fazendaRepo,
    userRepo: _userRepo,
  );
  static const _kMapaHorizontal = "forn_dash_mapa_horizontal";
  static const _kLinhaFiltro = "forn_dash_linha_filtro";
  static const _kCurralSelecionado = "forn_dash_curral_sel";

  // ✅ beep/alerta
  late final _BeepAlerter _beeper;
  bool _showRfidControls = false;
  bool _mapaHorizontalFixo = false;
  String? _linhaFiltroSaved;
  String? _curralSelSaved;
  final ScrollController _mapaHScrollCtrl = ScrollController();
  double _mapaHScrollOffset = 0;
  bool _ctrlWasLoading = false;

  @override
  void initState() {
    super.initState();

    _ctrl = FornecimentoDashboardController(
      repo: widget.repo,
      scale: widget.scale,
      rfid: widget.rfid,
    );

    _beeper = _BeepAlerter(
      nearKg: 50,
      criticalKg: 10,
      cooldown: const Duration(seconds: 2),
    );

    _mapaHScrollCtrl.addListener(_trackMapaHorizontalScroll);
    _ctrl.addListener(_onCtrlLoadingForMapaScroll);

    _boot();
  }

  void _trackMapaHorizontalScroll() {
    if (!_mapaHScrollCtrl.hasClients) return;
    _mapaHScrollOffset = _mapaHScrollCtrl.offset;
  }

  void _onCtrlLoadingForMapaScroll() {
    final loading = _ctrl.loading;
    if (_ctrlWasLoading && !loading && _mapaHScrollOffset > 0) {
      _scheduleMapaHorizontalScrollRestore();
    }
    _ctrlWasLoading = loading;
  }

  void _captureMapaHorizontalScroll() {
    if (_mapaHScrollCtrl.hasClients) {
      _mapaHScrollOffset = _mapaHScrollCtrl.offset;
    }
  }

  void _scheduleMapaHorizontalScrollRestore({int attempt = 0}) {
    if (_mapaHScrollOffset <= 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_mapaHScrollCtrl.hasClients) {
        final max = _mapaHScrollCtrl.position.maxScrollExtent;
        final target = _mapaHScrollOffset.clamp(0.0, max);
        if ((_mapaHScrollCtrl.offset - target).abs() > 1) {
          _mapaHScrollCtrl.jumpTo(target);
        }
        return;
      }
      if (attempt < 8) {
        _scheduleMapaHorizontalScrollRestore(attempt: attempt + 1);
      }
    });
  }

  Future<void> _loadUiPrefs() async {
    final sp = await SharedPreferences.getInstance();
    _mapaHorizontalFixo = sp.getBool(_kMapaHorizontal) ?? false;

    final linha = (sp.getString(_kLinhaFiltro) ?? "").trim();
    _linhaFiltroSaved = linha.isEmpty ? null : linha;

    final curral = (sp.getString(_kCurralSelecionado) ?? "").trim();
    _curralSelSaved = curral.isEmpty ? null : curral;
  }

  Future<void> _saveMapaHorizontalPref(bool value) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kMapaHorizontal, value);
  }

  Future<void> _saveLinhaFiltroPref(String? linha) async {
    final sp = await SharedPreferences.getInstance();
    final v = (linha ?? "").trim();
    if (v.isEmpty) {
      await sp.remove(_kLinhaFiltro);
    } else {
      await sp.setString(_kLinhaFiltro, v);
    }
  }

  Future<void> _saveCurralSelecionadoPref(String? idFornecimento) async {
    final sp = await SharedPreferences.getInstance();
    final v = (idFornecimento ?? "").trim();
    if (v.isEmpty) {
      await sp.remove(_kCurralSelecionado);
    } else {
      await sp.setString(_kCurralSelecionado, v);
    }
  }

  String _currentUserId() {
    final s = (SessionService.instance.userId ?? "").trim();
    if (s.isNotEmpty) return s;

    final w = (widget.idUsuario).trim();
    if (w.isNotEmpty) return w;

    return "";
  }

  Future<void> _ensureLoggedOrRedirect() async {
    final id = _currentUserId();
    if (id.isNotEmpty) return;

    _ctrl.setError("Exception: Usuário não definido. Faça login novamente.");

    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, "/login", (r) => false);
  }

  ScaleModel _mapModeloBalancaInt(int v) => scaleModelFromConfigInt(v);

  String _ymd(DateTime d) {
    final y = d.year.toString().padLeft(4, "0");
    final m = d.month.toString().padLeft(2, "0");
    final dd = d.day.toString().padLeft(2, "0");
    return "$y-$m-$dd";
  }

  /// Atualiza baias + previsão do dia antes de montar o mapa (evita SQLite desatualizado).
  Future<void> _refreshMapaRemoto({required DateTime data}) async {
    try {
      var idFazenda = widget.idFazenda.trim();
      if (idFazenda.isEmpty) {
        idFazenda = (await _cfgRepo.getIdFazendaSelecionada()).trim();
      }
      await widget.repo.prefetchMapaDoDia(
        idFazenda: idFazenda,
        data: data,
        trato: _ctrl.header?.trato ?? widget.trato,
      );
    } catch (e) {
      debugPrint("Fornecimento dashboard: falha ao atualizar mapa remoto: $e");
    }
  }

  /// Após fabricação → fornecimento o SQLite pode ainda estar sincronizando.
  Future<void> _ensureMapaCarregado(DateTime dataBoot) async {
    if (_ctrl.previsaoRacaoOk) return;

    await _refreshMapaRemoto(data: dataBoot);
    await _ctrl.carregarPrevisaoPorRacao();
    if (_ctrl.previsaoRacaoOk) return;

    await Future<void>.delayed(const Duration(milliseconds: 400));
    await _refreshMapaRemoto(data: dataBoot);
    await _ctrl.carregarPrevisaoPorRacao();
  }

  Future<bool> _pickTratoModal() async {
    final h = _ctrl.header;
    final racaoTxt = (h?.racaoNome ?? h?.racaoId ?? "").trim();
    final ordenadas = _ctrl.tratosDisponiveis.isNotEmpty
        ? _ctrl.tratosDisponiveis
        : <int>[1, 2, 3, 4, 5, 6];

    final picked = await showModalBottomSheet<int>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "Selecione o trato",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
                if (racaoTxt.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    "Ração: $racaoTxt",
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final t in ordenadas)
                      SizedBox(
                        width: 110,
                        height: 44,
                        child: FilledButton.tonal(
                          onPressed: () => Navigator.pop(ctx, t),
                          child: Text(
                            "Trato $t",
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted) return false;
    if (picked == null || picked <= 0) {
      Navigator.pop(context);
      return false;
    }

    await _ctrl.selecionarTrato(picked);
    return true;
  }

  Future<void> _connectDevicesFromConfig() async {
    try {
      final hostB = (await _cfgRepo.getHostBalanca()).trim();
      final portB = await _cfgRepo.getPortaBalanca();
      final modeloB = await _cfgRepo.getModeloBalanca();

      if (hostB.isEmpty || portB <= 0) {
        // deixa status aparecer via stream como "OFF"
      } else {
        widget.scale.configure(
          host: hostB,
          port: portB,
          model: _mapModeloBalancaInt(modeloB),
          allowNegative: true,
        );
        unawaited(widget.scale.connect());
      }

      final hostR = (await _cfgRepo.getHostRfid()).trim();
      final portR = await _cfgRepo.getPortaRfid();
      final canUseRfid = hostR.isNotEmpty;

      if (_showRfidControls != canUseRfid && mounted) {
        setState(() => _showRfidControls = canUseRfid);
      } else {
        _showRfidControls = canUseRfid;
      }

      if (hostR.isNotEmpty && portR > 0) {
        widget.rfid.configure(host: hostR, port: portR);
        if (_ctrl.rfidPausado) {
          try {
            await widget.rfid.disconnect();
          } catch (_) {}
          widget.rfid.setLeituraAtiva(false);
        } else {
          try {
            await widget.rfid.disconnect();
          } catch (_) {}
          widget.rfid.setLeituraAtiva(true);
          await widget.rfid.connect();
        }
      } else {
        _ctrl.setLeituraRfid(false);
      }
    } catch (e) {
      debugPrint("Fornecimento dashboard: falha ao configurar balança/RFID: $e");
    }
  }

  Future<void> _boot() async {
    _ctrl.beginBoot();
    await _loadUiPrefs();
    await _ensureLoggedOrRedirect();
    if (!mounted) return;

    var car = await widget.repo.getCarregamentoAberto(
      data: widget.data ?? DateTime.now(),
    );

    if (car == null) {
      final tipo = await _cfgRepo.getTipoTrabalho();
      if (tipo == 2) {
        final ok = await widget.repo.tryImportCarregamentoFromEstacionario(
          data: widget.data ?? DateTime.now(),
        );
        if (ok) {
          car = await widget.repo.getCarregamentoAberto(
            data: widget.data ?? DateTime.now(),
          );
        }
      }
    }

    if (car == null) {
      final tipo = await _cfgRepo.getTipoTrabalho();
      final msg = tipo == 2
          ? "Não há carregamento aberto hoje.\n"
              "Realize o carregamento da ração antes de fornecer."
          : "Não existe carregamento em aberto (STATUS=0).\n"
              "Finalize a fabricação e gere o carregamento antes de entrar no mapa.";
      _ctrl.setError(msg);
      return;
    }

    final idDietaCarregada = (car.idDieta ?? "").toString().trim();
    if (idDietaCarregada.isEmpty) {
      _ctrl.setError(
        "Carregamento em aberto sem ID_DIETA.\n"
        "Não é possível filtrar os currais sem a dieta carregada.",
      );
      return;
    }

    // Conecta balança/RFID sem bloquear a abertura do mapa.
    unawaited(_connectDevicesFromConfig());

    final dataBoot = widget.data ?? DateTime.now();

    var idFazenda = widget.idFazenda.trim();
    if (idFazenda.isEmpty) {
      idFazenda = (await _cfgRepo.getIdFazendaSelecionada()).trim();
    }

    await _ctrl.init(
      data: dataBoot,
      idFazenda: idFazenda,
      idRacaoFiltro: widget.idRacaoFiltro ?? idDietaCarregada,
    );

    if (!mounted) return;

    await _ensureMapaCarregado(dataBoot);

    if (!mounted) return;

    if (!_ctrl.previsaoRacaoOk) {
      _ctrl.setError(
        "Nenhuma previsão encontrada para a ração "
        "${widget.idRacaoFiltro ?? idDietaCarregada} no dia de hoje.\n"
        "Sincronize a previsão e tente novamente.",
      );
      return;
    }

    if (!_ctrl.tratoSelecionado) {
      final ok = await _pickTratoModal();
      if (!ok || !mounted) return;
    }

    if (widget.startCleared) {
      await _saveLinhaFiltroPref(null);
      _linhaFiltroSaved = null;
      _ctrl.setLinhaFiltro(null);
      await _saveCurralSelecionadoPref(null);
      _curralSelSaved = null;
      _ctrl.restaurarSelecaoPorIdFornecimento("");
    } else {
      if ((_linhaFiltroSaved ?? "").trim().isNotEmpty) {
        _ctrl.setLinhaFiltro(_linhaFiltroSaved);
      }
      if ((_curralSelSaved ?? "").trim().isNotEmpty) {
        await _ctrl.recuperarSelecaoAposBoot(_curralSelSaved!);
      }
    }
  }

  @override
  void dispose() {
    try {
      widget.scale.stopNow();
    } catch (_) {}
    try {
      widget.rfid.setLeituraAtiva(false);
      // ignore: unawaited_futures
      widget.rfid.disconnect();
    } catch (_) {}

    _beeper.dispose();
    _ctrl.removeListener(_onCtrlLoadingForMapaScroll);
    _mapaHScrollCtrl.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  String _fmtNum(num v, {int dec = 0}) {
    final s = v.toStringAsFixed(dec);
    return s.replaceAll(".", ",");
  }

  int _gridCols(double w) {
    if (w >= 1100) return 5;
    if (w >= 900) return 4;
    if (w >= 650) return 3;
    return 2;
  }

  double _progress(double realizado, double previsto) {
    if (previsto <= 0) return 0;
    return (realizado / previsto).clamp(0.0, 1.0);
  }

  Future<void> _onSalvarSeguro() async {
    _captureMapaHorizontalScroll();
    try {
      await _ensureLoggedOrRedirect();
      if (_currentUserId().isEmpty) return;

      await _ctrl.salvarFornecimento(idFazenda: widget.idFazenda);
      _scheduleMapaHorizontalScrollRestore();
    } catch (e) {
      _ctrl.setError("Erro ao salvar: $e");
    }
  }

  Future<void> _openMapaPopup() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (_, __) {
                final linhas = _ctrl.linhasDisponiveis;
                final width = MediaQuery.of(ctx).size.width;
                final cols = _gridCols(width);
                final list = _ctrl.curraisFiltrados;
                const cardHeight = 118.0;

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Text("Linha:",
                            style: TextStyle(fontWeight: FontWeight.w900)),
                        const SizedBox(width: 10),
                        DropdownButton<String?>(
                          value: _ctrl.linhaFiltro,
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text("Todas"),
                            ),
                            ...linhas.map(
                              (l) => DropdownMenuItem<String?>(
                                value: l,
                                child: Text(l),
                              ),
                            ),
                          ],
                          onChanged: (v) {
                            _ctrl.setLinhaFiltro(v);
                            // ignore: unawaited_futures
                            _saveLinhaFiltroPref(_ctrl.linhaFiltro);
                          },
                        ),
                        const Spacer(),
                        Text("${list.length} currais"),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: MediaQuery.of(ctx).size.height * 0.70,
                      child: GridView.builder(
                        itemCount: list.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: cols,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                          mainAxisExtent: cardHeight,
                        ),
                        itemBuilder: (_, i) {
                          final c = list[i];
                          final isSel = _ctrl.selected?.idFornecimento ==
                              c.idFornecimento;

                          return _CurralCardSmall(
                            c: c,
                            isSelected: isSel,
                            onTap: () {
                              // ignore: unawaited_futures
                              _ctrl.selecionarCurralPorClique(c);
                              // ignore: unawaited_futures
                              _saveCurralSelecionadoPref(c.idFornecimento);
                              Navigator.pop(ctx);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _reconnect() async {
    try {
      widget.scale.stopNow();
    } catch (_) {}
    if (!_ctrl.rfidPausado) {
      try {
        await widget.rfid.disconnect();
      } catch (_) {}
    }

    await _connectDevicesFromConfig();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final h = _ctrl.header;
        final sel = _ctrl.selected;

        final realizadoEst = _ctrl.realizadoEstimadoKg;
        final aFornecerEst = _ctrl.aFornecerEstimadoKg;
        final previstoPainel = _ctrl.previstoPainelKg;
        final isFieldpecUltimo = _ctrl.isFieldpecUltimoTratoSelecionado;

        final progress = sel == null
            ? 0.0
            : _progress(realizadoEst, previstoPainel);

        final level = _computeLevel(sel, realizadoEst, aFornecerEst);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _beeper.maybeBeep(level);
        });

        Widget mainBody() {
          if (_ctrl.error != null && !_ctrl.loading) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _ctrl.error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Colors.red,
                  ),
                ),
              ),
            );
          }

          if (_ctrl.loading && _ctrl.header == null) {
            return const Center(child: CircularProgressIndicator());
          }

          return Column(
            children: [
              _HeaderBar(
                trato: h?.trato,
                racaoId: h?.racaoId,
                racaoNome: h?.racaoNome,
                onTratoTap: () {
                  // ignore: unawaited_futures
                  _pickTratoModal();
                },
              ),
              SizedBox(height: (MediaQuery.of(context).size.width < 600) ? 4 : 8),
              Expanded(
                child: _ctrl.loading
                    ? const Center(child: CircularProgressIndicator())
                    : !_ctrl.tratoSelecionado
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.restaurant,
                                      size: 48, color: Colors.teal.shade700),
                                  const SizedBox(height: 12),
                                  const Text(
                                    "Previsão carregada para a ração.",
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    "Selecione o trato para exibir os currais.",
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 16),
                                  FilledButton.icon(
                                    onPressed: _pickTratoModal,
                                    icon: const Icon(Icons.touch_app),
                                    label: const Text("Escolher trato"),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : Padding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                            child: _RightPanel(
                              selected: sel,
                              pesoAtual: _ctrl.pesoAtual,
                              lastScaleRaw: _ctrl.lastScaleRaw,
                              scaleStatus: _ctrl.scaleStatus,
                              scaleMsg: _ctrl.scaleMsg,
                              rfidStatus: _ctrl.rfidStatus,
                              rfidMsg: _ctrl.rfidMsg,
                              rfidPausado: _ctrl.rfidPausado,
                              sessaoAtiva: _ctrl.sessaoAtiva,
                              fornecidoSessaoKg: _ctrl.fornecidoSessaoKg,
                              realizadoEstimadoKg: realizadoEst,
                              aFornecerEstimadoKg: aFornecerEst,
                              previstoPainelKg: previstoPainel,
                              isFieldpecUltimoTrato: isFieldpecUltimo,
                              ultimo: _ctrl.ultimo,
                              fmt: _fmtNum,
                              progress: progress,
                              level: level,
                            ),
                          ),
              ),
              if (_mapaHorizontalFixo) _mapaHorizontalBar(),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: _BottomActions(
                  onMapa: _openMapaPopup,
                  onToggleRfid: _ctrl.toggleRfidPausado,
                  onSalvar: _onSalvarSeguro,
                  rfidPausado: _ctrl.rfidPausado,
                  sessaoAtiva: _ctrl.sessaoAtiva,
                  showMapaButton: !_mapaHorizontalFixo,
                  showRfidButton: _showRfidControls,
                  disabled: _ctrl.loading ||
                      _ctrl.error != null ||
                      !_ctrl.tratoSelecionado,
                ),
              ),
            ],
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text("Dashboard de Fornecimento"),
            actions: [
              IconButton(
                onPressed: _reconnect,
                icon: const Icon(Icons.refresh),
                tooltip: "Reconectar",
              ),
              IconButton(
                onPressed: () async {
                  final next = !_mapaHorizontalFixo;
                  setState(() => _mapaHorizontalFixo = next);
                  await _saveMapaHorizontalPref(next);
                },
                icon: Icon(
                  _mapaHorizontalFixo ? Icons.view_carousel : Icons.grid_view,
                ),
                tooltip: _mapaHorizontalFixo
                    ? "Mapa horizontal ativo"
                    : "Mapa popup ativo",
              ),
              if (_showRfidControls)
                IconButton(
                  onPressed: _ctrl.toggleRfidPausado,
                  icon:
                      Icon(_ctrl.rfidPausado ? Icons.pause : Icons.play_arrow),
                  tooltip: _ctrl.rfidPausado ? "RFID pausado" : "RFID ativo",
                ),
            ],
          ),
          body: SafeArea(
            top: false,
            child: Stack(
              children: [
                mainBody(),

                // ✅ Notice bonito
                if ((_ctrl.uiNotice ?? "").trim().isNotEmpty)
                  Positioned(
                    top: 10,
                    left: 12,
                    right: 12,
                    child: _NoticeCard(
                      title: (_ctrl.uiNoticeTitle ?? "Aviso").trim(),
                      message: _ctrl.uiNotice!.trim(),
                      onClose: _ctrl.clearNotice,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _resumoDietaTratoBar() {
    final h = _ctrl.header;
    final t = _ctrl.totais;
    final dieta = (h?.racaoNome ?? "").trim().isEmpty
        ? "Dieta"
        : h!.racaoNome!.trim();
    final trato = h?.tratoSelecionado == true ? "Trato ${h!.trato}" : "Trato —";
    String n0(num v) => v.toStringAsFixed(0).replaceAll(".", ",");

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.blueGrey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              "$dieta · $trato",
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
            ),
          ),
          _resumoChip("Prev", n0(t.totalPrevistoKg)),
          const SizedBox(width: 6),
          _resumoChip("Real", n0(t.totalRealizadoKg)),
          const SizedBox(width: 6),
          _resumoChip("Falta", n0(t.faltaKg), emphasize: true),
        ],
      ),
    );
  }

  Widget _resumoChip(String label, String value, {bool emphasize = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: emphasize ? Colors.orange.shade100 : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black.withValues(alpha: 0.10)),
      ),
      child: Text(
        "$label $value",
        style: TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: 12,
          color: emphasize ? Colors.orange.shade900 : Colors.black87,
        ),
      ),
    );
  }

  Widget _mapaHorizontalBar() {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final list = _ctrl.curraisFiltrados;
        final linhas = _ctrl.linhasDisponiveis;

        return Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.black.withValues(alpha: 0.10)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  const Text(
                    "Mapa horizontal",
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      isExpanded: true,
                      initialValue: _ctrl.linhaFiltro,
                      decoration: const InputDecoration(
                        labelText: "Linha",
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text("Todas"),
                        ),
                        ...linhas.map(
                          (l) => DropdownMenuItem<String?>(
                            value: l,
                            child: Text(l),
                          ),
                        ),
                      ],
                      onChanged: (v) {
                        _ctrl.setLinhaFiltro(v);
                        // ignore: unawaited_futures
                        _saveLinhaFiltroPref(_ctrl.linhaFiltro);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text("${list.length}"),
                ],
              ),
              const SizedBox(height: 8),
              _resumoDietaTratoBar(),
              const SizedBox(height: 8),
              SizedBox(
                height: 125,
                child: list.isEmpty
                    ? const Center(
                        child: Text("Sem currais para o filtro selecionado."))
                    : ListView.separated(
                        controller: _mapaHScrollCtrl,
                        scrollDirection: Axis.horizontal,
                        itemCount: list.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (_, i) {
                          final c = list[i];
                          final isSel = _ctrl.selected?.idFornecimento ==
                              c.idFornecimento;
                          return SizedBox(
                            width: 250,
                            height: 118,
                            child: _CurralCardSmall(
                              c: c,
                              isSelected: isSel,
                              // Duplo clique: evita abrir curral ao arrastar o mapa.
                              onDoubleTap: () async {
                                await _ctrl.selecionarCurralPorClique(c);
                                // ignore: unawaited_futures
                                _saveCurralSelecionadoPref(c.idFornecimento);
                              },
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  _BeepLevel _computeLevel(
    CurralCardVM? s,
    double realizadoEstimadoKg,
    double aFornecerEstimadoKg,
  ) {
    if (s == null) return _BeepLevel.ok;

    final previsto = s.previstoFixoKg;
    if (previsto <= 0) return _BeepLevel.ok;

    final faltando = previsto - realizadoEstimadoKg;

    if (faltando <= 0) return _BeepLevel.reached;
    if (faltando <= _beeper.criticalKg) return _BeepLevel.critical;
    if (faltando <= _beeper.nearKg) return _BeepLevel.near;
    return _BeepLevel.ok;
  }
}

// ============================
// UI
// ============================

class _HeaderBar extends StatelessWidget {
  const _HeaderBar({
    required this.trato,
    required this.racaoId,
    required this.racaoNome,
    required this.onTratoTap,
  });

  final int? trato;
  final String? racaoId;
  final String? racaoNome;
  final VoidCallback onTratoTap;

  @override
  Widget build(BuildContext context) {
    final isPhone = MediaQuery.of(context).size.width < 600 ||
        MediaQuery.of(context).size.height < 700;
    final dietaTxt = (racaoNome ?? "").trim().isNotEmpty
        ? racaoNome!.trim()
        : ((racaoId ?? "-").trim().isEmpty ? "-" : racaoId!.trim());

    Widget cardBody({
      required String label,
      required String value,
      required IconData icon,
    }) {
      return Container(
        padding: EdgeInsets.symmetric(
          horizontal: isPhone ? 10 : 14,
          vertical: isPhone ? 8 : 12,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.black.withValues(alpha: 0.10)),
          color: Colors.white,
        ),
        child: Row(
          children: [
            Icon(icon, size: isPhone ? 22 : 28, color: Colors.teal.shade700),
            SizedBox(width: isPhone ? 6 : 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: isPhone ? 10 : 12,
                      fontWeight: FontWeight.w800,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: isPhone ? 15 : 22,
                      fontWeight: FontWeight.w900,
                      height: 1.1,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(
        isPhone ? 8 : 12, isPhone ? 8 : 12, isPhone ? 8 : 12, 0,
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: onTratoTap,
                  child: cardBody(
                    label: "Trato",
                    value: (trato ?? 0) > 0 ? trato.toString() : "Selecione",
                    icon: Icons.restaurant,
                  ),
                ),
              ),
            ),
            SizedBox(width: isPhone ? 6 : 10),
            Expanded(
              flex: 2,
              child: cardBody(
                label: "Dieta",
                value: dietaTxt,
                icon: Icons.grass,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomActions extends StatelessWidget {
  const _BottomActions({
    required this.onMapa,
    required this.onToggleRfid,
    required this.onSalvar,
    required this.rfidPausado,
    required this.sessaoAtiva,
    required this.showMapaButton,
    required this.showRfidButton,
    required this.disabled,
  });

  final VoidCallback onMapa;
  final VoidCallback onToggleRfid;
  final Future<void> Function() onSalvar;
  final bool rfidPausado;
  final bool sessaoAtiva;
  final bool showMapaButton;
  final bool showRfidButton;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: Row(
        children: [
          if (showMapaButton) ...[
            Expanded(
              child: ElevatedButton.icon(
                onPressed: disabled ? null : onMapa,
                icon: const Icon(Icons.grid_view),
                label: const Text("Mapa"),
              ),
            ),
            const SizedBox(width: 10),
          ],
          if (showRfidButton) ...[
            Expanded(
              child: ElevatedButton.icon(
                onPressed: disabled ? null : onToggleRfid,
                icon: Icon(rfidPausado ? Icons.play_arrow : Icons.pause),
                label: Text(rfidPausado ? "RFID pausado" : "Pausar RFID"),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: FilledButton.icon(
              onPressed: (disabled || !sessaoAtiva) ? null : onSalvar,
              icon: const Icon(Icons.save),
              label: const Text("Salvar"),
            ),
          ),
        ],
      ),
    );
  }
}

// ✅ card pequeno do mapa (popup)
// ✅ verde claro se realizado > 0
class _CurralCardSmall extends StatelessWidget {
  const _CurralCardSmall({
    required this.c,
    required this.isSelected,
    this.onTap,
    this.onDoubleTap,
  });

  final CurralCardVM c;
  final bool isSelected;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;

  @override
  Widget build(BuildContext context) {
    final hasRealizado = c.realizadoKg > 0;
    final semPrevisto = c.previstoKg <= 0;

    final bg = isSelected
        ? Colors.black
        : (hasRealizado
            ? Colors.green.shade100
            : (semPrevisto ? Colors.grey.shade200 : Colors.white));

    final fg = isSelected ? Colors.white : Colors.black;

    String n0(num v) => v.toStringAsFixed(0).replaceAll(".", ",");

    final nome = c.curralNome.trim().isEmpty ? "Curral" : c.curralNome.trim();
    final linhaTxt = (c.linha ?? "-").trim().isEmpty ? "-" : c.linha!.trim();

    return Material(
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isSelected
              ? Colors.black
              : Colors.black.withValues(alpha: 0.10),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onDoubleTap: onDoubleTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      nome,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: fg,
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                        height: 1.1,
                      ),
                    ),
                  ),
                  if (!isSelected && hasRealizado) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        color: Colors.green.shade700,
                      ),
                      child: const Text(
                        "OK",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(
                "Linha: $linhaTxt",
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: fg.withValues(alpha: 0.75),
                  fontSize: 11,
                  height: 1.1,
                ),
              ),
              const Spacer(),
              SizedBox(
                height: 28,
                child: Row(
                  children: [
                    Expanded(child: _mini(fg, "P", n0(c.previstoExibicaoKg))),
                    const SizedBox(width: 4),
                    Expanded(child: _mini(fg, "R", n0(c.realizadoKg))),
                    const SizedBox(width: 4),
                    Expanded(child: _mini(fg, "D", n0(c.diffKg))),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _mini(Color fg, String t, String v) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: fg.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Text(
            t,
            style: TextStyle(color: fg.withValues(alpha: 0.8), fontSize: 11),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              v,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: fg,
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RightPanel extends StatelessWidget {
  const _RightPanel({
    required this.selected,
    required this.pesoAtual,
    required this.lastScaleRaw,
    required this.scaleStatus,
    required this.scaleMsg,
    required this.rfidStatus,
    required this.rfidMsg,
    required this.rfidPausado,
    required this.sessaoAtiva,
    required this.fornecidoSessaoKg,
    required this.realizadoEstimadoKg,
    required this.aFornecerEstimadoKg,
    required this.previstoPainelKg,
    required this.isFieldpecUltimoTrato,
    required this.ultimo,
    required this.fmt,
    required this.progress,
    required this.level,
  });

  final CurralCardVM? selected;
  final double pesoAtual;
  final String lastScaleRaw;
  final ScaleStatus scaleStatus;
  final String? scaleMsg;
  final RfidStatus rfidStatus;
  final String? rfidMsg;
  final bool rfidPausado;
  final bool sessaoAtiva;
  final double fornecidoSessaoKg;

  final double realizadoEstimadoKg;
  final double aFornecerEstimadoKg;
  final double previstoPainelKg;
  final bool isFieldpecUltimoTrato;

  final UltimoFornecimentoVM? ultimo;

  final String Function(num, {int dec}) fmt;
  final double progress;

  final _BeepLevel level;

  Color _scoreBg() {
    if (selected == null) {
      return const Color(0xFF90A4AE);
    }
    switch (level) {
      case _BeepLevel.near:
        return Colors.amber.shade700;
      case _BeepLevel.critical:
        return Colors.deepOrange.shade700;
      case _BeepLevel.reached:
        return Colors.green.shade700;
      case _BeepLevel.ok:
        return Colors.black;
    }
  }

  String _levelTxt() {
    switch (level) {
      case _BeepLevel.near:
        return "PERTO";
      case _BeepLevel.critical:
        return "MUITO PERTO";
      case _BeepLevel.reached:
        return "ATINGIU";
      case _BeepLevel.ok:
        return "OK";
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = selected;
    final hasSel = s != null;
    final screenW = MediaQuery.of(context).size.width;
    final screenH = MediaQuery.of(context).size.height;
    final isPhone = screenW < 600 || screenH < 700;
    final cardH = isPhone
        ? (screenH * 0.26).clamp(140.0, 180.0)
        : (screenH * 0.28).clamp(180.0, 240.0);

    String linhaTxt(String? l) {
      final t = (l ?? "").trim();
      return t.isEmpty ? "-" : t;
    }

    final previsto = hasSel ? previstoPainelKg : 0.0;
    final realizado = hasSel
        ? (sessaoAtiva ? realizadoEstimadoKg : s.realizadoKg)
        : 0.0;
    final dif = hasSel ? (realizadoEstimadoKg - previsto) : 0.0;
    final difEst = hasSel ? (realizadoEstimadoKg - previsto) : 0.0;
    final curralNome = hasSel ? s.curralNome : "ESPERANDO CURRAL";
    final linha = hasSel ? linhaTxt(s.linha) : "-";
    final progressValue = hasSel ? progress : 0.0;
    String signed(num v) {
      final t = fmt(v, dec: 0);
      return v > 0 ? "+$t" : t;
    }

    String aFornecerSigned() {
      final v = aFornecerEstimadoKg;
      if (v > 0) return signed(v);
      if (v < 0) return fmt(-v, dec: 0);
      return fmt(0, dec: 0);
    }

    final scaleUi = scaleConnectionUi(scaleStatus, message: scaleMsg);
    final scaleDetail = () {
      var d = scaleUi.detail;
      final raw = lastScaleRaw.trim();
      if (raw.isNotEmpty) {
        final snippet = raw.length > 40 ? "${raw.substring(0, 40)}…" : raw;
        d = "$d · RX: $snippet";
      }
      return d;
    }();
    final rfidUi = rfidConnectionUi(
      rfidStatus,
      message: rfidMsg,
      pausado: rfidPausado,
    );

    final previstoSel = hasSel ? previsto : 0.0;

    return SingleChildScrollView(
      child: Column(
        children: [
          ScalePesoHighlightCard(
            pesoKg: pesoAtual,
            pesoLabel: "Peso balança",
            secondaryLabel: hasSel ? "Previsto (curral)" : null,
            secondaryKg: hasSel ? previstoSel : null,
            connectionSlots: [
              ScaleConnectionStatusChip(
                title: "Balança",
                detail: scaleDetail,
                icon: scaleUi.icon,
                color: scaleUi.color,
              ),
              ScaleConnectionStatusChip(
                title: "RFID",
                detail: rfidUi.detail,
                icon: rfidUi.icon,
                color: rfidUi.color,
              ),
            ],
          ),
          SizedBox(height: isPhone ? 4 : 10),
          Container(
            padding: EdgeInsets.all(isPhone ? 8 : 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(isPhone ? 14 : 18),
              border: Border.all(color: Colors.black.withValues(alpha: 0.10)),
              color: hasSel ? Colors.white : const Color(0xFFF3F5F8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  "Modo Pesagem",
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: isPhone ? 13 : 16,
                  ),
                ),
                SizedBox(height: isPhone ? 4 : 8),
                Text(
                  curralNome,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: isPhone ? 24 : 46,
                    height: 0.98,
                    letterSpacing: 0.2,
                  ),
                ),
                SizedBox(height: isPhone ? 4 : 6),
                Row(
                  children: [
                    Icon(Icons.alt_route,
                        size: 18, color: Colors.black.withValues(alpha: 0.65)),
                    const SizedBox(width: 6),
                    Text(
                      "Linha: $linha",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: Colors.black.withValues(alpha: 0.75),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        color: Colors.black.withValues(alpha: 0.06),
                      ),
                      child: Text(
                        _levelTxt(),
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (hasSel && !sessaoAtiva)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.orange.shade50,
                      border: Border.all(color: Colors.orange.shade300),
                    ),
                    child: const Text(
                      "Sessão não iniciada — leia a tag RFID ou toque no curral para começar a pesar.",
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ),
                if (hasSel && !sessaoAtiva) const SizedBox(height: 10),
                Row(
                  children: [
                    _infoBig(
                      "Previsto",
                      fmt(previsto, dec: 0),
                      icon: Icons.flag,
                      inactive: !hasSel,
                    ),
                    const SizedBox(width: 10),
                    _infoBig(
                      "Realizado",
                      fmt(realizado, dec: 0),
                      icon: Icons.check_circle_outline,
                      inactive: !hasSel,
                    ),
                    const SizedBox(width: 10),
                    _infoBig(
                      "Dif",
                      signed(dif),
                      icon: Icons.swap_vert,
                      inactive: !hasSel,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: cardH,
                  child: Container(
                    padding: EdgeInsets.all(isPhone ? 12 : 18),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(isPhone ? 18 : 26),
                      color: _scoreBg(),
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
                      children: [
                        Row(
                          children: [
                            Icon(Icons.scale,
                                color: Colors.white, size: isPhone ? 18 : 28),
                            SizedBox(width: isPhone ? 6 : 10),
                            Text(
                              "A FORNECER (kg)",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: isPhone ? 14 : 22,
                              ),
                            ),
                            const Spacer(),
                            if (!isPhone)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(999),
                                  color: Colors.white.withValues(alpha: 0.16),
                                ),
                                child: Text(
                                  "estimado",
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.95),
                                    fontWeight: FontWeight.w900,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        SizedBox(height: isPhone ? 6 : 14),

                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              aFornecerSigned(),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: isPhone ? 100 : 160,
                                fontWeight: FontWeight.w900,
                                height: 0.90,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ),
                        ),

                        SizedBox(height: isPhone ? 4 : 8),

                        Text(
                          isPhone
                              ? "Real: ${fmt(realizadoEstimadoKg, dec: 0)}  •  Dif: ${signed(difEst)}"
                              : "Real (est.): ${fmt(realizadoEstimadoKg, dec: 0)}  •  A fornecer: ${aFornecerSigned()}  •  Dif (est.): ${signed(difEst)}",
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.92),
                            fontWeight: FontWeight.w800,
                            fontSize: isPhone ? 11 : 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: SizedBox(
                    height: 10,
                    child: LinearProgressIndicator(value: progressValue),
                  ),
                ),
                const SizedBox(height: 14),
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (ultimo != null)
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
                color: Colors.green.shade100,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    "Último fornecimento",
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          "Curral: ${ultimo!.curralNome}",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        "Realizado: ${fmt(ultimo!.fornecidoKg, dec: 0)} kg",
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _infoBig(String t, String v, {IconData? icon, bool inactive = false}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.black.withValues(alpha: 0.10)),
          color: inactive ? const Color(0xFFEFF2F6) : Colors.white,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon,
                      size: 16, color: Colors.black.withValues(alpha: 0.65)),
                  const SizedBox(width: 6),
                ],
                Text(t,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w900)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              v,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================
// ✅ Notice Card
// ============================

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({
    required this.title,
    required this.message,
    required this.onClose,
  });

  final String title;
  final String message;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Colors.black,
          boxShadow: [
            BoxShadow(
              blurRadius: 18,
              offset: const Offset(0, 8),
              color: Colors.black.withValues(alpha: 0.25),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.14),
                ),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      message,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onClose,
                icon: const Icon(Icons.close, color: Colors.white),
                tooltip: "Fechar",
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================
// Beep / Alert helper (sem pacote)
// ============================

enum _BeepLevel { ok, near, critical, reached }

class _BeepAlerter {
  _BeepAlerter({
    required this.nearKg,
    required this.criticalKg,
    required this.cooldown,
  });

  final int nearKg;
  final int criticalKg;
  final Duration cooldown;

  _BeepLevel _lastLevel = _BeepLevel.ok;
  DateTime _lastBeepAt = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _t;

  bool _canBeepNow() {
    final now = DateTime.now();
    return now.difference(_lastBeepAt) >= cooldown;
  }

  void maybeBeep(_BeepLevel level) {
    if (level == _lastLevel) return;

    if (level == _BeepLevel.ok) {
      _lastLevel = level;
      return;
    }

    if (!_canBeepNow()) {
      _lastLevel = level;
      _t?.cancel();
      _t = Timer(cooldown, () {
        _play(level);
      });
      return;
    }

    _lastLevel = level;
    _play(level);
  }

  void _play(_BeepLevel level) {
    _lastBeepAt = DateTime.now();

    if (level == _BeepLevel.reached) {
      SystemSound.play(SystemSoundType.alert);
      HapticFeedback.mediumImpact();
      return;
    }

    if (level == _BeepLevel.critical) {
      SystemSound.play(SystemSoundType.alert);
      HapticFeedback.heavyImpact();
      return;
    }

    SystemSound.play(SystemSoundType.click);
    HapticFeedback.lightImpact();
  }

  void dispose() {
    _t?.cancel();
    _t = null;
  }
}
