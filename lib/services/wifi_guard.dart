import "dart:io";
import "package:network_info_plus/network_info_plus.dart";
import "package:permission_handler/permission_handler.dart";
import "package:app_settings/app_settings.dart";

class WifiGuard {
  /// Android 10+ exige permissão de localização para ler SSID.
  static Future<String> getCurrentSsid() async {
    if (!Platform.isAndroid) return "";

    // tenta garantir permissão
    final st = await Permission.locationWhenInUse.status;
    if (!st.isGranted) {
      final req = await Permission.locationWhenInUse.request();
      if (!req.isGranted) return "";
    }

    final info = NetworkInfo();
    String? ssid = await info.getWifiName(); // pode vir com aspas
    ssid ??= "";
    ssid = ssid.replaceAll('"', "").trim();
    return ssid;
  }

  static Future<void> openWifiSelector() async {
    if (!Platform.isAndroid) return;
    await AppSettings.openAppSettings(type: AppSettingsType.wifi);
  }

  static bool isBlockedSsid(String ssid) {
    if (ssid.trim().isEmpty) return true;
    return ssid.toLowerCase().startsWith("rfeed");
  }
}


