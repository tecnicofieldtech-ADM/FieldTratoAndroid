// lib/features/fabricacao/ui/fabricacao_list_page.dart
import "package:flutter/material.dart";
import "../../../repo/config_repo.dart";
import "../domain/fabricacao_flow.dart";

import "../data/fabricacao_repo.dart";
import "../domain/models.dart";
import "ingredientes_modal.dart";
import "fabricacao_prefab_page.dart";
import "fabricacao_weigh_page.dart";
import "fabricacao_dashboard_page.dart";

enum _SyncAcao { habilitar, marcarSincronizado }

class FabricacaoListPage extends StatefulWidget {
  const FabricacaoListPage({super.key, required this.repo});
  final FabricacaoRepo repo;

  @override
  State<FabricacaoListPage> createState() => _FabricacaoListPageState();
}

class _FabricacaoListPageState extends State<FabricacaoListPage>
    with SingleTickerProviderStateMixin {
  final _cfgRepo = ConfigRepo();
  bool _loading = false;
  List<FabricacaoHeader> _items = [];
  int? _tipoTrabalho;
  bool _modoHibrido = false;

  // ---------- filtros ----------
  late DateTime _filterDate; // data do dia (padrão: hoje)
  String? _filterDieta; // nome da ração (combo)
  int? _filterTrato; // trato (combo)

  // cache listas para combos
  List<String> _dietaOpts = [];
  List<int> _tratoOpts = [];

  // animação "finalizada"
  late final AnimationController _animCtrl;
  int _carregRefreshTick = 0;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _filterDate = _today();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _pulse = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _animCtrl, curve: Curves.easeInOut),
    );

    _load();
    _loadOperacaoFlags();
  }

  @override
  void activate() {
    super.activate();
    _loadOperacaoFlags();
  }

  Future<void> _loadOperacaoFlags() async {
    try {
      final t = await _cfgRepo.getTipoTrabalho();
      final h = await _cfgRepo.getModoHibrido();
      if (!mounted) return;
      if (t == 2 && !h) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          Navigator.of(context).pushReplacementNamed("/menu");
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "Modo Distribuidor: use Carregamento e Fornecimento.",
              ),
            ),
          );
        });
        return;
      }
      setState(() {
        _tipoTrabalho = t;
        _modoHibrido = h;
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await widget.repo.listFabricacoes();
      setState(() {
        _items = list;
        _rebuildFilterOptions();
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _rebuildFilterOptions() {
    final dietas = <String>{};
    final tratos = <int>{};

    for (final it in _items) {
      final dn = it.dietaNome.trim();
      if (dn.isNotEmpty) dietas.add(dn);
      tratos.add(it.trato);
    }

    _dietaOpts = dietas.toList()..sort();
    _tratoOpts = tratos.toList()..sort();

    // se a opção selecionada não existir mais, limpa
    if (_filterDieta != null && !_dietaOpts.contains(_filterDieta)) {
      _filterDieta = null;
    }
    if (_filterTrato != null && !_tratoOpts.contains(_filterTrato)) {
      _filterTrato = null;
    }
  }

  // ---------- helpers ----------
  String _fmtDateDdMmYy(String rawIso) {
    final s = rawIso.trim();
    if (s.isEmpty) return "--/--/--";
    try {
      final d = DateTime.parse(s);
      String dd(int v) => v.toString().padLeft(2, "0");
      final yy = (d.year % 100).toString().padLeft(2, "0");
      return "${dd(d.day)}/${dd(d.month)}/$yy";
    } catch (_) {
      return s;
    }
  }

  bool _sameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  int get _qtdFiltradosSyncHabilitavel {
    final ids = <String>{};
    for (final f in _filtered) {
      final id = f.id.trim();
      if (id.isEmpty) continue;
      ids.add(id);
    }
    return ids.length;
  }

  List<FabricacaoHeader> get _filtered {
    Iterable<FabricacaoHeader> it = _items;

    final d0 = _filterDate;
    it = it.where((e) {
      try {
        final d = DateTime.parse(e.dataFabricacao);
        return _sameDate(d, d0);
      } catch (_) {
        return false;
      }
    });

    if (_filterDieta != null && _filterDieta!.trim().isNotEmpty) {
      final dn = _filterDieta!.trim().toLowerCase();
      it = it.where((e) => e.dietaNome.toLowerCase().trim() == dn);
    }

    if (_filterTrato != null) {
      it = it.where((e) => e.trato == _filterTrato);
    }

    return it.toList();
  }

  Future<void> _openAddFlow() async {
    final tipo = await _cfgRepo.getTipoTrabalho();
    final hibrido = await _cfgRepo.getModoHibrido();
    if (!mounted) return;

    setState(() {
      _tipoTrabalho = tipo;
      _modoHibrido = hibrido;
    });

    // Só redireciona para receber carregamento quando é distribuidor **sem** híbrido.
    if (tipo == 2 && !hibrido) {
      Navigator.pushNamed(context, "/carregamento-estacionario");
      return;
    }

    final aberto = await widget.repo.getFabricacaoEmAbertoHoje();
    if (!mounted) return;

    if (aberto != null) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text("Fabricação em aberto"),
          content: Text(
            "Existe uma fabricação em aberto.\n\n"
            "Ração: ${aberto.dietaNome}\n"
            "Trato: ${aberto.trato}\n\n"
            "Deseja continuar?",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Não"),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Continuar"),
            ),
          ],
        ),
      );

      if (ok == true && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => FabricacaoWeighPage(repo: widget.repo)),
        ).then((_) => _load());
      }
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => FabricacaoPreFabPage(repo: widget.repo)),
    ).then((_) => _load());
  }

  Future<void> _tryDelete(String idFab) async {
    final pode = await widget.repo.canDeleteFabricacao(idFab);
    if (!mounted) return;

    if (!pode) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("So pode excluir fabricacao nao sincronizada."),
        ),
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Excluir Fabricação?"),
        content: const Text("Essa Fabricação será removida do banco local."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancelar")),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Excluir")),
        ],
      ),
    );

    if (ok == true) {
      await widget.repo.deleteFabricacao(idFab);
      if (!mounted) return;
      await _load();
    }
  }

  Future<void> _habilitarSyncFiltrados() async {
    if (_loading) return;
    final qtd = _qtdFiltradosSyncHabilitavel;
    if (qtd <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Nao ha itens filtrados para habilitar sincronizacao."),
        ),
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Habilitar sincronizacao"),
        content: Text(
          "Habilitar sincronizacao novamente para $qtd fabricacao(oes) filtrada(s)?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text("Cancelar"),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text("Habilitar"),
          ),
        ],
      ),
    );

    if (ok != true) return;
    if (!mounted) return;

    setState(() => _loading = true);
    try {
      final alterados = await widget.repo.reabilitarSyncFiltrados(
        itens: _filtered,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Sincronizacao habilitada em $alterados fabricacao(oes).",
          ),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Erro ao habilitar sincronizacao: $e")),
      );
      setState(() => _loading = false);
    }
  }

  Future<void> _marcarSyncOkFiltrados() async {
    if (_loading) return;
    final qtd = _qtdFiltradosSyncHabilitavel;
    if (qtd <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Nao ha itens filtrados para marcar como sincronizado."),
        ),
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Marcar como sincronizado"),
        content: Text(
          "Marcar $qtd fabricacao(oes) filtrada(s) como ja sincronizadas?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text("Cancelar"),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text("Marcar"),
          ),
        ],
      ),
    );

    if (ok != true) return;
    if (!mounted) return;

    setState(() => _loading = true);
    try {
      final alterados = await widget.repo.marcarSyncOkFiltrados(
        itens: _filtered,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Marcadas como sincronizadas: $alterados fabricacao(oes).",
          ),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Erro ao marcar sincronizacao: $e")),
      );
      setState(() => _loading = false);
    }
  }

  Widget _syncFiltradosAction() {
    final qtd = _qtdFiltradosSyncHabilitavel;
    final txt = qtd > 99 ? "99+" : "$qtd";

    return PopupMenuButton<_SyncAcao>(
      tooltip: "Acoes de sincronizacao dos filtrados ($qtd)",
      enabled: !_loading && qtd > 0,
      onSelected: (acao) async {
        switch (acao) {
          case _SyncAcao.habilitar:
            await _habilitarSyncFiltrados();
            break;
          case _SyncAcao.marcarSincronizado:
            await _marcarSyncOkFiltrados();
            break;
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem<_SyncAcao>(
          value: _SyncAcao.habilitar,
          child: Text("Habilitar para sincronizacao"),
        ),
        PopupMenuItem<_SyncAcao>(
          value: _SyncAcao.marcarSincronizado,
          child: Text("Marcar como ja sincronizado"),
        ),
      ],
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.sync_problem),
          if (qtd > 0)
            Positioned(
              right: -8,
              top: -6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.red.shade700,
                  borderRadius: BorderRadius.circular(10),
                ),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                child: Text(
                  txt,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ---------- UI filtros ----------
  Future<void> _pickDate() async {
    final now = DateTime.now();

    final picked = await showDatePicker(
      context: context,
      initialDate: _filterDate,
      firstDate: DateTime(now.year - 2, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
    );

    if (!mounted) return;
    if (picked == null) return;

    setState(() {
      _filterDate = DateTime(picked.year, picked.month, picked.day);
    });
  }

  void _clearFilters() {
    setState(() {
      _filterDate = _today();
      _filterDieta = null;
      _filterTrato = null;
    });
  }

  String _fmtFilterDate(DateTime d) {
    final yy = (d.year % 100).toString().padLeft(2, "0");
    return "${d.day.toString().padLeft(2, "0")}/"
        "${d.month.toString().padLeft(2, "0")}/$yy";
  }

  Widget _filtersBar() {
    final hasFilters = !_sameDate(_filterDate, _today()) ||
        _filterDieta != null ||
        _filterTrato != null;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.event),
                  label: Text(_fmtFilterDate(_filterDate)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _filterDieta,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: "Ração",
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text("Todas"),
                    ),
                    ..._dietaOpts.map(
                      (e) => DropdownMenuItem<String>(value: e, child: Text(e)),
                    ),
                  ],
                  onChanged: (v) => setState(() => _filterDieta = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _filterTrato,
                  decoration: const InputDecoration(
                    labelText: "Trato",
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem<int>(
                      value: null,
                      child: Text("Todos"),
                    ),
                    ..._tratoOpts.map(
                      (e) => DropdownMenuItem<int>(
                          value: e, child: Text(e.toString())),
                    ),
                  ],
                  onChanged: (v) => setState(() => _filterTrato = v),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: hasFilters
                    ? FilledButton.icon(
                        onPressed: _clearFilters,
                        icon: const Icon(Icons.clear),
                        label: const Text("Limpar"),
                      )
                    : OutlinedButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh),
                        label: const Text("Atualizar"),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // pill do carregamento (ficou no nível do State, não dentro do _statusPill)
  Future<void> _forcarGerarCarregamento(FabricacaoHeader it) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text("Gerar carregamento"),
        content: Text(
          "Criar carregamento para a fabricação de ${it.dietaNome.trim().isEmpty ? "ração" : it.dietaNome}?\n\n"
          "Use quando a finalização ocorreu sem gerar o carregamento (ex.: vagão não configurado).",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text("Cancelar"),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text("Gerar"),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    try {
      var idVagao = await _cfgRepo.getIdVagao();
      if (idVagao.trim().isEmpty) {
        idVagao = await widget.repo.getIdVagaoByFabricacaoId(it.id);
      }

      await widget.repo.criarCarregamentoParaFabricacao(
        idFabricacao: it.id,
        idVagaoOverride: idVagao.trim().isEmpty ? null : idVagao.trim(),
        tipoTrabalho: _tipoTrabalho ?? 0,
      );

      if (!mounted) return;
      setState(() => _carregRefreshTick++);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Carregamento criado com sucesso."),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          title: const Text("Erro ao gerar carregamento"),
          content: Text("$e"),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text("OK"),
            ),
          ],
        ),
      );
    }
  }

  Widget _carregamentoPill(String fabId, {FabricacaoHeader? item}) {
    final emAberto = item?.status == FabricacaoStatus.emAndamento;
    return FutureBuilder<Map<String, Object?>?>(
      key: ValueKey("carreg-$fabId-$_carregRefreshTick"),
      future: widget.repo.getCarregamentoStatusByFabricacao(fabId),
      builder: (_, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.blueGrey.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(999),
              border:
                  Border.all(color: Colors.blueGrey.withValues(alpha: 0.25)),
            ),
            child: const Text(
              "Carregamento: ...",
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
            ),
          );
        }

        final m = snap.data;
        if (m == null) {
          return Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.25)),
                ),
                child: const Text(
                  "Carregamento: Não criado",
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
                ),
              ),
              if (item != null && !emAberto)
                TextButton.icon(
                  onPressed: () => _forcarGerarCarregamento(item),
                  icon: const Icon(Icons.local_shipping_outlined, size: 18),
                  label: const Text("Gerar carregamento"),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          );
        }

        final st = (m["status_text"] ?? "ABERTO").toString();
        final isAberto = st.toUpperCase().contains("ABERTO");

        final bg = isAberto
            ? Colors.orange.withValues(alpha: 0.12)
            : Colors.green.withValues(alpha: 0.12);

        final border = isAberto
            ? Colors.orange.withValues(alpha: 0.35)
            : Colors.green.withValues(alpha: 0.35);

        final fg = isAberto ? Colors.deepOrange : Colors.green.shade800;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: border),
          ),
          child: Text(
            "Carregamento: ${isAberto ? "Aberto" : "Fechado"}",
            style:
                TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: fg),
          ),
        );
      },
    );
  }

  // ---------- item visual ----------
  Widget _statusPill(FabricacaoHeader it) {
    final emAberto = it.status == FabricacaoStatus.emAndamento;
    final pendente = it.status == FabricacaoStatus.pendenteCaminhao;

    final Color bg = emAberto
        ? Colors.orange.withValues(alpha: 0.12)
        : pendente
            ? Colors.blue.withValues(alpha: 0.12)
            : Colors.green.withValues(alpha: 0.12);
    final Color border = emAberto
        ? Colors.orange.withValues(alpha: 0.35)
        : pendente
            ? Colors.blue.withValues(alpha: 0.35)
            : Colors.green.withValues(alpha: 0.35);
    final Color fg = emAberto
        ? Colors.deepOrange
        : pendente
            ? Colors.blue.shade800
            : Colors.green.shade800;

    final icon =
        emAberto ? Icons.pending_actions : (pendente ? Icons.outbox : Icons.verified);

    Widget child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: fg),
        const SizedBox(width: 6),
        Text(
          emAberto ? "Em andamento" : (pendente ? "Pendente caminhão" : "Finalizada"),
          style:
              TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: fg),
        ),
      ],
    );

    // animação só em finalizadas
    if (!emAberto && !pendente) {
      child = ScaleTransition(scale: _pulse, child: child);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;
    final isDistribuidor = _tipoTrabalho == 2;
    final mostrarNovaFabricacao = !isDistribuidor || _modoHibrido;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text("Fabricação"),
        actions: [
          IconButton(
            tooltip: "Atualizar",
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
          _syncFiltradosAction(),
          IconButton(
            tooltip: "Dashboard",
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => FabricacaoDashboardPage(repo: widget.repo)),
              );
            },
            icon: const Icon(Icons.insights),
          ),
          if (isDistribuidor)
            IconButton(
              tooltip: "Carregar do Estacionario",
              onPressed: () =>
                  Navigator.pushNamed(context, "/carregamento-estacionario"),
              icon: const Icon(Icons.download_for_offline_outlined),
            ),
        ],
      ),
      bottomNavigationBar: !mostrarNovaFabricacao
          ? null
          : SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: SizedBox(
                  height: 54,
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: _openAddFlow,
                    icon: const Icon(Icons.add),
                    label: const Text(
                      "Nova Fabricação",
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ),
            ),
      body: Column(
        children: [
          _filtersBar(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : list.isEmpty
                    ? const Center(
                        child: Text("Nenhuma Fabricação encontrada."))
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
                        itemCount: list.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) {
                          final it = list[i];

                          final pct = it.qtdPrevista <= 0
                              ? 0
                              : (it.qtdRealizada / it.qtdPrevista) * 100.0;
                          final dif = (it.qtdRealizada - it.qtdPrevista);

                          final dt = _fmtDateDdMmYy(it.dataFabricacao);

                          final emAberto =
                              it.status == FabricacaoStatus.emAndamento;
                          final pendente =
                              it.status == FabricacaoStatus.pendenteCaminhao;
                          final bloqueadaStation = _tipoTrabalho == 1 &&
                              it.status == FabricacaoStatus.pendenteCaminhao;
                          final podeAbrir =
                              (emAberto || pendente) && !bloqueadaStation;

                          return Card(
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(color: Colors.grey.shade200),
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: podeAbrir
                                  ? () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => FabricacaoWeighPage(
                                            repo: widget.repo,
                                            initialFabricacaoId: it.id,
                                          ),
                                        ),
                                      ).then((_) => _load());
                                    }
                                  : bloqueadaStation
                                      ? () => ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                "Fabricacao pendente no caminhao. Somente leitura no estacionario.",
                                              ),
                                            ),
                                          )
                                  : null,
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        color: Colors.brown
                                            .withValues(alpha: 0.10),
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: Icon(
                                        Icons.agriculture,
                                        color: Colors.brown.shade700,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Text(
                                                dt,
                                                style: const TextStyle(
                                                    fontWeight:
                                                        FontWeight.w900),
                                              ),
                                              const SizedBox(width: 10),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 10,
                                                        vertical: 5),
                                                decoration: BoxDecoration(
                                                  color: Colors.blueGrey
                                                      .withValues(alpha: 0.10),
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          999),
                                                  border: Border.all(
                                                      color: Colors.blueGrey
                                                          .withValues(
                                                              alpha: 0.25)),
                                                ),
                                                child: Text(
                                                  "Trato ${it.trato}",
                                                  style: const TextStyle(
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w800),
                                                ),
                                              ),
                                              const Spacer(),
                                              _statusPill(it),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 8,
                                            children: [
                                              _carregamentoPill(it.id, item: it),
                                            ],
                                          ),
                                          Text(
                                            it.dietaNome.trim().isEmpty
                                                ? "(Sem nome de Ração)"
                                                : it.dietaNome,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w800),
                                          ),
                                          const SizedBox(height: 10),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      "Prev ${it.qtdPrevista.toStringAsFixed(0)}  até  "
                                                      "Real ${it.qtdRealizada.toStringAsFixed(0)}  até  "
                                                      "Dif ${dif >= 0 ? "+" : ""}${dif.toStringAsFixed(0)}",
                                                      style: TextStyle(
                                                          color: Colors
                                                              .grey.shade800,
                                                          fontSize: 12),
                                                    ),
                                                    const SizedBox(height: 6),
                                                    ClipRRect(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              999),
                                                      child:
                                                          LinearProgressIndicator(
                                                        value: it.qtdPrevista >
                                                                0
                                                            ? (it.qtdRealizada /
                                                                    it.qtdPrevista)
                                                                .clamp(0, 1)
                                                            : 0,
                                                        minHeight: 8,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 10,
                                                        vertical: 8),
                                                decoration: BoxDecoration(
                                                  color: Colors.grey.shade100,
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  border: Border.all(
                                                      color:
                                                          Colors.grey.shade200),
                                                ),
                                                child: Text(
                                                  "${pct.clamp(0, 999).toStringAsFixed(1)}%",
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w900),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 10),
                                          Row(
                                            children: [
                                              OutlinedButton.icon(
                                                icon:
                                                    const Icon(Icons.list_alt),
                                                label: const Text("Insumos"),
                                                onPressed: () async {
                                                  await showModalBottomSheet(
                                                    context: context,
                                                    isScrollControlled: true,
                                                    useSafeArea: true,
                                                    builder: (_) =>
                                                        IngredientesModal(
                                                      repo: widget.repo,
                                                      fabId: it.id,
                                                    ),
                                                  );
                                                },
                                              ),
                                              const SizedBox(width: 10),
                                              FutureBuilder<bool>(
                                                future: widget.repo
                                                    .canDeleteFabricacao(it.id),
                                                builder: (_, snap) {
                                                  final pode =
                                                      snap.data == true;
                                                  return OutlinedButton.icon(
                                                    icon: const Icon(
                                                        Icons.delete_outline),
                                                    label:
                                                        const Text("Excluir"),
                                                    onPressed: pode
                                                        ? () =>
                                                            _tryDelete(it.id)
                                                        : null,
                                                  );
                                                },
                                              ),
                                            ],
                                          ),
                                        ],
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
        ],
      ),
    );
  }
}
