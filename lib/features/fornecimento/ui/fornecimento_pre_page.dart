import "dart:async";
import "dart:math" as math;

import "package:flutter/material.dart";

import "package:rfeed_flutter/helpers/scale_comm.dart";
import "package:rfeed_flutter/helpers/rfid_comm.dart";

import "../data/fornecimento_repo.dart";
import "../domain/fornecimento_models.dart";
import "fornecimento_weigh_page.dart";



class FornecimentoPrePage extends StatefulWidget {
  const FornecimentoPrePage({
    super.key,
    required this.curral,
    required this.idFazenda,
    required this.idUsuario,
    required this.repo,
    required this.scale,
    required this.rfid,
  });

  final CurralPrev curral;
  final String idFazenda;
  final String idUsuario;
  final FornecimentoRepo repo;
  final ScaleComm scale;
  final RfidComm rfid;

  @override
  State<FornecimentoPrePage> createState() => _FornecimentoPrePageState();
}

class _FornecimentoPrePageState extends State<FornecimentoPrePage> {
  late final _FornecimentoPreController ctrl;

  @override
  void initState() {
    super.initState();
    ctrl = _FornecimentoPreController(
      repo: widget.repo,
      scale: widget.scale,
      rfid: widget.rfid,
      idFazenda: widget.idFazenda,
      idUsuario: widget.idUsuario,
      initial: widget.curral,
    );
    scheduleMicrotask(ctrl.init);
  }

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {},
      child: AnimatedBuilder(
        animation: ctrl,
        builder: (context, _) {
          final c = ctrl.curral;
          return Scaffold(
            appBar: AppBar(
              title: const Text("Fornecimento"),
              actions: [
                IconButton(
                  tooltip: "Recarregar",
                  onPressed: ctrl.busy ? null : ctrl.reloadCurralFromDb,
                  icon: const Icon(Icons.refresh),
                ),
                const SizedBox(width: 4),
              ],
            ),
            body: SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  _ConnCard(ctrl: ctrl),
                  const SizedBox(height: 12),
                  _CurralInfoCard(ctrl: ctrl, curral: c),
                  const SizedBox(height: 12),
                  _PesoCard(ctrl: ctrl),
                  const SizedBox(height: 12),
                  _AcoesCard(
                    ctrl: ctrl,
                    onGoWeighPage: () async {
                      final res = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => FornecimentoWeighPage(
                            curral: c,
                            idFazenda: widget.idFazenda,
                            idUsuario: widget.idUsuario,
                            repo: widget.repo,
                            scale: widget.scale,
                            rfid: widget.rfid,
                          ),
                        ),
                      );

                      if (!mounted) return;
                      await ctrl.reloadCurralFromDb();

                      // ignore: unused_local_variable
                      final _ = res;
                    },
                  ),
                  const SizedBox(height: 14),
                  if (ctrl.info != null) _BannerInfo(text: ctrl.info!),
                  if (ctrl.error != null) _BannerError(text: ctrl.error!),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FornecimentoPreController extends ChangeNotifier {
  _FornecimentoPreController({
    required this.repo,
    required this.scale,
    required this.rfid,
    required this.idFazenda,
    required this.idUsuario,
    required CurralPrev initial,
  }) : curral = initial;

  final FornecimentoRepo repo;
  final ScaleComm scale;
  final RfidComm rfid;


  final String idFazenda;
  final String idUsuario;

  CurralPrev curral;

  StreamSubscription? _subPeso;
  StreamSubscription? _subScaleStatus;
  StreamSubscription? _subRfidStatus;
  StreamSubscription? _subEpc;

  bool busy = false;

  String scaleStatus = "";
  String rfidStatus = "";

  String lastEpc = "";

  num pesoAtual = 0;
  num? pesoInicial;

  bool invertDelta = false; // padrão: descarregando => ini - atual
  double toleranciaPct = 2; // 2%
  bool concluirAutomatico = true;

  String? info;
  String? error;

  DateTime _lastEpcAt = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> init() async {
    _clearMsgs();
    _attachStreamsOnce();
    _setRfidLeituraAtiva(true);
    await reloadCurralFromDb(silent: true);
    notifyListeners();
  }

  @override
  void dispose() {
    _setRfidLeituraAtiva(false);
    _detachStreams();
    super.dispose();
  }

  // setters (evita notifyListeners fora do controller)
  void setInvertDelta(bool v) {
    invertDelta = v;
    notifyListeners();
  }

  void setToleranciaPct(double v) {
    toleranciaPct = v;
    notifyListeners();
  }

  void setConcluirAutomatico(bool v) {
    concluirAutomatico = v;
    notifyListeners();
  }

  void _clearMsgs() {
    info = null;
    error = null;
  }

  void _setInfo(String msg) {
    info = msg;
    error = null;
    notifyListeners();
  }

  void _setError(String msg) {
    error = msg;
    info = null;
    notifyListeners();
  }

  // ---------------------------
  // ID FORNECIMENTO (garante String não-nula)
  // ---------------------------
  String get _idFornec {
    final dynamic d = curral as dynamic;
    final Object? raw = _try(() => d.idFornecimento);
    final String id = (raw?.toString().trim() ?? "");
    if (id.isEmpty) {
      throw Exception(
          "CurralPrev.idFornecimento está vazio/null (preciso disso para salvar/atualizar).");
    }
    return id;
  }

  // ---------------------------
  // STREAM ADAPTER (dynamic)
  // ---------------------------
  Stream<num> _scaleWeightStream() {
    final d = scale as dynamic;
    final candidates = <Object?>[
      _try(() => d.peso$),
      _try(() => d.weight$),
      _try(() => d.pesoStream),
      _try(() => d.weightStream),
      _try(() => d.streamPeso),
      _try(() => d.streamWeight),
    ];
    for (final c in candidates) {
      if (c is Stream) return c.cast<num>();
    }
    return const Stream<num>.empty();
  }

  Stream<String> _scaleStatusStream() {
    final d = scale as dynamic;
    final candidates = <Object?>[
      _try(() => d.status$),
      _try(() => d.state$),
      _try(() => d.statusStream),
      _try(() => d.stateStream),
      _try(() => d.streamStatus),
      _try(() => d.streamState),
    ];
    for (final c in candidates) {
      if (c is Stream) return c.map((e) => e.toString()).cast<String>();
    }
    return const Stream<String>.empty();
  }

  Stream<String> _rfidEpcStream() {
    final d = rfid as dynamic;
    final candidates = <Object?>[
      _try(() => d.epc$),
      _try(() => d.tag$),
      _try(() => d.epcStream),
      _try(() => d.tagStream),
      _try(() => d.streamEpc),
      _try(() => d.streamTag),
    ];
    for (final c in candidates) {
      if (c is Stream) return c.map((e) => e.toString()).cast<String>();
    }
    return const Stream<String>.empty();
  }

  Stream<String> _rfidStatusStream() {
    final d = rfid as dynamic;
    final candidates = <Object?>[
      _try(() => d.status$),
      _try(() => d.state$),
      _try(() => d.statusStream),
      _try(() => d.stateStream),
      _try(() => d.streamStatus),
      _try(() => d.streamState),
    ];
    for (final c in candidates) {
      if (c is Stream) return c.map((e) => e.toString()).cast<String>();
    }
    return const Stream<String>.empty();
  }

  Object? _try(Object? Function() fn) {
    try {
      return fn();
    } catch (_) {
      return null;
    }
  }

  void _setRfidLeituraAtiva(bool on) {
    try {
      final d = rfid as dynamic;
      _try(() => d.setLeituraAtiva(on));
      _try(() => d.setActive(on));
      _try(() => d.setReading(on));
    } catch (_) {}
  }

  // ---------------------------
  // STREAMS LIFECYCLE
  // ---------------------------
  void _attachStreamsOnce() {
    _subPeso ??= _scaleWeightStream().listen(
      (v) {
        pesoAtual = v;
        notifyListeners();
      },
      onError: (_) {},
    );

    _subScaleStatus ??= _scaleStatusStream().listen(
      (s) {
        scaleStatus = s;
        notifyListeners();
      },
      onError: (_) {},
    );

    _subRfidStatus ??= _rfidStatusStream().listen(
      (s) {
        rfidStatus = s;
        notifyListeners();
      },
      onError: (_) {},
    );

    _subEpc ??= _rfidEpcStream().listen(
      (raw) => _onEpc(raw),
      onError: (_) {},
    );
  }

  void _detachStreams() {
    _subPeso?.cancel();
    _subPeso = null;

    _subScaleStatus?.cancel();
    _subScaleStatus = null;

    _subRfidStatus?.cancel();
    _subRfidStatus = null;

    _subEpc?.cancel();
    _subEpc = null;
  }

  // ---------------------------
  // EPC -> curral
  // ---------------------------
  String _normalizeEpc(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return "";
    final idx = t.indexOf("EPC:");
    if (idx >= 0) return t.substring(idx + 4).trim();
    return t.replaceAll(";", "").trim();
  }

  Future<void> _onEpc(String raw) async {
    final epc = _normalizeEpc(raw);
    if (epc.isEmpty) return;

    final now = DateTime.now();
    if (now.difference(_lastEpcAt).inMilliseconds < 350) return;
    _lastEpcAt = now;

    lastEpc = epc;
    _clearMsgs();
    notifyListeners();

    try {
      busy = true;
      notifyListeners();

      final found = await _resolveByEpc(epc);
      if (found == null) {
        _setInfo("Curral sem previsto ou fim de linha.");
        return;
      }

      curral = found;
      pesoInicial = null;

      _setInfo("Curral carregado: ${_s(curral.nomeLocal)}");
    } catch (e) {
      _setError("Falha ao processar RFID: $e");
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<CurralPrev?> _resolveByEpc(String epc) async {
    final d = repo as dynamic;
    try {
      final CurralPrev? c = await d.findByEpc(
        epc: epc,
        idFazenda: idFazenda,
      );
      return c;
    } catch (_) {
      throw Exception(
        "Implemente FornecimentoRepo.findByEpc({epc, idFazenda}) para resolver EPC -> CurralPrev.",
      );
    }
  }

  // ---------------------------
  // PESAGEM / REGRA REALIZADO
  // ---------------------------
  void registrarPesoInicial() {
    _clearMsgs();
    pesoInicial = pesoAtual;
    notifyListeners();
  }

  void limparPesoInicial() {
    _clearMsgs();
    pesoInicial = null;
    notifyListeners();
  }

  num get realizadoSessao {
    final ini = pesoInicial;
    if (ini == null) return 0;
    final delta = invertDelta ? (pesoAtual - ini) : (ini - pesoAtual);
    return math.max<num>(0, delta);
  }

  num get realizadoFinal => curral.realizadoKg + realizadoSessao;

  num get metaConcluirKg {
    final previsto = curral.previstoKg;
    final tolKg = previsto * (toleranciaPct / 100.0);
    return math.max<num>(0, previsto - tolKg);
  }

  bool get deveConcluir =>
      concluirAutomatico && (realizadoFinal >= metaConcluirKg);

  // ---------------------------
  // DB SYNC / SAVE
  // ---------------------------
  Future<void> reloadCurralFromDb({bool silent = false}) async {
    if (busy) return;
    try {
      busy = true;
      if (!silent) notifyListeners();

      final d = repo as dynamic;
      final CurralPrev? refreshed = await _safeGetPrevById(d, _idFornec);
      if (refreshed != null) curral = refreshed;

      if (!silent) _setInfo("Atualizado.");
    } catch (e) {
      if (!silent) _setError("Falha ao recarregar: $e");
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<CurralPrev?> _safeGetPrevById(dynamic d, String idFornecimento) async {
    try {
      final CurralPrev? x = await d.getPrevById(idFornecimento);
      return x;
    } catch (_) {}
    try {
      final CurralPrev? x = await d.getById(idFornecimento);
      return x;
    } catch (_) {}
    try {
      final CurralPrev? x = await d.findById(idFornecimento);
      return x;
    } catch (_) {}
    return null;
  }

  Future<void> salvar({bool forcarConcluir = false}) async {
    if (busy) return;
    _clearMsgs();

    try {
      busy = true;
      notifyListeners();

      final novoRealizado = realizadoFinal;
      final concluiu = forcarConcluir ? true : deveConcluir;

      final d = repo as dynamic;

      try {
        await d.updateRealizado(
          idFornecimento: _idFornec,
          realizadoKg: novoRealizado,
          concluido: concluiu,
          idUsuario: idUsuario,
        );
      } catch (_) {
        await d.updateRealizado(_idFornec, novoRealizado, concluiu);
      }

      curral = curral.copyWith(
        realizadoKg: novoRealizado.toDouble(),
      );

      pesoInicial = null;

      _setInfo(concluiu ? "Salvo e concluído ✅" : "Salvo ✅");
    } catch (e) {
      _setError("Falha ao salvar: $e");
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  String _s(Object? v, {String dash = "-"}) {
    if (v == null) return dash;
    final t = v.toString().trim();
    return t.isEmpty ? dash : t;
  }
}

// ---------------------------
// UI WIDGETS
// ---------------------------

class _ConnCard extends StatelessWidget {
  const _ConnCard({required this.ctrl});
  final _FornecimentoPreController ctrl;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Conexões",
                style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            _kv("Balança", ctrl.scaleStatus.isEmpty ? "—" : ctrl.scaleStatus),
            const SizedBox(height: 4),
            _kv("RFID", ctrl.rfidStatus.isEmpty ? "—" : ctrl.rfidStatus),
            const SizedBox(height: 8),
            _kv("Último EPC", ctrl.lastEpc.isEmpty ? "—" : ctrl.lastEpc),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Row(
        children: [
          SizedBox(
            width: 92,
            child: Text(k, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(v)),
        ],
      );
}

class _CurralInfoCard extends StatelessWidget {
  const _CurralInfoCard({required this.ctrl, required this.curral});
  final _FornecimentoPreController ctrl;
  final CurralPrev curral;

  String _s(Object? v, {String dash = "-"}) {
    if (v == null) return dash;
    final t = v.toString().trim();
    return t.isEmpty ? dash : t;
  }

  @override
  Widget build(BuildContext context) {
    final racaoTxt = _s(curral.racao);
    final previsto = curral.previstoKg;
    final realizadoBase = curral.realizadoKg;
    final sessao = ctrl.realizadoSessao;
    final finalKg = ctrl.realizadoFinal;

    final prog =
        (previsto <= 0) ? 0.0 : (finalKg / previsto).clamp(0, 1).toDouble();

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _s(curral.nomeLocal, dash: "Curral"),
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                ),
                const SizedBox(width: 8),
                Chip(label: Text(curral.concluido ? "Concluído" : "Em aberto")),
              ],
            ),
            const SizedBox(height: 10),
            _kv("Linha", _s(curral.linha)),
            _kv("Trato", _s(curral.trato)),
            _kv("Ração", racaoTxt),
            const Divider(height: 18),
            _kv("Previsto (kg)", previsto.toStringAsFixed(3)),
            _kv("Realizado (base)", realizadoBase.toStringAsFixed(3)),
            _kv("Sessão (delta)", sessao.toStringAsFixed(3)),
            _kv("Realizado (final)", finalKg.toStringAsFixed(3)),
            _kv("Meta concluir", ctrl.metaConcluirKg.toStringAsFixed(3)),
            const SizedBox(height: 10),
            LinearProgressIndicator(value: prog),
            const SizedBox(height: 6),
            Text("${(prog * 100).toStringAsFixed(0)}%"),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
                child: Text(k,
                    style: const TextStyle(fontWeight: FontWeight.w700))),
            Text(v),
          ],
        ),
      );
}

class _PesoCard extends StatelessWidget {
  const _PesoCard({required this.ctrl});
  final _FornecimentoPreController ctrl;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Pesagem",
                style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    "Peso atual: ${ctrl.pesoAtual.toStringAsFixed(3)}",
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                ),
                if (ctrl.busy)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: ctrl.busy ? null : ctrl.registrarPesoInicial,
                    icon: const Icon(Icons.flag),
                    label: Text(ctrl.pesoInicial == null
                        ? "Registrar peso inicial"
                        : "Atualizar peso inicial"),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: (ctrl.busy || ctrl.pesoInicial == null)
                      ? null
                      : ctrl.limparPesoInicial,
                  child: const Text("Limpar"),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              ctrl.pesoInicial == null
                  ? "Peso inicial: —"
                  : "Peso inicial: ${ctrl.pesoInicial!.toStringAsFixed(3)}",
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: ctrl.invertDelta,
              onChanged: ctrl.busy ? null : ctrl.setInvertDelta,
              title: const Text(
                  "Inverter delta (se a balança subir ao descarregar)"),
            ),
          ],
        ),
      ),
    );
  }
}

