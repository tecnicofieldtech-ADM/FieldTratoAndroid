// lib/main.dart
import "package:flutter/material.dart";

import "pages/splash_page.dart";
import "pages/config_page.dart";
import "pages/login_page.dart";
import "pages/menu_page.dart";
import "pages/sync_page.dart";

// FABRICAÇÃO
import "features/fabricacao/ui/fabricacao_prefab_page.dart";
import "features/fabricacao/ui/fabricacao_weigh_page.dart";
import "features/fabricacao/ui/fabricacao_list_page.dart";
import "features/fabricacao/data/fabricacao_repo.dart";

// FORNECIMENTO
import "features/fornecimento/ui/fornecimento_list_page.dart";
import "features/fornecimento/ui/fornecimento_pre_page.dart";
import "features/fornecimento/ui/fornecimento_weigh_page.dart";
import "features/fornecimento/domain/fornecimento_models.dart";
import "features/fornecimento/data/fornecimento_repo.dart";
import "features/fornecimento/services/scale_tcp_service.dart";
import "features/fornecimento/services/rfid_tcp_service.dart";

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RFeedApp());
}

class RFeedApp extends StatelessWidget {
  const RFeedApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: Colors.white,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF0F766E),
        brightness: Brightness.light,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
    );

    final fabRepo = FabricacaoRepo();

    // ✅ singletons fornecimento
    final fornRepo = FornecimentoRepo();
    final scale = ScaleTcpService();
    final rfid = RfidTcpService();

    // ✅ coloque aqui de onde você pega o usuário logado (por enquanto vazio compila)
    const String idUsuario = "";

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: "RFeed",
      theme: theme,
      initialRoute: "/",
      routes: {
        "/": (_) => const SplashPage(),
        "/config": (_) => const ConfigPage(),
        "/login": (_) => const LoginPage(),
        "/menu": (_) => const MenuPage(),
        "/sync": (_) => const SyncPage(),

        // FAB
        "/fabricacao": (_) => FabricacaoListPage(repo: fabRepo),
        "/fabricacao/nova": (_) => FabricacaoPreFabPage(repo: fabRepo),
        "/fabricacao/pesagem": (_) => FabricacaoWeighPage(repo: fabRepo),
      },
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case "/fornecimento": {
            final args = (settings.arguments as Map?) ?? const {};
            final idFazenda = (args["idFazenda"] ?? "").toString();

            return MaterialPageRoute(
              builder: (_) => FornecimentoListPage(
                idFazenda: idFazenda,
                idUsuario: idUsuario,
                repo: fornRepo,
                scale: scale,
                rfid: rfid,
              ),
              settings: settings,
            );
          }

          case "/fornecimento/pre": {
            final args = settings.arguments as Map;
            return MaterialPageRoute(
              builder: (_) => FornecimentoPrePage(
                curral: args["curral"] as CurralPrev,
                idFazenda: args["idFazenda"] as String,
                idUsuario: idUsuario,
                repo: fornRepo,
                scale: scale,
                rfid: rfid,
              ),
              settings: settings,
            );
          }

          case "/fornecimento/pesagem": {
            final args = settings.arguments as Map;
            return MaterialPageRoute(
              builder: (_) => FornecimentoWeighPage(
                curral: args["curral"] as CurralPrev,
                idFazenda: args["idFazenda"] as String,
                idUsuario: idUsuario,
                repo: fornRepo,
                scale: scale,
                rfid: rfid,
              ),
              settings: settings,
            );
          }
        }
        return null;
      },
    );
  }
}
