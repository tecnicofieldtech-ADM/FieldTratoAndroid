// lib/features/fornecimento/ui/fornecimento_list_page.dart
import "package:flutter/material.dart";

import "../data/fornecimento_repo.dart";
import "../domain/fornecimento_models.dart";
import "../services/scale_tcp_service.dart";
import "../services/rfid_tcp_service.dart";
import "fornecimento_pre_page.dart";

class FornecimentoListPage extends StatefulWidget {
  const FornecimentoListPage({
    super.key,
    required this.idFazenda,
    required this.idUsuario,
    required this.repo,
    required this.scale,
    required this.rfid,
  });

  final String idFazenda;
  final String idUsuario;
  final FornecimentoRepo repo;
  final ScaleTcpService scale;
  final RfidTcpService rfid;

  @override
  State<FornecimentoListPage> createState() => _FornecimentoListPageState();
}

class _FornecimentoListPageState extends State<FornecimentoListPage> {
  bool _loading = true;
  List<CurralPrev> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await widget.repo.listCurraisPrevistosHoje(
        idFazenda: widget.idFazenda,
      );
      setState(() => _items = list);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _open(CurralPrev c) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FornecimentoPrePage(
          curral: c,
          idFazenda: widget.idFazenda,
          idUsuario: widget.idUsuario,
          repo: widget.repo,
          scale: widget.scale,
          rfid: widget.rfid,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Fornecimento"),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const Center(child: Text("Sem previsão para hoje."))
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final c = _items[i];
                    return ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(color: Colors.black.withOpacity(0.06)),
                      ),
                      title: Text("${c.nomeLocal}  •  Linha ${c.linha}"),
                      subtitle: Text(
                        "Prev: ${c.previstoKg.toStringAsFixed(0)} kg  |  Real: ${c.realizadoKg.toStringAsFixed(0)} kg  |  Falta: ${c.faltaKg.toStringAsFixed(0)} kg",
                      ),
                      trailing: Icon(
                        c.concluido ? Icons.check_circle : Icons.arrow_forward_ios,
                        size: 18,
                        color: c.concluido ? Colors.green : null,
                      ),
                      onTap: () => _open(c),
                    );
                  },
                ),
    );
  }
}
