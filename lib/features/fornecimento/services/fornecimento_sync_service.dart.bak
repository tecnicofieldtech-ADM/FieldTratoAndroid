import "package:sqflite/sqflite.dart"; // Database / DatabaseExecutor / Transaction

import "../data/fornecimento_sync_dao.dart";
import "fornecimento_api.dart";

class FornecimentoSyncService {
  FornecimentoSyncService({
    required this.db,
    required this.api,
  }) : dao = FornecimentoSyncDao(db);

  /// ✅ agora é DatabaseExecutor (funciona com Database e Transaction)
  final DatabaseExecutor db;

  final FornecimentoApi api;
  final FornecimentoSyncDao dao;

  static String _toDateOnly(dynamic v) {
    final s = (v ?? "").toString().trim();
    if (s.isEmpty) return "";
    return s.length >= 10 ? s.substring(0, 10) : s;
  }

  static double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    final s = v.toString().trim().replaceAll(",", ".");
    return double.tryParse(s) ?? 0;
  }

  static int _toInt(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  /// ✅ executa em transação quando possível
  Future<T> _runInTxn<T>(Future<T> Function(DatabaseExecutor exec) fn) async {
    final exec = db;

    // se veio Database, podemos abrir transaction de verdade
    if (exec is Database) {
      return exec.transaction((txn) async => fn(txn));
    }

    // se já veio Transaction (ou outro executor), executa direto
    return fn(exec);
  }

  // =========================
  // PREVISAO_TRATO -> PREVISAO
  // =========================
  Future<int> syncPrevisaoTrato({
    required String idFazenda,
    required String dataPrev, // yyyy-mm-dd
    required void Function(String) log,
  }) async {
    final list = await api.getPrevisaoTrato(
      idFazenda: idFazenda,
      dataPrev: dataPrev,
    );

    return _runInTxn((exec) async {
      final tdao = FornecimentoSyncDao(exec);

      await FornecimentoSyncDao.ensureTables(exec);
      await tdao.clearPrevisao();

      var count = 0;

      for (final item in list) {
        if (item is! Map) continue;

        final idFornecimento = (item["idFornecimento"] ?? "").toString();
        final idBaia = (item["id"] ?? "").toString(); // igual Delphi
        final trato = _toInt(item["trato"]);
        final idDieta = (item["idDieta"] ?? "").toString();
        final previsto = _toDouble(item["previsto"]);
        final realizado = _toDouble(item["realizado"]);
        final dataIso = _toDateOnly(item["data"]);

        if (idFornecimento.isEmpty || idBaia.isEmpty || dataIso.isEmpty) {
          continue;
        }

        await tdao.insertPrevisao(
          idFornecimento: idFornecimento,
          dataIso: dataIso,
          idBaia: idBaia,
          trato: trato,
          previstoKg: previsto,
          realizadoKg: realizado,
          idRacao: idDieta,
        );

        count++;
      }

      log("PREVISAO: $count registros.");
      return count;
    });
  }

  // =========================
  // DIETAS_DETALHES -> DETALHES_DIETAS
  // =========================
  Future<int> syncDietasDetalhes({
    required String idFazenda,
    required void Function(String) log,
  }) async {
    final list = await api.getDietasDetalhes(idFazenda: idFazenda);

    return _runInTxn((exec) async {
      final tdao = FornecimentoSyncDao(exec);

      await FornecimentoSyncDao.ensureTables(exec);
      await tdao.clearDietasDetalhes();

      var count = 0;

      for (final item in list) {
        if (item is! Map) continue;

        final id = (item["id"] ?? "").toString();
        final idDieta = (item["idDieta"] ?? "").toString();
        final idInsumo = (item["idInsumo"] ?? "").toString();
        final ingrediente = (item["ingrediente"] ?? "").toString();

        final msInsumo = _toDouble(item["msInsumo"]);
        final msInclusao = _toDouble(item["msInclusao"]);
        final mnPerc = _toDouble(item["mnPerc"]);
        final ordem = _toInt(item["ordem"]);

        final pre = (item["prePesagem"] ?? "").toString().trim().toUpperCase();
        final prePesado = (pre == "S") ? 1 : 0;

        if (id.isEmpty) continue;

        await tdao.upsertDietaDetalhe(
          id: id,
          idDieta: idDieta,
          idInsumo: idInsumo,
          insumo: ingrediente,
          msInsumo: msInsumo,
          msInclusao: msInclusao,
          mnPercent: mnPerc,
          ordem: ordem,
          prePesado: prePesado,
        );

        count++;
      }

      log("DETALHES_DIETAS: $count registros.");
      return count;
    });
  }
}
