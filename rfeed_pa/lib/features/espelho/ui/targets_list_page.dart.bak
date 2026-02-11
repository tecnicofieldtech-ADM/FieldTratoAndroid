import "package:flutter/material.dart";
import "../controller/pa_server_controller.dart";
import "../data/mirror_targets_repo.dart";
import "../domain/mirror_target.dart";
import "target_form_page.dart";

class TargetsListPage extends StatefulWidget {
  const TargetsListPage({super.key, required this.repo, required this.server});
  final MirrorTargetsRepo repo;
  final PaServerController server;

  @override
  State<TargetsListPage> createState() => _TargetsListPageState();
}

class _TargetsListPageState extends State<TargetsListPage> {
  bool _loading = true;
  List<MirrorTarget> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
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

    // recarrega lista e alvo ativo
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

    // atualiza estado + lista (t.ativo muda)
    await widget.server.loadActive();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Caminhões (Espelhamento)"),
        actions: [
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
                        const Text("Nenhum caminhão cadastrado."),
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
                  separatorBuilder: (_, separatorIndex) => const Divider(height: 1),
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
