// lib/features/fornecimento/data/fornecimento_repo.dart
import "package:flutter/foundation.dart";

import "../../../repo/config_repo.dart";
import "../domain/histerese_params.dart";

import "carregamento_dao.dart";
import "../domain/fornecimento_models.dart";
import "fornecimento_dao.dart";
import "fornecimento_tables.dart";

class FornecimentoConnParams {
  FornecimentoConnParams({
    required this.hostBalanca,
    required this.portaBalanca,
    required this.modeloBalanca,
    this.hostRfid,
    this.portaRfid,
    this.toleranciaKg,
    this.histerese,
  });

  final String hostBalanca;
  final int portaBalanca;
  final ModeloBalanca modeloBalanca;

  final String? hostRfid;
  final int? portaRfid;

  final double? toleranciaKg;
  final HistereseParams? histerese;
}

/// Modelo mínimo pro carregamento aberto (sem inventar campos)
class CarregamentoAberto {
  CarregamentoAberto({
    required this.id,
    required this.status,
    required this.idVagao,
    this.idFabricacao,
    this.idDieta, // ID_DIETA == ID_RACAO
  });

  final String id;
  final int status; // 0 = aberto
  final int idVagao;

  final String? idFabricacao;
  final String? idDieta;
}

class FornecimentoRepo {
  FornecimentoRepo({
    FornecimentoDao? dao,
    CarregamentoDao? carregDao,
    ConfigRepo? configRepo,
  })  : _dao = dao ?? FornecimentoDao(),
        _carregDao = carregDao ?? CarregamentoDao(),
        _cfg = configRepo ?? ConfigRepo();

  final FornecimentoDao _dao;
  final CarregamentoDao _carregDao;
  final ConfigRepo _cfg;

  int tratoAtual = 1;

  /// ✅ ID_RACAO atual (vem do carregamento aberto)
  String? idRacaoAtual;

  void setTrato(int trato) => tratoAtual = trato <= 0 ? 1 : trato;

  void setIdRacaoAtual(String? id) {
    final t = (id ?? "").trim();
    idRacaoAtual = t.isEmpty ? null : t;
  }

  // ===========================
  // Helpers de data (YYYY-MM-DD)
  // ===========================
  static String _ymd(DateTime d) {
    final y = d.year.toString().padLeft(4, "0");
    final m = d.month.toString().padLeft(2, "0");
    final dd = d.day.toString().padLeft(2, "0");
    return "$y-$m-$dd";
  }

  /// ✅ chave estável (ID_BAIA + ID_RACAO + DATA + TRATO)
  static String comboKey({
    required String idBaia,
    required String idRacao,
    required String dataYmd,
    required int trato,
  }) =>
      "$idBaia|$idRacao|$dataYmd|$trato";

  Future<FornecimentoConnParams> getConnectionParams() async {
    final hostBal = (await _cfg.getHostBalanca()).trim();
    final portBal = await _cfg.getPortaBalanca();
    final modeloInt = await _cfg.getModeloBalanca();
    final modelo = _mapModeloBalanca(modeloInt);

    final hostRfid = (await _cfg.getHostRfid()).trim();
    final portRfid = await _cfg.getPortaRfid();

    final tolKg = await _cfg.getToleranciaCarregamentoKg();

    return FornecimentoConnParams(
      hostBalanca: hostBal,
      portaBalanca: portBal,
      modeloBalanca: modelo,
      hostRfid: hostRfid.isEmpty ? null : hostRfid,
      portaRfid: portRfid <= 0 ? null : portRfid,
      toleranciaKg: tolKg,
      histerese: null,
    );
  }

  ModeloBalanca _mapModeloBalanca(int v) {
    switch (v) {
      case 1:
        return ModeloBalanca.dinamica;
      case 2:
        return ModeloBalanca.alfa;
      default:
        return ModeloBalanca.topcon;
    }
  }

  // ===========================
  // CARREGAMENTO (Rotormix)
  // ===========================

  /// ✅ retorna o carregamento aberto de hoje (DAO decide)
  /// ✅ seta `idRacaoAtual` quando conseguir
  Future<CarregamentoAberto?> getCarregamentoAberto({DateTime? data}) async {
  final car = await _carregDao.getAbertoHoje(data: data ?? DateTime.now());
  if (car == null) return null;

  // se getAbertoHoje SEMPRE retorna Map, não precisa de type check
  final id = (car["ID"] ?? "").toString().trim();
  final status = (car["STATUS"] is num) ? (car["STATUS"] as num).toInt() : 0;
  final idVagao = (car["ID_VAGAO"] is num) ? (car["ID_VAGAO"] as num).toInt() : 0;
  final idFab = (car["ID_FABRICACAO"] ?? "").toString().trim();
  final idDieta = (car["ID_DIETA"] ?? "").toString().trim();

  final aberto = CarregamentoAberto(
    id: id.isEmpty ? "?" : id,
    status: status,
    idVagao: idVagao,
    idFabricacao: idFab.isEmpty ? null : idFab,
    idDieta: idDieta.isEmpty ? null : idDieta,
  );

  // ✅ ID_DIETA == ID_RACAO
  setIdRacaoAtual(aberto.idDieta);

  return aberto;
}


