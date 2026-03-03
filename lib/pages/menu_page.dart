// lib/pages/menu_page.dart
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "../repo/config_repo.dart";
import "../services/carregamento_bridge.dart";
import "../widgets/app_logo.dart";

class MenuPage extends StatefulWidget {
  const MenuPage({super.key});

  @override
  State<MenuPage> createState() => _MenuPageState();
}

class _MenuPageState extends State<MenuPage> {
  final _cfgRepo = ConfigRepo();

  int? _tipoTrabalho;

  @override
  void initState() {
    super.initState();
    _loadTipoTrabalho();
  }

  Future<void> _loadTipoTrabalho() async {
    try {
      final t = await _cfgRepo.getTipoTrabalho();
      debugPrint("[MENU] tipoTrabalho=$t");
      if (t == 1) {
        final port = await _cfgRepo.getPortaEstacionario();
        debugPrint("[MENU] tentando ligar bridge na porta $port");
        await CarregamentoBridgeServer.instance.start(port: port);
      } else {
        debugPrint("[MENU] tipo != estacionario, desligando bridge");
        await CarregamentoBridgeServer.instance.stop();
      }
      if (!mounted) return;
      setState(() => _tipoTrabalho = t);
    } catch (e, st) {
      debugPrint("[MENU] erro ao iniciar/parar bridge: $e");
      debugPrint("$st");
      // deixa null para nao bloquear menus se config falhar
    }
  }
  void _go(BuildContext context, String route) {
    Navigator.pushNamed(context, route);
  }

  static void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    const padding = 18.0;
    const gap = 12.0;

    // â ajuste pro seu caminho real
    const bgAsset = "assets/images/bg_boi_tech.png";

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // FUNDO ocupa 100%
          Image.asset(
            bgAsset,
            fit: BoxFit.cover,
            alignment: Alignment.center,
            errorBuilder: (_, __, ___) => const SizedBox.expand(),
          ),

