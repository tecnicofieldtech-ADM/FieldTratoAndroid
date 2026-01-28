// lib/features/fornecimento/ui/fornecimento_pre_page.dart
import "package:flutter/material.dart";

import "../data/fornecimento_repo.dart";
import "../domain/fornecimento_models.dart";
import "../services/scale_tcp_service.dart";
import "../services/rfid_tcp_service.dart";
import "fornecimento_weigh_page.dart";

class FornecimentoPrePage extends StatelessWidget {
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
  final ScaleTcpService scale;
  final RfidTcpService rfid;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Pré-Fornecimento")),
      body: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _kv("Curral", curral.nomeLocal),
            _kv("Linha", curral.linha),
            _kv("Trato", curral.trato.toString()),
            _kv("Previsto (kg)", curral.previstoKg.toStringAsFixed(0)),
            _kv("Realizado (kg)", curral.realizadoKg.toStringAsFixed(0)),
            _kv("Falta (kg)", curral.faltaKg.toStringAsFixed(0)),
            const Spacer(),
            FilledButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => FornecimentoWeighPage(
                      curral: curral,
                      idFazenda: idFazenda,
                      idUsuario: idUsuario,
                      repo: repo,
                      scale: scale,
                      rfid: rfid,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.scale),
              label: const Text("Iniciar pesagem"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(child: Text(k, style: const TextStyle(fontWeight: FontWeight.w700))),
            Text(v),
          ],
        ),
      );
}
