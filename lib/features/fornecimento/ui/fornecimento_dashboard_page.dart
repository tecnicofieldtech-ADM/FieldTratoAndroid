// lib/features/fornecimento/ui/fornecimento_dashboard_page.dart
import "dart:async";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:shared_preferences/shared_preferences.dart";

import "../../../helpers/scale_comm.dart";
import "../../../helpers/rfid_comm.dart";

import "../controller/fornecimento_dashboard_controller.dart";
import "../data/fornecimento_repo.dart";
import "../../../services/session_service.dart";
import "../../../repo/config_repo.dart";

class FornecimentoDashboardPage extends StatefulWidget {
  const FornecimentoDashboardPage({
    super.key,
    required this.idFazenda,
    required this.idUsuario,
    required this.trato,
    required this.repo,
    required this.scale,
    required this.rfid,
    this.data,
    this.idRacaoFiltro,
    this.startCleared = false,
  });

  final String idFazenda;
  final String idUsuario;
  final int trato;

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
  static const _kMapaHorizontal = "forn_dash_mapa_horizontal";
  static const _kLinhaFiltro = "forn_dash_linha_filtro";
  static const _kCurralSelecionado = "forn_dash_curral_sel";

  // ✅ beep/alerta
  late final _BeepAlerter _beeper;
  bool _showRfidControls = false;
  bool _mapaHorizontalFixo = false;
  String? _linhaFiltroSaved;
  String? _curralSelSaved;

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

    _boot();
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

