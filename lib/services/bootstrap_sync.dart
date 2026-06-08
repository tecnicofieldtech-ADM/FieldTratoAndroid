// lib/services/bootstrap_sync.dart
import "package:flutter/foundation.dart";
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
    final backend = int.tryParse((cfg["BACKEND"] ?? "0").toString()) ?? 0;
    return ApiService(baseUrl: base, backend: backend);
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

    if (kDebugMode) {
      debugPrint("[BOOT_BAIAS] API retornou ${list.length} registros");
    }

    final db = await AppDb.instance.db;
    await db.transaction((txn) async {
      await txn.delete("DETALHES_BAIAS");
      var inserted = 0;
      final samples = <String>[];
      for (final it in list) {
        final m = _normalizeKeys(it as Map);

        final idBaia = _pickStr(m, [
          "idbaia",
          "id_baia",
          "id",
          "idcurral",
          "id_curral",
          "idpastocurral",
          "id_pasto_curral",
        ]);
        if (idBaia.isEmpty) continue;

        final idLote = _pickStr(m, ["idlote", "id_lote", "loteid", "lote_id"]);
        final nomeLocal = _pickStr(m, [
          "nomelocal",
          "nome_local",
          "baia",
          "curral",
          "nome",
          "descricao",
        ]);
        final linha = _pickStr(m, ["linha", "linha_trato", "linhatrato"]);
        final ordemTratoRaw = _pickStr(
          m,
          ["ordemtrato", "ordem_trato", "ordertrato", "order_trato", "ordem"],
        );
        final ordemTrato = int.tryParse(ordemTratoRaw) ?? 0;

        final idFaz = _pickStr(m, [
          "idfazenda",
          "id_fazenda",
          "fazendaid",
          "fazenda_id",
        ]);
        final idFazFinal = idFaz.isNotEmpty ? idFaz : idFazenda;

        final rfid = _pickStr(m, ["rfid", "tag", "epc"]);

        await txn.insert(
          "DETALHES_BAIAS",
          {
            "ID": idBaia,
            "ID_LOTE": idLote,
            "NOME_LOCAL": nomeLocal,

            // ✅ LINHA sempre TEXT
            "LINHA": linha,

            // ✅ ORDER_TRATO sempre int
            "ORDER_TRATO": ordemTrato,

            "ID_FAZENDA": idFazFinal,
            "RFID": rfid,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        inserted++;
        if (samples.length < 5) {
          samples.add("$idBaia|$idFazFinal|$nomeLocal");
        }
      }

      if (kDebugMode) {
        debugPrint("[BOOT_BAIAS] inseridos=$inserted");
        if (samples.isNotEmpty) {
          debugPrint("[BOOT_BAIAS] amostra=${samples.join(" ; ")}");
        }
      }
    });
  }

  Future<void> baixarDietas(Map<String, Object?> cfg, String idFazenda) async {
    final api = await _apiFromCfg(cfg);
    final list = await api.getDietas(idFazenda);

    if (kDebugMode) {
      debugPrint("[BOOT_DIETAS] API retornou ${list.length} registros");
    }

    final db = await AppDb.instance.db;
    await db.transaction((txn) async {
      await txn.delete("DIETA");
      var inserted = 0;
      final samples = <String>[];
      for (final it in list) {
        final m = _normalizeKeys(it as Map);

        final id = _pickStr(m, ["id", "iddieta", "id_dieta", "idracao", "id_racao"]);
        if (id.isEmpty) continue;

        final nome = _pickStr(m, ["nomedieta", "nome_dieta", "dieta", "nome", "descricao"]);
        final tipo = _pickStr(m, ["tipodieta", "tipo_dieta", "tipo"]);
        final ms = _toNum(m["msdieta"] ?? m["ms_dieta"] ?? m["ms"]);

        final idFaz = _pickStr(m, [
          "idfazenda",
          "id_fazenda",
          "fazendaid",
          "fazenda_id",
        ]);
        final idFazFinal = idFaz.isNotEmpty ? idFaz : idFazenda;

        await txn.insert(
          "DIETA",
          {
            "ID": id,
            "NOME": nome,
            "TIPO": tipo,
            "MS": ms,
            "ID_FAZENDA": idFazFinal,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        inserted++;
        if (samples.length < 5) {
          samples.add("$id|$idFazFinal|$nome");
        }
      }

      if (kDebugMode) {
        debugPrint("[BOOT_DIETAS] inseridas=$inserted");
        if (samples.isNotEmpty) {
          debugPrint("[BOOT_DIETAS] amostra=${samples.join(" ; ")}");
        }
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
        final m = _normalizeKeys(it as Map);

        final idDieta = _pickStr(m, ["iddieta", "id_dieta", "idracao", "id_racao"]);
        final idInsumo = _pickStr(m, [
          "idinsumo",
          "id_insumo",
          "idingrediente",
          "id_ingrediente",
          "insumoid",
        ]);

        final ordemRaw = _pickStr(m, ["ordem", "ordem_trato", "ordemtrato"]);
        final ordem = int.tryParse(ordemRaw) ?? 0;

        final id = _pickStr(m, ["id", "iddetalhe", "id_detalhe"]);
        final idFinal = id.isNotEmpty
            ? id
            : [idDieta, idInsumo, ordem.toString()].where((e) => e.isNotEmpty).join("::");
        if (idFinal.isEmpty || idDieta.isEmpty) continue;

        final prePesagem = _pickStr(m, [
          "prepesagem",
          "pre_pesagem",
          "prepesado",
          "pre_pesado",
        ]).toUpperCase();
        final prePesadoInt = (prePesagem == "S") ? 1 : 0;

        final ingrediente = _pickStr(m, [
          "ingrediente",
          "insumo",
          "nomeinsumo",
          "nome_insumo",
          "descricao",
        ]);

        final msInsumo = _toNum(m["msinsumo"] ?? m["ms_insumo"] ?? m["ms"]);
        final msInclusao = _toNum(m["msinclusao"] ?? m["ms_inclusao"] ?? m["mnperc"] ?? m["mn_perc"]);
        final mnPerc = _toNum(m["mnperc"] ?? m["mn_perc"] ?? m["percentual"] ?? m["perc"]);

        await txn.insert(
          "DETALHES_DIETAS",
          {
            "ID": idFinal,
            "ID_DIETA": idDieta,
            "ID_INSUMO": idInsumo,
            "INSUMO": ingrediente,
            "MS_INSUMO": msInsumo,
            "MS_INCLUSAO": msInclusao,
            "MN_PERCENT": mnPerc,
            "MN_PERC": mnPerc,
            "ORDEM": ordem,
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
  // 2) PREVISAO.REALIZADO_KG = valor da API (acumulado no servidor).
  //    O mapa local soma CADASTRO_FORNECIMENTO para exibição.
  // 3) DATA sempre gravada como "YYYY-MM-DD"
  // 4) Logs úteis + amostra
  // =========================================================
  double _mergeRealizadoPosDownload({
    required double localReal,
    required double apiRealizado,
  }) {
    if (apiRealizado <= 0) return localReal > 0 ? localReal : 0;
    if (localReal <= 0) return apiRealizado;

    // Servidor CG Pec (FornecimentoAcumulativo=1) pode devolver ~2x após re-sync.
    if (apiRealizado >= localReal * 1.8 &&
        apiRealizado <= localReal * 2.2) {
      return localReal;
    }

    return apiRealizado >= localReal ? apiRealizado : localReal;
  }

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

        // PREVISAO guarda só o acumulado vindo da API; mapa usa também CADASTRO local.
        final key = "$idFornecimento|$idBaia|$trato|$data|$idRacao".toUpperCase();
        final localReal = realizadoLocal[key] ?? 0.0;
        final realizadoFinal = apiRealizado > 0
            ? _mergeRealizadoPosDownload(
                localReal: localReal,
                apiRealizado: apiRealizado,
              )
            : 0.0;

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