  Future<bool> existeCarregamentoAbertoHoje({DateTime? data}) async {
    final car = await _carregDao.getAbertoHoje(data: data ?? DateTime.now());
    return car != null;
  }

  // ===========================
  // PREVISÃO (Mapa / Hoje)
  // ===========================

  /// ✅ filtra também por ID_RACAO quando informado
  Future<List<CurralPrev>> listCurraisPrevistosHoje({
    DateTime? data,
    int? trato,
    String? idFazenda,
    String? idRacao,
  }) async {
    final d = data ?? DateTime.now();
    final ymd = _ymd(d);

    final t = trato ?? tratoAtual;
    final racao = (idRacao ?? idRacaoAtual)?.trim();
    final racaoFinal = (racao != null && racao.isNotEmpty) ? racao : null;

    final rows = await _listPrevRaw(
      dataYYYYMMDD: ymd,
      trato: t,
      idFazenda: idFazenda,
      idRacao: racaoFinal,
    );

    return rows.map((m) => CurralPrev.fromMap(m)).toList();
  }

  Future<List<CurralPrev>> listCurraisPrevistosHojeSimple() =>
      listCurraisPrevistosHoje();

  // ===========================
  // SNAPSHOT
  // ===========================
  Future<CurralSnapshot?> loadCurralSnapshot(String idFornecimento) {
    final dataYmd = _ymd(DateTime.now());
    return _dao.loadCurralSnapshot(
      idFornecimento: idFornecimento,
      dataYmd: dataYmd,
      trato: tratoAtual,
    );
  }

  Future<String?> findIdFornecimentoByRfid({
    required String epc,
    required int trato,
    String? idRacao,
    DateTime? data,
  }) {
    final dataYmd = _ymd(data ?? DateTime.now());

    return _dao.findIdFornecimentoByRfid(
      epc: epc,
      trato: trato,
      idRacao: idRacao,
      dataYmd: dataYmd,
    );
  }

  // ===========================
  // FORNECIMENTO ABERTO / CADASTRO
  // ===========================
  Future<FornecimentoAbertoMini?> getFornecimentoAberto({
    required String idFornecimento,
    required String idCurral,
    required DateTime data,
    required int trato,
  }) =>
      _dao.getFornecimentoAberto(
        idFornecimento: idFornecimento,
        idBaia: idCurral,
        data: data,
        trato: trato,
      );

  Future<String> iniciarCadastroFornecimento({
    required String idFornecimento,
    required String idCurral,
    required DateTime data,
    required int trato,
    required double previstoKg,
    required double pesoInicio,
  }) async {
    final idUsuario = (await _dao.getUsuarioAtualId()) ?? "";
    if (idUsuario.trim().isEmpty) {
      throw Exception("Usuário não definido. Faça login novamente.");
    }

    final okCar = await existeCarregamentoAbertoHoje(data: data);
    if (!okCar) {
      throw Exception(
        "Não existe CARREGAMENTO aberto. Abra um carregamento antes de fornecer.",
      );
    }

    final aberto = await _dao.getFornecimentoAberto(
      idFornecimento: idFornecimento,
      idBaia: idCurral,
      data: data,
      trato: trato,
    );
    if (aberto != null) return aberto.idCadastro;

    final newId = _dao.newId40();
    final fab = await _dao.getFabricacaoEmAbertoId() ?? "";

    await _dao.abrir(
      id: newId,
      idFornecimento: idFornecimento,
      idFabricacao: fab,
      idBaia: idCurral,
      data: data,
      pesoInicio: pesoInicio,
      previsto: previstoKg,
      trato: trato,
      idUsuario: idUsuario,
      idDieta: idRacaoAtual, // ✅ ID_DIETA == ID_RACAO
    );

    return newId;
  }

  Future<void> finalizarCadastroFornecimento({
    required String idCadastro,
    required double pesoFim,
    required double realizadoKg,
  }) =>
      _dao.finalizarCadastro(
        id: idCadastro,
        pesoFim: pesoFim,
        realizado: realizadoKg,
      );

  Future<void> cancelarCadastroFornecimentoAberto(
          {required String idCadastro}) =>
      _dao.cancelarCadastroAberto(idCadastro);

  Future<void> salvarParcialFornecimento({
    required String motivo,
    required String idCadastro,
    required double pesoInicio,
    required double pesoFim,
    required double realizadoKg,
  }) =>
      _dao.salvarParcial(
        motivo: motivo,
        id: idCadastro,
        pesoInicio: pesoInicio,
        pesoFim: pesoFim,
        realizado: realizadoKg,
      );

  Future<double> getRealizadoAcumuladoDoCurral({
    required String idFornecimento,
    required String idCurral,
    required DateTime data,
    required int trato,
  }) =>
      _dao.getRealizadoAcumulado(
        idFornecimento: idFornecimento,
        idBaia: idCurral,
        data: data,
        trato: trato,
      );

