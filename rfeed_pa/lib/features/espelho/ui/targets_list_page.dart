import "package:flutter/material.dart";
import "package:package_info_plus/package_info_plus.dart";
import "package:shared_preferences/shared_preferences.dart";
import "../controller/pa_server_controller.dart";
import "../data/mirror_targets_repo.dart";
import "../domain/mirror_target.dart";
import "target_form_page.dart";

class TargetsListPage extends StatefulWidget {
  const TargetsListPage({
    super.key,
    required this.repo,
    required this.server,
    this.onSelected,
    this.autoPopOnSelect = false,
  });

  final MirrorTargetsRepo repo;
  final PaServerController server;
  final ValueChanged<MirrorTarget>? onSelected;
  final bool autoPopOnSelect;

  @override
  State<TargetsListPage> createState() => _TargetsListPageState();
}

class _TargetsListPageState extends State<TargetsListPage> {
  static const String _styleRfeed = "rfeed";
  static const String _styleMbTratos = "mbtratos";
  static const String _stylePrefKey = "pa_style_mode";

  bool _loading = true;
  List<MirrorTarget> _items = const [];
  String _versionLabel = "--";
  String _styleMode = _styleRfeed;

  @override
  void initState() {
    super.initState();
    // ignore: discarded_futures
    _loadVersion();
    // ignore: discarded_futures
    _loadStyleMode();
    _load();
  }

  Future<void> _loadVersion() async {
    try {
      final p = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _versionLabel = "${p.version}+${p.buildNumber}");
    } catch (_) {
      if (!mounted) return;
      setState(() => _versionLabel = "--");
    }
  }

  Future<void> _loadStyleMode() async {
    try {
      final pref = await SharedPreferences.getInstance();
      final mode = (pref.getString(_stylePrefKey) ?? _styleRfeed).trim();
      if (!mounted) return;
      setState(() {
        _styleMode = (mode == _styleMbTratos) ? _styleMbTratos : _styleRfeed;
      });
    } catch (_) {}
  }

  Future<void> _saveStyleMode(String mode) async {
    final next = (mode == _styleMbTratos) ? _styleMbTratos : _styleRfeed;
    setState(() => _styleMode = next);
    try {
      final pref = await SharedPreferences.getInstance();
      await pref.setString(_stylePrefKey, next);
    } catch (_) {}
  }

  Future<void> _openStylePicker() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) {
        final current = _styleMode;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                title: Text(
                  "Estilo visual",
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              ListTile(
                leading: Icon(
                  current == _styleRfeed
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                ),
                title: const Text("RFeed"),
                subtitle: const Text("Mantem o visual atual"),
                onTap: () => Navigator.of(ctx).pop(_styleRfeed),
              ),
              ListTile(
                leading: Icon(
                  current == _styleMbTratos
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                ),
                title: const Text("MBTratos"),
                subtitle: const Text("Paleta verde + botoes turquesa"),
                onTap: () => Navigator.of(ctx).pop(_styleMbTratos),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (selected == null) return;
    await _saveStyleMode(selected);
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);

    try {
      final items = await widget.repo.listAll();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _add() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TargetFormPage(repo: widget.repo),
      ),
    );

    await widget.server.loadActive();
    await _load();
  }

  Future<void> _edit(MirrorTarget t) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TargetFormPage(repo: widget.repo, existing: t),
      ),
    );

    await widget.server.loadActive();
    await _load();
  }

  Future<void> _delete(MirrorTarget t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Excluir"),
        content: Text("Excluir '${t.nome}'?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancelar"),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Excluir"),
          ),
        ],
      ),
    );

    if (ok != true) return;

    await widget.repo.remove(t.id);

    await widget.server.loadActive();
    await _load();
  }

  Future<void> _setActive(MirrorTarget t) async {
    await widget.server.setActiveTargetById(t.id);

    await widget.server.loadActive();
    await _load();

    widget.onSelected?.call(t);
    if (widget.autoPopOnSelect && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Vagoes (Espelhamento)  v$_versionLabel"),
        actions: [
          IconButton(
            onPressed: _openStylePicker,
            tooltip: "Estilo visual",
            icon: const Icon(Icons.palette_outlined),
          ),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
          IconButton(onPressed: _add, icon: const Icon(Icons.add)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.directions_bus_filled_outlined, size: 48),
                        const SizedBox(height: 10),
                        const Text("Nenhum vagao cadastrado."),
                        const SizedBox(height: 10),
                        FilledButton.icon(
                          onPressed: _add,
                          icon: const Icon(Icons.add),
                          label: const Text("Cadastrar"),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final t = _items[i];
                    return ListTile(
                      leading: Icon(
                        t.ativo ? Icons.check_circle : Icons.circle_outlined,
                        color: t.ativo ? Colors.green : Colors.grey,
                      ),
                      title: Text(
                        t.nome,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text("IP: ${t.host}:${t.porta}"),
                      onTap: () => _setActive(t),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: "Editar",
                            onPressed: () => _edit(t),
                            icon: const Icon(Icons.edit),
                          ),
                          IconButton(
                            tooltip: "Excluir",
                            onPressed: () => _delete(t),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}


