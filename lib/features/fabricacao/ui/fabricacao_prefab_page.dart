import "package:flutter/material.dart";
import "package:flutter/services.dart";

import "../../../repo/user_repo.dart";
import "../../../repo/dieta_repo.dart";
import "../../../repo/config_repo.dart";

import "../../../services/session_service.dart";

import "../data/fabricacao_repo.dart";
import "fabricacao_weigh_page.dart";
import "../services/fabricacao_create_service.dart";

class FabricacaoPreFabPage extends StatefulWidget {
  const FabricacaoPreFabPage({super.key, required this.repo});
  final FabricacaoRepo repo;

  @override
  State<FabricacaoPreFabPage> createState() => _FabricacaoPreFabPageState();
}

class _FabricacaoPreFabPageState extends State<FabricacaoPreFabPage> {
  final _dietaRepo = DietaRepo();
  final _userRepo = UserRepo();
  final _cfg = ConfigRepo();

  bool _loading = false;

  List<Map<String, Object?>> _dietas = [];
  List<Map<String, Object?>> _users = [];

  String? _dietaId;
  String? _operadorId;

  int? _tratoSelecionado;
  final _kgCtrl = TextEditingController(text: "0");
  bool _loadingResumo = false;
  List<_ResumoTrato> _resumos = [];

  @override
  void initState() {
    super.initState();
    _loadCombos();
  }

  Future<void> _loadCombos() async {
    if (mounted) setState(() => _loading = true);
    try {
      final backend = await _cfg.getBackend();
      final isFieldpec = backend == 1;
      final idFazendaSel = await _cfg.getIdFazendaSelecionada();

      var dietas = await _dietaRepo.listAll(
        idFazenda: isFieldpec ? null : idFazendaSel,
      );
      final dietasPorFazenda = dietas.length;

      if (!isFieldpec && dietas.isEmpty && idFazendaSel.trim().isNotEmpty) {
        debugPrint(
          "[FAB_PREFAB] nenhuma dieta para fazenda='$idFazendaSel' (filtrado). Tentando sem filtro...",
        );
        dietas = await _dietaRepo.listAll();
      }

      final users = await _userRepo.listAll();

      final amostra = dietas
          .take(5)
          .map(
            (d) =>
                "${(d["ID"] ?? "").toString()}|${(d["ID_FAZENDA"] ?? "").toString()}|${(d["NOME"] ?? "").toString()}",
          )
          .join(" ; ");

      debugPrint(
        "[FAB_PREFAB] backend=$backend isFieldpec=$isFieldpec fazendaSel='$idFazendaSel' dietasFiltradas=$dietasPorFazenda dietasFinal=${dietas.length} users=${users.length}",
      );
      if (amostra.isNotEmpty) {
        debugPrint("[FAB_PREFAB] amostra dietas: $amostra");
      }

      if (!mounted) return;

      setState(() {
        _dietas = dietas;
        _users = users;

        if (_dietas.isNotEmpty) {
          _dietaId = (_dietas.first["ID"] ?? "").toString();
        }
        if (_users.isNotEmpty) {
          _operadorId = (_users.first["ID"] ?? "").toString();
        }
      });

      if (_dietas.isEmpty) {
        _msg(
          "Nenhuma dieta encontrada para a fabricação. Verifique sincronização e vínculo de fazenda.",
        );
      }

      await _loadResumo();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadResumo() async {
    final id = (_dietaId ?? "").trim();
    if (id.isEmpty) {
      if (mounted) {
        setState(() {
          _resumos = [];
          _loadingResumo = false;
        });
      }
      return;
    }

    if (mounted) setState(() => _loadingResumo = true);
    try {
      final rows = await widget.repo.listResumoPorDietaDataTrato(
        idDieta: id,
        trato: _tratoSelecionado,
      );
      final list = rows.map(_ResumoTrato.fromMap).toList();
      if (!mounted) return;
      setState(() => _resumos = list);
    } finally {
      if (mounted) setState(() => _loadingResumo = false);
    }
  }

  @override
  void dispose() {
    _kgCtrl.dispose();
    super.dispose();
  }

  void _msg(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  String _fmt(num v) => v.toStringAsFixed(0).replaceAll(".", ",");

  Future<void> _applyPrevisto(double previstoTotal) async {
    if (previstoTotal <= 0) return;

    var total = previstoTotal;
    if (previstoTotal > 10000) {
      final ctrl = TextEditingController(text: "2");
      final n = await showDialog<int>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text("Dividir fabricacao?"),
          content: TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: "Quantidade de fabricacoes",
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancelar"),
            ),
            ElevatedButton(
              onPressed: () {
                final v = int.tryParse(ctrl.text.trim()) ?? 1;
                Navigator.pop(context, v <= 0 ? 1 : v);
              },
              child: const Text("Ok"),
            ),
          ],
        ),
      );
      if (n != null && n > 1) {
        total = previstoTotal / n;
      }
    }

