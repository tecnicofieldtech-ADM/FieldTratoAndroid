// lib/features/fornecimento/ui/fornecimento_dashboard_page.dart
import "dart:async";
import "dart:math";
import "package:flutter/material.dart";
import "package:flutter/services.dart";

import "package:rfeed_flutter/helpers/scale_comm.dart";
import "package:rfeed_flutter/helpers/rfid_comm.dart";

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
  });

  final String idFazenda;
  final String idUsuario;
  final int trato;

  final DateTime? data;
  final String? idRacaoFiltro;

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

  // ✅ beep/alerta
  late final _BeepAlerter _beeper;

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

      if (hostR.isNotEmpty && portR > 0) {
        widget.rfid.configure(host: hostR, port: portR);
        _ctrl.setLeituraRfid(true);
        // ignore: unawaited_futures
        widget.rfid.connect();
      } else {
        _ctrl.setLeituraRfid(false);
      }
    } catch (e) {
      _ctrl.setError("Erro ao configurar conexões (balança/RFID): $e");
    }
  }

  Future<void> _boot() async {
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

    // ✅ conecta por config
    // ignore: unawaited_futures
    _connectDevicesFromConfig();

    await _ctrl.init(
      data: widget.data ?? DateTime.now(),
      trato: widget.trato,
      idFazenda: widget.idFazenda,
      idRacaoFiltro: idDietaCarregada,
    );
  }

  @override
  void dispose() {
    try {
      widget.scale.stopNow();
    } catch (_) {}
    try {
      // ignore: unawaited_futures
      widget.rfid.disconnect();
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

  Future<void> _onIniciarSeguro() async {
    try {
      await _ensureLoggedOrRedirect();
      if (_currentUserId().isEmpty) return;
      await _ctrl.iniciarCarregamento();
    } catch (e) {
      _ctrl.setError("Erro ao iniciar: $e");
    }
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
                final cols = _gridCols(MediaQuery.of(ctx).size.width);
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
                          onChanged: (v) => _ctrl.setLinhaFiltro(v),
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
                          childAspectRatio: 2.05,
                        ),
                        itemBuilder: (_, i) {
                          final c = list[i];
                          final isSel = _ctrl.selected?.idFornecimento ==
                              c.idFornecimento;

                          return _CurralCardSmall(
                            c: c,
                            isSelected: isSel,
                            onTap: () {
                              _ctrl.selecionarCurralPorClique(c);
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
              _TotaisBar(
                previsto: _ctrl.totais.totalPrevistoKg,
                realizado: _ctrl.totais.totalRealizadoKg,
                dif: _ctrl.totais.diffKg,
                fmt: _fmtNum,
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
                    onIniciar: _onIniciarSeguro,
                    onSalvar: _onSalvarSeguro,
                    ultimo: _ctrl.ultimo,
                    fmt: _fmtNum,
                    progress: progress,
                    level: level,
                  ),
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
                onPressed: _ctrl.toggleRfidPausado,
                icon: Icon(_ctrl.rfidPausado ? Icons.pause : Icons.play_arrow),
                tooltip: _ctrl.rfidPausado ? "RFID pausado" : "RFID ativo",
              ),
            ],
          ),
          body: Stack(
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

          // ✅ BOTÃO MAPA EMBAIXO (bottom)
          // ✅ BOTÃO MAPA EMBAIXO (bottom)
          // ✅ BOTOES EMBAIXO: MAPA + PAUSE (mesmo tamanho)
          floatingActionButton: SizedBox(
            width: MediaQuery.of(context).size.width * 0.92,
            height: 54,
            child: Row(
              children: [
                Expanded(
                  child: FloatingActionButton.extended(
                    heroTag: "fab_mapa",
                    onPressed: _ctrl.loading || _ctrl.error != null
                        ? null
                        : _openMapaPopup,
                    icon: const Icon(Icons.grid_view),
                    label: const Text("Mapa"),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FloatingActionButton.extended(
                    heroTag: "fab_pause",
                    onPressed: _ctrl.loading || _ctrl.error != null
                        ? null
                        : _ctrl.toggleRfidPausado,
                    icon: Icon(
                        _ctrl.rfidPausado ? Icons.play_arrow : Icons.pause),
                    label: Text(
                        _ctrl.rfidPausado ? "RFID pausado" : "Pausar RFID"),
                  ),
                ),
              ],
            ),
          ),
          floatingActionButtonLocation:
              FloatingActionButtonLocation.centerFloat,
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
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              chip("Trato", trato.toString(), icon: Icons.restaurant),
              chip("Dieta", dietaTxt, icon: Icons.grass),
              chip("Peso", pesoTxt, icon: Icons.monitor_weight),
              chip("Balança", _statusTxt(scaleStatus), dot: scaleDot),
              chip("RFID", rfidTxt, dot: rfidDot),
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

class _TotaisBar extends StatelessWidget {
  const _TotaisBar({
    required this.previsto,
    required this.realizado,
    required this.dif,
    required this.fmt,
  });

  final double previsto;
  final double realizado;
  final double dif;
  final String Function(num, {int dec}) fmt;

  @override
  Widget build(BuildContext context) {
    Widget box(String title, String value) {
      return Expanded(
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.black.withValues(alpha: 0.10)),
            color: Colors.white,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text(
                value,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
      child: Row(
        children: [
          box("Total Previsto (kg)", fmt(previsto, dec: 0)),
          const SizedBox(width: 10),
          box("Total Realizado (kg)", fmt(realizado, dec: 0)),
          const SizedBox(width: 10),
          box("Diferença (kg)", fmt(dif, dec: 0)),
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
    required this.onIniciar,
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

  final Future<void> Function() onIniciar;
  final Future<void> Function() onSalvar;

  final UltimoFornecimentoVM? ultimo;

  final String Function(num, {int dec}) fmt;
  final double progress;

  final _BeepLevel level;

  Color _scoreBg() {
    switch (level) {
      case _BeepLevel.near:
        return Colors.amber.shade700;
      case _BeepLevel.critical:
        return Colors.deepOrange.shade700;
      case _BeepLevel.reached:
        return Colors.green.shade700;
      case _BeepLevel.ok:
      default:
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
      default:
        return "OK";
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = selected;

    String linhaTxt(String? l) {
      final t = (l ?? "").trim();
      return t.isEmpty ? "-" : t;
    }

    final previsto = s?.previstoKg ?? 0.0;
    final faltandoEst = (s == null) ? 0.0 : (previsto - realizadoEstimadoKg);

    return SingleChildScrollView(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.black.withValues(alpha: 0.10)),
              color: Colors.white,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  s == null
                      ? "Selecione um curral (Mapa)"
                      : "Curral selecionado",
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 10),
                if (s != null) ...[
                  Text(
                    s.curralNome,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 52,
                      height: 0.98,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.alt_route,
                          size: 18,
                          color: Colors.black.withValues(alpha: 0.65)),
                      const SizedBox(width: 6),
                      Text(
                        "Linha: ${linhaTxt(s.linha)}",
                        style: TextStyle(
                          fontSize: 18,
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
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: SizedBox(
                      height: 12,
                      child: LinearProgressIndicator(value: progress),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      _infoBig("Previsto", fmt(s.previstoKg, dec: 0),
                          icon: Icons.flag),
                      const SizedBox(width: 10),
                      _infoBig("Realizado", fmt(s.realizadoKg, dec: 0),
                          icon: Icons.check_circle_outline),
                      const SizedBox(width: 10),
                      _infoBig("Dif", fmt(s.diffKg, dec: 0),
                          icon: Icons.swap_vert),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    constraints: const BoxConstraints(
                      minHeight: 280, // ✅ dobra a altura visual do card
                    ),
                    padding: const EdgeInsets.fromLTRB(
                        24, 28, 24, 28), // mais respiro
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
                                fontSize: 26, // 🔼 título maior
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(999),
                                color: Colors.white.withValues(alpha: 0.16),
                              ),
                              child: Text(
                                "estimado",
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.95),
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 26),

                        // 🔥 NÚMERO GIGANTE
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            fmt(max(0.0, aFornecerEstimadoKg), dec: 0),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 200, // ✅ DOBRADO
                              fontWeight: FontWeight.w900,
                              height: 0.90,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        Text(
                          "Real (est.): ${fmt(realizadoEstimadoKg, dec: 0)}  •  Falta (est.): ${fmt(faltandoEst, dec: 0)}",
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.92),
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: s == null ? null : onIniciar,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text("Iniciar"),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed:
                            (!sessaoAtiva || s == null) ? null : onSalvar,
                        icon: const Icon(Icons.save),
                        label: const Text("Salvar"),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (ultimo != null)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.black.withValues(alpha: 0.10)),
                color: Colors.white,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text("Último fornecimento",
                      style: TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  Text("Curral: ${ultimo!.curralNome}"),
                  Text("Fornecido: ${fmt(ultimo!.fornecidoKg, dec: 0)} kg"),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _infoBig(String t, String v, {IconData? icon}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.black.withValues(alpha: 0.10)),
          color: Colors.white,
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
