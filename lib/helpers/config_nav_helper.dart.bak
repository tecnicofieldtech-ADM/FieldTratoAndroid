import 'package:flutter/material.dart';
import 'package:rfeed_flutter/repo/config_repo.dart';
import 'package:rfeed_flutter/repo/user_repo.dart';

Future<void> salvarConfigEVoltar({
  required BuildContext context,
  required Map<String, Object?> cfgData,
  required Future<void> Function(String baseUrl) baixarUsuarios,
}) async {
  final cfgRepo = ConfigRepo();
  final userRepo = UserRepo();

  await cfgRepo.saveConfig(cfgData);

  final hasUser = await userRepo.hasAnyUser();
  if (!context.mounted) return;

  if (!hasUser) {
    final baseUrl = cfgRepo.buildBaseUrl(cfgData);
    await baixarUsuarios(baseUrl);

    if (!context.mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
  } else {
    Navigator.of(context).pushNamedAndRemoveUntil('/menu', (_) => false);
  }
}
