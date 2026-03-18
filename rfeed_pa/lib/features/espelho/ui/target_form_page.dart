import "package:flutter/material.dart";
import "../data/mirror_targets_repo.dart";
import "../domain/mirror_target.dart";

class TargetFormPage extends StatefulWidget {
  const TargetFormPage({super.key, required this.repo, this.existing});
  final MirrorTargetsRepo repo;
  final MirrorTarget? existing;

  @override
  State<TargetFormPage> createState() => _TargetFormPageState();
}

class _TargetFormPageState extends State<TargetFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _nome = TextEditingController();
  final _host = TextEditingController();
  final _porta = TextEditingController(text: "9000");
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _nome.text = e.nome;
      _host.text = e.host;
      _porta.text = e.porta.toString();
    }
  }

  @override
  void dispose() {
    _nome.dispose();
    _host.dispose();
    _porta.dispose();
    super.dispose();
  }

  int _parsePort() {
    final n = int.tryParse(_porta.text.trim()) ?? 9000;
    return n <= 0 ? 9000 : n;
  }

  bool _isValidIpv4(String ip) {
    final s = ip.trim();
    if (s.isEmpty) return false;

    final parts = s.split(".");
    if (parts.length != 4) return false;

    for (final p in parts) {
      if (p.isEmpty) return false;
      final n = int.tryParse(p);
      if (n == null || n < 0 || n > 255) return false;
      if (p.length > 1 && p.startsWith("0")) return false;
    }

    return true;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      final porta = _parsePort();

      if (widget.existing == null) {
        await widget.repo.insert(
          nome: _nome.text.trim(),
          host: _host.text.trim(),
          porta: porta,
        );
      } else {
        await widget.repo.update(
          id: widget.existing!.id,
          nome: _nome.text.trim(),
          host: _host.text.trim(),
          porta: porta,
        );
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;

    return Scaffold(
      appBar: AppBar(title: Text(editing ? "Editar Vagao" : "Novo Vagao")),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nome,
              decoration: const InputDecoration(labelText: "Nome do Vagao"),
              validator: (v) => (v ?? "").trim().isEmpty ? "Informe o nome" : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _host,
              decoration: const InputDecoration(
                labelText: "IP do Vagao (ex: 10.10.100.101)",
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (v) {
                final ip = (v ?? "").trim();
                if (ip.isEmpty) return "Informe o IP";
                if (!_isValidIpv4(ip)) {
                  return "IP invalido (ex: 10.10.100.101)";
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _porta,
              decoration: const InputDecoration(labelText: "Porta (padrao 9000)"),
              keyboardType: TextInputType.number,
              validator: (v) {
                final n = int.tryParse((v ?? "").trim());
                if (n == null || n <= 0 || n > 65535) return "Porta invalida";
                return null;
              },
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: SizedBox(
          height: 50,
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save),
            label: Text(_saving ? "Cadastrando Vagao..." : "Cadastrar Vagao"),
          ),
        ),
      ),
    );
  }
}