  // ✅ MODELO_BALANCA INT -> ScaleModel
  // 0=topcom, 1=dg500, 2=alfa, 3=raw
  ScaleModel _mapModeloBalancaInt(int v) {
    switch (v) {
      case 0:
        return ScaleModel.topcom;
      case 1:
        return ScaleModel.dg500;
      case 2:
        return ScaleModel.alfa;
      case 3:
        return ScaleModel.raw;
      default:
        return ScaleModel.topcom;
    }
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
        // ignore: unawaited_futures
        widget.scale.connect();
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
        // Garante estado limpo antes de reconectar (evita corrida connect/disconnect).
        try {
          await widget.rfid.disconnect();
        } catch (_) {}

        widget.rfid.configure(host: hostR, port: portR);
        await widget.rfid.connect();
        _ctrl.setLeituraRfid(true);
      } else {
        _ctrl.setLeituraRfid(false);
      }
    } catch (e) {
      _ctrl.setError("Erro ao configurar conexões (balança/RFID): $e");
    }
  }

  Future<void> _boot() async {
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
      _ctrl.setError(
        "Não existe carregamento em aberto (STATUS=0).\n"
        "Finalize a fabricação e gere o carregamento antes de entrar no mapa.",
      );
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

    // ✅ conecta por config (await para evitar corrida de lifecycle)
    await _connectDevicesFromConfig();

    await _ctrl.init(
      data: widget.data ?? DateTime.now(),
      trato: widget.trato,
      idFazenda: widget.idFazenda,
      idRacaoFiltro: idDietaCarregada,
    );

    if ((_linhaFiltroSaved ?? "").trim().isNotEmpty) {
      _ctrl.setLinhaFiltro(_linhaFiltroSaved);
    }
    if (widget.startCleared) {
      // sempre inicia zerado no fluxo "Novo Fornecimento"
      await _saveCurralSelecionadoPref(null);
      _curralSelSaved = null;
      _ctrl.restaurarSelecaoPorIdFornecimento("");
    } else if ((_curralSelSaved ?? "").trim().isNotEmpty) {
      _ctrl.restaurarSelecaoPorIdFornecimento(_curralSelSaved!);
    }
  }

  @override
  void dispose() {
    try {
      widget.scale.stopNow();
    } catch (_) {}
    try {
      widget.rfid.setLeituraAtiva(false);
    } catch (_) {}

    _beeper.dispose();
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
    try {
      await _ensureLoggedOrRedirect();
      if (_currentUserId().isEmpty) return;

      await _ctrl.salvarFornecimento(idFazenda: widget.idFazenda);
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
                final isNarrow = width < 390;
                final cardRatio = cols <= 2
                    ? (isNarrow ? 1.68 : 1.85)
                    : (cols == 3 ? 1.95 : 2.05);
                final list = _ctrl.curraisFiltrados;

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
                          childAspectRatio: cardRatio,
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
    try {
      // ignore: unawaited_futures
      widget.rfid.disconnect();
    } catch (_) {}

    // ignore: unawaited_futures
    _connectDevicesFromConfig();
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

        final progress =
            sel == null ? 0.0 : _progress(realizadoEst, sel.previstoKg);

        final level = _computeLevel(sel, realizadoEst);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _beeper.maybeBeep(level);
        });

        Widget mainBody() {
          if (_ctrl.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (_ctrl.error != null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _ctrl.error!,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Colors.red,
                  ),
                ),
              ),
            );
          }

          return Column(
            children: [
              _HeaderBar(
                trato: h?.trato ?? widget.trato,
                racaoId: h?.racaoId,
                racaoNome: h?.racaoNome,
                pesoAtual: _ctrl.pesoAtual,
                scaleStatus: _ctrl.scaleStatus,
                rfidStatus: _ctrl.rfidStatus,
                scaleMsg: _ctrl.scaleMsg,
                rfidMsg: _ctrl.rfidMsg,
                rfidPausado: _ctrl.rfidPausado,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: _RightPanel(
                    selected: sel,
                    sessaoAtiva: _ctrl.sessaoAtiva,
                    fornecidoSessaoKg: _ctrl.fornecidoSessaoKg,
                    realizadoEstimadoKg: realizadoEst,
                    aFornecerEstimadoKg: aFornecerEst,
                    onSalvar: _onSalvarSeguro,
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
                  rfidPausado: _ctrl.rfidPausado,
                  showMapaButton: !_mapaHorizontalFixo,
                  showRfidButton: _showRfidControls,
                  disabled: _ctrl.loading || _ctrl.error != null,
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
                      title: "Curral sem previsto",
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
              SizedBox(
                height: 125,
                child: list.isEmpty
                    ? const Center(
                        child: Text("Sem currais para o filtro selecionado."))
                    : ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: list.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (_, i) {
                          final c = list[i];
                          final isSel = _ctrl.selected?.idFornecimento ==
                              c.idFornecimento;
                          return SizedBox(
                            width: 250,
                            child: _CurralCardSmall(
                              c: c,
                              isSelected: isSel,
                              onTap: () async {
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

  _BeepLevel _computeLevel(CurralCardVM? s, double realizadoEstimadoKg) {
    if (s == null) return _BeepLevel.ok;
    final previsto = s.previstoKg;
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
    required this.pesoAtual,
    required this.scaleStatus,
    required this.rfidStatus,
    required this.scaleMsg,
    required this.rfidMsg,
    required this.rfidPausado,
  });

  final int trato;
  final String? racaoId;
  final String? racaoNome;
  final double pesoAtual;

  final ScaleStatus scaleStatus;
  final RfidStatus rfidStatus;

  final String? scaleMsg;
  final String? rfidMsg;
  final bool rfidPausado;

  Color _dot(Color ok, Color warn, Color bad, dynamic status) {
    final s = status.toString().toLowerCase();
    if (s.contains("connected")) return ok;
    if (s.contains("connecting")) return warn;
    if (s.contains("error")) return bad;
    return Colors.grey;
  }

  String _statusTxt(dynamic st) {
    final s = st.toString().split(".").last;
    if (s == "connected") return "ON";
    if (s == "connecting") return "Conectando";
    if (s == "error") return "ERRO";
    return "OFF";
  }

  @override
  Widget build(BuildContext context) {
    Widget chip(String title, String value, {IconData? icon, Color? dot}) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black.withValues(alpha: 0.10)),
          color: Colors.white,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dot != null) ...[
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
            ],
            if (icon != null) ...[
              Icon(icon, size: 18),
              const SizedBox(width: 6),
            ],
            Text("$title: ",
                style: const TextStyle(fontWeight: FontWeight.w900)),
            Flexible(
              child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      );
    }

    final dietaTxt = (racaoNome ?? "").trim().isNotEmpty
        ? racaoNome!.trim()
        : ((racaoId ?? "-").trim().isEmpty ? "-" : racaoId!.trim());

    final pesoTxt = pesoAtual.toStringAsFixed(0);

    final scaleDot = _dot(Colors.green, Colors.orange, Colors.red, scaleStatus);
    final rfidDot = _dot(Colors.green, Colors.orange, Colors.red, rfidStatus);

    final rfidTxt = rfidPausado
        ? "${_statusTxt(rfidStatus)} (pausado)"
        : _statusTxt(rfidStatus);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    chip("Trato", trato.toString(), icon: Icons.restaurant),
                    chip("Dieta", dietaTxt, icon: Icons.grass),
                    chip("Peso", pesoTxt, icon: Icons.monitor_weight),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  chip("Balança", _statusTxt(scaleStatus), dot: scaleDot),
                  const SizedBox(height: 8),
                  chip("RFID", rfidTxt, dot: rfidDot),
                ],
              ),
            ],
          ),
          if ((scaleMsg ?? "").trim().isNotEmpty ||
              (rfidMsg ?? "").trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            if ((scaleMsg ?? "").trim().isNotEmpty)
              Text("Balança: ${scaleMsg!.trim()}",
                  style: const TextStyle(color: Colors.red)),
            if ((rfidMsg ?? "").trim().isNotEmpty)
              Text("RFID: ${rfidMsg!.trim()}",
                  style: const TextStyle(color: Colors.red)),
          ],
        ],
      ),
    );
  }
}

class _BottomActions extends StatelessWidget {
  const _BottomActions({
    required this.onMapa,
    required this.onToggleRfid,
    required this.rfidPausado,
    required this.showMapaButton,
    required this.showRfidButton,
    required this.disabled,
  });

