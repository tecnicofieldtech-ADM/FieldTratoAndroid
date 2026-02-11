import "package:flutter/material.dart";

import "../repo/config_repo.dart";
import "../repo/user_repo.dart";
import "../widgets/app_logo.dart";
import "../services/session_service.dart"; // ✅ NOVO

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  final _cfgRepo = ConfigRepo();
  final _userRepo = UserRepo();

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // pequena pausa para mostrar a splash
    await Future.delayed(const Duration(milliseconds: 800));

    // 1) carrega config (se existir)
    await _cfgRepo.getConfig();

    // 2) restaura sessão (SharedPreferences)
    await SessionService.instance.restore();

    if (!mounted) return;

    // ✅ se já tem sessão, vai direto pro menu
    if (SessionService.instance.isLogged) {
      Navigator.pushReplacementNamed(context, "/menu");
      return;
    }

    // 3) checa usuários no SQLite (pra decidir config vs login)
    final hasUser = await _userRepo.hasAnyUser();

    if (!mounted) return;

    // primeiro acesso => vai direto para Configuração
    if (!hasUser) {
      Navigator.pushReplacementNamed(context, "/config");
      return;
    }

    // já existe usuário => Login
    Navigator.pushReplacementNamed(context, "/login");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            AppLogo(height: 160),
            SizedBox(height: 24),
            CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
