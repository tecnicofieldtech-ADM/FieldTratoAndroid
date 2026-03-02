import "package:app_settings/app_settings.dart";
import "package:flutter/foundation.dart";
import "package:wifi_iot/wifi_iot.dart";

class WifiSwitchResult {
  WifiSwitchResult({
    required this.ok,
    required this.message,
    this.usedSettingsFallback = false,
  });

  final bool ok;
  final String message;
  final bool usedSettingsFallback;
}

class WifiSwitcher {
  Future<WifiSwitchResult> connectToWifi({
    required String ssid,
    required String password,
  }) {
    return connect(ssid: ssid, password: password);
  }

  Future<WifiSwitchResult> connect({
    required String ssid,
    required String password,
  }) async {
    final target = ssid.trim();
    if (target.isEmpty) {
      return WifiSwitchResult(ok: false, message: "SSID invalido");
    }

    try {
      final available = await WiFiForIoTPlugin.isEnabled();
      if (!available) {
        await WiFiForIoTPlugin.setEnabled(true, shouldOpenSettings: true);
      }

      final connected = await WiFiForIoTPlugin.connect(
        target,
        password: password,
        security: NetworkSecurity.WPA,
        joinOnce: true,
      );

      if (connected) {
        final current = await WiFiForIoTPlugin.getSSID();
        debugPrint("[WIFI] conectado em $current");
        return WifiSwitchResult(ok: true, message: "Conectado em $target");
      }

      await openAndroidWifiSettings();
      return WifiSwitchResult(
        ok: false,
        message: "Nao foi possivel conectar automaticamente",
        usedSettingsFallback: true,
      );
    } catch (e) {
      debugPrint("[WIFI] erro connect: $e");
      await openAndroidWifiSettings();
      return WifiSwitchResult(
        ok: false,
        message: "Erro ao trocar rede: $e",
        usedSettingsFallback: true,
      );
    }
  }

  Future<void> openAndroidWifiSettings() async {
    try {
      await AppSettings.openAppSettings(type: AppSettingsType.wifi);
    } catch (e) {
      debugPrint("[WIFI] erro abrindo settings: $e");
    }
  }
}
