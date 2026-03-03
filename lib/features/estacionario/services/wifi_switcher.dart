import "package:app_settings/app_settings.dart";
import "package:flutter/foundation.dart";

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

    // Em alguns dispositivos (ex.: Xiaomi/MIUI), a troca automática pode
    // cair em rede "fictícia"/sem rota. Forçamos conexão manual pelo Android.
    await openAndroidWifiSettings();
    return WifiSwitchResult(
      ok: true,
      message:
          "Abra a lista de Wi-Fi e conecte manualmente na rede '$target'.",
      usedSettingsFallback: true,
    );
  }

  Future<void> openAndroidWifiSettings() async {
    try {
      await AppSettings.openAppSettings(type: AppSettingsType.wifi);
    } catch (e) {
      debugPrint("[WIFI] erro abrindo settings: $e");
    }
  }
}
