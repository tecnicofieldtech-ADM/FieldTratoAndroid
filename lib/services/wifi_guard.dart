import "dart:io";
import "package:network_info_plus/network_info_plus.dart";
import "package:app_settings/app_settings.dart";
import "package:flutter/services.dart";
import "package:permission_handler/permission_handler.dart";

class WifiGuard {
  static const MethodChannel _androidNetworkPanelChannel =
      MethodChannel("rfeed/android_network");

  /// Solicita permissao de localizacao sob demanda quando ainda nao concedida.
  static Future<bool> requestLocationPermissionIfNeeded() async {
    if (!Platform.isAndroid) return true;

    try {
      final current = await Permission.locationWhenInUse.status;
      if (current.isGranted) return true;
      // Em alguns aparelhos MIUI, o request nativo pode derrubar o app.
      // Aqui apenas informamos que ainda nao ha permissao para o fluxo
      // de UI guiar o usuario ate as configuracoes do app.
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Retorna SSID quando disponível, sem disparar prompt de permissão.
  /// Em alguns Android/MIUI pode retornar vazio/unknown sem permissões.
  static Future<String> getCurrentSsid() async {
    if (!Platform.isAndroid) return "";

    try {
      final info = NetworkInfo();
      String ssid = (await info.getWifiName() ?? "").replaceAll('"', "").trim();
      if (ssid.isNotEmpty && ssid.toLowerCase() != "<unknown ssid>") {
        return ssid;
      }

      final nativeSsid =
          await _androidNetworkPanelChannel.invokeMethod<String>("getWifiSsid") ?? "";
      return nativeSsid.trim();
    } catch (_) {
      try {
        final nativeSsid =
            await _androidNetworkPanelChannel.invokeMethod<String>("getWifiSsid") ?? "";
        return nativeSsid.trim();
      } catch (_) {
        return "";
      }
    }
  }

  static Future<bool> isLocationServiceEnabled() async {
    if (!Platform.isAndroid) return true;
    try {
      return await _androidNetworkPanelChannel.invokeMethod<bool>("isLocationEnabled") ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> openLocationSettings() async {
    if (!Platform.isAndroid) return;
    try {
      final opened =
          await _androidNetworkPanelChannel.invokeMethod<bool>("openLocationSettings") ?? false;
      if (opened) return;
    } catch (_) {
      // fallback abaixo
    }
    await AppSettings.openAppSettings(type: AppSettingsType.location);
  }

  static Future<void> openWifiSelector() async {
    if (!Platform.isAndroid) return;
    try {
      final opened =
          await _androidNetworkPanelChannel.invokeMethod<bool>("openWifiPicker") ??
              false;
      if (opened) return;
    } catch (_) {
      // fallback abaixo
    }
    await AppSettings.openAppSettings(type: AppSettingsType.wifi);
  }

  static bool isRFeedSsid(String ssid) {
    final normalized = ssid.trim().toLowerCase();
    return normalized.startsWith("rfeed");
  }

  static bool isBlockedSsid(String ssid) {
    if (ssid.trim().isEmpty) return true;
    return isRFeedSsid(ssid);
  }
}