          // leve âwashâ para a logo e botÃµes destacarem
          Container(color: Colors.white.withValues(alpha: 0.50)),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(padding),
              child: LayoutBuilder(
                builder: (context, c) {
                  final w = c.maxWidth;

                  // 2 colunas fixas
                  final tileW = (w - gap) / 2;

                  // â altura um pouco maior (antes ~56-70)
                  final tileH = (w * 0.18).clamp(66.0, 86.0);

                  final t = _tipoTrabalho;
                  final podeFabricar = (t == null) || t == 0 || t == 1 || t == 2;
                  final podeFornecer = (t == null) || t == 0 || t == 2;
                  final podeCarregamento = t == 2;

                  return Column(
                    children: [
                      if (t == 1) ...[
                        ValueListenableBuilder<String>(
                          valueListenable:
                              CarregamentoBridgeServer.instance.statusText,
                          builder: (_, v, __) {
                            return Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.80),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.15),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.link,
                                      color: Colors.white, size: 18),
                                  const SizedBox(width: 8),
                                  const Text(
                                    "Bridge:",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      v,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color:
                                            Colors.white.withValues(alpha: 0.9),
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 10),
                      ],

                      // ConteÃºdo scrollÃ¡vel
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            children: [
                              const SizedBox(height: 6),

                              // LOGO grande
                              ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxHeight: 260),
                                child:
                                    const Center(child: AppLogo(height: 230)),
                              ),

                              const SizedBox(height: 14),

                              // ===== LINHA 1 =====
                              Row(
                                children: [
                                  SizedBox(
                                    width: tileW,
                                    height: tileH,
                                    child: _Tile(
                                      icon: Icons.settings,
                                      title: "Configuração",
                                      bg: Colors.black.withValues(alpha: 0.80),
                                      fg: Colors.white,
                                      onTap: () =>
                                          Navigator.pushReplacementNamed(
                                              context, "/config"),
                                    ),
                                  ),
                                  const SizedBox(width: gap),
                                  SizedBox(
                                    width: tileW,
                                    height: tileH,
                                    child: _Tile(
                                      icon: Icons.sync,
                                      title: "Sincronização",
                                      bg: Colors.black.withValues(alpha: 0.80),
                                      fg: Colors.white,
                                      onTap: () => _go(context, "/sync"),
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: gap),

                              // ===== LINHA 2 =====
                              Row(
                                children: [
                                  SizedBox(
                                    width: tileW,
                                    height: tileH,
                                    child: _Tile(
                                      icon: Icons.precision_manufacturing,
                                      title: "Fabricação",
                                      bg: Colors.black.withValues(alpha: 0.80),
                                      fg: Colors.white,
                                      enabled: podeFabricar,
                                      onTap: () => _go(context, "/fabricacao"),
                                      onDisabledTap: () => _toast(
                                        context,
                                        "Modo Distribuidor: Fabricação desabilitada.",
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: gap),
                                  SizedBox(
                                    width: tileW,
                                    height: tileH,
                                    child: _Tile(
                                      icon: Icons.local_shipping,
                                      title: "Fornecimento",
                                      bg: Colors.black.withValues(alpha: 0.80),
                                      fg: Colors.white,
                                      enabled: podeFornecer,
                                      onTap: () =>
                                          _go(context, "/fornecimento"),
                                      onDisabledTap: () => _toast(
                                        context,
                                        "Modo Estacionário: Fornecimento desabilitado.",
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: gap),

                              // ===== LINHA 3 =====
                              Row(
                                children: [
                                  SizedBox(
                                    width: tileW,
                                    height: tileH,
                                    child: _Tile(
                                      icon: Icons.download_for_offline_outlined,
                                      title: "Carregamento",
                                      bg: Colors.black.withValues(alpha: 0.80),
                                      fg: Colors.white,
                                      enabled: podeCarregamento,
                                      onTap: () => _go(
                                        context,
                                        "/carregamento-estacionario",
                                      ),
                                      onDisabledTap: () => _toast(
                                        context,
                                        "Modo Estacionario: funcao exclusiva do distribuidor.",
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: gap),
                                  SizedBox(
                                    width: tileW,
                                    height: tileH,
                                    child: _Tile(
                                      icon: Icons.dashboard_outlined,
                                      title: "Dashboard",
                                      bg: Colors.black.withValues(alpha: 0.80),
                                      fg: Colors.white,
                                      onTap: () => _go(context, "/dashboard"),
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: gap),

                              // ===== LINHA 4 =====
                              Row(
                                children: [
                                  SizedBox(
                                    width: tileW,
                                    height: tileH,
                                    child: _Tile(
                                      icon: Icons.nfc,
                                      title: "Gravar TAG",
                                      bg: Colors.black.withValues(alpha: 0.80),
                                      fg: Colors.white,
                                      onTap: () => _go(context, "/grava-tag"),
                                    ),
                                  ),
                                  const SizedBox(width: gap),
                                  SizedBox(
                                    width: tileW,
                                    height: tileH,
                                    child: const SizedBox.shrink(),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 18),
                            ],
                          ),
                        ),
                      ),

                      // â SAIR NO RODAPÃ (fixo)
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            side: BorderSide(
                              color: Colors.black.withValues(alpha: 0.35),
                            ),
                            foregroundColor: Colors.black87,
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.9),
                          ),
                          onPressed: () => _go(context, "/about"),
                          icon: const Icon(Icons.info_outline),
                          label: const Text(
                            "Sobre o app",
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.red.shade700,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          onPressed: () =>
                              Navigator.pushReplacementNamed(context, "/login"),
                          icon: const Icon(Icons.logout),
                          label: const Text(
                            "Sair",
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color bg;
  final Color fg;
  final VoidCallback onTap;
  final bool enabled;
  final VoidCallback? onDisabledTap;

  const _Tile({
    required this.icon,
    required this.title,
    required this.bg,
    required this.fg,
    required this.onTap,
    this.enabled = true,
    this.onDisabledTap,
  });

  @override
  Widget build(BuildContext context) {
    final canTap = enabled;
    final bgFinal = canTap ? bg : Colors.grey.shade400;
    final fgFinal = canTap ? fg : Colors.black54;
    final borderColor = canTap
        ? Colors.white.withValues(alpha: 0.15)
        : Colors.black.withValues(alpha: 0.10);

    return InkWell(
      onTap: canTap ? onTap : onDisabledTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: bgFinal,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
        ),
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        child: Column(
          children: [
            Align(
              alignment: Alignment.topCenter,
              child: Icon(icon, size: 28, color: fgFinal),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: fgFinal,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    height: 1.05,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

