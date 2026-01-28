// lib/features/fornecimento/ui/fornecimento_weigh_page.dart
import "package:flutter/material.dart";

import "../controller/fornecimento_controller.dart";
import "../data/fornecimento_repo.dart";
import "../domain/fornecimento_models.dart";
import "../services/scale_tcp_service.dart";
import "../services/rfid_tcp_service.dart";

class FornecimentoWeighPage extends StatefulWidget {
  const FornecimentoWeighPage({
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
  final ScaleTcpService scale;
  final RfidTcpService rfid;

  @override
  State<FornecimentoWeighPage> createState() => _FornecimentoWeighPageState();
}

class _FornecimentoWeighPageState extends State<FornecimentoWeighPage> {
  late final FornecimentoController c;

  @override
  void initState() {
    super.initState();
    c = FornecimentoController(
      repo: widget.repo,
      scale: widget.scale,
      rfid: widget.rfid,
      idUsuario: widget.idUsuario,
    )..addListener(_on);

    // init lista + conexões (carrega currais do dia)
    // ignore: unawaited_futures
    c.init(idFazenda: widget.idFazenda);

    // tenta já posicionar no curral que veio da lista
    // ignore: unawaited_futures
    c.goToFornecimento(widget.curral.idFornecimento);
  }

  void _on() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    c.removeListener(_on);
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final atual = c.atual ?? widget.curral;

    return Scaffold(
      appBar: AppBar(title: const Text("Pesagem")),
      body: c.loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    "${atual.nomeLocal}  •  Linha ${atual.linha}",
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  _box("Peso atual (kg)", c.pesoAtual.toStringAsFixed(1)),
                  const SizedBox(height: 10),
                  _box("Previsto (kg)", atual.previstoKg.toStringAsFixed(0)),
                  _box("Realizado (kg)", atual.realizadoKg.toStringAsFixed(0)),
                  _box("Falta (kg)", atual.faltaKg.toStringAsFixed(0)),
                  const Spacer(),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: c.prev,
                          icon: const Icon(Icons.chevron_left),
                          label: const Text("Anterior"),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: c.next,
                          icon: const Icon(Icons.chevron_right),
                          label: const Text("Próximo"),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  Widget _box(String k, String v) {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withOpacity(0.07)),
      ),
      child: Row(
        children: [
          Expanded(child: Text(k, style: const TextStyle(fontWeight: FontWeight.w800))),
          Text(v, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}
