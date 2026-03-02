import "package:flutter/foundation.dart";
import "package:sqflite/sqflite.dart";
import "package:uuid/uuid.dart";

import "../../../db/app_db.dart";
import "../../fabricacao/domain/fabricacao_flow.dart";
import "../domain/carregamento_payload.dart";

class ImportadorFabricacaoEstacionario {
  Future<Database> get _db async => AppDb.instance.db;
  final _uuid = const Uuid();

  Future<String> importar({
    required CarregamentoDetalheDto payload,
    required String idUsuario,
    required String idFazenda,
  }) async {
    final db = await _db;
    final f = payload.fabricacao;
    final handoffId = f.handoffId.trim();
    if (handoffId.isEmpty) {
      throw Exception("Payload sem handoff_id");
    }

    final existente = await db.rawQuery(
      "SELECT ID FROM CADASTRO_FABRICA_RACAO WHERE TRIM(COALESCE(HANDOFF_ID,'')) = TRIM(?) LIMIT 1",
      [handoffId],
    );
    if (existente.isNotEmpty) {
      throw Exception("Esse carregamento ja foi recebido.");
    }

    final somaInsumos =
        payload.insumos.fold<double>(0, (p, e) => p + e.realizadoKg);
    final diff = (somaInsumos - f.totalRealizadoKg).abs();
    if (diff > 2.0) {
      debugPrint(
        "[IMPORT_EST] divergencia total: fab=${f.totalRealizadoKg.toStringAsFixed(3)} insumos=${somaInsumos.toStringAsFixed(3)} diff=${diff.toStringAsFixed(3)}",
      );
    }

    final novoIdFab = _uuid.v4();

    await db.transaction((txn) async {
      await txn.insert("CADASTRO_FABRICA_RACAO", {
        "ID": novoIdFab,
        "ID_DIETA": f.idRacao,
        "QTD_PREVISTA": f.totalPrevistoKg,
        "QTD_REALIZADA": f.totalRealizadoKg,
        "DATA_FABRICACAO": f.data,
        "HORA_INICIO": f.horaInicio,
        "HORA_FIM": f.horaFim,
        "TRATO": 0,
        "FINALIZADA": f.finalizada ? 1 : 0,
        "CARREGADA": 0,
        "ID_OPERADOR": idUsuario,
        "ID_USUARIO": idUsuario,
        "STATUS": 1,
        "FLAG_SYNC": 0,
        "ID_FAZENDA": idFazenda,
        "MS_PREVISTA": 0,
        "MS_REALIZADA": 0,
        "ORIGEM": "ESTACIONARIO",
        "ID_ORIGEM_ESTACIONARIO": f.idOrigem,
        "FAB_STATUS": fabricacaoStatusToDb(f.status),
        "HANDOFF_ID": handoffId,
        "EXPORTADO_EM": (f.status == FabricacaoStatus.pendenteCaminhao)
            ? DateTime.now().toIso8601String()
            : null,
        "ORIGIN_DEVICE": "ESTACIONARIO",
      });

      for (final i in payload.insumos) {
        await txn.insert("DETALHES_FABRICA_RACAO", {
          "ID": _uuid.v4(),
          "ID_FABRICACAO": novoIdFab,
          "ID_INSUMO": i.idInsumo,
          "QTD_PREVISTA": i.previstoKg,
          "QTD_REALIZADA": i.realizadoKg,
          "DATA_FABRICACAO": f.data,
          "ORDEM": i.ordem,
          "HORA_INICIO": f.horaInicio,
          "HORA_FIM": f.horaFim,
          "ID_OPERADOR": idUsuario,
          "ID_USUARIO": idUsuario,
          "STATUS": 1,
          "FLAG_SYNC": 0,
          "ID_FAZENDA": idFazenda,
          "INSUMO_NOME": i.nomeInsumo,
          "MS_INSUMO": 0,
          "MS_INCLUSAO": 0,
          "MN_PERC": 0,
          "PRE_PESADO": 0,
        });
      }

      if (f.status == FabricacaoStatus.finalizada ||
          f.status == FabricacaoStatus.pendenteCaminhao) {
        await txn.insert(
          "CARREGAMENTO",
          {
            "ID": _uuid.v4(),
            "DATA_REGISTRO": DateTime.now().toIso8601String(),
            "STATUS": 0,
            "ID_FABRICACAO": novoIdFab,
            "ID_DIETA": f.idRacao,
            "PESO_FABRICADO": f.totalRealizadoKg,
            "PESO_CARREGADO": 0,
            "ID_VAGAO": "",
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    });

    return novoIdFab;
  }
}
