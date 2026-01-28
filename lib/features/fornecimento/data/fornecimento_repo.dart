// lib/features/fornecimento/data/fornecimento_repo.dart
import "package:flutter/foundation.dart";

import "../../../repo/config_repo.dart";
import "../domain/histerese_params.dart";
import "../domain/fornecimento_models.dart";

import "fornecimento_dao.dart";
import "carregamento_dao.dart";

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
  String? idRacaoAtual;

  void setTrato(int trato) => tratoAtual = trato <= 0 ? 1 : trato;

  void setIdRacaoAtual(String? id) {
    final t = (id ?? "").trim();
    idRacaoAtual = t.isEmpty ? null : t;
  }

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
  // Helpers de data (YYYY-MM-DD)
  // ===========================
  static String _ymd(DateTime d) {
    final y = d.year.toString().padLeft(4, "0");
    final m = d.month.toString().padLeft(2, "0");
    final dd = d.day.toString().padLeft(2, "0");
    return "$y-$m-$dd";
  }

  // ===========================
  // PREVISÃO (lista)
  // ===========================
  Future<List<CurralPrev>> listCurraisPrevistosHoje({
  DateTime? data,
  int? trato,
  String? idFazenda,
}) async {
  final d = data ?? DateTime.now();
  final ymd =
      "${d.year.toString().padLeft(4, "0")}-${d.month.toString().padLeft(2, "0")}-${d.day.toString().padLeft(2, "0")}";

  final rows = await _dao.listCurraisPrevistos(
    dataYmd: ymd,
    trato: trato ?? tratoAtual,
    idFazenda: idFazenda,
  );

  return rows.map((m) => CurralPrev.fromMap(m)).toList();
}


  Future<List<CurralPrev>> listCurraisPrevistosHojeSimple() =>
      listCurraisPrevistosHoje();

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
  // CARREGAMENTO
  // ===========================
  Future<bool> existeCarregamentoAbertoHoje({DateTime? data}) async {
    final car = await _carregDao.getAbertoHoje(data: data ?? DateTime.now());
    return car != null;
  }

  // ===========================
  // FORNECIMENTO ABERTO / CADASTRO (registro real)
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
      idDieta: idRacaoAtual,
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

  Future<void> cancelarCadastroFornecimentoAberto({required String idCadastro}) =>
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
    required String idFornecimento,
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
}