  Future<void> setPrevRealizado({
    required String idFornecimento, // mantido
    required String idCurral,
    required DateTime data,
    required int trato,
    required double realizadoKg,
  }) =>
      _dao.setPrevRealizado(
        data: data,
        trato: trato,
        idBaia: idCurral,
        realizadoKg: realizadoKg,
      );

  // ===========================
  // Mantidos
  // ===========================
  Future<void> abrir(FornecimentoRow row) => _dao.upsert(row);

  Future<List<FornecimentoRow>> pendentesSync({int limit = 200}) =>
      _dao.listPendentesSync(limit: limit);

  Future<void> marcarSyncOk(String id) => _dao.marcarSyncOk(id);

  Future<void> upsertBaia(BaiaRow b) => _dao.upsertBaia(b);
  Future<BaiaRow?> getBaiaByRfid(String rfid) => _dao.getBaiaByRfid(rfid);

  @visibleForTesting
  FornecimentoDao get debugDao => _dao;

  // ===========================
  // ✅ UI: listPrevisao (com filtros)
  // ===========================
  Future<List<CurralPrev>> listPrevisao({
    required String idFazenda,
    required DateTime data,
    int? trato,
    String? racaoNome, // mantido, mas não usado no SQL (sem tabela)
    String? curralNome,
    bool? realizadoMaiorZero,
  }) async {
    final ymd = _ymd(data);

    return listPrevisaoByYmd(
      idFazenda: idFazenda,
      dataYYYYMMDD: ymd,
      trato: trato,
      racaoNome: racaoNome,
      curralNome: curralNome,
      realizadoMaiorZero: realizadoMaiorZero,
    );
  }

  Future<List<CurralPrev>> listPrevisaoByYmd({
    required String idFazenda,
    required String dataYYYYMMDD,
    int? trato,
    String? racaoNome, // mantido (não usado)
    String? curralNome,
    bool? realizadoMaiorZero,
  }) async {
    final rows = await _listPrevRaw(
      dataYYYYMMDD: dataYYYYMMDD,
      trato: trato,
      idFazenda: idFazenda,
      curralNome: curralNome,
      realizadoMaiorZero: realizadoMaiorZero,
    );

    return rows.map((m) => CurralPrev.fromMap(m)).toList();
  }

  // ===========================
  // ✅ SQL centralizado (usando FornTables)
  // ===========================
  Future<List<Map<String, Object?>>> _listPrevRaw({
    required String dataYYYYMMDD,
    int? trato,
    String? idFazenda,
    String? idRacao,
    String? curralNome,
    bool? realizadoMaiorZero,
  }) async {
    final where = StringBuffer("WHERE 1=1 ");
    final args = <Object?>[];

    // DATA_LEITURA
    where.write(" AND a.${FornTables.pv_data} = ? ");
    args.add(dataYYYYMMDD);

    // fazenda via DETALHES_BAIAS (se vier)
    final faz = (idFazenda ?? "").trim();
    if (faz.isNotEmpty) {
      where.write(" AND db.${FornTables.db_idFazenda} = ? ");
      args.add(faz);
    }

    if (trato != null) {
      where.write(" AND a.${FornTables.pv_trato} = ? ");
      args.add(trato);
    }

    final racao = (idRacao ?? "").trim();
    if (racao.isNotEmpty) {
      where.write(" AND a.${FornTables.pv_idRacao} = ? ");
      args.add(racao);
    }

    final curral = (curralNome ?? "").trim();
    if (curral.isNotEmpty) {
      where.write(" AND db.${FornTables.db_nomeLocal} = ? ");
      args.add(curral);
    }

    if (realizadoMaiorZero == true) {
      where.write(" AND COALESCE(a.${FornTables.pv_realizadoKg},0) > 0 ");
    } else if (realizadoMaiorZero == false) {
      where.write(" AND COALESCE(a.${FornTables.pv_realizadoKg},0) = 0 ");
    }

    // ✅ Aliases compatíveis com CurralPrev.fromMap (sem inventar tabelas)
    final sql = '''
SELECT
  a.${FornTables.pv_idFornecimento} AS idFornecimento,
  a.${FornTables.pv_idBaia}         AS idBaia,
  db.${FornTables.db_nomeLocal}     AS nomeBaia,
  db.${FornTables.db_nomeLocal}     AS nomeLocal,
  COALESCE(db.${FornTables.db_linha}, 0) AS linha,
  COALESCE(db.${FornTables.db_rfid}, '') AS rfid,
  '' AS racaoNome,
  a.${FornTables.pv_previstoKg}     AS previstoKg,
  COALESCE(a.${FornTables.pv_realizadoKg}, 0) AS realizadoKg,
  a.${FornTables.pv_trato}          AS trato,
  0 AS sync
FROM ${FornTables.previsao} a
JOIN ${FornTables.detalhesBaias} db
  ON db.${FornTables.db_id} = a.${FornTables.pv_idBaia}
${where.toString()}
ORDER BY
  a.${FornTables.pv_trato},
  COALESCE(db.${FornTables.db_orderTrato}, 0),
  db.${FornTables.db_nomeLocal}
''';

    return _dao.rawQuery(sql, args);
  }
}
