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

  Future<void> baixarUsuarios(
      Map<String, Object?> cfg, String idFazenda) async {
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
            "LINHA": (m["linha"] ?? "").toString(),
            "ORDER_TRATO":
                int.tryParse((m["ordemTrato"] ?? "0").toString()) ?? 0,
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

  Future<void> baixarDietasDetalhes(
      Map<String, Object?> cfg, String idFazenda) async {
    final api = await _apiFromCfg(cfg);
    final list = await api.getDietasDetalhes(idFazenda);

    final db = await AppDb.instance.db;
    await db.transaction((txn) async {
      await txn.delete("DETALHES_DIETAS");
      for (final it in list) {
        final m = Map<String, dynamic>.from(it as Map);

        final prePesagem =
            (m["prePesagem"] ?? "").toString().trim().toUpperCase();
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
    await db.transaction((txn) async {
      await txn.delete("PREVISAO");

      for (final it in list) {
        final m = Map<String, dynamic>.from(it as Map);

        await txn.insert(
          "PREVISAO",
          {
            "ID_FORNECIMENTO": (m["idFornecimento"] ?? "").toString(),
            "DATA": (m["data"] ?? "").toString(),
            "ID_BAIA": (m["id"] ?? "").toString(),
            "TRATO": int.tryParse((m["trato"] ?? "0").toString()) ?? 0,
            "PREVISTO_KG": _toNum(m["previsto"]),
            "REALIZADO_KG": _toNum(m["realizado"]),
            "ID_RACAO": (m["idDieta"] ?? "").toString(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        inserted++;
      }
    });

    // ✅ COUNT fora da transaction (sem txn)
    final r = await db.rawQuery("SELECT COUNT(*) as c FROM PREVISAO");
    final total = (r.first["c"] as int?) ?? 0;

    log?.call("💾 Previsão (SQLite): $inserted gravados");
    log?.call("📊 PREVISAO no SQLite agora: $total registros");

    return inserted;
  }

  static String _dateOnly(dynamic v) {
    final s = (v ?? "").toString().trim();
    if (s.isEmpty) return "";
    return s.length >= 10 ? s.substring(0, 10) : s; // YYYY-MM-DD
  }

  static num _toNum(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v;
    final s = v.toString().replaceAll(",", ".").trim();
    return num.tryParse(s) ?? 0;
  }
}
