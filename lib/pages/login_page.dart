import "package:flutter/material.dart";
import "../repo/user_repo.dart";
import "../widgets/app_logo.dart";
import "../widgets/app_version_label.dart";
import "../repo/last_login_repo.dart";
import "../services/session_service.dart";

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _userRepo = UserRepo();
  final _lastLoginRepo = LastLoginRepo();
  final _senhaCtrl = TextEditingController();

  List<Map<String, Object?>> _users = [];
  String? _selectedUserId;

  bool _loading = true;
  bool _logging = false;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    if (mounted) setState(() => _loading = true);

    final list = await _userRepo.listAll();

    // filtra só usuários com LOGIN preenchido (sem espaços)
    final filtered = list.where((u) {
      final login = (u["LOGIN"] ?? "").toString().trim();
      return login.isNotEmpty;
    }).toList();

    if (!mounted) return;

    final lastUserId = await _lastLoginRepo.getLastUserId();
    final firstId =
        filtered.isNotEmpty ? (filtered.first["ID"]?.toString()) : null;

    String? preferredId = lastUserId;
    if (preferredId != null &&
        !filtered.any((u) => (u["ID"] ?? "").toString() == preferredId)) {
      preferredId = null;
    }

    final stillValid = (_selectedUserId != null) &&
        filtered.any((u) => (u["ID"] ?? "").toString() == _selectedUserId);

    setState(() {
      _users = filtered;
      _selectedUserId =
          stillValid ? _selectedUserId : (preferredId ?? firstId);
      _loading = false;
    });
  }

  Future<void> _doLogin() async {
    if (_logging) return;

    final userId = (_selectedUserId ?? "").trim();

    if (_users.isEmpty) {
      _toast("Nenhum usuário com LOGIN preenchido. Sincronize novamente.");
      return;
    }

    if (userId.isEmpty) {
      _toast("Selecione um usuário.");
      return;
    }

    final senhaInf = _senhaCtrl.text.trim();
    if (senhaInf.isEmpty) {
      _toast("Informe a senha.");
      return;
    }

    setState(() => _logging = true);

    try {
      final row = await _userRepo.findById(userId);
      if (row == null) {
        _toast("Usuário inválido.");
        return;
      }

      final id = (row["ID"] ?? "").toString().trim();
      final nome = (row["NOME"] ?? "").toString();
      final login = (row["LOGIN"] ?? "").toString().trim();
      final senhaDb = (row["SENHA"] ?? "").toString();
      final cargo = (row["CARGO"] ?? "").toString();

      if (id.isEmpty) {
        _toast("Usuário sem ID. Sincronize novamente.");
        return;
      }
      if (login.isEmpty) {
        _toast("Usuário sem LOGIN. Sincronize novamente.");
        return;
      }

      if (senhaInf != senhaDb) {
        _senhaCtrl.clear();
        _toast("Senha incorreta.");
        return;
      }

      await SessionService.instance.setLogin(
        userId: id,
        nome: nome,
        login: login,
        cargo: cargo,
      );

      debugPrint("LOGADO userId=${SessionService.instance.userId}");

      if (!mounted) return;
      Navigator.pushReplacementNamed(context, "/menu");
    } catch (e) {
      _toast("Erro no login: $e");
    } finally {
      if (mounted) setState(() => _logging = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    _senhaCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final isPhone = mq.size.width < 600 || mq.size.height < 700;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              "assets/images/bg_boi_tech.png",
              fit: BoxFit.cover,
              alignment: Alignment.center,
            ),
          ),
          Positioned.fill(
            child: Container(
              color: Colors.white.withValues(alpha: 0.72),
            ),
          ),
          SafeArea(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : Center(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.all(isPhone ? 12 : 16),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: Card(
                          elevation: 10,
                          color: Colors.white.withValues(alpha: 0.90),
                          child: Padding(
                            padding: EdgeInsets.all(isPhone ? 12 : 16),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                AppLogo(height: isPhone ? 80 : 150),
                                const SizedBox(height: 8),
                                const AppVersionLabel(
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.black54,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                DropdownButtonFormField<String>(
                                  key: ValueKey(_selectedUserId),
                                  initialValue: _selectedUserId,
                                  items: _users.map((u) {
                                    final id = (u["ID"] ?? "").toString();
                                    final login =
                                        (u["LOGIN"] ?? "").toString().trim();

                                    return DropdownMenuItem<String>(
                                      value: id,
                                      child: Text(
                                        login,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (v) =>
                                      setState(() => _selectedUserId = v),
                                  decoration: const InputDecoration(
                                    labelText: "Usuário (LOGIN)",
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _senhaCtrl,
                                  obscureText: _obscure,
                                  decoration: InputDecoration(
                                    labelText: "Senha",
                                    border: const OutlineInputBorder(),
                                    suffixIcon: IconButton(
                                      onPressed: () =>
                                          setState(() => _obscure = !_obscure),
                                      icon: Icon(
                                        _obscure
                                            ? Icons.visibility
                                            : Icons.visibility_off,
                                      ),
                                    ),
                                  ),
                                  onSubmitted: (_) => _doLogin(),
                                ),
                                const SizedBox(height: 16),
                                SizedBox(
                                  width: double.infinity,
                                  height: 50,
                                  child: FilledButton(
                                    onPressed: _logging ? null : _doLogin,
                                    style: FilledButton.styleFrom(
                                      backgroundColor: const Color(0xFF25A7CF),
                                      foregroundColor: Colors.white,
                                      textStyle: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    child: _logging
                                        ? const SizedBox(
                                            width: 22,
                                            height: 22,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Text("Entrar"),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                TextButton(
                                  onPressed: _logging
                                      ? null
                                      : () => Navigator.pushReplacementNamed(
                                            context,
                                            "/config",
                                          ),
                                  child: const Text("Voltar para Configuração"),
                                ),
                                SizedBox(
                                  height: mq.viewInsets.bottom > 0 ? 10 : 0,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