  final VoidCallback onMapa;
  final VoidCallback onToggleRfid;
  final bool rfidPausado;
  final bool showMapaButton;
  final bool showRfidButton;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: Row(
        children: [
          if (showMapaButton)
            Expanded(
              child: ElevatedButton.icon(
                onPressed: disabled ? null : onMapa,
                icon: const Icon(Icons.grid_view),
                label: const Text("Mapa"),
              ),
            ),
          if (showMapaButton && showRfidButton) const SizedBox(width: 10),
          if (showRfidButton)
            Expanded(
              child: ElevatedButton.icon(
                onPressed: disabled ? null : onToggleRfid,
                icon: Icon(rfidPausado ? Icons.play_arrow : Icons.pause),
                label: Text(rfidPausado ? "RFID pausado" : "Pausar RFID"),
              ),
            ),
          if (!showMapaButton && !showRfidButton)
            const Expanded(child: SizedBox.shrink()),
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
    required this.onTap,
  });

  final CurralCardVM c;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasRealizado = c.realizadoKg > 0;

    final bg = isSelected
        ? Colors.black
        : (hasRealizado ? Colors.green.shade100 : Colors.white);

    final fg = isSelected ? Colors.white : Colors.black;

    String n0(num v) => v.toStringAsFixed(0).replaceAll(".", ",");

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: bg,
          border: Border.all(
            color: isSelected
                ? Colors.black
                : Colors.black.withValues(alpha: 0.10),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    c.curralNome,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: fg,
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                    ),
                  ),
                ),
                if (!isSelected && hasRealizado) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: Colors.green.shade700,
                    ),
                    child: const Text(
                      "OK",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 2),
            Text(
              "Linha: ${(c.linha ?? "-").trim().isEmpty ? "-" : c.linha!.trim()}",
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: fg.withValues(alpha: 0.75), fontSize: 12),
            ),
            const Spacer(),
            Row(
              children: [
                Expanded(child: _mini(fg, "P", n0(c.previstoKg))),
                const SizedBox(width: 6),
                Expanded(child: _mini(fg, "R", n0(c.realizadoKg))),
                const SizedBox(width: 6),
                Expanded(child: _mini(fg, "D", n0(c.diffKg))),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _mini(Color fg, String t, String v) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
    required this.sessaoAtiva,
    required this.fornecidoSessaoKg,
    required this.realizadoEstimadoKg,
    required this.aFornecerEstimadoKg,
    required this.onSalvar,
    required this.ultimo,
    required this.fmt,
    required this.progress,
    required this.level,
  });

  final CurralCardVM? selected;
  final bool sessaoAtiva;
  final double fornecidoSessaoKg;

  final double realizadoEstimadoKg;
  final double aFornecerEstimadoKg;

  final Future<void> Function() onSalvar;

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
    final screenH = MediaQuery.of(context).size.height;
    final cardH = (screenH * 0.28).clamp(180.0, 240.0);

    String linhaTxt(String? l) {
      final t = (l ?? "").trim();
      return t.isEmpty ? "-" : t;
    }

    final previsto = hasSel ? s.previstoKg : 0.0;
    final realizado = hasSel ? s.realizadoKg : 0.0;
    final dif = hasSel ? s.diffKg : 0.0;
    final difEst = hasSel ? (realizadoEstimadoKg - previsto) : 0.0;
    final curralNome = hasSel ? s.curralNome : "ESPERANDO CURRAL";
    final linha = hasSel ? linhaTxt(s.linha) : "-";
    final progressValue = hasSel ? progress : 0.0;
    String signed(num v) {
      final t = fmt(v, dec: 0);
      return v > 0 ? "+$t" : t;
    }

    String aFornecerSigned() {
      final t = fmt(aFornecerEstimadoKg, dec: 0);
      return difEst > 0 ? "+$t" : t;
    }

    return SingleChildScrollView(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.black.withValues(alpha: 0.10)),
              color: hasSel ? Colors.white : const Color(0xFFF3F5F8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  "Modo Pesagem",
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  curralNome,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 46,
                    height: 0.98,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 6),
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
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: SizedBox(
                    height: 10,
                    child: LinearProgressIndicator(value: progressValue),
                  ),
                ),
                const SizedBox(height: 10),
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
                    padding:
                        const EdgeInsets.fromLTRB(18, 18, 18, 18), // compacto
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(26),
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
                            const Icon(Icons.scale,
                                color: Colors.white, size: 28),
                            const SizedBox(width: 10),
                            const Text(
                              "A FORNECER (kg)",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 22,
                              ),
                            ),
                            const Spacer(),
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
                        const SizedBox(height: 14),

                        // 🔥 NÚMERO GIGANTE
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              aFornecerSigned(),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 160,
                                fontWeight: FontWeight.w900,
                                height: 0.90,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 8),

                        Text(
                          "Real (est.): ${fmt(realizadoEstimadoKg, dec: 0)}  •  A fornecer: ${aFornecerSigned()}  •  Dif (est.): ${signed(difEst)}",
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.92),
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                if (hasSel)
                  FilledButton.icon(
                    onPressed: !sessaoAtiva ? null : onSalvar,
                    icon: const Icon(Icons.save),
                    label: const Text("Salvar"),
                  ),
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
