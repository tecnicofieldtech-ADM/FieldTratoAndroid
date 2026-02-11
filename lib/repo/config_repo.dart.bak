import "package:sqflite/sqflite.dart";
import "../db/app_db.dart";

class ConfigRepo {
  Future<Database> get _db async => AppDb.instance.db;

  // =========================================================
  // ✅ GARANTE COLUNAS (migração segura)
  // =========================================================
  Future<void> _ensureColumns(Database db) async {
    // Se a tabela não existir ainda, não faz nada aqui.
    // (normalmente ela já foi criada no onCreate do AppDb)
    try {
      final cols = await _getConfigColumns(db);

      Future<void> addIfMissing(String col, String ddl) async {
        if (cols.contains(col.toLowerCase())) return;
        await db.execute("ALTER TABLE CONFIG ADD COLUMN $ddl");
      }

      // Campos antigos (caso algum ambiente não tenha)
      await addIfMissing(
          "pulo_automatico", "PULO_AUTOMATICO INTEGER DEFAULT 1");
      await addIfMissing("tempo_em_segundos_pulo",
          "TEMPO_EM_SEGUNDOS_PULO INTEGER DEFAULT 10");
      await addIfMissing(
          "incremento_peso", "INCREMENTO_PESO INTEGER DEFAULT 1");

      // ✅ NOVOS CAMPOS
      await addIfMissing("tempo_mistura",
          "TEMPO_MISTURA INTEGER"); // você vai usar como SEGUNDOS
      await addIfMissing(
        "tolerancia_carregamento",
        "TOLERANCIA_CARREGAMENTO NUMERIC(15,3) DEFAULT 0",
      );
    } catch (_) {
      // se der algum erro de PRAGMA/tabela não existe, ignora aqui.
      // seu AppDb onCreate deve garantir a criação.
    }
  }

  Future<Set<String>> _getConfigColumns(Database db) async {
    final rows = await db.rawQuery("PRAGMA table_info(CONFIG)");
    final set = <String>{};
    for (final r in rows) {
      final name = (r["name"] ?? "").toString().toLowerCase();
      if (name.isNotEmpty) set.add(name);
    }
    return set;
  }

  // =========================================================
  // CRUD BASE
  // =========================================================
  Future<Map<String, Object?>?> getConfig() async {
    final db = await _db;
    await _ensureColumns(db);

    final rows = await db.rawQuery("SELECT * FROM CONFIG LIMIT 1");
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> saveConfig(Map<String, Object?> data) async {
    final db = await _db;
    await _ensureColumns(db);

    await db.transaction((txn) async {
      await txn.delete("CONFIG");
      await txn.insert("CONFIG", data);
    });
  }

  // -------------------------
  // Helpers
  // -------------------------
  Future<Object?> _getField(String field) async {
    final cfg = await getConfig();
    if (cfg == null) return null;

    final lower = field.toLowerCase();
    for (final k in cfg.keys) {
      if (k.toLowerCase() == lower) return cfg[k];
    }
    return null;
  }

  Object? _getFieldFromCfg(Map<String, Object?> cfg, String field) {
    final lower = field.toLowerCase();
    for (final k in cfg.keys) {
      if (k.toLowerCase() == lower) return cfg[k];
    }
    return null;
  }

  int _toInt(Object? v, {int def = 0}) {
    if (v == null) return def;
    if (v is int) return v;
    if (v is num) return v.toInt();
    final s = v.toString().trim();
    if (s.isEmpty) return def;
    return int.tryParse(s) ?? def;
  }

  double _toDouble(Object? v, {double def = 0}) {
    if (v == null) return def;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is num) return v.toDouble();
    final s0 = v.toString().trim();
    if (s0.isEmpty) return def;

    // aceita vírgula
    final s = s0.replaceAll(",", ".");
    return double.tryParse(s) ?? def;
  }

  String _toStr(Object? v, {String def = ""}) {
    if (v == null) return def;
    return v.toString();
  }

  // -------------------------
  // BALANÇA
  // -------------------------
  Future<String> getHostBalanca() async =>
      _toStr(await _getField("HOST_BALANCA"));
  Future<int> getPortaBalanca() async =>
      _toInt(await _getField("PORTA_BALANCA"));
  Future<int> getModeloBalanca() async =>
      _toInt(await _getField("MODELO_BALANCA"));

  Future<int> getIncrementoPeso() async {
    final v = _toInt(await _getField("INCREMENTO_PESO"), def: 1);
    if (v < 1) return 1;
    if (v > 10) return 10;
    return v;
  }

  Future<int> getPuloAutomatico() async =>
      _toInt(await _getField("PULO_AUTOMATICO"), def: 1);

