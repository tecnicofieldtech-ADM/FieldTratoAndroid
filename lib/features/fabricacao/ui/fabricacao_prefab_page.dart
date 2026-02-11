import "package:flutter/material.dart";
import "package:flutter/services.dart";

import "../../../repo/user_repo.dart";
import "../../../repo/dieta_repo.dart";
import "../../../repo/config_repo.dart";

import "../../../services/session_service.dart";

import "../data/fabricacao_repo.dart";
import "fabricacao_weigh_page.dart";
import "../services/fabricacao_create_service.dart";

class FabricacaoPreFabPage extends StatefulWidget {
  const FabricacaoPreFabPage({super.key, required this.repo});
  final FabricacaoRepo repo;

  @override
  State<FabricacaoPreFabPage> createState() => _FabricacaoPreFabPageState();
}

class _FabricacaoPreFabPageState extends State<FabricacaoPreFabPage> {
  final _dietaRepo = DietaRepo();
  final _userRepo = UserRepo();
  final _cfg = ConfigRepo();

  bool _loading = false;

  List<Map<String, Object?>> _dietas = [];
  List<Map<String, Object?>> _users = [];

  String? _dietaId;
  String? _operadorId;

  int? _tratoSelecionado;
  final _kgCtrl = TextEditingController(text: "0");

  @override
  void initState() {
    super.initState();
    _loadCombos();
  }

  Future<void> _loadCombos() async {
    if (mounted) setState(() => _loading = true);
    try {
      // se você quiser filtrar dieta por fazenda selecionada:
      final idFazendaSel = await _cfg.getIdFazendaSelecionada();
      final dietas = await _dietaRepo.listAll(idFazenda: idFazendaSel);

      final users = await _userRepo.listAll();

      if (!mounted) return;

      setState(() {
        _dietas = dietas;
        _users = users;

        if (_dietas.isNotEmpty) {
          _dietaId = (_dietas.first["ID"] ?? "").toString();
        }
        if (_users.isNotEmpty) {
          _operadorId = (_users.first["ID"] ?? "").toString();
        }
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _kgCtrl.dispose();
    super.dispose();
  }

  void _msg(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _onFabricar() async {
    if ((_dietaId ?? "").isEmpty) return _msg("Selecione a dieta.");
    if ((_operadorId ?? "").isEmpty) return _msg("Selecione o operador.");

    final trato = _tratoSelecionado;
    if (trato == null || trato <= 0) return _msg("Informe o trato.");

    final kg = double.tryParse(_kgCtrl.text.trim().replaceAll(",", "."));
    if (kg == null || kg <= 0) return _msg("Informe o previsto em KG.");
    if (kg > 15000) return _msg("Quantidade máxima é 15.000 KG.");

    // ✅ GARANTE LOGIN (global)
    final idUsuarioLogado = SessionService.instance.userId;
    if (idUsuarioLogado == null || idUsuarioLogado.trim().isEmpty) {
      _msg("Sessão vazia. Faça login novamente.");
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, "/login");
      return;
    }

    // ✅ 1) Se existe fabricação em aberto (FINALIZADA=0), pergunta
    final aberto = await widget.repo.getFabricacaoEmAberto();
    if (!mounted) return;

    if (aberto != null) {
      final ok = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Text("Fabricação em aberto"),
          content: const Text(
            "Existe uma fabricação em aberto. Deseja continuar de onde parou?",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Não"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Sim"),
            ),
          ],
        ),
      );

      if (!mounted) return;

      if (ok == true) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => FabricacaoWeighPage(repo: widget.repo),
          ),
        );
      }
      return;
    }

    // ✅ 2) Se não tem em aberto, cria e popula tabelas e vai pra tela fabricar
    if (mounted) setState(() => _loading = true);
    try {
      final idFazenda = await _cfg.getIdFazendaSelecionada();
      if (idFazenda.isEmpty) {
        throw Exception("Nenhuma fazenda selecionada na CONFIG.");
      }

      final service = FabricacaoCreateService();
      await service.criarFabricacao(
        idDieta: _dietaId!,
        idOperador: _operadorId!,
        idUsuarioLogado: idUsuarioLogado,
        idFazenda: idFazenda,
        trato: trato,
        totalKg: kg,
      );

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => FabricacaoWeighPage(repo: widget.repo),
        ),
      );
    } catch (e) {
      _msg("Erro ao criar fabricação: $e");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Nova Fabricação")),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: DropdownButtonFormField<String>(
                        key: ValueKey(_dietaId),
                        initialValue: _dietaId,
                        items: _dietas
                            .map(
                              (d) => DropdownMenuItem<String>(
                                value: (d["ID"] ?? "").toString(),
                                child: Text((d["NOME"] ?? "").toString()),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => _dietaId = v),
                        decoration: const InputDecoration(labelText: "Dieta"),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Trato",
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [1, 2, 3, 4].map((t) {
                              final sel = _tratoSelecionado == t;
                              return ChoiceChip(
                                label: Text("Trato $t"),
                                selected: sel,
                                onSelected: (_) =>
                                    setState(() => _tratoSelecionado = t),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: TextField(
                        controller: _kgCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r"[0-9.,]"),
                          ),
                          TextInputFormatter.withFunction((oldValue, newValue) {
                            final raw = newValue.text.trim();
                            if (raw.isEmpty) return newValue;
                            final v =
                                double.tryParse(raw.replaceAll(",", "."));
                            if (v == null) return oldValue;
                            return v > 15000 ? oldValue : newValue;
                          }),
                        ],
                        decoration: const InputDecoration(
                          labelText: "Quantidade total (KG)",
                          helperText: "Máximo: 15.000 KG",
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: DropdownButtonFormField<String>(
                        key: ValueKey(_operadorId),
                        initialValue: _operadorId,
                        items: _users
                            .map(
                              (u) => DropdownMenuItem<String>(
                                value: (u["ID"] ?? "").toString(),
                                child: Text((u["NOME"] ?? "").toString()),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => _operadorId = v),
                        decoration:
                            const InputDecoration(labelText: "Operador"),
                      ),
                    ),
                  ),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _onFabricar,
                      child: const Text("Fabricar"),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
