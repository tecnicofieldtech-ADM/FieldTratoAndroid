import "dart:io";
import "package:network_info_plus/network_info_plus.dart";
import "package:app_settings/app_settings.dart";
import "package:flutter/services.dart";
import "package:permission_handler/permission_handler.dart";

class WifiGuard {
  static const MethodChannel _androidNetworkPanelChannel =
      MethodChannel("rfeed/android_network");

  static bool isSsidIdentifiable(String ssid) {
    final s = ssid.trim().replaceAll('"', "");
    if (s.isEmpty) return false;
    return s.toLowerCase() != "<unknown ssid>";
  }

  static Future<bool> _locationPermissionGranted() async {
    final whenInUse = await Permission.locationWhenInUse.status;
    if (whenInUse.isGranted) return true;
    final loc = await Permission.location.status;
    return loc.isGranted;
  }

  static Future<bool> _nearbyWifiPermissionGranted() async {
    try {
      final nearby = await Permission.nearbyWifiDevices.status;
      return nearby.isGranted;
    } catch (_) {
      return false;
    }
  }

  /// Verifica acesso ao SSID (permissoes + leitura real no aparelho).
  static Future<bool> requestLocationPermissionIfNeeded() async {
    if (!Platform.isAndroid) return true;

    try {
      final ssid = await getCurrentSsid();
      if (isSsidIdentifiable(ssid)) return true;

      if (await _locationPermissionGranted()) return true;
      if (await _nearbyWifiPermissionGranted()) return true;

      // Alguns OEMs so atualizam o status apos request().
      try {
        final locReq = await Permission.locationWhenInUse.request();
        if (locReq.isGranted) return true;
      } catch (_) {}

      try {
        final nearbyReq = await Permission.nearbyWifiDevices.request();
        if (nearbyReq.isGranted) return true;
      } catch (_) {}

      if (await _locationPermissionGranted()) return true;
      if (await _nearbyWifiPermissionGranted()) return true;

      final ssidAfter = await getCurrentSsid();
      return isSsidIdentifiable(ssidAfter);
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

  static String _normalizeSsid(String ssid) {
    return ssid
        .trim()
        .toLowerCase()
        .replaceAll('"', "")
        .replaceAll(RegExp(r"[\s_-]+"), "");
  }

  /// Rede do vagao/tablet (balanca, RFID). No Field Trato o prefixo e FieldTrato*.
  static bool isFieldTratoSsid(String ssid) {
    final normalized = _normalizeSsid(ssid);
    if (normalized.isEmpty || normalized == "<unknownssid>") return false;
    return normalized.startsWith("fieldtrato");
  }

  /// Alias legado no codigo Field Trato — preferir [isFieldTratoSsid].
  static bool isRFeedSsid(String ssid) => isFieldTratoSsid(ssid);

  /// Compara SSID atual com o valor salvo na config (ex.: rede do estacionário).
  static bool ssidMatchesExpected(String current, String expected) {
    final a = current.trim().replaceAll('"', "").toLowerCase();
    final b = expected.trim().replaceAll('"', "").toLowerCase();
    if (b.isEmpty) return false;
    return a == b;
  }

  /// Após receber carregamento: exige rede FieldTrato* e **diferente** da estacionária.
  static bool isVagaoNetworkAfterCarregamento({
    required String current,
    required String stationSsid,
  }) {
    final cur = current.trim().replaceAll('"', "");
    if (cur.isEmpty || cur.toLowerCase() == "<unknown ssid>") return false;
    if (!isFieldTratoSsid(cur)) return false;
    final station = stationSsid.trim();
    if (station.isEmpty) return true;
    return !ssidMatchesExpected(cur, station);
  }

  static bool isBlockedSsid(String ssid) {
    if (ssid.trim().isEmpty) return true;
    return isFieldTratoSsid(ssid);
  }
}


