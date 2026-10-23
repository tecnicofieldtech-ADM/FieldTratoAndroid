import "package:sqflite/sqflite.dart";
import "package:uuid/uuid.dart";
import "../constants/config_options.dart";
import "../db/app_db.dart";
import "../domain/sync_pendencia_registro.dart";
import "../features/fabricacao/domain/fabricacao_flow.dart";
import "../services/config_disk_backup.dart";
import "../utils/station_bridge_url.dart";

class ConfigRepo {
  Future<Database> get _db async => AppDb.instance.db;

  // =========================================================
  // ✅ GARANTE COLUNAS (migração segura)
  // =========================================================
  Future<void> _ensureColumns(Database db) async {
    try {
      final cols = await _getConfigColumns(db);

      Future<void> addIfMissing(String col, String ddl) async {
        if (cols.contains(col.toLowerCase())) return;
        await db.execute("ALTER TABLE CONFIG ADD COLUMN $ddl");
      }

      // Campos antigos (caso algum device esteja com tabela velha)
      await addIfMissing(
          "pulo_automatico", "PULO_AUTOMATICO INTEGER DEFAULT 1");
      await addIfMissing(
        "tempo_em_segundos_pulo",
        "TEMPO_EM_SEGUNDOS_PULO INTEGER DEFAULT 10",
      );
      await addIfMissing(
          "incremento_peso", "INCREMENTO_PESO INTEGER DEFAULT 1");

      // ✅ NOVOS CAMPOS (você já tem no onCreate, mas isso protege upgrades)
      await addIfMissing("tempo_mistura", "TEMPO_MISTURA INTEGER");
      await addIfMissing(
        "tolerancia_carregamento",
        "TOLERANCIA_CARREGAMENTO NUMERIC DEFAULT 0",
      );

      // ✅ opcional (se você for usar tolerância em KG também)
      await addIfMissing(
        "tolerancia_carregamento_kg",
        "TOLERANCIA_CARREGAMENTO_KG NUMERIC DEFAULT 0",
      );

      await addIfMissing(
        "ponto_corte_fornecimento_kg",
        "PONTO_CORTE_FORNECIMENTO_KG NUMERIC DEFAULT 50",
      );

      // ✅ GARANTE que ID_VAGAO exista como TEXT (UUID)
      await addIfMissing("id_vagao", "ID_VAGAO TEXT");
      await addIfMissing("nome_vagao", "NOME_VAGAO TEXT");
      await addIfMissing(
          "porta_espelho", "PORTA_ESPELHO INTEGER DEFAULT 9000");
        await addIfMissing(
          "modo_saida_fab", "MODO_SAIDA_FAB INTEGER DEFAULT 0");
      await addIfMissing("led_bt_address", "LED_BT_ADDRESS TEXT");
      await addIfMissing("led_bt_name", "LED_BT_NAME TEXT");
      await addIfMissing("host_estacionario", "HOST_ESTACIONARIO TEXT");
      await addIfMissing("porta_estacionario", "PORTA_ESTACIONARIO INTEGER");
      await addIfMissing("flow_mode", "FLOW_MODE INTEGER DEFAULT 0");
      await addIfMissing("modo_hibrido", "MODO_HIBRIDO INTEGER DEFAULT 0");
      await addIfMissing("station_wifi_ssid", "STATION_WIFI_SSID TEXT");
      await addIfMissing(
          "station_wifi_password", "STATION_WIFI_PASSWORD TEXT");
      await addIfMissing("station_base_url", "STATION_BASE_URL TEXT");
      await addIfMissing("station_base_url_legacy", "STATION_BASE_URL_LEGACY TEXT");
      await addIfMissing(
        "ignorar_prefixo_rfid",
        "IGNORAR_PREFIXO_RFID INTEGER DEFAULT 0",
      );
      await addIfMissing("prefixo_rfid", "PREFIXO_RFID TEXT DEFAULT 'H'");
      await addIfMissing("cliente_codigo", "CLIENTE_CODIGO TEXT DEFAULT ''");
      await addIfMissing(
        "balanca_simulador",
        "BALANCA_SIMULADOR INTEGER DEFAULT 0",
      );
      await addIfMissing("importacao_id", "IMPORTACAO_ID TEXT");
      await addIfMissing("station_id", "STATION_ID TEXT");
      await addIfMissing("station_name", "STATION_NAME TEXT");
      await addIfMissing("truck_device_id", "TRUCK_DEVICE_ID TEXT");
    } catch (_) {
      // se der erro (tabela não existe, etc.), ignora aqui.
      // seu AppDb.onCreate garante a criação.
    }
  }

