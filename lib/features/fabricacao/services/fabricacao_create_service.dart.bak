import "package:sqflite/sqflite.dart";
import "package:uuid/uuid.dart";

import "../../../db/app_db.dart";

class FabricacaoCreateService {
  Future<Database> get _db async => AppDb.instance.db;

  final _uuid = const Uuid();
  String _newId() => _uuid.v4();

  /// ✅ Replica o Delphi:
  /// - INSERT CADASTRO_FABRICA_RACAO
  /// - SELECT DETALHES_DIETAS usando MN_PERCENT 1..100
  /// - INSERT DETALHES_FABRICA_RACAO copiando PRE_PESADO
  Future<String> criarFabricacao({
    required String idDieta,
    required String idOperador,
    required String idUsuarioLogado,
    required String idFazenda,
    required int trato,
    required double totalKg,
  }) async {
    final db = await _db;
    final idFab = _newId();
    final now = DateTime.now();

    final dataFab =
        "${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
    final horaInicio =
        "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";

    await db.transaction((txn) async {
      // 1) Cabeçalho
      await txn.insert("CADASTRO_FABRICA_RACAO", {
        "ID": idFab,
        "ID_DIETA": idDieta,
        "QTD_PREVISTA": totalKg,
        "QTD_REALIZADA": 0,
        "DATA_FABRICACAO": dataFab,
        "HORA_INICIO": horaInicio,
        "HORA_FIM": null,
        "TRATO": trato,
        "FINALIZADA": 0,
        "CARREGADA": 0,
        "ID_OPERADOR": idOperador,
        "ID_USUARIO": idUsuarioLogado,
        "STATUS": 1,
        "FLAG_SYNC": 0,
        "ID_FAZENDA": idFazenda,
        "MS_PREVISTA": 0,
        "MS_REALIZADA": 0,
      });

      // 2) Ingredientes da dieta (MN_PERCENT 1..100)
      final det = await txn.rawQuery("""
        SELECT
          ID_INSUMO,
          INSUMO,
          MN_PERCENT,
          ORDEM,
          MS_INSUMO,
          MS_INCLUSAO,
          MN_PERC,
          PRE_PESADO
        FROM DETALHES_DIETAS
        WHERE ID_DIETA = ?
        ORDER BY COALESCE(ORDEM, 0), INSUMO
      """, [idDieta]);

      if (det.isEmpty) {
        throw Exception("Nenhum ingrediente encontrado em DETALHES_DIETAS.");
      }

      // 3) Inserir DETALHES_FABRICA_RACAO com proporcional
      for (final r in det) {
        final mnPercent = _toNum(r["MN_PERCENT"]); // 1..100
        final previsto = (totalKg * (mnPercent / 100.0)).round(); // igual Delphi (arredonda)
        final ordem = _toInt(r["ORDEM"]);
        final prePesado = _toInt(r["PRE_PESADO"]);

        await txn.insert("DETALHES_FABRICA_RACAO", {
          "ID": _newId(),
          "ID_FABRICACAO": idFab,
          "ID_INSUMO": (r["ID_INSUMO"] ?? "").toString(),
          "QTD_PREVISTA": previsto,
          "QTD_REALIZADA": 0,
          "DATA_FABRICACAO": now.toIso8601String(),
          "ORDEM": ordem,
          "HORA_INICIO": horaInicio,
          "HORA_FIM": null,
          "ID_OPERADOR": idOperador,
          "ID_USUARIO": idUsuarioLogado,
          "STATUS": 1,
          "FLAG_SYNC": 0,
          "ID_FAZENDA": idFazenda,
          "INSUMO_NOME": (r["INSUMO"] ?? "").toString(),
          "MS_INSUMO": _toNum(r["MS_INSUMO"]),
          "MS_INCLUSAO": _toNum(r["MS_INCLUSAO"]),
          "MN_PERC": _toNum(r["MN_PERC"]),
          "PRE_PESADO": prePesado, // ✅ copia da dieta
        });
      }
    });

    return idFab;
  }

  static double _toNum(Object? v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().replaceAll(",", ".")) ?? 0.0;
  }

  static int _toInt(Object? v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }
}
