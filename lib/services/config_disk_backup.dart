import "dart:convert";
import "dart:io";

import "package:flutter/foundation.dart";
import "package:path/path.dart" as p;
import "package:path_provider/path_provider.dart";

import "../repo/config_repo.dart";
import "../repo/session_repo.dart";

/// Backup da CONFIG (e sessão) em pasta pública para sobreviver a reinstalação do APK.
class ConfigDiskBackup {
  static const String fileName = "rfeed_config_backup.json";
  static const int schemaVersion = 1;

  static Future<File?> _backupFile() async {
    try {
      if (Platform.isAndroid) {
        final downloads = await getDownloadsDirectory();
        if (downloads != null) {
          final dir = Directory(p.join(downloads.path, "RFeed"));
          if (!await dir.exists()) {
            await dir.create(recursive: true);
          }
          return File(p.join(dir.path, fileName));
        }
      }

      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(docs.path, "RFeedBackup"));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return File(p.join(dir.path, fileName));
    } catch (e) {
      if (kDebugMode) debugPrint("[ConfigDiskBackup] _backupFile: $e");
      return null;
    }
  }

  static Future<String?> backupPathLabel() async {
    final f = await _backupFile();
    return f?.path;
  }

  static bool _configHasBase(Map<String, Object?> cfg) {
    final host = (cfg["HOST"] ?? "").toString().trim();
    final hostB = (cfg["HOST_BALANCA"] ?? "").toString().trim();
    return host.isNotEmpty || hostB.isNotEmpty;
  }

  /// Grava backup após salvar configuração.
  static Future<void> exportAfterSave({
    required Map<String, Object?> config,
  }) async {
    final file = await _backupFile();
    if (file == null) return;

    final session = await SessionRepo().getLogin();
    final payload = <String, dynamic>{
      "schema": schemaVersion,
      "savedAt": DateTime.now().toUtc().toIso8601String(),
      "appId": "com.rfeed.fieldtrato",
      "config": _configToJsonMap(config),
      if (session != null) "session": session,
    };

    try {
      await file.writeAsString(
        const JsonEncoder.withIndent("  ").convert(payload),
        flush: true,
      );
      if (kDebugMode) {
        debugPrint("[ConfigDiskBackup] salvo em ${file.path}");
      }
    } catch (e) {
      if (kDebugMode) debugPrint("[ConfigDiskBackup] export: $e");
    }
  }

  static Map<String, dynamic> _configToJsonMap(Map<String, Object?> cfg) {
    final out = <String, dynamic>{};
    for (final e in cfg.entries) {
      final v = e.value;
      if (v == null) {
        out[e.key] = null;
      } else if (v is num || v is String || v is bool) {
        out[e.key] = v;
      } else {
        out[e.key] = v.toString();
      }
    }
    return out;
  }

  static Future<Map<String, dynamic>?> _readPayload() async {
    final file = await _backupFile();
    if (file == null || !await file.exists()) return null;

    try {
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return Map<String, dynamic>.from(decoded);
    } catch (e) {
      if (kDebugMode) debugPrint("[ConfigDiskBackup] read: $e");
      return null;
    }
  }

  /// Se não há CONFIG no app, tenta restaurar do arquivo em disco.
  static Future<bool> tryRestoreIfConfigEmpty(ConfigRepo repo) async {
    final current = await repo.getConfig();
    if (current != null && _configHasBase(current)) {
      return false;
    }

    final payload = await _readPayload();
    if (payload == null) return false;

    final cfgRaw = payload["config"];
    if (cfgRaw is! Map) return false;

    final cfg = <String, Object?>{};
    for (final e in cfgRaw.entries) {
      cfg[e.key.toString()] = e.value;
    }
    if (!_configHasBase(cfg)) return false;

    await repo.saveConfig(cfg);

    // Não restaura sessão ativa — login/senha são obrigatórios a cada abertura.
    final sessRaw = payload["session"];
    if (sessRaw is Map) {
      final id = (sessRaw["ID"] ?? "").toString().trim();
      if (id.isNotEmpty) {
        await SessionRepo().saveLastUserOnly(userId: id);
      }
    }

    if (kDebugMode) {
      debugPrint("[ConfigDiskBackup] config restaurada do disco");
    }
    return true;
  }

  /// Restaura manualmente (substitui CONFIG atual).
  static Future<bool> restoreNow(ConfigRepo repo) async {
    final payload = await _readPayload();
    if (payload == null) return false;

    final cfgRaw = payload["config"];
    if (cfgRaw is! Map) return false;

    final cfg = <String, Object?>{};
    for (final e in cfgRaw.entries) {
      cfg[e.key.toString()] = e.value;
    }
    if (!_configHasBase(cfg)) return false;

    await repo.saveConfig(cfg);

    // Não restaura sessão ativa — só último usuário para pré-seleção.
    final sessRaw = payload["session"];
    if (sessRaw is Map) {
      final id = (sessRaw["ID"] ?? "").toString().trim();
      if (id.isNotEmpty) {
        await SessionRepo().saveLastUserOnly(userId: id);
      }
    }
    return true;
  }
}
