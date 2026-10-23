import "../repo/config_repo.dart";
import "scale_comm.dart";
import "scale_model_config.dart";

class ScaleLinkConfig {
  final String host;
  final int port;
  final ScaleModel model;

  const ScaleLinkConfig({
    required this.host,
    required this.port,
    required this.model,
  });

  bool get canConnect => host.isNotEmpty && port > 0;
}

Future<ScaleLinkConfig> loadScaleLink(ConfigRepo cfg) async {
  final host = (await cfg.getHostBalanca()).trim();
  final port = await cfg.getPortaBalanca();
  final model = scaleModelFromConfigInt(await cfg.getModeloBalanca());
  return ScaleLinkConfig(
    host: host,
    port: port,
    model: model,
  );
}

/// Liga [ScaleComm] no TCP da balança real.
Future<bool> connectScaleFromLink(ScaleComm comm, ScaleLinkConfig link) async {
  if (!link.canConnect) return false;
  comm.configure(
    host: link.host,
    port: link.port,
    model: link.model,
    allowNegative: true,
  );
  await comm.connect();
  return true;
}

Future<bool> connectScaleFromConfig(ScaleComm comm, ConfigRepo cfg) async {
  final link = await loadScaleLink(cfg);
  return connectScaleFromLink(comm, link);
}
