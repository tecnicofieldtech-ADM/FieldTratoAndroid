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
      appBar: AppBar(title: Text(editing ? "Editar Caminhão" : "Novo Caminhão")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _nome,
                decoration: const InputDecoration(labelText: "Nome do espelhamento"),
                validator: (v) => (v ?? "").trim().isEmpty ? "Informe o nome" : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _host,
                decoration: const InputDecoration(labelText: "IP do caminhão (ex: 10.10.100.101)"),
                keyboardType: TextInputType.number,
                validator: (v) => (v ?? "").trim().isEmpty ? "Informe o IP" : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _porta,
                decoration: const InputDecoration(labelText: "Porta (padrão 9000)"),
                keyboardType: TextInputType.number,
                validator: (v) {
                  final n = int.tryParse((v ?? "").trim());
                  if (n == null || n <= 0 || n > 65535) return "Porta inválida";
                  return null;
                },
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save),
                  label: Text(_saving ? "Salvando…" : "Salvar"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
