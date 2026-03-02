// lib/services/bootstrap_sync.dart
import "package:sqflite/sqflite.dart";

import "../db/app_db.dart";
import "../repo/config_repo.dart";
import "../repo/vagao_repo.dart";
import "../repo/fazenda_repo.dart";
import "../repo/user_repo.dart";
import "api_service.dart";

class BootstrapSync {
  final ConfigRepo cfgRepo;
  final VagaoRepo vagaoRepo;
  final FazendaRepo fazendaRepo;
  final UserRepo userRepo;

  BootstrapSync({
    required this.cfgRepo,
    required this.vagaoRepo,
    required this.fazendaRepo,
    required this.userRepo,
  });

  Future<ApiService> _apiFromCfg(Map<String, Object?> cfg) async {
    final base = cfgRepo.buildBaseUrl(cfg);
    if (base.isEmpty) throw Exception("HOST/PORTA inválidos.");
    return ApiService(baseUrl: base);
  }

  // =========================
  // Helpers
  // =========================
  static num _toNum(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v;

    var s = v.toString().trim();
    if (s.isEmpty || s.toLowerCase() == "null") return 0;

    // aceita "1.234,56" e "1,234.56"
    final hasComma = s.contains(",");
    final hasDot = s.contains(".");
    if (hasComma && hasDot) {
      // assume BR: "1.234,56"
      s = s.replaceAll(".", "").replaceAll(",", ".");
    } else if (hasComma) {
      s = s.replaceAll(",", ".");
    }
    return num.tryParse(s) ?? 0;
  }

  static String _ymdFromAny(dynamic v, {String fallback = ""}) {
    final s = (v ?? "").toString().trim();
    if (s.isEmpty || s.toLowerCase() == "null") return fallback;
    return s.length >= 10 ? s.substring(0, 10) : s;
  }

  // helper: normaliza as chaves do map (lowercase + trim)
  static Map<String, dynamic> _normalizeKeys(Map raw) {
    final out = <String, dynamic>{};
    raw.forEach((k, v) {
      final key = (k ?? "").toString().trim().toLowerCase();
      if (key.isNotEmpty) out[key] = v;
    });
    return out;
  }

