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

  /// Após receber carregamento: exige SSID identificável e **diferente** da estacionária.
  static bool isVagaoNetworkAfterCarregamento({
    required String current,
    required String stationSsid,
  }) {
    final cur = current.trim().replaceAll('"', "");
    if (cur.isEmpty || cur.toLowerCase() == "<unknown ssid>") return false;
    final station = stationSsid.trim();
    if (station.isEmpty) return true;
    return !ssidMatchesExpected(cur, station);
  }

  static bool isBlockedSsid(String ssid) {
    if (ssid.trim().isEmpty) return true;
    return isFieldTratoSsid(ssid);
  }
}


