// lib/pages/menu_page.dart
import "dart:async";

import "package:flutter/material.dart";
import "package:network_info_plus/network_info_plus.dart";
import "package:permission_handler/permission_handler.dart";
import "../repo/config_repo.dart";
import "../repo/last_login_repo.dart";
import "../services/session_service.dart";
import "../services/carregamento_bridge.dart";
import "../services/wifi_guard.dart";
import "../widgets/app_logo.dart";
import "../widgets/app_version_label.dart";

class MenuPage extends StatefulWidget {
  const MenuPage({super.key});

  @override
  State<MenuPage> createState() => _MenuPageState();
}

class _MenuPageState extends State<MenuPage> {
  final _cfgRepo = ConfigRepo();
  final _netInfo = NetworkInfo();

  int? _tipoTrabalho;
  bool _modoHibrido = false;
  String _wifiIp = "--";
  Timer? _ipTimer;

  @override
  void initState() {
    super.initState();
    _loadTipoTrabalho();
    _refreshWifiIp();
    _ipTimer = Timer.periodic(
      const Duration(seconds: 8),
      (_) => _refreshWifiIp(),
    );
  }

  @override
  void dispose() {
    _ipTimer?.cancel();
    super.dispose();
  }

  @override
  void activate() {
    super.activate();
    _loadTipoTrabalho();
  }

  Future<void> _refreshWifiIp() async {
    try {
      final ip = (await _netInfo.getWifiIP())?.trim() ?? "";
      if (!mounted) return;
      setState(() => _wifiIp = ip.isEmpty ? "--" : ip);
    } catch (_) {
      if (!mounted) return;
      setState(() => _wifiIp = "--");
    }
  }

  Future<void> _loadTipoTrabalho() async {
    try {
      final t = await _cfgRepo.getTipoTrabalho();
      final hibrido = await _cfgRepo.getModoHibrido();
      debugPrint("[MENU] tipoTrabalho=$t modoHibrido=$hibrido");
      if (t == 1) {
        final port = await _cfgRepo.getPortaEstacionario();
        debugPrint("[MENU] tentando ligar bridge na porta $port");
        await CarregamentoBridgeServer.instance.start(port: port);
      } else {
        debugPrint("[MENU] tipo != estacionario, desligando bridge");
        await CarregamentoBridgeServer.instance.stop();
      }
      if (!mounted) return;
      setState(() {
        _tipoTrabalho = t;
        _modoHibrido = hibrido;
      });
    } catch (e, st) {
      debugPrint("[MENU] erro ao iniciar/parar bridge: $e");
      debugPrint("$st");
      // deixa null para nao bloquear menus se config falhar
    }
  }
  Future<void> _go(BuildContext context, String route) async {
    final syncRoute = route == "/sync";
    final rfeedRequiredRoutes = {
      "/fabricacao",
      "/fornecimento",
      "/grava-tag",
    };
    final needsWifiPermission = syncRoute || rfeedRequiredRoutes.contains(route);

    if (needsWifiPermission) {
      final granted = await WifiGuard.requestLocationPermissionIfNeeded();
      if (!mounted) return;
      if (!granted) {
        final abrir = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text("Permissao necessaria"),
            content: const Text(
              "Para verificar o nome da rede Wi-Fi, permita a Localizacao do app nas configuracoes.",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text("Cancelar"),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text("Abrir permissoes"),
              ),
            ],
          ),
        ) ?? false;
        if (abrir) {
          await openAppSettings();
        }
        return;
      }
    }

    if (syncRoute) {
      final ssid = await WifiGuard.getCurrentSsid();
      if (!mounted) return;
      if (ssid.isEmpty) {
        final locOn = await WifiGuard.isLocationServiceEnabled();
        if (!mounted) return;
        if (!locOn) {
          final abrirLoc = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text("Ative a Localizacao"),
                  content: const Text(
                    "Permissao concedida, mas a Localizacao do aparelho esta desligada.\n\n"
                    "Ative a Localizacao para o app conseguir ler o nome da rede Wi-Fi.",
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text("Cancelar"),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text("Abrir localizacao"),
                    ),
                  ],
                ),
              ) ??
              false;

          if (abrirLoc) {
            await WifiGuard.openLocationSettings();
          }
          return;
        }
      }
      if (WifiGuard.isRFeedSsid(ssid)) {
        final trocar = await showDialog<bool>(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text("Rede para sincronizacao"),
                content: Text(
                  "Rede atual: ${ssid.isEmpty ? "RFeed" : ssid}.\n\n"
                  "Para sincronizar, conecte no Wi-Fi do servidor da fazenda (nao RFeed*).",
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text("Voltar"),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text("Abrir Wi-Fi"),
                  ),
                ],
              ),
            ) ??
            false;

        if (!mounted) return;
        if (trocar) {
          await WifiGuard.openWifiSelector();
          return;
        }
      }
    }

    if (rfeedRequiredRoutes.contains(route)) {
      final ssid = await WifiGuard.getCurrentSsid();
      if (!mounted) return;
      if (ssid.isEmpty) {
        final locOn = await WifiGuard.isLocationServiceEnabled();
        if (!mounted) return;
        if (!locOn) {
          final abrirLoc = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text("Ative a Localizacao"),
                  content: const Text(
                    "Permissao concedida, mas a Localizacao do aparelho esta desligada.\n\n"
                    "Ative a Localizacao para o app conseguir ler o nome da rede Wi-Fi.",
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text("Cancelar"),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text("Abrir localizacao"),
                    ),
                  ],
                ),
              ) ??
              false;

          if (abrirLoc) {
            await WifiGuard.openLocationSettings();
          }
          return;
        }
      }

      if (!WifiGuard.isRFeedSsid(ssid)) {
        final trocar = await showDialog<bool>(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text("Rede para operacao"),
                content: Text(
                  "Para operar Fabricacao, Fornecimento e Gravar TAG, conecte em uma rede RFeed*.\n\n"
                  "Rede atual: ${ssid.isEmpty ? "nao identificada" : ssid}",
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text("Continuar"),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text("Abrir Wi-Fi"),
                  ),
                ],
              ),
            ) ??
            false;

        if (!mounted) return;
        if (trocar) {
          await WifiGuard.openWifiSelector();
          return;
        }
      }
    }

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
                  final hibrido = _modoHibrido;
                  final podeFabricar = (t == null) || t == 0 || t == 1 || t == 2;
                  final podeFornecer = (t == null) || t == 0 || t == 2;
                  final podeCarregamento = t == 2 || (t == 1 && hibrido);

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

                              const SizedBox(height: 6),
                              const AppVersionLabel(),
                              const SizedBox(height: 10),

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
                      const SizedBox(height: 6),
                      Text(
                        "IP da rede: $_wifiIp",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.black.withValues(alpha: 0.75),
                          fontWeight: FontWeight.w700,
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
                          onPressed: () async {
                            final user = SessionService.instance.current;
                            if (user != null) {
                              await LastLoginRepo().save(
                                userId: user.id,
                                nome: user.nome,
                                login: user.login,
                              );
                            }
                            await SessionService.instance.logout();
                            if (!context.mounted) return;
                            Navigator.pushReplacementNamed(context, "/login");
                          },
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

