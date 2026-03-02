import "package:flutter/material.dart";

import "../../../helpers/scale_comm.dart";
import "../../../helpers/rfid_comm.dart";

import "../data/fornecimento_repo.dart";
import "../domain/fornecimento_models.dart";
import "fornecimento_dashboard_page.dart";
import "fornecimento_bi_page.dart";

enum _StatusFiltro { todos, realizados, pendentes }

class FornecimentoListPage extends StatefulWidget {
  const FornecimentoListPage({
    super.key,
    required this.idFazenda,
    required this.idUsuario,
    required this.repo,
    required this.scale,
    required this.rfid,
    this.autoOpenNovoFornecimento = false,
    this.tratoSugerido,
  });

  final String idFazenda;
  final String idUsuario;

  final FornecimentoRepo repo;

  // usa os helpers de comunicacao compartilhados
  final ScaleComm scale;
  final RfidComm rfid;
  final bool autoOpenNovoFornecimento;
  final int? tratoSugerido;

  @override
  State<FornecimentoListPage> createState() => _FornecimentoListPageState();
}

class _FornecimentoListPageState extends State<FornecimentoListPage> {
  bool _loading = true;

  DateTime _date = DateTime.now();
  _StatusFiltro _status = _StatusFiltro.todos;

  int? _trato; // null = todos
  String? _racao; // filtro texto (nome da racao) - mantido (nao filtra por id)
  String? _linha; // filtro por linha
  final TextEditingController _curralCtrl = TextEditingController();

  List<CurralPrev> _items = const [];
  bool _autoNovoTriggered = false;

  @override
  void initState() {
    super.initState();
    _buscar().then((_) => _maybeAutoOpenNovoFornecimento());
  }

  @override
  void dispose() {
    _curralCtrl.dispose();
    super.dispose();
  }

  void _msg(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  Future<void> _buscar() async {
    if (!mounted) return;
    setState(() => _loading = true);

    try {
      final bool? realizadoMaiorZero = switch (_status) {
        _StatusFiltro.todos => null,
        _StatusFiltro.realizados => true,
        _StatusFiltro.pendentes => false,
      };

      final list = await widget.repo.listPrevisao(
        idFazenda: widget.idFazenda,
        data: _date,
        trato: _trato,
        racaoNome:
            (_racao == null || _racao!.trim().isEmpty) ? null : _racao!.trim(),
        linha: _linha,
        curralNome:
            _curralCtrl.text.trim().isEmpty ? null : _curralCtrl.text.trim(),
        realizadoMaiorZero: realizadoMaiorZero,
      );

      if (!mounted) return;
      setState(() => _items = list);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // =========================================================
  // NOVO FLUXO
  // - item tap: abre Dashboard no trato do item e filtra por idRacao do item
  // - novo fornecimento: escolhe trato e abre Dashboard (sem idRacao filtro)
  // =========================================================

  void _openDashboard({
    required int trato,
    String? idRacaoFiltro,
    bool startCleared = false,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FornecimentoDashboardPage(
          idFazenda: widget.idFazenda,
          idUsuario: widget.idUsuario,
          trato: trato,
          repo: widget.repo,
          scale: widget.scale,
          rfid: widget.rfid,
          data: _date,
          idRacaoFiltro: idRacaoFiltro,
          startCleared: startCleared,
        ),
      ),
    );
  }

  Future<int?> _pickTratoModal() async {
    // opcoes: sempre em ordem crescente
    final ordenadas =
        _tratoOptions.isNotEmpty ? _tratoOptions : <int>[1, 2, 3, 4, 5, 6];

    return showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "Novo Fornecimento",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 10),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "Selecione o trato:",
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(height: 8),
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
  }

  // item da lista agora vai pro dashboard
  void _open(CurralPrev c) {
    _openDashboard(
      trato: c.trato,
      idRacaoFiltro:
          (c.idRacao ?? "").trim().isEmpty ? null : c.idRacao!.trim(),
    );
  }

  Future<void> _onNovoFornecimento() async {
    final trato = await _pickTratoModal();
    if (trato == null) return;

    // abre dashboard no trato escolhido
    _openDashboard(trato: trato, startCleared: true);
  }

  Future<void> _habilitarSyncFiltrados() async {
    if (_loading) return;
    final qtd = _qtdFiltradosSyncHabilitavel;
    if (qtd <= 0) {
      _msg("Nao ha itens filtrados para habilitar sincronizacao.");
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Habilitar sincronizacao"),
        content: Text(
          "Habilitar sincronizacao novamente para $qtd item(ns) filtrado(s)?",
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
        data: _date,
        itens: _items,
      );
      _msg("Sincronizacao habilitada em $alterados registro(s).");
      await _buscar();
    } catch (e) {
      _msg("Erro ao habilitar sincronizacao: $e");
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _syncFiltradosAction() {
    final qtd = _qtdFiltradosSyncHabilitavel;
    final txt = qtd > 99 ? "99+" : "$qtd";

    return IconButton(
      tooltip: "Habilitar sincronizacao dos filtrados ($qtd)",
      onPressed: (_loading || qtd <= 0) ? null : _habilitarSyncFiltrados,
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

  Future<void> _maybeAutoOpenNovoFornecimento() async {
    if (_autoNovoTriggered) return;
    if (!widget.autoOpenNovoFornecimento) return;
    _autoNovoTriggered = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final trato = await _pickTratoModal();
      if (!mounted || trato == null) return;
      _openDashboard(trato: trato, startCleared: true);
    });
  }

  Future<void> _replicarPrevisaoDiaAnterior() async {
    final d = _date;
    final ontem = d.subtract(const Duration(days: 1));

    String ymd(DateTime x) =>
        "${x.year.toString().padLeft(4, "0")}-${x.month.toString().padLeft(2, "0")}-${x.day.toString().padLeft(2, "0")}";

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Replicar previsao"),
        content: Text(
          "Replicar a previsao de ${ymd(ontem)} para ${ymd(d)}?\n\n"
          "A acao so e permitida se o dia destino ainda nao tiver previsao.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text("Cancelar"),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text("Replicar"),
          ),
        ],
      ),
    );

    if (ok != true) return;
    if (!mounted) return;

    setState(() => _loading = true);
    try {
      final res = await widget.repo.replicarPrevisaoDoDiaAnterior(
        dataDestino: d,
        idFazenda: widget.idFazenda,
      );

      switch (res.status) {
        case ReplicarPrevisaoStatus.copiado:
          _msg(
              "Previsao replicada com sucesso (${res.registrosCopiados} registros).");
          break;
        case ReplicarPrevisaoStatus.diaJaPossuiPrevisao:
          _msg("Ja existe previsao para a data selecionada.");
          break;
        case ReplicarPrevisaoStatus.diaAnteriorSemPrevisao:
          _msg("Nao existe previsao no dia anterior para replicar.");
          break;
      }

      await _buscar();
    } catch (e) {
      _msg("Erro ao replicar previsao: $e");
      if (mounted) setState(() => _loading = false);
    }
  }