  Future<int> getTempoPuloSegundos() async {
    final v = _toInt(await _getField("TEMPO_EM_SEGUNDOS_PULO"), def: 10);
    return v <= 0 ? 10 : v;
  }

  // -------------------------
  // RFID
  // -------------------------
  Future<String> getHostRfid() async => _toStr(await _getField("HOST_RFID"));
  Future<int> getPortaRfid() async => _toInt(await _getField("PORTA_RFID"));
  Future<int> getModeloRfid() async => _toInt(await _getField("MODELO_RFID"));

  // -------------------------
  // FABRICAÇÃO
  // -------------------------
  Future<int> getTipoTrabalho() async =>
      _toInt(await _getField("TIPO_TRABALHO"), def: 0);

  Future<String> getIdVagao() async =>
      _toStr(await _getField("ID_VAGAO"), def: "");

  // TEMPO_MISTURA em MINUTOS (INTEGER)
  Future<int> getTempoMisturaMinutos() async {
    final cfg = await getConfig();
    final v = (cfg?["TEMPO_MISTURA"] ?? 0).toString().trim();
    return int.tryParse(v) ?? 0;
  }

  /// TOLERANCIA_CARREGAMENTO em % (NUMERIC)  ex: 2.5 = 2,5%
  Future<double> getToleranciaCarregamentoPct() async {
    final cfg = await getConfig();
    final raw = (cfg?["TOLERANCIA_CARREGAMENTO"] ?? 0).toString().trim();
    if (raw.isEmpty) return 0.0;

    // aceita "2,5" e "2.5"
    final norm = raw.replaceAll(".", "").replaceAll(",", ".");
    final d = double.tryParse(norm) ??
        double.tryParse(raw.replaceAll(",", ".")) ??
        0.0;
    return d < 0 ? 0.0 : d;
  }

  /// ✅ NOVO: tolerância de carregamento em KG (ex.: 15.000)
  Future<double> getToleranciaCarregamentoKg() async {
    final v1 = await _getField("TOLERANCIA_CARREGAMENTO");
    final v2 = await _getField("TOLERANCIA_CARREGAMENTO_KG");
    final v = _toDouble(v1 ?? v2, def: 0.0);
    return v < 0 ? 0.0 : v;
  }

  // =========================================================
  // ✅ Fazendas
  // =========================================================
  Future<String> getIdFazendaSelecionada() async {
    final v1 = await _getField("ID_FAZENDA");
    final v2 = await _getField("IDFAZENDA");
    final v3 = await _getField("FAZENDA_ID");
    final v = _toStr(v1 ?? v2 ?? v3, def: "");
    return v.trim();
  }

  // =========================================================
  // ✅ monta baseUrl
  // =========================================================
  String buildBaseUrl(Map<String, Object?> cfg) {
    final host = _toStr(
      _getFieldFromCfg(cfg, "HOST_API") ??
          _getFieldFromCfg(cfg, "HOST") ??
          _getFieldFromCfg(cfg, "SERVER") ??
          _getFieldFromCfg(cfg, "IP") ??
          _getFieldFromCfg(cfg, "API_HOST"),
      def: "127.0.0.1",
    ).trim();

    final port = _toInt(
      _getFieldFromCfg(cfg, "PORTA_API") ??
          _getFieldFromCfg(cfg, "PORTA") ??
          _getFieldFromCfg(cfg, "API_PORT") ??
          _getFieldFromCfg(cfg, "PORT"),
      def: 3000,
    );

    final useHttps = _toInt(
          _getFieldFromCfg(cfg, "HTTPS") ??
              _getFieldFromCfg(cfg, "USE_HTTPS") ??
              _getFieldFromCfg(cfg, "SSL"),
          def: 0,
        ) ==
        1;

    final scheme = useHttps ? "https" : "http";

    if (host.startsWith("http://") || host.startsWith("https://")) {
      return host;
    }

    if (port <= 0) return "$scheme://$host";
    return "$scheme://$host:$port";
  }

// -------------------------
// ESPELHO (PÁ)
// -------------------------
  Future<String> getIpEspelho() async {
    final v1 = await _getField("IP_ESPELHO");
    final v2 = await _getField("HOST_ESPELHO");
    final v3 = await _getField("ESPELHO_IP");
    final ip = _toStr(v1 ?? v2 ?? v3, def: "").trim();
    return ip;
  }

  Future<int> getPortaEspelho() async {
    final v1 = await _getField("PORTA_ESPELHO");
    final v = _toInt(v1, def: 9000);
    return v <= 0 ? 9000 : v;
  }
}
