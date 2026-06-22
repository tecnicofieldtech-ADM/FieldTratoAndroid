import "package:flutter/foundation.dart";

import "../../../services/wifi_guard.dart";

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

    // Abre o seletor nativo de Wi‑Fi (Settings.Panel no Android 10+).
    await WifiGuard.openWifiSelector();
    return WifiSwitchResult(
      ok: true,
      message:
          "Selecione a rede '$target' na lista de Wi‑Fi.",
      usedSettingsFallback: true,
    );
  }

  Future<void> openAndroidWifiSettings() async {
    await WifiGuard.openWifiSelector();
  }
}
