import "package:flutter/material.dart";
import "package:package_info_plus/package_info_plus.dart";

import "../widgets/app_logo.dart";

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  Future<String> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    return "${info.version}+${info.buildNumber}";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Sobre o app")),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              const Center(child: AppLogo(height: 140)),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: FutureBuilder<String>(
                    future: _loadVersion(),
                    builder: (context, snapshot) {
                      final version = snapshot.data ?? "Carregando...";
                      return Row(
                        children: [
                          const Icon(Icons.info_outline),
                          const SizedBox(width: 10),
                          Text(
                            "Versao atual: $version",
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    "O RFeed e um aplicativo para apoiar a operacao de "
                    "fabricacao, fornecimento e sincronizacao de dados no "
                    "campo, com foco em agilidade, controle e confiabilidade.",
                    style: TextStyle(fontSize: 15, height: 1.45),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