  // =========================================================
  // UI helpers (os seus, mantidos)
  // =========================================================

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 2),
    );
    if (picked != null) {
      setState(() => _date = picked);
      await _buscar();
    }
  }

  String _fmtDate(DateTime d) {
    String two(int x) => x.toString().padLeft(2, "0");
    return "${two(d.day)}/${two(d.month)}/${d.year}";
  }

  List<int> get _tratoOptions {
    final set = <int>{};
    for (final i in _items) {
      set.add(i.trato);
    }
    final list = set.toList()..sort();
    return list;
  }

  void _openBi() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FornecimentoBiPage(
          idFazenda: widget.idFazenda,
          repo: widget.repo,
          dataInicial: _date,
          tratoInicial: _trato,
        ),
      ),
    );
  }

  List<String> get _linhaOptions {
    final set = <String>{};
    for (final i in _items) {
      final l = _resolveLinha(i).trim();
      if (l.isNotEmpty && l != "-") set.add(l);
    }
    final list = set.toList()..sort();
    return list;
  }

  List<String> get _racaoOptions {
    final set = <String>{};
    for (final i in _items) {
      final r = (i.racao ?? i.idRacao ?? "").trim();
      if (r.isNotEmpty && r != "-") set.add(r);
    }
    final list = set.toList()..sort();
    return list;
  }

  num get _totalPrev => _items.fold<num>(0, (a, b) => a + b.previstoKg);
  num get _totalReal => _items.fold<num>(0, (a, b) => a + b.realizadoKg);
  num get _totalDif => _totalReal - _totalPrev;
  int get _qtdFiltradosSyncHabilitavel {
    final keys = <String>{};
    for (final c in _items) {
      final idFornecimento = (c.idFornecimento ?? "").trim();
      final idBaia = c.idBaia.trim();
      if (idFornecimento.isEmpty || idBaia.isEmpty) continue;
      keys.add("${c.trato}|$idFornecimento|$idBaia");
    }
    return keys.length;
  }

  String _money(num v) => v.toStringAsFixed(2).replaceAll(".", ",");

  String _linhaFromCurral(String? nomeLocal) {
    final s = (nomeLocal ?? "").trim();
    if (s.isEmpty) return "-";
    final compact = s.replaceAll(" ", "");
    final idx = compact.indexOf("-");
    final left = (idx > 0) ? compact.substring(0, idx) : compact;
    final out = left.trim();
    if (out.isEmpty) return "-";
    return out.toUpperCase();
  }

  String _resolveLinha(CurralPrev c) {
    final raw = (c.linha ?? "").toString().trim();
    if (raw.isNotEmpty && raw.toLowerCase() != "null") {
      return raw.toUpperCase();
    }
    return _linhaFromCurral(c.nomeLocal);
  }

  Widget _pill({
    required String title,
    required String value,
    required List<Color> gradient,
  }) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 16,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.center,
              child: Text(
                title,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.visible,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              gradient: LinearGradient(colors: gradient),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                maxLines: 1,
                softWrap: false,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterBarResponsive() {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.10)),
    );

    Widget dataField() {
      return InkWell(
        onTap: _pickDate,
        borderRadius: BorderRadius.circular(10),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: "Data",
            border: border,
            enabledBorder: border,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            suffixIcon: const Icon(Icons.arrow_drop_down),
          ),
          child: Text(_fmtDate(_date)),
        ),
      );
    }

    Widget tracaoField() {
      return DropdownButtonFormField<int?>(
        initialValue: _trato,
        decoration: InputDecoration(
          labelText: "Trato",
          border: border,
          enabledBorder: border,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        items: [
          const DropdownMenuItem<int?>(
            value: null,
            child: Text("Todos"),
          ),
          ..._tratoOptions.map(
            (t) => DropdownMenuItem<int?>(
              value: t,
              child: Text(t.toString()),
            ),
          ),
        ],
        onChanged: (v) => setState(() => _trato = v),
      );
    }

    Widget linhaField() {
      return DropdownButtonFormField<String?>(
        initialValue: _linha,
        decoration: InputDecoration(
          labelText: "Linha",
          border: border,
          enabledBorder: border,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        items: [
          const DropdownMenuItem<String?>(
            value: null,
            child: Text("Todas"),
          ),
          ..._linhaOptions.map(
            (l) => DropdownMenuItem<String?>(
              value: l,
              child: Text(l),
            ),
          ),
        ],
        onChanged: (v) => setState(() => _linha = v),
      );
    }

    Widget racaoField() {
      final current = (_racao ?? "").trim();
      final opts = _racaoOptions;
      final selected = current.isEmpty || !opts.contains(current)
          ? null
          : current;

      return DropdownButtonFormField<String?>(
        initialValue: selected,
        decoration: InputDecoration(
          labelText: "Racao",
          border: border,
          enabledBorder: border,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        items: [
          const DropdownMenuItem<String?>(
            value: null,
            child: Text("Todas"),
          ),
          ...opts.map(
            (r) => DropdownMenuItem<String?>(
              value: r,
              child: Text(r),
            ),
          ),
        ],
        onChanged: (v) => setState(() => _racao = v),
      );
    }

    Widget curralField() {
      return TextField(
        controller: _curralCtrl,
        decoration: InputDecoration(
          labelText: "Curral",
          border: border,
          enabledBorder: border,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        onSubmitted: (_) => _buscar(),
      );
    }

    Widget searchButton() {
      return SizedBox(
        height: 46,
        width: 46,
        child: FilledButton(
          style: FilledButton.styleFrom(
            padding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onPressed: _buscar,
          child: const Icon(Icons.search),
        ),
      );
    }

    return Card(
      elevation: 0,
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.black.withValues(alpha: 0.10)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: LayoutBuilder(
          builder: (context, c) {
            final compact = c.maxWidth < 360;
            return Column(
              children: [
                if (compact) ...[
                  Row(
                    children: [
                      Expanded(flex: 3, child: dataField()),
                      const SizedBox(width: 8),
                      Expanded(flex: 2, child: tracaoField()),
                    ],
                  ),
                  const SizedBox(height: 8),
                  linhaField(),
                ] else ...[
                  Row(
                    children: [
                      Expanded(flex: 4, child: dataField()),
                      const SizedBox(width: 8),
                      Expanded(flex: 2, child: tracaoField()),
                      const SizedBox(width: 8),
                      Expanded(flex: 2, child: linhaField()),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                if (compact) ...[
                  racaoField(),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: curralField()),
                      const SizedBox(width: 8),
                      searchButton(),
                    ],
                  ),
                ] else ...[
                  Row(
                    children: [
                      Expanded(flex: 4, child: racaoField()),
                      const SizedBox(width: 8),
                      Expanded(flex: 4, child: curralField()),
                      const SizedBox(width: 8),
                      searchButton(),
                    ],
                  ),
                ],
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SegmentedButton<_StatusFiltro>(
                      segments: const <ButtonSegment<_StatusFiltro>>[
                        ButtonSegment(
                          value: _StatusFiltro.todos,
                          label: Text("Todos"),
                        ),
                        ButtonSegment(
                          value: _StatusFiltro.realizados,
                          label: Text("Realizados"),
                        ),
                        ButtonSegment(
                          value: _StatusFiltro.pendentes,
                          label: Text("Pendentes"),
                        ),
                      ],
                      selected: <_StatusFiltro>{_status},
                      onSelectionChanged: (set) async {
                        final v = set.first;
                        if (v == _status) return;
                        setState(() => _status = v);
                        await _buscar();
                      },
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _itemCard(CurralPrev c) {
    final racaoTxt = (c.racao ?? c.idRacao ?? "").trim().isEmpty
        ? "-"
        : (c.racao ?? c.idRacao)!.trim();

    final linhaTxt = _resolveLinha(c);

    return InkWell(
      onTap: () => _open(c),
      child: Card(
        elevation: 0,
        margin: const EdgeInsets.symmetric(horizontal: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  const Icon(Icons.local_shipping,
                      size: 34, color: Colors.blueGrey),
                  const SizedBox(height: 6),
                  Icon(Icons.wifi,
                      size: 18, color: Colors.blue.withValues(alpha: 0.75)),
                ],
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Trato: ${c.trato}  Racao: $racaoTxt",
                      style: const TextStyle(fontWeight: FontWeight.w900),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "Curral: ${c.nomeLocal}",
                      style: const TextStyle(fontWeight: FontWeight.w800),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "Linha: $linhaTxt",
                      style: TextStyle(
                          color: Colors.black.withValues(alpha: 0.70)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 136,
                child: Column(
                  children: [
                    Row(
                      children: [
                        _pill(
                          title: "Previsto",
                          value: c.previstoKg.toStringAsFixed(0),
                          gradient: const [
                            Color(0xFF2F6BFF),
                            Color(0xFF0B45D6)
                          ],
                        ),
                        const SizedBox(width: 6),
                        _pill(
                          title: "Realizado",
                          value: c.realizadoKg.toStringAsFixed(0),
                          gradient: const [
                            Color(0xFF19A36B),
                            Color(0xFF0B7D53)
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Icon(
                        c.concluido
                            ? Icons.check_circle
                            : Icons.arrow_forward_ios,
                        size: 18,
                        color: c.concluido
                            ? Colors.green
                            : Colors.black.withValues(alpha: 0.35),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _totaisBar() {
    Widget box(String title, String value) {
      return Expanded(
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.black.withValues(alpha: 0.10)),
            color: Colors.white,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(value,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w900)),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Row(
        children: [
          box("Total Previsto", _money(_totalPrev)),
          const SizedBox(width: 8),
          box("Total Realizado", _money(_totalReal)),
          const SizedBox(width: 8),
          box("Diferenca", _money(_totalDif)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Fornecimento"),
        actions: [
          IconButton(
            tooltip: "Replicar previsao de ontem",
            onPressed: _loading ? null : _replicarPrevisaoDiaAnterior,
            icon: const Icon(Icons.copy_all),
          ),
          _syncFiltradosAction(),
          IconButton(
            tooltip: "Dashboard",
            onPressed: _openBi,
            icon: const Icon(Icons.insights),
          ),
          IconButton(onPressed: _buscar, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(
        children: [
          _filterBarResponsive(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                    ? const Center(
                        child:
                            Text("Sem previsao para os filtros selecionados."))
                    : ListView.separated(
                        padding: const EdgeInsets.only(top: 6, bottom: 6),
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) => _itemCard(_items[i]),
                      ),
          ),
          _totaisBar(),
        ],
      ),
      bottomNavigationBar: SafeArea(
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
                    borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _onNovoFornecimento,
              icon: const Icon(Icons.local_shipping),
              label: const Text(
                "Novo Fornecimento",
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