    _kgCtrl.text = total.toStringAsFixed(0).replaceAll(".", ",");
  }

  Future<void> _onFabricar() async {
    if ((_dietaId ?? "").isEmpty) return _msg("Selecione a dieta.");
    if ((_operadorId ?? "").isEmpty) return _msg("Selecione o operador.");

    final trato = _tratoSelecionado;
    if (trato == null || trato <= 0) return _msg("Informe o trato.");

    final kg = double.tryParse(_kgCtrl.text.trim().replaceAll(",", "."));
    if (kg == null || kg <= 0) return _msg("Informe o previsto em KG.");
    if (kg > 15000) return _msg("Quantidade maxima e 15.000 KG.");

    final idUsuarioLogado = SessionService.instance.userId;
    if (idUsuarioLogado == null || idUsuarioLogado.trim().isEmpty) {
      _msg("Sessao vazia. Faca login novamente.");
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, "/login");
      return;
    }

    final aberto = await widget.repo.getFabricacaoEmAberto();
    if (!mounted) return;

    if (aberto != null) {
      final ok = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Text("Fabricacao em aberto"),
          content: const Text(
            "Existe uma fabricacao em aberto. Deseja continuar de onde parou?",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Nao"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Sim"),
            ),
          ],
        ),
      );

      if (!mounted) return;

      if (ok == true) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => FabricacaoWeighPage(repo: widget.repo),
          ),
        );
      }
      return;
    }

    if (mounted) setState(() => _loading = true);
    try {
      final idFazenda = await _cfg.getIdFazendaSelecionada();
      if (idFazenda.isEmpty) {
        throw Exception("Nenhuma fazenda selecionada na CONFIG.");
      }

      final service = FabricacaoCreateService();
      await service.criarFabricacao(
        idDieta: _dietaId!,
        idOperador: _operadorId!,
        idUsuarioLogado: idUsuarioLogado,
        idFazenda: idFazenda,
        trato: trato,
        totalKg: kg,
      );

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => FabricacaoWeighPage(repo: widget.repo),
        ),
      );
    } catch (e) {
      _msg("Erro ao criar fabricacao: $e");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboardBottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      appBar: AppBar(title: const Text("Nova Fabricacao")),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _onFabricar,
              child: const Text("Fabricar"),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: EdgeInsets.fromLTRB(
                      16,
                      28,
                      16,
                      16 + keyboardBottomInset,
                    ),
                    child: ConstrainedBox(
                      constraints:
                          BoxConstraints(minHeight: constraints.maxHeight),
                      child: IntrinsicHeight(
                        child: Column(
                          children: [
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: DropdownButtonFormField<String>(
                                  key: ValueKey(_dietaId),
                                  initialValue: _dietaId,
                                  items: _dietas
                                      .map(
                                        (d) => DropdownMenuItem<String>(
                                          value: (d["ID"] ?? "").toString(),
                                          child: Text(
                                              (d["NOME"] ?? "").toString()),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (v) async {
                                    setState(() => _dietaId = v);
                                    await _loadResumo();
                                  },
                                  decoration: const InputDecoration(
                                    labelText: "Dieta",
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    disabledBorder: InputBorder.none,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: DropdownButtonFormField<String>(
                                  key: ValueKey(_operadorId),
                                  initialValue: _operadorId,
                                  items: _users
                                      .map(
                                        (u) => DropdownMenuItem<String>(
                                          value: (u["ID"] ?? "").toString(),
                                          child: Text(
                                              (u["NOME"] ?? "").toString()),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (v) =>
                                      setState(() => _operadorId = v),
                                  decoration: const InputDecoration(
                                    labelText: "Operador",
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    disabledBorder: InputBorder.none,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "Trato",
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                              fontWeight: FontWeight.w800),
                                    ),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 10,
                                      runSpacing: 10,
                                      children: [1, 2, 3, 4].map((t) {
                                        final sel = _tratoSelecionado == t;
                                        return ChoiceChip(
                                          label: Text("Trato $t"),
                                          selected: sel,
                                          onSelected: (_) async {
                                            setState(
                                              () => _tratoSelecionado = t,
                                            );
                                            await _loadResumo();
                                          },
                                        );
                                      }).toList(),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (_loadingResumo)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 6),
                                child: LinearProgressIndicator(minHeight: 3),
                              ),
                            if (_resumos.isNotEmpty)
                              Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        "Resumo por trato",
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      ..._resumos.map((r) {
                                        final falta = (r.previsto - r.realizado)
                                            .clamp(0.0, double.infinity)
                                            .toDouble();
                                        return Container(
                                          margin:
                                              const EdgeInsets.only(bottom: 8),
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            border: Border.all(
                                              color: Colors.black
                                                  .withValues(alpha: 0.10),
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      "Trato ${r.trato} - ${r.dataYmd}",
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w800,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      "Prev: ${_fmt(r.previsto)}  -  Real: ${_fmt(r.realizado)}  -  Falta: ${_fmt(falta)}",
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              FilledButton(
                                                onPressed: () async {
                                                  setState(() =>
                                                      _tratoSelecionado =
                                                          r.trato);
                                                  await _applyPrevisto(falta);
                                                },
                                                child: const Text("Selecionar"),
                                              ),
                                            ],
                                          ),
                                        );
                                      }),
                                    ],
                                  ),
                                ),
                              ),
                            const SizedBox(height: 12),
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: TextField(
                                  controller: _kgCtrl,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 52,
                                    fontWeight: FontWeight.w900,
                                  ),
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(
                                      RegExp(r"[0-9.,]"),
                                    ),
                                    TextInputFormatter.withFunction(
                                      (oldValue, newValue) {
                                        final raw = newValue.text.trim();
                                        if (raw.isEmpty) return newValue;
                                        final v = double.tryParse(
                                          raw.replaceAll(",", "."),
                                        );
                                        if (v == null) return oldValue;
                                        return v > 15000 ? oldValue : newValue;
                                      },
                                    ),
                                  ],
                                  decoration: const InputDecoration(
                                    labelText: "Quantidade total (KG)",
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    isDense: true,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _ResumoTrato {
  _ResumoTrato({
    required this.idDieta,
    required this.dataYmd,
    required this.trato,
    required this.previsto,
    required this.realizado,
  });

  final String idDieta;
  final String dataYmd;
  final int trato;
  final double previsto;
  final double realizado;

  static _ResumoTrato fromMap(Map<String, Object?> m) {
    String s(String k) => (m[k] ?? "").toString().trim();
    int i(String k) => int.tryParse(s(k)) ?? 0;
    double d(String k) => double.tryParse(s(k).replaceAll(",", ".")) ?? 0.0;

    return _ResumoTrato(
      idDieta: s("id_dieta"),
      dataYmd: s("data_ymd"),
      trato: i("trato"),
      previsto: d("previsto"),
      realizado: d("realizado"),
    );
  }
}
