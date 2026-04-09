import "package:flutter/material.dart";

import "pages/splash_page.dart";
import "pages/config_page.dart";
import "pages/login_page.dart";
import "pages/menu_page.dart";
import "pages/sync_page.dart";
import "pages/about_page.dart";
import "pages/grava_tag_page.dart";
import "features/estacionario/ui/carregamento_estacionario_page.dart";

// FABRICAÃ‡ÃƒO
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
import "features/dashboard/ui/dashboard_unificado_page.dart";
import "features/dashboard/data/dashboard_unificado_repo.dart";

// âœ… helpers
import "helpers/scale_comm.dart";
import "helpers/rfid_comm.dart";

// âœ… sessÃ£o global
import "services/session_service.dart";

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // âœ… carrega sessÃ£o do SharedPreferences (se tiver)
  await SessionService.instance.restore();

  runApp(const RFeedApp());
}

class RFeedApp extends StatelessWidget {
  const RFeedApp({super.key});

  @override
  Widget build(BuildContext context) {
    const primaryBlue = Color(0xFF25A7CF);
    final theme = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: Colors.white,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryBlue,
        brightness: Brightness.light,
      ).copyWith(
        primary: primaryBlue,
        secondary: primaryBlue,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primaryBlue,
          foregroundColor: Colors.white,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryBlue,
          foregroundColor: Colors.white,
        ),
      ),
    );

    final fabRepo = FabricacaoRepo();
    final fornRepo = FornecimentoRepo();
    final dashRepo = DashboardUnificadoRepo();

    // âœ… singletons de comunicaÃ§Ã£o
    final scale = ScaleComm(
      host: "0.0.0.0",
      port: 0,
      model: ScaleModel.topcom,
      allowNegative: true,
    );

    final rfid = RfidComm(
      host: "0.0.0.0",
      port: 0,
      autoReconnect: true,
      readWatchdog: Duration.zero,
    );

    bool isLogged() =>
        SessionService.instance.userId?.trim().isNotEmpty == true;

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
        "/about": (_) => const AboutPage(),
        "/grava-tag": (_) => const GravaTagPage(),
        "/carregamento-estacionario": (_) =>
            const CarregamentoEstacionarioPage(),
        "/dashboard": (_) => DashboardUnificadoPage(repo: dashRepo),

        // FAB
        "/fabricacao": (_) => FabricacaoListPage(repo: fabRepo),
        "/fabricacao/nova": (_) => FabricacaoPreFabPage(repo: fabRepo),
        "/fabricacao/pesagem": (_) => FabricacaoWeighPage(repo: fabRepo),
      },
      onGenerateRoute: (settings) {
        // âœ… protege fornecimento (e qualquer outra rota que vocÃª quiser)
        bool requireLogin() {
          const protected = {
            "/fornecimento",
            "/fornecimento/pre",
            "/fornecimento/pesagem",
          };
          return protected.contains(settings.name);
        }

        if (requireLogin() && !isLogged()) {
          return MaterialPageRoute(
            builder: (_) => const LoginPage(),
            settings: const RouteSettings(name: "/login"),
          );
        }

        switch (settings.name) {
          case "/fornecimento":
            {
              final args = (settings.arguments as Map?) ?? const {};
              final idFazenda = (args["idFazenda"] ?? "").toString();
              final autoOpenNovoFornecimento =
                  (args["autoOpenNovoFornecimento"] == true);
              final tratoSugerido = (args["tratoSugerido"] as int?);
              return MaterialPageRoute(
                builder: (_) => FornecimentoListPage(
                  idFazenda: idFazenda,
                  // âœ… pega da sessÃ£o global (nÃ£o depende de tabela)
                  idUsuario: SessionService.instance.userId ?? "",
                  repo: fornRepo,
                  scale: scale,
                  rfid: rfid,
                  autoOpenNovoFornecimento: autoOpenNovoFornecimento,
                  tratoSugerido: tratoSugerido,
                ),
                settings: settings,
              );
            }

          case "/fornecimento/pre":
            {
              final args = settings.arguments as Map;

              return MaterialPageRoute(
                builder: (_) => FornecimentoPrePage(
                  curral: args["curral"] as CurralPrev,
                  idFazenda: args["idFazenda"] as String,
                  idUsuario: SessionService.instance.userId ?? "",
                  repo: fornRepo,
                  scale: scale,
                  rfid: rfid,
                ),
                settings: settings,
              );
            }

          case "/fornecimento/pesagem":
            {
              final args = settings.arguments as Map;

              return MaterialPageRoute(
                builder: (_) => FornecimentoWeighPage(
                  curral: args["curral"] as CurralPrev,
                  idFazenda: args["idFazenda"] as String,
                  idUsuario: SessionService.instance.userId ?? "",
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