  static String _pickStr(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty && s.toLowerCase() != "null") return s;
    }
    return "";
  }

  // =========================
  // BOOTSTRAP: VAGÃO/FAZENDA/USUÁRIO/BAIAS/DIETAS
  // =========================

  Future<void> baixarVagao(Map<String, Object?> cfg) async {
    final api = await _apiFromCfg(cfg);
    final list = await api.getVagoes();

    final db = await AppDb.instance.db;
    await db.transaction((txn) async {
      await txn.delete("VAGAO");
      for (final it in list) {
        final m = Map<String, dynamic>.from(it as Map);
        await txn.insert(
          "VAGAO",
          {
            "ID": (m["id"] ?? "").toString(),
            "NOME": (m["nome"] ?? "").toString(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<void> baixarFazendas(Map<String, Object?> cfg) async {
    final api = await _apiFromCfg(cfg);
    final list = await api.getFazendas();

    final db = await AppDb.instance.db;
    await db.transaction((txn) async {
      await txn.delete("CADASTRO_FAZENDAS");
      for (final it in list) {
        final m = Map<String, dynamic>.from(it as Map);
        await txn.insert(
          "CADASTRO_FAZENDAS",
          {
            "ID": (m["idfazenda"] ?? "").toString(),
            "NOME": (m["fazenda"] ?? "").toString(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<void> baixarUsuarios(Map<String, Object?> cfg, String idFazenda) async {
    final api = await _apiFromCfg(cfg);
    final list = await api.getUsuarios(idFazenda);

    final db = await AppDb.instance.db;
    await db.transaction((txn) async {
      await txn.delete("CADASTRO_USUARIO");
      for (final it in list) {
        final m = Map<String, dynamic>.from(it as Map);
        await txn.insert(
          "CADASTRO_USUARIO",
          {
            "ID": (m["id"] ?? "").toString(),
            "NOME": (m["nome"] ?? "").toString(),
            "LOGIN": (m["usuario"] ?? "").toString(),
            "SENHA": (m["senha"] ?? "").toString(),
            "CARGO": (m["cargo"] ?? "").toString(),
            "ID_FAZENDA": idFazenda,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<void> baixarBaias(Map<String, Object?> cfg, String idFazenda) async {
    final api = await _apiFromCfg(cfg);
    final list = await api.getBaias(idFazenda);

    final db = await AppDb.instance.db;
    await db.transaction((txn) async {
      await txn.delete("DETALHES_BAIAS");
      for (final it in list) {
        final m = Map<String, dynamic>.from(it as Map);
        await txn.insert(
          "DETALHES_BAIAS",
          {
            "ID": (m["idBaia"] ?? "").toString(),
            "ID_LOTE": (m["idLote"] ?? "").toString(),
            "NOME_LOCAL": (m["nomeLocal"] ?? "").toString(),

            // ✅ LINHA sempre TEXT
            "LINHA": (m["linha"] ?? "").toString(),

            // ✅ ORDER_TRATO sempre int
            "ORDER_TRATO": int.tryParse((m["ordemTrato"] ?? "0").toString()) ?? 0,

            "ID_FAZENDA": (m["idFazenda"] ?? "").toString(),
            "RFID": (m["rfid"] ?? "").toString(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<void> baixarDietas(Map<String, Object?> cfg, String idFazenda) async {
    final api = await _apiFromCfg(cfg);
    final list = await api.getDietas(idFazenda);

    final db = await AppDb.instance.db;
    await db.transaction((txn) async {
      await txn.delete("DIETA");
      for (final it in list) {
        final m = Map<String, dynamic>.from(it as Map);
        await txn.insert(
          "DIETA",
          {
            "ID": (m["id"] ?? "").toString(),
            "NOME": (m["nomeDieta"] ?? "").toString(),
            "TIPO": (m["tipoDieta"] ?? "").toString(),
            "MS": _toNum(m["msDieta"]),
            "ID_FAZENDA": (m["idFazenda"] ?? "").toString(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<void> baixarDietasDetalhes(Map<String, Object?> cfg, String idFazenda) async {
    final api = await _apiFromCfg(cfg);
    final list = await api.getDietasDetalhes(idFazenda);

    final db = await AppDb.instance.db;
    await db.transaction((txn) async {
      await txn.delete("DETALHES_DIETAS");
      for (final it in list) {
        final m = Map<String, dynamic>.from(it as Map);

        final prePesagem = (m["prePesagem"] ?? "").toString().trim().toUpperCase();
        final prePesadoInt = (prePesagem == "S") ? 1 : 0;

        await txn.insert(
          "DETALHES_DIETAS",
          {
            "ID": (m["id"] ?? "").toString(),
            "ID_DIETA": (m["idDieta"] ?? "").toString(),
            "ID_INSUMO": (m["idInsumo"] ?? "").toString(),
            "INSUMO": (m["ingrediente"] ?? "").toString(),
            "MS_INSUMO": _toNum(m["msInsumo"]),
            "MS_INCLUSAO": _toNum(m["msInclusao"]),
            "MN_PERCENT": _toNum(m["mnPerc"]),
            "MN_PERC": _toNum(m["mnPerc"]),
            "ORDEM": int.tryParse((m["ordem"] ?? "0").toString()) ?? 0,
            "PRE_PESADO": prePesadoInt,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  // =========================================================
  // ✅ PREVISAO TRATO (ROBUSTO)
  //
  // Mudanças aplicadas:
  // 1) NÃO dá delete geral: limpa apenas o DIA/TRATO e (se existir) a RAÇÃO.
  // 2) Preserva REALIZADO_KG local: se API vier 0/null e local > 0, mantém local.
  // 3) DATA sempre gravada como "YYYY-MM-DD"
  // 4) Logs úteis + amostra
  // =========================================================
  Future<int> baixarPrevisaoTrato(
    Map<String, Object?> cfg,
    String idFazenda,
    String dataYmd, {
    void Function(String)? log,
  }) async {
    final api = await _apiFromCfg(cfg);
    final list = await api.getPrevisaoTrato(idFazenda, dataYmd);

    log?.call("📥 Previsão (API): ${list.length} registros");

    final db = await AppDb.instance.db;
    int inserted = 0;

    // --- helper: lê realizado local antes de limpar (pra preservar) ---
    Future<Map<String, double>> loadRealizadoLocalMap(Transaction txn) async {
      // chave: "idFornecimento|idBaia|trato|data|idRacao"
      final map = <String, double>{};

      final rows = await txn.rawQuery("""
        SELECT
          COALESCE(ID_FORNECIMENTO,'') AS id_fornecimento,
          COALESCE(ID_BAIA,'')         AS id_baia,
          COALESCE(TRATO,0)            AS trato,
          substr(COALESCE(DATA,''),1,10) AS data_ymd,
          COALESCE(ID_RACAO,'')        AS id_racao,
          COALESCE(REALIZADO_KG,0)     AS realizado
        FROM PREVISAO
        WHERE substr(COALESCE(DATA,''),1,10) = ?
      """, [dataYmd]);

      for (final r in rows) {
        final idF = (r["id_fornecimento"] ?? "").toString().trim();
        final idB = (r["id_baia"] ?? "").toString().trim();
        final t = int.tryParse((r["trato"] ?? "0").toString()) ?? 0;
        final d = (r["data_ymd"] ?? "").toString().trim();
        final rac = (r["id_racao"] ?? "").toString().trim();
        final real = _toNum(r["realizado"]).toDouble();

        if (idB.isEmpty || d.isEmpty) continue;
        final key = "$idF|$idB|$t|$d|$rac".toUpperCase();
        if (real > 0) map[key] = real;
      }

      return map;
    }

    // --- helper: delete seletivo (dia/trato/ração) ---
    Future<void> clearPrevisaoDiaTratoRacao(
      Transaction txn, {
      required String dayYmd,
      required int trato,
      String? idRacao,
    }) async {
      final where = StringBuffer("substr(DATA,1,10) = ? AND TRATO = ?");
      final args = <Object?>[dayYmd, trato];

      final rac = (idRacao ?? "").trim();
      if (rac.isNotEmpty) {
        where.write(" AND TRIM(ID_RACAO) = TRIM(?)");
        args.add(rac);
      }

      await txn.delete("PREVISAO", where: where.toString(), whereArgs: args);
    }

    await db.transaction((txn) async {
      // 1) snapshot do realizado local do dia (pra preservar)
      final realizadoLocal = await loadRealizadoLocalMap(txn);

      // 2) decide “escopo” do delete:
      //    - se a API retorna só 1 ração (comum), a gente limpa apenas essa ração
      //    - senão, limpa só por trato (todas rações daquele trato)
      String? racaoUnica;
      final setRacoes = <String>{};
      final setTratos = <int>{};

      for (final it in list) {
        if (it is! Map) continue;
        final m = _normalizeKeys(it);
        final idRacao = _pickStr(m, ["idracao", "id_racao", "iddieta", "id_dieta"]).trim();
        if (idRacao.isNotEmpty) setRacoes.add(idRacao);

        final t = int.tryParse(_pickStr(m, ["trato", "tr", "ordemtrato", "ordem_trato"])) ?? 0;
        if (t > 0) setTratos.add(t);
      }

      // se a API não mandou trato nos itens, usa "todas"? não: aqui precisa do trato.
      // então vamos limpar por cada trato detectado; se vazio, não faz delete.
      if (setTratos.isEmpty) {
        log?.call("⚠️ API não retornou TRATO nos itens. Não foi possível limpar PREVISAO seletivamente.");
      } else {
        if (setRacoes.length == 1) racaoUnica = setRacoes.first;

        for (final t in setTratos) {
          await clearPrevisaoDiaTratoRacao(
            txn,
            dayYmd: dataYmd,
            trato: t,
            idRacao: racaoUnica, // ✅ se 1 ração, limpa só ela; senão limpa todas do trato
          );
        }
      }

      // 3) inserts (preservando realizado)
      for (final it in list) {
        final raw = (it is Map) ? it : <dynamic, dynamic>{};
        final m = _normalizeKeys(raw);

        // ✅ tenta todas as variações comuns de id da baia
        final idBaia = _pickStr(m, [
          "idbaia",
          "id_baia",
          "baia",
          "baia_id",
          "idbaiafk",
          "id", // (se a API estiver errada e mandar ID da baia como "id")
        ]);

        // data vindo da API
        final data = _ymdFromAny(
          m["data"] ?? m["data_prev"] ?? m["dataprev"],
          fallback: dataYmd,
        );

        // trato
        final trato =
            int.tryParse(_pickStr(m, ["trato", "tr", "ordemtrato", "ordem_trato"])) ?? 0;

        // idRacao / idDieta
        final idRacao = _pickStr(m, ["idracao", "id_racao", "iddieta", "id_dieta"]);

        // valores
        final previsto = _toNum(m["previsto"] ?? m["previsto_kg"] ?? m["previstokg"]).toDouble();
        final apiRealizado =
            _toNum(m["realizado"] ?? m["realizado_kg"] ?? m["realizadokg"]).toDouble();

        final idFornecimento = _pickStr(m, ["idfornecimento", "id_fornecimento"]);

        if (idBaia.isEmpty) {
          log?.call(
            "⚠️ PREVISAO ignorada (ID_BAIA vazio). Keys: ${m.keys.toList()} | raw: $raw",
          );
          continue;
        }
        if (trato <= 0) {
          log?.call(
            "⚠️ PREVISAO ignorada (TRATO inválido). idBaia=$idBaia raw: $raw",
          );
          continue;
        }

        // ✅ preserva realizado local se API veio 0 e local > 0
        final key = "$idFornecimento|$idBaia|$trato|$data|$idRacao".toUpperCase();
        final localReal = realizadoLocal[key] ?? 0.0;
        final realizadoFinal = (apiRealizado <= 0 && localReal > 0) ? localReal : apiRealizado;

        await txn.insert(
          "PREVISAO",
          {
            "ID_FORNECIMENTO": idFornecimento,
            "DATA": data,
            "ID_BAIA": idBaia,
            "TRATO": trato,
            "PREVISTO_KG": previsto,
            "REALIZADO_KG": realizadoFinal,
            "ID_RACAO": idRacao,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        inserted++;
      }
    });

    // 🔍 LOGS DE CONFERÊNCIA
    final r = await db.rawQuery(
      "SELECT COUNT(*) as c FROM PREVISAO WHERE substr(DATA,1,10)=?",
      [dataYmd],
    );
    final total = (r.first["c"] as int?) ?? 0;

    log?.call("💾 Previsão (SQLite): $inserted gravados");
    log?.call("📊 PREVISAO no SQLite (dia $dataYmd): $total registros");

    final sample = await db.rawQuery("""
      SELECT ID_BAIA, DATA, TRATO, ID_RACAO, PREVISTO_KG, REALIZADO_KG
      FROM PREVISAO
      WHERE substr(DATA,1,10)=?
      LIMIT 5
    """, [dataYmd]);

    log?.call("🔎 Amostra PREVISAO:");
    for (final row in sample) {
      log?.call(" → $row");
    }

    return inserted;
  }
}