class _AcoesCard extends StatelessWidget {
  const _AcoesCard({
    required this.ctrl,
    required this.onGoWeighPage,
  });

  final _FornecimentoPreController ctrl;
  final Future<void> Function() onGoWeighPage;

  @override
  Widget build(BuildContext context) {
    final sliderValue = ctrl.toleranciaPct.clamp(0, 20).toDouble();

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Salvar", style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Row(
              children: [
                const SizedBox(width: 120, child: Text("Tolerância (%)")),
                Expanded(
                  child: Slider(
                    value: sliderValue,
                    min: 0,
                    max: 20,
                    divisions: 20,
                    label: "${sliderValue.toStringAsFixed(0)}%",
                    onChanged: ctrl.busy ? null : ctrl.setToleranciaPct,
                  ),
                ),
                SizedBox(
                    width: 52,
                    child: Text("${sliderValue.toStringAsFixed(0)}%")),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: ctrl.concluirAutomatico,
              onChanged: ctrl.busy ? null : ctrl.setConcluirAutomatico,
              title: const Text("Concluir automaticamente ao atingir a meta"),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: ctrl.busy ? null : () => ctrl.salvar(),
                    icon: const Icon(Icons.save),
                    label: const Text("Salvar"),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: ctrl.busy
                        ? null
                        : () => ctrl.salvar(forcarConcluir: true),
                    icon: const Icon(Icons.check_circle),
                    label: const Text("Concluir e salvar"),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: ctrl.busy ? null : () => onGoWeighPage(),
              icon: const Icon(Icons.open_in_new),
              label: const Text("Abrir tela de pesagem (antiga)"),
            ),
          ],
        ),
      ),
    );
  }
}

class _BannerInfo extends StatelessWidget {
  const _BannerInfo({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final bg = Colors.blue.withValues(alpha: 0.08);
    final bd = Colors.blue.withValues(alpha: 0.25);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: bd),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _BannerError extends StatelessWidget {
  const _BannerError({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final bg = Colors.red.withValues(alpha: 0.08);
    final bd = Colors.red.withValues(alpha: 0.25);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: bd),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
