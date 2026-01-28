// lib/pages/login_page.dart
import "package:flutter/material.dart";

import "../repo/user_repo.dart";
import "../repo/session_repo.dart";
import "../widgets/app_logo.dart";

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _userRepo = UserRepo();
  final _sess = SessionRepo();

  final _senhaCtrl = TextEditingController();

  List<Map<String, Object?>> _users = [];
  String? _selectedUserId;
  bool _loading = true;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() => _loading = true);

    final list = await _userRepo.listAll();

    // filtra só usuários com LOGIN preenchido (sem espaços)
    final filtered = list.where((u) {
      final login = (u["LOGIN"] ?? "").toString().trim();
      return login.isNotEmpty;
    }).toList();

    setState(() {
      _users = filtered;
      _selectedUserId =
          filtered.isNotEmpty ? (filtered.first["ID"]?.toString()) : null;
      _loading = false;
    });
  }

  Future<void> _doLogin() async {
    final userId = _selectedUserId;

    if (_users.isEmpty) {
      _toast("Nenhum usuário com LOGIN preenchido. Sincronize novamente.");
      return;
    }

    if (userId == null) {
      _toast("Selecione um usuário.");
      return;
    }

    final row = await _userRepo.findById(userId);
    if (row == null) {
      _toast("Usuário inválido.");
      return;
    }

    final senhaDb = (row["SENHA"] ?? "").toString();
    final senhaInf = _senhaCtrl.text.trim();

    if (senhaInf.isEmpty) {
      _toast("Informe a senha.");
      return;
    }

    if (senhaInf != senhaDb) {
      _toast("Senha incorreta.");
      return;
    }

    // ✅ salva sessão
    await _sess.saveLogin(
      userId: (row["ID"] ?? "").toString(),
      nome: (row["NOME"] ?? "").toString(),
      login: (row["LOGIN"] ?? "").toString(),
    );

    if (!mounted) return;
    Navigator.pushReplacementNamed(context, "/menu");
  }

  void _toast(String msg) {
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

    return Scaffold(
      // deixa a tela “limpa” (sem AppBar) pra ficar igual o menu
      body: Stack(
        children: [
          // ✅ IMAGEM DE FUNDO (mesma do menu)
          Positioned.fill(
            child: Image.asset(
              "assets/images/bg_boi_tech.png",
              fit: BoxFit.cover,
              alignment: Alignment.center,
            ),
          ),

          // ✅ CAMADA BRANCA OPACA (destaca logo e botões)
          Positioned.fill(
            child: Container(
              // ajuste fino aqui:
              color: Colors.white.withOpacity(0.72),
            ),
          ),

          // conteúdo
          SafeArea(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: Card(
                          elevation: 10,
                          color: Colors.white.withOpacity(0.90), // 👈 aqui
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // logo maior e com presença
                                const AppLogo(height: 150),
                                const SizedBox(height: 18),

                                DropdownButtonFormField<String>(
                                  value: _selectedUserId,
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
                                      icon: Icon(_obscure
                                          ? Icons.visibility
                                          : Icons.visibility_off),
                                    ),
                                  ),
                                  onSubmitted: (_) => _doLogin(),
                                ),

                                const SizedBox(height: 16),

                                SizedBox(
                                  width: double.infinity,
                                  height: 50,
                                  child: FilledButton(
                                    onPressed: _doLogin,
                                    style: FilledButton.styleFrom(
                                      backgroundColor: const Color.fromARGB(255, 1, 1, 1), // verde claro
                                      foregroundColor:
                                          Colors.white, // texto preto
                                      textStyle: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    child: const Text("Entrar"),
                                  ),
                                ),
                                const SizedBox(height: 10),

                                TextButton(
                                  onPressed: () =>
                                      Navigator.pushReplacementNamed(
                                          context, "/config"),
                                  child: const Text("Voltar para Configuração"),
                                ),

                                // espaçador “seguro” em telas pequenas
                                SizedBox(
                                    height: mq.viewInsets.bottom > 0 ? 10 : 0),
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