  Future<Set<String>> _getConfigColumns(Database db) async {
    final rows = await db.rawQuery("PRAGMA table_info(CONFIG)");
    final set = <String>{};
    for (final r in rows) {
      final name = (r["name"] ?? "").toString().toLowerCase().trim();
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
    return rows.isEmpty ? null : Map<String, Object?>.from(rows.first);
  }

  Future<void> saveConfig(Map<String, Object?> data) async {
    final db = await _db;
    await _ensureColumns(db);

    await db.transaction((txn) async {
      if (!data.containsKey("IMPORTACAO_ID")) {
        final prev = await txn.query(
          "CONFIG",
          columns: const ["IMPORTACAO_ID"],
          limit: 1,
        );
        if (prev.isNotEmpty) {
          data["IMPORTACAO_ID"] = prev.first["IMPORTACAO_ID"];
        }
      }
      await txn.delete("CONFIG");
      await txn.insert("CONFIG", data);
    });

    await ConfigDiskBackup.exportAfterSave(config: data);
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

  Future<bool> getBalancaSimulador() async =>
      _toInt(await _getField("BALANCA_SIMULADOR")) == 1;

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

  /// Antena Intelbras etc.: ignora letra de prefixo ao consultar tag no banco.
  Future<bool> getIgnorarPrefixoRfid() async {
    return _toInt(await _getField("IGNORAR_PREFIXO_RFID"), def: 0) == 1;
  }

  Future<String> getPrefixoRfid() async {
    final v = _toStr(await _getField("PREFIXO_RFID"), def: "H").trim();
    if (v.isEmpty) return "H";
    return v.substring(0, 1).toUpperCase();
  }

  // -------------------------
  // FABRICAÇÃO
  // -------------------------
  Future<int> getTipoTrabalho() async =>
      _toInt(await _getField("TIPO_TRABALHO"), def: 0);

  Future<bool> getModoHibrido() async =>
      _toInt(await _getField("MODO_HIBRIDO"), def: 0) == 1;

    Future<int> getBackend() async =>
      _toInt(await _getField("BACKEND"), def: 0);

  /// Código do cliente na API online (multi-tenant). Header X-Client-Code.
  Future<String> getClienteCodigo() async {
    return _toStr(await _getField("CLIENTE_CODIGO"), def: "")
        .trim()
        .toUpperCase();
  }

  String clienteCodigoFromCfg(Map<String, Object?> cfg) {
    return _toStr(_getFieldFromCfg(cfg, "CLIENTE_CODIGO"), def: "")
        .trim()
        .toUpperCase();
  }

  Future<String> getImportacaoId() async {
    return _toStr(await _getField("IMPORTACAO_ID"), def: "").trim();
  }

  Future<void> setImportacaoId(String id) async {
    final db = await _db;
    await _ensureColumns(db);
    await db.update("CONFIG", {"IMPORTACAO_ID": id.trim()});
  }

  /// ✅ ID do vagão é TEXT (UUID)
  Future<String> getIdVagao() async =>
      _toStr(await _getField("ID_VAGAO"), def: "").trim();

  Future<String> getNomeVagao() async =>
      _toStr(await _getField("NOME_VAGAO"), def: "").trim();

  /// TEMPO_MISTURA em MINUTOS (INTEGER)
  Future<int> getTempoMisturaMinutos() async {
    final v = await _getField("TEMPO_MISTURA");
    return _toInt(v, def: 0);
  }

  /// TOLERANCIA_CARREGAMENTO em % (NUMERIC) ex: 2.5 = 2,5%
  Future<double> getToleranciaCarregamentoPct() async {
    final raw =
        _toStr(await _getField("TOLERANCIA_CARREGAMENTO"), def: "").trim();
    if (raw.isEmpty) return 0.0;

    // apenas troca vírgula por ponto
    final norm = raw.replaceAll(",", ".");
    final d = double.tryParse(norm) ?? 0.0;
    return d < 0 ? 0.0 : d;
  }

  /// ✅ opcional: tolerância em KG
  Future<double> getToleranciaCarregamentoKg() async {
    final v = await _getField("TOLERANCIA_CARREGAMENTO_KG");
    final d = _toDouble(v, def: 0.0);
    return d < 0 ? 0.0 : d;
  }

  /// Mínimo de kg para gravar linha em CADASTRO_FORNECIMENTO (padrão 50).
  Future<double> getPontoCorteFornecimentoKg() async {
    final v = await _getField("PONTO_CORTE_FORNECIMENTO_KG");
    final d = _toDouble(v, def: 50.0);
    return d < 0 ? 0.0 : d;
  }

  // =========================================================
  // ✅ Fazendas
  // =========================================================
  Future<String> getIdFazendaSelecionada() async {
    final v1 = await _getField("ID_FAZENDA");
    final v2 = await _getField("IDFAZENDA");
    final v3 = await _getField("FAZENDA_ID");
    return _toStr(v1 ?? v2 ?? v3, def: "").trim();
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
      def: ConfigOptions.defaultApiPort,
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

  // =========================================================
  // ✅ PENDÊNCIAS DE SINCRONIZAÇÃO (OUTBOX)
  // =========================================================

  Future<({bool skip, List<String> where})> _fabricacaoPendenteFiltro() async {
    final flowMode = await getFabricacaoFlowMode();
    final tipoTrabalho = await getTipoTrabalho();

    if (flowMode == FabricacaoFlowMode.startStationFinishTruck &&
        tipoTrabalho == 1) {
      return (skip: true, where: const <String>[]);
    }

    final where = <String>["IFNULL(FLAG_SYNC,0) = 0"];

    if (flowMode == FabricacaoFlowMode.startStationFinishTruck) {
      where.add("IFNULL(FAB_STATUS,0) = $fabricacaoStatusFinalizada");
      where.add("UPPER(TRIM(COALESCE(ORIGIN_DEVICE,''))) = 'CAMINHAO'");
    } else {
      where.add("IFNULL(QTD_REALIZADA,0) > 0");
    }

    return (skip: false, where: where);
  }

  String _fmtDataBr(String iso) {
    final t = iso.trim();
    if (t.length >= 10) {
      final p = t.substring(0, 10).split("-");
      if (p.length == 3) return "${p[2]}/${p[1]}/${p[0]}";
    }
    return t.isEmpty ? "-" : t;
  }

  double _toD(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().replaceAll(",", ".")) ?? 0;
  }

  Future<List<SyncPendenciaRegistro>> listPendenciasSyncDetalhe({
    int limitPerTipo = 80,
  }) async {
    final out = <SyncPendenciaRegistro>[];
    out.addAll(await _listGravaTagPendenteDetalhe(limit: limitPerTipo));
    out.addAll(await _listFabricacaoPendenteDetalhe(limit: limitPerTipo));
    out.addAll(await _listFornecimentoPendenteDetalhe(limit: limitPerTipo));
    return out;
  }

  Future<List<SyncPendenciaRegistro>> _listGravaTagPendenteDetalhe({
    int limit = 80,
  }) async {
    final db = await _db;
    try {
      final rows = await db.rawQuery("""
        SELECT
          g.ID AS id,
          COALESCE(g.TAG, '') AS tag,
          COALESCE(g.ID_PASTO_CURRAL, '') AS id_curral,
          COALESCE(c.NOME, b.NOME_LOCAL, g.ID_PASTO_CURRAL, '') AS nome_curral
        FROM GRAVA_TAG g
        LEFT JOIN CADASTRO_CURRAL c
          ON TRIM(CAST(c.ID AS TEXT)) = TRIM(CAST(g.ID_PASTO_CURRAL AS TEXT))
        LEFT JOIN DETALHES_BAIAS b
          ON TRIM(CAST(b.ID AS TEXT)) = TRIM(CAST(g.ID_PASTO_CURRAL AS TEXT))
        WHERE IFNULL(g.SYNC, 0) = 0
        ORDER BY g.ID DESC
        LIMIT ?
      """, [limit]);

      return rows.map((r) {
        final nome = (r["nome_curral"] ?? "").toString().trim();
        final tag = (r["tag"] ?? "").toString().trim();
        final idCurral = (r["id_curral"] ?? "").toString().trim();
        final titulo = nome.isNotEmpty
            ? nome
            : (idCurral.isNotEmpty ? "Curral $idCurral" : "Curral");
        final tagTxt = tag.isEmpty ? "sem TAG" : tag;
        return SyncPendenciaRegistro(
          tipo: SyncPendenciaTipo.gravaTag,
          titulo: titulo,
          subtitulo: "TAG: $tagTxt",
        );
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<SyncPendenciaRegistro>> _listFabricacaoPendenteDetalhe({
    int limit = 80,
  }) async {
    final db = await _db;
    try {
      final filtro = await _fabricacaoPendenteFiltro();
      if (filtro.skip) return const [];

      final rows = await db.rawQuery("""
        SELECT
          h.ID AS id,
          substr(COALESCE(h.DATA_FABRICACAO, ''), 1, 10) AS data_iso,
          COALESCE(h.TRATO, 0) AS trato,
          COALESCE(d.NOME, h.ID_DIETA, '') AS racao,
          COALESCE(h.QTD_REALIZADA, 0) AS realizado
        FROM CADASTRO_FABRICA_RACAO h
        LEFT JOIN DIETA d ON TRIM(CAST(d.ID AS TEXT)) = TRIM(CAST(h.ID_DIETA AS TEXT))
        WHERE ${filtro.where.join(" AND ")}
        ORDER BY h.DATA_FABRICACAO DESC, h.HORA_INICIO DESC, h.ID DESC
        LIMIT ?
      """, [limit]);

      return rows.map((r) {
        final racao = (r["racao"] ?? "").toString().trim();
        final trato = int.tryParse("${r["trato"]}") ?? 0;
        final data = _fmtDataBr((r["data_iso"] ?? "").toString());
        final kg = _toD(r["realizado"]);
        final titulo = racao.isEmpty
            ? "Fabricação trato $trato"
            : "$racao · Trato $trato";
        return SyncPendenciaRegistro(
          tipo: SyncPendenciaTipo.fabricacao,
          titulo: titulo,
          subtitulo: "$data · ${kg.toStringAsFixed(0)} kg",
        );
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<SyncPendenciaRegistro>> _listFornecimentoPendenteDetalhe({
    int limit = 80,
  }) async {
    final db = await _db;
    try {
      final rows = await db.rawQuery("""
        SELECT
          substr(COALESCE(F.DATA, ''), 1, 10) AS data_iso,
          COALESCE(F.TRATO, 0) AS trato,
          COALESCE(F.REALIZADO, 0) AS realizado,
          COALESCE(B.NOME_LOCAL, F.ID_BAIA, '') AS nome_baia,
          COALESCE(d.NOME, F.ID_DIETA, '') AS racao
        FROM CADASTRO_FORNECIMENTO F
        LEFT JOIN DETALHES_BAIAS B
          ON TRIM(CAST(B.ID AS TEXT)) = TRIM(CAST(F.ID_BAIA AS TEXT))
        LEFT JOIN DIETA d
          ON TRIM(CAST(d.ID AS TEXT)) = TRIM(CAST(F.ID_DIETA AS TEXT))
        WHERE IFNULL(F.REALIZADO, 0) > 0
          AND IFNULL(F.FLAG_SYNC, 0) = 0
        ORDER BY F.DATA DESC, F.HORA_INICIO DESC, F.ID DESC
        LIMIT ?
      """, [limit]);

      return rows.map((r) {
        final baia = (r["nome_baia"] ?? "").toString().trim();
        final trato = int.tryParse("${r["trato"]}") ?? 0;
        final data = _fmtDataBr((r["data_iso"] ?? "").toString());
        final kg = _toD(r["realizado"]);
        final racao = (r["racao"] ?? "").toString().trim();
        final titulo = baia.isEmpty ? "Trato $trato" : "$baia · Trato $trato";
        final racaoTxt = racao.isEmpty ? "" : " · $racao";
        return SyncPendenciaRegistro(
          tipo: SyncPendenciaTipo.fornecimento,
          titulo: titulo,
          subtitulo: "$data · ${kg.toStringAsFixed(0)} kg$racaoTxt",
        );
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<int> countFabricacaoPendenteSync() async {
    final db = await _db;
    try {
      final filtro = await _fabricacaoPendenteFiltro();
      if (filtro.skip) return 0;

      final rows = await db.rawQuery(
        "SELECT COUNT(*) AS QTD "
        "FROM CADASTRO_FABRICA_RACAO "
        "WHERE ${filtro.where.join(" AND ")}",
      );
      if (rows.isEmpty) return 0;
      final v = rows.first["QTD"];
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v?.toString() ?? "") ?? 0;
    } catch (_) {
      return 0; // se tabela/coluna não existir ainda em algum device velho
    }
  }

  Future<int> countFornecimentoPendenteSync() async {
    final db = await _db;
    try {
      final rows = await db.rawQuery(
        "SELECT COUNT(*) AS QTD "
        "FROM CADASTRO_FORNECIMENTO "
        "WHERE IFNULL(REALIZADO,0) > 0 AND IFNULL(FLAG_SYNC,0) = 0",
      );
      if (rows.isEmpty) return 0;
      final v = rows.first["QTD"];
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v?.toString() ?? "") ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<int> countGravaTagPendenteSync() async {
    final db = await _db;
    try {
      final rows = await db.rawQuery(
        "SELECT COUNT(*) AS QTD "
        "FROM GRAVA_TAG "
        "WHERE IFNULL(SYNC,0) = 0",
      );
      if (rows.isEmpty) return 0;
      final v = rows.first["QTD"];
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v?.toString() ?? "") ?? 0;
    } catch (_) {
      return 0;
    }
  }

  // -------------------------
  // ESPELHO (PÁ)
  // -------------------------
  Future<int> getPortaEspelho() async {
    final v1 = await _getField("PORTA_ESPELHO");
    final v = _toInt(v1, def: 9000);
    return v <= 0 ? 9000 : v;
  }

  /// 0 = Pá (espelhamento), 1 = LED Bluetooth
  Future<int> getModoSaidaFabricacao() async {
    final v = _toInt(await _getField("MODO_SAIDA_FAB"), def: 0);
    return (v == 1) ? 1 : 0;
  }

  Future<String> getLedBtAddress() async =>
      _toStr(await _getField("LED_BT_ADDRESS"), def: "").trim();

  Future<String> getLedBtName() async =>
      _toStr(await _getField("LED_BT_NAME"), def: "").trim();

  // -------------------------
  // BRIDGE ESTACIONARIO
  // -------------------------
  Future<String> getHostEstacionario() async =>
      _hostFromBaseUrl(
        _toStr(await _getField("STATION_BASE_URL"), def: ""),
        fallback: _toStr(await _getField("HOST_ESTACIONARIO"), def: ""),
      );

  Future<int> getPortaEstacionario() async {
    final v = _toInt(await _getField("PORTA_ESTACIONARIO"), def: 8080);
    if (v <= 0) return 8080;
    // Android normalmente bloqueia bind em portas privilegiadas (<1024).
    if (v < 1024) return 8080;
    return v;
  }

  Future<FabricacaoFlowMode> getFabricacaoFlowMode() async {
    return fabricacaoFlowModeFromDb(await _getField("FLOW_MODE"));
  }

  Future<String> getStationWifiSsid() async =>
      _toStr(await _getField("STATION_WIFI_SSID"), def: "").trim();

  Future<String> getStationWifiPassword() async =>
      _toStr(await _getField("STATION_WIFI_PASSWORD"), def: "").trim();

  Future<String> getStationBaseUrl() async {
    var raw = _toStr(await _getField("STATION_BASE_URL"), def: "").trim();
    if (raw.isEmpty) {
      final host = _toStr(await _getField("HOST_ESTACIONARIO"), def: "").trim();
      if (host.isNotEmpty) {
        final port = await getPortaEstacionario();
        raw = "http://$host:$port";
      }
    }
    return normalizeStationBridgeUrl(raw);
  }

  Future<String> getStationId() async =>
      _toStr(await _getField("STATION_ID"), def: "").trim();

  Future<String> getStationName() async =>
      _toStr(await _getField("STATION_NAME"), def: "").trim();

  Future<String> getTruckDeviceId() async =>
      _toStr(await _getField("TRUCK_DEVICE_ID"), def: "").trim();

  /// Nome amigável da estação (STATION_NAME → NOME_VAGAO → fallback).
  Future<String> getStationDisplayName() async {
    final named = await getStationName();
    if (named.isNotEmpty) return named;
    final vagao = await getNomeVagao();
    if (vagao.isNotEmpty) return vagao;
    return "Estacionária";
  }

  /// Gera e persiste STATION_ID uma vez (nunca regenera se já existir).
  /// Só auto-gera quando TIPO_TRABALHO=1 (estacionária).
  Future<String> ensureStationId() async {
    final existing = await getStationId();
    if (existing.isNotEmpty) return existing;
    final tipo = await getTipoTrabalho();
    if (tipo != 1) return "";
    final id = const Uuid().v4();
    final cfg = await getConfig() ?? <String, Object?>{};
    cfg["STATION_ID"] = id;
    await saveConfig(cfg);
    return id;
  }

  /// Gera e persiste TRUCK_DEVICE_ID uma vez.
  /// Só auto-gera quando TIPO_TRABALHO=2 (vagão/caminhão).
  Future<String> ensureTruckDeviceId() async {
    final existing = await getTruckDeviceId();
    if (existing.isNotEmpty) return existing;
    final tipo = await getTipoTrabalho();
    if (tipo != 2) return "";
    final id = const Uuid().v4();
    final cfg = await getConfig() ?? <String, Object?>{};
    cfg["TRUCK_DEVICE_ID"] = id;
    await saveConfig(cfg);
    return id;
  }

  Future<void> setStationName(String name) async {
    final cfg = await getConfig() ?? <String, Object?>{};
    cfg["STATION_NAME"] = name.trim();
    await saveConfig(cfg);
  }

  Future<void> setOperacaoEstacionarioConfig({
    required FabricacaoFlowMode flowMode,
    required String stationWifiSsid,
    required String stationWifiPassword,
    required String stationBaseUrl,
    String? stationName,
  }) async {
    final cfg = await getConfig() ?? <String, Object?>{};
    cfg["FLOW_MODE"] = fabricacaoFlowModeToDb(flowMode);
    cfg["STATION_WIFI_SSID"] = stationWifiSsid.trim();
    cfg["STATION_WIFI_PASSWORD"] = stationWifiPassword;
    cfg["STATION_BASE_URL"] = stationBaseUrl.trim();
    if (stationName != null) {
      cfg["STATION_NAME"] = stationName.trim();
    }
    await saveConfig(cfg);
  }

  String _hostFromBaseUrl(String baseUrl, {required String fallback}) {
    final uri = Uri.tryParse(baseUrl.trim());
    if (uri != null && uri.host.trim().isNotEmpty) return uri.host.trim();
    return fallback.trim();
  }

  int? _portFromBaseUrl(String baseUrl) {
    final uri = Uri.tryParse(baseUrl.trim());
    if (uri == null || uri.host.trim().isEmpty) return null;
    if (uri.hasPort) return uri.port;
    return uri.scheme.toLowerCase() == "https" ? 443 : 8080;
  }
}
