import "package:flutter/foundation.dart";
import "package:sqflite/sqflite.dart";
import "package:uuid/uuid.dart";

import "../../../db/app_db.dart";
import "../../../services/planilha_importacao.dart";
import "../../fabricacao/domain/fabricacao_flow.dart";
import "../domain/carregamento_payload.dart";
import "../domain/station_handoff_mode.dart";

class ImportadorFabricacaoEstacionario {
  Future<Database> get _db async => AppDb.instance.db;
  final _uuid = const Uuid();

  /// [inserido] false = lote já existia neste tablet (mesmo handoff ou mesmo id da fabricação no estacionário).
  Future<({String idFabricacaoLocal, bool inserido})> importar({
    required CarregamentoDetalheDto payload,
    required String idUsuario,
    required String idFazenda,
  }) async {
    final db = await _db;
    final f = payload.fabricacao;
    final handoffId = f.handoffId.trim();
    final idOrigem = f.idOrigem.trim();
    if (handoffId.isEmpty && idOrigem.isEmpty) {
      throw Exception(
        "Payload sem identificador (handoff_id ou id da fabricação no estacionário).",
      );
    }

    final mode = f.handoffMode ??
        resolveStationHandoffMode(
          fabStatus: fabricacaoStatusToDb(f.status),
          finalizada: f.finalizada ? 1 : 0,
        );
    if (mode == null) {
      debugPrint(
        "[IMPORT_EST] handoffMode inválido status=${f.statusApi} "
        "finalizada=${f.finalizada}",
      );
      throw Exception(
        "Estado da fabricação inconsistente para handoff "
        "(status=${f.statusApi}, finalizada=${f.finalizada}).",
      );
    }
    debugPrint("[IMPORT_EST] handoffMode=${mode.apiValue}");

    String? idJaImportado;
    if (handoffId.isNotEmpty) {
      final r = await db.rawQuery(
        """
        SELECT ID FROM CADASTRO_FABRICA_RACAO
        WHERE TRIM(COALESCE(HANDOFF_ID,'')) = TRIM(?)
        LIMIT 1
        """,
        [handoffId],
      );
      if (r.isNotEmpty) {
        idJaImportado = (r.first["ID"] ?? "").toString().trim();
      }
    }
    if (idJaImportado == null && idOrigem.isNotEmpty) {
      try {
        final r = await db.rawQuery(
          """
          SELECT ID FROM CADASTRO_FABRICA_RACAO
          WHERE TRIM(COALESCE(ID_ORIGEM_ESTACIONARIO,'')) = TRIM(?)
          LIMIT 1
          """,
          [idOrigem],
        );
        if (r.isNotEmpty) {
          idJaImportado = (r.first["ID"] ?? "").toString().trim();
        }
      } catch (_) {
        // Base sem coluna ID_ORIGEM_ESTACIONARIO: dedupe só por HANDOFF_ID.
      }
    }
    if (idJaImportado != null && idJaImportado.isNotEmpty) {
      return (idFabricacaoLocal: idJaImportado, inserido: false);
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
    final importacaoId = await PlanilhaImportacao.freezeFromDb();

    await db.transaction((txn) async {
      try {
        await _ensureDietaNomeParaJoin(
          txn,
          idDieta: f.idRacao,
          nomeRacao: f.nomeRacao,
          idFazenda: idFazenda,
        );
      } catch (e, st) {
        debugPrint("[IMPORT_EST] DIETA ensure: $e\n$st");
      }

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
        if (importacaoId != null) "IMPORTACAO_ID": importacaoId,
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

    return (idFabricacaoLocal: novoIdFab, inserido: true);
  }

  /// Garante linha em [DIETA] para o [idDieta] do payload, pois [listFabricacoes]
  /// resolve o nome via `LEFT JOIN DIETA`; no vagão o catálogo de dietas pode não
  /// estar sincronizado. Não sobrescreve [NOME] já preenchido (dados vindos do sync).
  Future<void> _ensureDietaNomeParaJoin(
    Transaction txn, {
    required String idDieta,
    required String nomeRacao,
    required String idFazenda,
  }) async {
    final id = idDieta.trim();
    if (id.isEmpty) return;
    final nome =
        nomeRacao.trim().isNotEmpty ? nomeRacao.trim() : "Ração";

    final existing = await txn.rawQuery(
      """
      SELECT TRIM(COALESCE(NOME,'')) AS n
      FROM DIETA
      WHERE ID = ?
      LIMIT 1
      """,
      [id],
    );
    if (existing.isEmpty) {
      await txn.insert("DIETA", {
        "ID": id,
        "NOME": nome,
        "TIPO": "",
        "MS": 0,
        "ID_FAZENDA": idFazenda,
      });
      return;
    }
    final cur = (existing.first["n"] ?? "").toString();
    if (cur.isEmpty) {
      await txn.update(
        "DIETA",
        {"NOME": nome},
        where: "ID = ?",
        whereArgs: [id],
      );
    }
  }
}
