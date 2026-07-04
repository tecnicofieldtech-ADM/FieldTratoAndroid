// lib/features/fornecimento/data/fornecimento_repo.dart
import "dart:convert";
import "dart:io";

import "package:flutter/foundation.dart";

import "../../../constants/config_options.dart";
import "../../../repo/config_repo.dart";
import "../../../repo/fazenda_repo.dart";
import "../../../repo/user_repo.dart";
import "../../../repo/vagao_repo.dart";
import "../../../services/bootstrap_sync.dart";
import "../domain/fornecimento_models.dart";
import "../domain/histerese_params.dart";

import "carregamento_dao.dart";
import "../../../helpers/scale_model_config.dart";
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
enum ReplicarPrevisaoStatus {
  copiado,
  diaJaPossuiPrevisao,
  diaAnteriorSemPrevisao,
}

class ReplicarPrevisaoResult {
  ReplicarPrevisaoResult({
    required this.status,
    this.registrosCopiados = 0,
  });

  final ReplicarPrevisaoStatus status;
  final int registrosCopiados;
}

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

  /// ✅ não vamos filtrar por vagão (sua regra), mas mantemos por compat
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

  ModeloBalanca _mapModeloBalanca(int v) => modeloBalancaFromConfigInt(v);

  // ===========================
  // ✅ DIETA (NOME)
  // ===========================
  Future<bool> _hasTable(String table) async {
    try {
      final rows = await _dao.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND upper(name)=upper(?) LIMIT 1",
        [table],
      );
      return rows.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// ✅ detecta coluna no SQLite (PRAGMA table_info)
  Future<bool> _hasColumn(String table, String col) async {
    try {
      final rows = await _dao.rawQuery("PRAGMA table_info($table)", const []);
      for (final r in rows) {
        final name = (r["name"] ?? "").toString().toUpperCase().trim();
        if (name == col.toUpperCase().trim()) return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// ✅ usado pra mostrar o NOME da dieta no header/pesagem
  Future<String?> getDietaNomeById(String idDieta) async {
    final id = idDieta.trim();
    if (id.isEmpty) return null;

    try {
      final rows = await _dao.rawQuery(
        "SELECT NOME AS nome FROM DIETA WHERE ID = ? LIMIT 1",
        [id],
      );
      if (rows.isEmpty) return null;

      final nome = (rows.first["nome"] ?? "").toString().trim();
      return nome.isEmpty ? null : nome;
    } catch (_) {
      return null;
    }
  }

  // ===========================
  // CARREGAMENTO (Rotormix)
  // ===========================
  Future<CarregamentoAberto?> getCarregamentoAberto({DateTime? data}) async {
    final ref = data ?? DateTime.now();
    final idVagao = (await _cfg.getIdVagao()).trim();
    final car = idVagao.isNotEmpty
        ? await _carregDao.getAbertoAtivo(data: ref, idVagao: idVagao)
        : await _carregDao.getAbertoHoje(data: ref);
    if (car == null) return null;

    final id = (car["ID"] ?? "").toString().trim();
    final status = int.tryParse((car["STATUS"] ?? "0").toString().trim()) ?? 0;

    final idFab = (car["ID_FABRICACAO"] ?? "").toString().trim();
    final idDieta = (car["ID_DIETA"] ?? "").toString().trim();

    final aberto = CarregamentoAberto(
      id: id.isEmpty ? "?" : id,
      status: status,
      idVagao: 0, // ✅ não usa / não lê do banco
      idFabricacao: idFab.isEmpty ? null : idFab,
      idDieta: idDieta.isEmpty ? null : idDieta,
    );

    // ✅ ID_DIETA == ID_RACAO
    setIdRacaoAtual(aberto.idDieta);

    return aberto;
  }

  Future<bool> existeCarregamentoAbertoHoje({DateTime? data}) async {
    final ref = data ?? DateTime.now();
    final idVagao = (await _cfg.getIdVagao()).trim();
    final car = idVagao.isNotEmpty
        ? await _carregDao.getAbertoAtivo(data: ref, idVagao: idVagao)
        : await _carregDao.getAbertoHoje(data: ref);
    return car != null;
  }

  /// Exige carregamento aberto. Com fabricação vinculada, exige QTD_REALIZADA > 0.
  /// Sem fabricação (ração pronta), exige dieta e peso carregado > 0.
  Future<FabricacaoFornecimentoGate> assertFabricacaoParaFornecimento({
    DateTime? data,
  }) async {
    final ref = data ?? DateTime.now();
    final car = await getCarregamentoAberto(data: ref);
    if (car == null || car.status != 0) {
      throw Exception(
        "Não existe carregamento aberto. Finalize a fabricação e gere o "
        "carregamento antes de fornecer.",
      );
    }

    final fabId = (car.idFabricacao ?? "").trim();
    if (fabId.isEmpty) {
      final idDieta = (car.idDieta ?? "").trim();
      if (idDieta.isEmpty) {
        throw Exception(
          "Carregamento aberto sem dieta. Registre o carregamento da ração.",
        );
      }

      final row = await _carregDao.getById(car.id);
      final peso = _toDouble(row?["PESO_CARREGADO"]);
      if (peso <= 0) {
        throw Exception(
          "Carregamento sem peso registrado. Salve o peso carregado antes de fornecer.",
        );
      }

      return FabricacaoFornecimentoGate.semVinculo(
        idDieta: idDieta,
        pesoCarregadoKg: peso,
      );
    }

    var fabIdResolved = fabId;
    if (fabIdResolved.isEmpty) {
      fabIdResolved = ((await _dao.getFabricacaoEmAbertoId(data: ref)) ?? "").trim();
    }
    if (fabIdResolved.isEmpty) {
      throw Exception(
        "Carregamento aberto sem fabricação vinculada. "
        "Receba o carregamento da BeatBox ou finalize a fabricação com peso "
        "realizado no caminhão.",
      );
    }

    final resumo = await _dao.getFabricacaoResumo(fabIdResolved);
    if (resumo == null) {
      throw Exception("Fabricação $fabIdResolved não encontrada no tablet.");
    }

    final qtdReal = _toDouble(resumo["qtd_realizada"]);
    if (qtdReal <= 0) {
      throw Exception(
        "Fabricação sem peso realizado (> 0 kg). Conclua a pesagem na "
        "BeatBox/caminhão antes de iniciar o fornecimento.",
      );
    }

    return FabricacaoFornecimentoGate.fromMap(resumo);
  }

  Future<String> criarCarregamentoSemVinculo({
    required String idDieta,
    required double pesoCarregadoKg,
    String? idVagaoOverride,
  }) async {
    var idVagao = (idVagaoOverride ?? "").trim();
    if (idVagao.isEmpty) {
      idVagao = (await _cfg.getIdVagao()).trim();
    }
    if (idVagao.isEmpty) {
      throw Exception("Vagão não configurado.");
    }

    final id = await _carregDao.criarAbertoSemFabricacao(
      idDieta: idDieta,
      idVagao: idVagao,
      pesoCarregado: pesoCarregadoKg,
    );
    setIdRacaoAtual(idDieta.trim());
    return id;
  }

  double _toDouble(Object? v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().replaceAll(",", ".")) ?? 0;
  }

  Future<bool> tryImportCarregamentoFromEstacionario({
    DateTime? data,
  }) async {
    final host = (await _cfg.getHostEstacionario()).trim();
    if (host.isEmpty) return false;

    final port = await _cfg.getPortaEstacionario();
    final uri = Uri(
      scheme: "http",
      host: host,
      port: port,
      path: "/carregamento/aberto",
      queryParameters: {"data": _ymd(data ?? DateTime.now())},
    );

    final client = HttpClient();
    try {
      final req = await client.getUrl(uri);
      final res = await req.close();
      if (res.statusCode != 200) return false;

      final body = await utf8.decoder.bind(res).join();
      if (body.trim().isEmpty) return false;

      final json = jsonDecode(body);
      if (json is! Map || json["ok"] != true) return false;

      final car = json["carregamento"];
      if (car is! Map) return false;

      await _carregDao.upsertFromRemote(
        Map<String, Object?>.from(car),
      );

      final id = (car["id"] ?? car["ID"] ?? "").toString().trim();
      if (id.isEmpty) return true;

      final uriConsume = Uri(
        scheme: "http",
        host: host,
        port: port,
        path: "/carregamento/consumido",
      );
      final req2 = await client.postUrl(uriConsume);
      req2.headers.contentType = ContentType.json;
      req2.write(jsonEncode({"id": id}));
      await req2.close();

      return true;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  // ===========================
  // PREVISÃO (Mapa / Hoje)
  // ===========================
  static String _normalizeRacaoId(String? raw) {
    return (raw ?? "").replaceAll(RegExp(r"\s+"), "").trim().toUpperCase();
  }

  /// Variantes do ID (ex.: "90", "090") para bater com PREVISAO.ID_RACAO.
  static List<String> _racaoIdCandidates(String? raw) {
    final out = <String>[];
    void add(String s) {
      final n = _normalizeRacaoId(s);
      if (n.isNotEmpty && !out.contains(n)) out.add(n);
    }

    add(raw ?? "");
    final asInt = int.tryParse((raw ?? "").trim());
    if (asInt != null) {
      add(asInt.toString());
      add(asInt.toString().padLeft(2, "0"));
      add(asInt.toString().padLeft(3, "0"));
    }
    return out;
  }

  static double _toDoubleLocal(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().trim().replaceAll(",", ".")) ?? 0;
  }

  bool _mapaRowFraco(Map<String, Object?> r) {
    final nome = (r["nomeLocal"] ?? r["nome_local"] ?? "").toString().trim();
    final nomeDb = (r["nomeLocalRaw"] ?? "").toString().trim();
    final prev = _toDoubleLocal(r["previstoKg"] ?? r["previsto"] ?? 0);
    final hasNome = (nome.isNotEmpty && nome != "(sem nome)") || nomeDb.isNotEmpty;
    return !hasNome || prev <= 0;
  }

  bool _mapaRowsSemDadosUteis(List<Map<String, Object?>> rows) {
    if (rows.isEmpty) return false;
    var fracos = 0;
    for (final r in rows) {
      if (_mapaRowFraco(r)) fracos++;
    }
    return fracos >= (rows.length * 0.5).ceil();
  }

  Future<List<CurralPrev>> listCurraisPrevistosHoje({
    DateTime? data,
    int? trato,
    String? idFazenda,
    String? idRacao,
    bool strictRacaoFilter = false,
    bool omitirFiltroTrato = false,
  }) async {
    final d = data ?? DateTime.now();
    final ymd = _ymd(d);

    final int? t = omitirFiltroTrato
        ? null
        : ((trato != null && trato > 0)
            ? trato
            : (tratoAtual > 0 ? tratoAtual : null));
    final racao = (idRacao ?? idRacaoAtual)?.trim();
    final racaoFinal = (racao != null && racao.isNotEmpty) ? racao : null;

    final backend = await _cfg.getBackend();
    final isFieldpec = ConfigOptions.isFieldPecBackend(backend);

    // ✅ mantém idRacaoAtual consistente
    if (racaoFinal != null) setIdRacaoAtual(racaoFinal);

    Future<List<Map<String, Object?>>> load({
      String? idRacaoFiltro,
      int? tratoFiltro,
    }) {
      return _listPrevRaw(
        dataYYYYMMDD: ymd,
        trato: tratoFiltro,
        idRacao: idRacaoFiltro,
      );
    }

    var rows = <Map<String, Object?>>[];
    if (racaoFinal != null) {
      for (final candidato in _racaoIdCandidates(racaoFinal)) {
        rows = await load(idRacaoFiltro: candidato, tratoFiltro: t);
        if (rows.isNotEmpty) break;
      }
    } else {
      rows = await load(idRacaoFiltro: null, tratoFiltro: t);
    }

    if (!strictRacaoFilter && rows.isEmpty && racaoFinal != null) {
      if (kDebugMode) {
        debugPrint(
          "[FORN_MAPA] Sem mapa com idRacao='$racaoFinal'. Recarregando sem filtro de ração.",
        );
      }
      rows = await load(
        idRacaoFiltro: null,
        tratoFiltro: t,
      );
    }

    if (!strictRacaoFilter &&
        rows.isNotEmpty &&
        racaoFinal != null &&
        _mapaRowsSemDadosUteis(rows)) {
      final semRacao = await load(
        idRacaoFiltro: null,
        tratoFiltro: t,
      );
      if (semRacao.isNotEmpty && !_mapaRowsSemDadosUteis(semRacao)) {
        if (kDebugMode) {
          debugPrint(
            "[FORN_MAPA] Mapa com idRacao='$racaoFinal' veio sem nomes/previstos. "
            "Usando ${semRacao.length} currais sem filtro de ração.",
          );
        }
        rows = semRacao;
      }
    }

    if (kDebugMode) {
      debugPrint(
        "[FORN_MAPA] backend=$backend isFieldpec=$isFieldpec data=$ymd trato=$t "
        "idRacao='${racaoFinal ?? ""}' "
        "strictRacao=$strictRacaoFilter omitirTrato=$omitirFiltroTrato rows=${rows.length}",
      );
    }

    return rows.map((m) => CurralPrev.fromMap(m)).toList();
  }

  /// Tratos com previsão para a ração/dia (para seletor do mapa).
  Future<List<int>> listTratosPrevisao({
    required DateTime data,
    required String idRacao,
    String? idFazenda,
  }) async {
    final ymd = _ymd(data);
    final racao = _normalizeRacaoId(idRacao.trim());
    if (racao.isEmpty) return const [];

    final args = <Object?>[ymd, racao];
    final where = StringBuffer(
      "substr(a.${FornTables.pvData}, 1, 10) = ? "
      "AND REPLACE(UPPER(TRIM(CAST(a.${FornTables.pvIdRacao} AS TEXT))), ' ', '') "
      "= REPLACE(UPPER(TRIM(CAST(? AS TEXT))), ' ', '') ",
    );

    final sql = """
      SELECT DISTINCT a.${FornTables.pvTrato} AS trato
      FROM ${FornTables.previsao} a
      WHERE ${where.toString()}
      ORDER BY a.${FornTables.pvTrato}
    """;

    final rows = await _dao.rawQuery(sql, args);
    final list = <int>[];
    for (final r in rows) {
      final t = int.tryParse((r["trato"] ?? "0").toString()) ?? 0;
      if (t > 0) list.add(t);
    }
    return list;
  }

  Future<List<CurralPrev>> listCurraisPrevistosHojeSimple() =>
      listCurraisPrevistosHoje();

  /// Baixa baias + previsão do dia na API antes de abrir o mapa de fornecimento.
  Future<void> prefetchMapaDoDia({
    required String idFazenda,
    DateTime? data,
    int? trato,
  }) async {
    final cfg = await _cfg.getConfig();
    if (cfg == null) return;

    if (trato != null && trato > 0) {
      setTrato(trato);
    }

    final bootstrap = BootstrapSync(
      cfgRepo: _cfg,
      vagaoRepo: VagaoRepo(),
      fazendaRepo: FazendaRepo(),
      userRepo: UserRepo(),
    );

    final ymd = _ymd(data ?? DateTime.now());
    await bootstrap.baixarBaias(cfg, idFazenda);

    final tratoAlvo = trato ?? tratoAtual;
    for (var tentativa = 0; tentativa < 2; tentativa++) {
      await bootstrap.baixarPrevisaoTrato(cfg, idFazenda, ymd);
      if (tratoAlvo <= 0) break;

      final rows = await _listPrevRaw(
        dataYYYYMMDD: ymd,
        trato: tratoAlvo,
      );
      if (rows.isNotEmpty) break;

      if (tentativa < 1) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
    }
  }

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
  // FORNECIMENTO (NOVO FLUXO)
  // ===========================

  /// Abre CADASTRO_FORNECIMENTO na sessão (HORA_INICIO) ou reutiliza registro aberto.
  Future<String> iniciarCadastroFornecimento({
    required String idFornecimento,
    required String idCurral,
    required DateTime data,
    required int trato,
    required double previstoKg,
    required double pesoInicio,
    required String idUsuario,
  }) async {
    final user = idUsuario.trim();
    if (user.isEmpty) {
      throw Exception(
        "Usuário não definido (idUsuario vazio). Faça login novamente.",
      );
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
    if (aberto != null) {
      await assertFabricacaoParaFornecimento(data: data);
      if (kDebugMode) {
        debugPrint(
          "🟦 iniciarCadastroFornecimento: reutiliza aberto id=${aberto.idCadastro} "
          "pesoIni=${aberto.pesoInicio}",
        );
      }
      return aberto.idCadastro;
    }

    final car = await getCarregamentoAberto(data: data);
    if (car == null || car.status != 0) {
      throw Exception(
        "Não existe CARREGAMENTO aberto. Abra um carregamento antes de fornecer.",
      );
    }

    final gate = await assertFabricacaoParaFornecimento(data: data);
    final fab = gate.idFabricacao;

    final idDieta = (car.idDieta ?? idRacaoAtual)?.trim();
    final idDietaFinal =
        (idDieta != null && idDieta.isNotEmpty) ? idDieta : gate.idDieta;

    final newId = _dao.newId40();
    await _dao.abrir(
      id: newId,
      idFornecimento: idFornecimento,
      idFabricacao: fab,
      idBaia: idCurral,
      data: data,
      pesoInicio: pesoInicio,
      previsto: previstoKg,
      trato: trato,
      idUsuario: user,
      idDieta: idDietaFinal.isNotEmpty ? idDietaFinal : null,
    );

    if (kDebugMode) {
      debugPrint(
        "🟦 iniciarCadastroFornecimento OK id=$newId "
        "idFornecimento=$idFornecimento idCurral=$idCurral trato=$trato data=${_ymd(data)}",
      );
    }

    return newId;
  }

  Future<double?> getPesoInicioCadastroAberto({
    required String idFornecimento,
    required String idCurral,
    required DateTime data,
    required int trato,
  }) async {
    final aberto = await _dao.getFornecimentoAberto(
      idFornecimento: idFornecimento,
      idBaia: idCurral,
      data: data,
      trato: trato,
    );
    return aberto?.pesoInicio;
  }

  Future<void> rebasePesoInicioCadastroAberto({
    required String idCadastro,
    required double pesoInicio,
  }) =>
      _dao.atualizarPesoInicioAberto(
        idCadastro: idCadastro,
        pesoInicio: pesoInicio,
      );

  Future<void> cancelarCadastroFornecimentoAberto({
    required String idCadastro,
  }) =>
      _dao.cancelarCadastroAberto(idCadastro);

  /// Finaliza registro aberto (HORA_FIM) ou insere linha completa se id ausente.
  Future<String> salvarCadastroFinalizado({
    required String idFornecimento,
    required String idCurral,
    required DateTime data,
    required int trato,
    required double previstoKg,
    required double pesoFim,
    required double realizadoKg,
    required String idUsuario,
    int origemMapa = 0,
    String? idCadastroAberto,
  }) async {
    final user = idUsuario.trim();
    if (user.isEmpty) {
      throw Exception(
        "Usuário não definido (idUsuario vazio). Faça login novamente.",
      );
    }

    // precisa ter carregamento aberto pra saber dieta/fabricação
    final car = await getCarregamentoAberto(data: data);
    if (car == null || car.status != 0) {
      throw Exception(
        "Não existe CARREGAMENTO aberto. Abra um carregamento antes de fornecer.",
      );
    }

    final gate = await assertFabricacaoParaFornecimento(data: data);
    final fab = gate.idFabricacao;

    // ✅ ID_DIETA == ID_RACAO
    final idDieta = (car.idDieta ?? idRacaoAtual)?.trim();
    final idDietaFinal =
        (idDieta != null && idDieta.isNotEmpty) ? idDieta : gate.idDieta;
    if (idDietaFinal.isEmpty && kDebugMode) {
      debugPrint("⚠️ salvarCadastroFinalizado: idDieta/idRacaoAtual vazio.");
    }

    final idAberto = (idCadastroAberto ?? "").trim();
    if (idAberto.isNotEmpty) {
      await _dao.finalizarCadastro(
        id: idAberto,
        pesoFim: pesoFim,
        realizado: realizadoKg,
      );

      await _dao.aplicarRealizadoLocalPrevisao(
        idFornecimento: idFornecimento,
        idBaia: idCurral,
        trato: trato,
        dataYmd: _ymd(data),
        deltaRealizado: realizadoKg,
      );

      if (kDebugMode) {
        debugPrint(
          "✅ FINALIZADO id=$idAberto data=${_ymd(data)} trato=$trato "
          "realizado=$realizadoKg (HORA_FIM gravada)",
        );
        await _dao.debugDumpCadastroFornecimento(limit: 5);
      }

      return idAberto;
    }

    final idCadastro = _dao.newId40();

    await _dao.salvarFinalizado(
      id: idCadastro,
      idFornecimento: idFornecimento,
      idFabricacao: fab,
      idBaia: idCurral,
      data: data,
      trato: trato,
      idUsuario: user,
      idDieta: idDietaFinal.isNotEmpty ? idDietaFinal : null,
      pesoFim: pesoFim,
      realizado: realizadoKg,
      previsto: previstoKg,
      mapa: origemMapa,
    );

    await _dao.aplicarRealizadoLocalPrevisao(
      idFornecimento: idFornecimento,
      idBaia: idCurral,
      trato: trato,
      dataYmd: _ymd(data),
      deltaRealizado: realizadoKg,
    );

    if (kDebugMode) {
      debugPrint(
        "✅ SALVO FINALIZADO id=$idCadastro data=${_ymd(data)} trato=$trato "
        "idFornecimento=$idFornecimento idBaia=$idCurral realizado=$realizadoKg flag_sync=0",
      );
      await _dao.debugDumpCadastroFornecimento(limit: 5);
    }

    return idCadastro;
  }

  Future<List<Map<String, Object?>>> listSessoesCurral(CurralPrev c) async {
    final dataYmd = c.dataIso.length >= 10 ? c.dataIso.substring(0, 10) : c.dataIso;
    final idRacao = (c.idRacao ?? c.idDieta ?? "").trim();
    return _dao.listSessoesPorChave(
      dataYmd: dataYmd,
      trato: c.trato,
      idBaia: c.idBaia,
      idRacao: idRacao,
      idFornecimento: c.idFornecimento,
    );
  }

  // ===========================
  // PREVISAO (REALIZADO)
  // ===========================
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
        idFornecimento: idFornecimento,
      );

  // ===========================
  // SYNC
  // ===========================
  Future<List<FornecimentoRow>> pendentesSync({int limit = 200}) =>
      _dao.listPendentesSync(limit: limit);

  Future<void> marcarSyncOk(String id) => _dao.marcarSyncOk(id);

  /// Reabilita sync local (FLAG_SYNC=0). Com FornecimentoAcumulativo=1 na API,
  /// o operador deve zerar REALIZADO no CG Pec antes de sincronizar de novo.
  Future<int> reabilitarSyncFiltrados({
    required DateTime data,
    required List<CurralPrev> itens,
  }) async {
    final vistos = <String>{};
    var total = 0;

    for (final c in itens) {
      final idFornecimento = (c.idFornecimento ?? "").trim();
      final idBaia = c.idBaia.trim();
      if (idFornecimento.isEmpty || idBaia.isEmpty) continue;

      final key = "${c.trato}|$idFornecimento|$idBaia";
      if (!vistos.add(key)) continue;

      total += await _dao.marcarSyncPendentePorChave(
        data: data,
        trato: c.trato,
        idFornecimento: idFornecimento,
        idBaia: idBaia,
      );
    }

    return total;
  }

  Future<int> marcarSyncOkFiltrados({
    required DateTime data,
    required List<CurralPrev> itens,
  }) async {
    final vistos = <String>{};
    var total = 0;

    for (final c in itens) {
      final idFornecimento = (c.idFornecimento ?? "").trim();
      final idBaia = c.idBaia.trim();
      if (idFornecimento.isEmpty || idBaia.isEmpty) continue;

      final key = "${c.trato}|$idFornecimento|$idBaia";
      if (!vistos.add(key)) continue;

      total += await _dao.marcarSyncOkPorChave(
        data: data,
        trato: c.trato,
        idFornecimento: idFornecimento,
        idBaia: idBaia,
      );
    }

    return total;
  }

  // ===========================
  // Mantidos (upsert usado por import/sync de fora)
  // ===========================
  Future<void> abrir(FornecimentoRow row) => _dao.upsert(row);

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
    String? idRacao,
    String? racaoNome,
    String? linha,
    String? curralNome,
    bool? realizadoMaiorZero,
  }) async {
    final ymd = _ymd(data);

    return listPrevisaoByYmd(
      idFazenda: idFazenda,
      dataYYYYMMDD: ymd,
      trato: trato,
      idRacao: idRacao,
      racaoNome: racaoNome,
      linha: linha,
      curralNome: curralNome,
      realizadoMaiorZero: realizadoMaiorZero,
    );
  }

  Future<List<CurralPrev>> listPrevisaoByYmd({
    required String idFazenda,
    required String dataYYYYMMDD,
    int? trato,
    String? idRacao,
    String? racaoNome,
    String? linha,
    String? curralNome,
    bool? realizadoMaiorZero,
  }) async {
    final rows = await _listPrevRaw(
      dataYYYYMMDD: dataYYYYMMDD,
      trato: trato,
      idRacao: idRacao,
      racaoNome: racaoNome,
      linha: linha,
      curralNome: curralNome,
      realizadoMaiorZero: realizadoMaiorZero,
    );

    return rows.map((m) => CurralPrev.fromMap(m)).toList();
  }

  // ===========================
  // UI: listRealizadosLocal (CADASTRO_FORNECIMENTO)
  // ===========================
  Future<List<FornecimentoLocalRow>> listRealizadosLocal({
    required DateTime data,
    int? trato,
    String? racaoNome,
    String? linha,
    String? curralNome,
    bool? syncOk,
  }) async {
    final rows = await _listRealizadosLocalRaw(
      dataYYYYMMDD: _ymd(data),
      trato: trato,
      racaoNome: racaoNome,
      linha: linha,
      curralNome: curralNome,
      syncOk: syncOk,
    );
    return rows.map((m) => FornecimentoLocalRow.fromMap(m)).toList();
  }

  Future<List<Map<String, Object?>>> _listRealizadosLocalRaw({
    required String dataYYYYMMDD,
    int? trato,
    String? racaoNome,
    String? linha,
    String? curralNome,
    bool? syncOk,
  }) async {
    final args = <Object?>[dataYYYYMMDD];
    final where = StringBuffer("""
      substr(COALESCE(F.${FornTables.cfData}, ''), 1, 10) = ?
      AND COALESCE(F.${FornTables.cfRealizado}, 0) > 0
    """);

    if (trato != null) {
      where.write(" AND F.${FornTables.cfTrato} = ? ");
      args.add(trato);
    }

    final curral = (curralNome ?? "").trim();
    if (curral.isNotEmpty) {
      where.write(
        " AND UPPER(COALESCE(B.${FornTables.dbNomeLocal}, '')) LIKE UPPER(?) ",
      );
      args.add("%$curral%");
    }

    final linhaTxt = (linha ?? "").trim();
    if (linhaTxt.isNotEmpty) {
      where.write(" AND TRIM(COALESCE(B.${FornTables.dbLinha}, '')) = TRIM(?) ");
      args.add(linhaTxt);
    }

    if (syncOk == true) {
      where.write(" AND COALESCE(F.${FornTables.cfFlagSync}, 0) = 1 ");
    } else if (syncOk == false) {
      where.write(" AND COALESCE(F.${FornTables.cfFlagSync}, 0) = 0 ");
    }

    final hasDieta = await _hasTable("DIETA");
    if (hasDieta) {
      final rn = (racaoNome ?? "").trim();
      if (rn.isNotEmpty) {
        where.write(" AND UPPER(COALESCE(d.NOME, '')) LIKE UPPER(?) ");
        args.add("%$rn%");
      }
    }

    final joinOn = """
      TRIM(CAST(B.${FornTables.dbId} AS TEXT)) =
      TRIM(CAST(F.${FornTables.cfIdBaia} AS TEXT))
    """;

    const fabJoin = """
      LEFT JOIN ${FornTables.cadastroFabrica} FAB
        ON TRIM(CAST(FAB.ID AS TEXT)) = TRIM(CAST(F.${FornTables.cfIdFabricacao} AS TEXT))
    """;

    const fabCols = """
        TRIM(COALESCE(F.${FornTables.cfIdFabricacao}, '')) AS id_fabricacao,
        substr(COALESCE(FAB.DATA_FABRICACAO, ''), 1, 10) AS fab_data_iso,
        COALESCE(FAB.HORA_INICIO, '') AS fab_hora_inicio,
        COALESCE(FAB.QTD_PREVISTA, 0) AS fab_qtd_prevista,
        COALESCE(FAB.QTD_REALIZADA, 0) AS fab_qtd_realizada,
        COALESCE(FAB.FLAG_SYNC, 0) AS fab_flag_sync,
        COALESCE(FAB.HANDOFF_ID, '') AS fab_handoff_id""";

    final sql = hasDieta
        ? """
      SELECT
        F.${FornTables.cfId}              AS id,
        substr(COALESCE(F.${FornTables.cfData}, ''), 1, 10) AS data_iso,
        COALESCE(F.${FornTables.cfHoraInicio}, '') AS hora_inicio,
        COALESCE(F.${FornTables.cfHoraFim}, '')    AS hora_fim,
        F.${FornTables.cfIdBaia}          AS id_baia,
        COALESCE(B.${FornTables.dbNomeLocal}, '')   AS nome_baia,
        COALESCE(CAST(B.${FornTables.dbLinha} AS TEXT), '') AS linha,
        F.${FornTables.cfTrato}           AS trato,
        COALESCE(F.${FornTables.cfIdDieta}, '')     AS id_dieta,
        COALESCE(d.NOME, '')              AS racao_nome,
        COALESCE(F.${FornTables.cfPrevisto}, 0)     AS previsto,
        COALESCE(F.${FornTables.cfRealizado}, 0)    AS realizado,
        COALESCE(F.${FornTables.cfFlagSync}, 0)     AS flag_sync,
        $fabCols,
        COALESCE(FAB_D.NOME, FAB.ID_DIETA, '') AS fab_racao_nome
      FROM ${FornTables.cadastroFornecimento} F
      LEFT JOIN ${FornTables.detalhesBaias} B ON $joinOn
      $fabJoin
      LEFT JOIN DIETA FAB_D
        ON TRIM(CAST(FAB_D.ID AS TEXT)) = TRIM(CAST(FAB.ID_DIETA AS TEXT))
      LEFT JOIN DIETA d
        ON TRIM(CAST(d.ID AS TEXT)) = TRIM(CAST(F.${FornTables.cfIdDieta} AS TEXT))
      WHERE ${where.toString()}
      ORDER BY
        F.${FornTables.cfTrato},
        COALESCE(CAST(B.${FornTables.dbLinha} AS TEXT), ''),
        COALESCE(B.${FornTables.dbOrderTrato}, 0),
        COALESCE(B.${FornTables.dbNomeLocal}, ''),
        COALESCE(F.${FornTables.cfHoraInicio}, ''),
        F.${FornTables.cfId}
    """
        : """
      SELECT
        F.${FornTables.cfId}              AS id,
        substr(COALESCE(F.${FornTables.cfData}, ''), 1, 10) AS data_iso,
        COALESCE(F.${FornTables.cfHoraInicio}, '') AS hora_inicio,
        COALESCE(F.${FornTables.cfHoraFim}, '')    AS hora_fim,
        F.${FornTables.cfIdBaia}          AS id_baia,
        COALESCE(B.${FornTables.dbNomeLocal}, '')   AS nome_baia,
        COALESCE(CAST(B.${FornTables.dbLinha} AS TEXT), '') AS linha,
        F.${FornTables.cfTrato}           AS trato,
        COALESCE(F.${FornTables.cfIdDieta}, '')     AS id_dieta,
        COALESCE(F.${FornTables.cfIdDieta}, '')     AS racao_nome,
        COALESCE(F.${FornTables.cfPrevisto}, 0)     AS previsto,
        COALESCE(F.${FornTables.cfRealizado}, 0)    AS realizado,
        COALESCE(F.${FornTables.cfFlagSync}, 0)     AS flag_sync,
        $fabCols,
        COALESCE(FAB.ID_DIETA, '') AS fab_racao_nome
      FROM ${FornTables.cadastroFornecimento} F
      LEFT JOIN ${FornTables.detalhesBaias} B ON $joinOn
      $fabJoin
      WHERE ${where.toString()}
      ORDER BY
        F.${FornTables.cfTrato},
        COALESCE(CAST(B.${FornTables.dbLinha} AS TEXT), ''),
        COALESCE(B.${FornTables.dbOrderTrato}, 0),
        COALESCE(B.${FornTables.dbNomeLocal}, ''),
        COALESCE(F.${FornTables.cfHoraInicio}, ''),
        F.${FornTables.cfId}
    """;

    if (!hasDieta) {
      final rn = (racaoNome ?? "").trim();
      if (rn.isNotEmpty) {
        final filtered = (await _dao.rawQuery(sql, args))
            .where((m) {
              final id = (m["id_dieta"] ?? "").toString().trim();
              return id.toUpperCase().contains(rn.toUpperCase());
            })
            .toList();
        return filtered;
      }
    }

    return _dao.rawQuery(sql, args);
  }

  Future<ReplicarPrevisaoResult> replicarPrevisaoDoDiaAnterior({
    required DateTime dataDestino,
    required String idFazenda,
  }) async {
    final destinoYmd = _ymd(dataDestino);
    final origemYmd = _ymd(dataDestino.subtract(const Duration(days: 1)));

    final existeNoDestino = await _dao.countPrevisaoByData(
      dataYmd: destinoYmd,
      idFazenda: idFazenda,
    );
    if (existeNoDestino > 0) {
      return ReplicarPrevisaoResult(
        status: ReplicarPrevisaoStatus.diaJaPossuiPrevisao,
      );
    }

    final existeNaOrigem = await _dao.countPrevisaoByData(
      dataYmd: origemYmd,
      idFazenda: idFazenda,
    );
    if (existeNaOrigem <= 0) {
      return ReplicarPrevisaoResult(
        status: ReplicarPrevisaoStatus.diaAnteriorSemPrevisao,
      );
    }

    final copiados = await _dao.replicarPrevisaoEntreDatas(
      dataOrigemYmd: origemYmd,
      dataDestinoYmd: destinoYmd,
      idFazenda: idFazenda,
    );

    return ReplicarPrevisaoResult(
      status: ReplicarPrevisaoStatus.copiado,
      registrosCopiados: copiados,
    );
  }

  // =========================================================
  // 🔥 QUERY “MAPA” (igual Delphi) + filtros
  // =========================================================
  Future<List<Map<String, Object?>>> _listPrevRaw({
    required String dataYYYYMMDD,
    int? trato,
    String? idRacao,
    String? racaoNome,
    String? linha,
    String? curralNome,
    bool? realizadoMaiorZero,
  }) async {
    final where = StringBuffer("WHERE 1=1 ");
    final args = <Object?>[];

    where.write(" AND substr(a.${FornTables.pvData}, 1, 10) = ? ");
    args.add(dataYYYYMMDD);

    if (trato != null) {
      where.write(" AND a.${FornTables.pvTrato} = ? ");
      args.add(trato);
    }

    final racaoId = (idRacao ?? "").trim();
    if (racaoId.isNotEmpty) {
      final racaoNorm = _normalizeRacaoId(racaoId);
      where.write(
        " AND REPLACE(UPPER(TRIM(CAST(a.${FornTables.pvIdRacao} AS TEXT))), ' ', '') "
        "= REPLACE(UPPER(TRIM(CAST(? AS TEXT))), ' ', '') ",
      );
      args.add(racaoNorm);
    }

    final curral = (curralNome ?? "").trim();
    if (curral.isNotEmpty) {
      where.write(" AND UPPER(db.${FornTables.dbNomeLocal}) LIKE UPPER(?) ");
      args.add("%$curral%");
    }

    final linhaTxt = (linha ?? "").trim();
    if (linhaTxt.isNotEmpty) {
      final linhaExpr = FornTables.sqlLinhaResolvida(
        "db.${FornTables.dbNomeLocal}",
        "db.${FornTables.dbLinha}",
      );
      where.write(" AND upper(trim($linhaExpr)) = upper(trim(?)) ");
      args.add(linhaTxt);
    }

    final realizadoExpr = FornTables.sqlRealizadoKgLocal("a");
    if (realizadoMaiorZero == true) {
      where.write(" AND $realizadoExpr > 0 ");
    } else if (realizadoMaiorZero == false) {
      where.write(" AND $realizadoExpr = 0 ");
    }

    final hasDieta = await _hasTable("DIETA");

    if (hasDieta) {
      final rn2 = (racaoNome ?? "").trim();
      if (rn2.isNotEmpty) {
        where.write(" AND UPPER(COALESCE(d.NOME,'')) LIKE UPPER(?) ");
        args.add("%$rn2%");
      }
    }

    final joinOn = """
      TRIM(CAST(db.${FornTables.dbId} AS TEXT)) =
      TRIM(CAST(a.${FornTables.pvIdBaia} AS TEXT))
    """;

    final nomeLocalExpr = """
      COALESCE(
        NULLIF(TRIM(db.${FornTables.dbNomeLocal}), ''),
        NULLIF(TRIM(CAST(a.${FornTables.pvIdBaia} AS TEXT)), ''),
        '(sem nome)'
      )
    """;

    final linhaExpr = FornTables.sqlLinhaResolvida(
      "db.${FornTables.dbNomeLocal}",
      "db.${FornTables.dbLinha}",
    );

    final sql = hasDieta
        ? '''
      SELECT
        COALESCE(db.${FornTables.dbOrderTrato}, 0) AS ordemFornecimento,
        a.${FornTables.pvIdFornecimento}           AS idFornecimento,
        $linhaExpr                                 AS linha,
        CASE
          WHEN instr(db.${FornTables.dbNomeLocal}, '-') > 0 THEN
            substr(db.${FornTables.dbNomeLocal}, instr(db.${FornTables.dbNomeLocal}, '-') + 1)
          ELSE
            '1'
        END AS numero,
        db.${FornTables.dbNomeLocal}              AS nomeLocalRaw,
        $nomeLocalExpr                            AS nomeLocal,
        COALESCE(a.${FornTables.pvPrevistoKg}, 0) AS previstoKg,
        COALESCE(NULLIF(a.${FornTables.pvPrevistoOriginalKg}, 0), 0)
          AS previstoOriginalKg,
        COALESCE(
          NULLIF(a.${FornTables.pvPrevistoRecalculadoKg}, 0),
          NULLIF(a.${FornTables.pvPrevistoKg}, 0),
          0
        ) AS previstoRecalculadoKg,
        COALESCE(a.${FornTables.pvUltimoTrato}, 0) AS isUltimoTrato,
        COALESCE(a.${FornTables.pvIdRacao}, '')   AS idRacao,
        ${FornTables.sqlRealizadoKgLocal("a")}    AS realizadoKg,
        ${FornTables.sqlQtdSessoesLocal("a")}     AS qtdSessoes,
        substr(COALESCE(a.${FornTables.pvData}, ''), 1, 10) AS dataIso,
        COALESCE(db.${FornTables.dbRfid}, '')     AS rfid,
        a.${FornTables.pvIdBaia}                  AS idBaia,
        a.${FornTables.pvTrato}                   AS trato,
        COALESCE(d.NOME, '')                      AS racaoNome
      FROM ${FornTables.previsao} a
      LEFT JOIN ${FornTables.detalhesBaias} db
        ON $joinOn
      LEFT JOIN DIETA d
        ON TRIM(CAST(d.ID AS TEXT)) = TRIM(CAST(a.${FornTables.pvIdRacao} AS TEXT))
      ${where.toString()}
      ORDER BY
        a.${FornTables.pvTrato},
        COALESCE(db.${FornTables.dbOrderTrato}, 0),
        $linhaExpr,
        $nomeLocalExpr
      '''
        : '''
      SELECT
        COALESCE(db.${FornTables.dbOrderTrato}, 0) AS ordemFornecimento,
        a.${FornTables.pvIdFornecimento}           AS idFornecimento,
        $linhaExpr                                 AS linha,
        CASE
          WHEN instr(db.${FornTables.dbNomeLocal}, '-') > 0 THEN
            substr(db.${FornTables.dbNomeLocal}, instr(db.${FornTables.dbNomeLocal}, '-') + 1)
          ELSE
            '1'
        END AS numero,
        db.${FornTables.dbNomeLocal}              AS nomeLocalRaw,
        $nomeLocalExpr                            AS nomeLocal,
        COALESCE(a.${FornTables.pvPrevistoKg}, 0) AS previstoKg,
        COALESCE(NULLIF(a.${FornTables.pvPrevistoOriginalKg}, 0), 0)
          AS previstoOriginalKg,
        COALESCE(
          NULLIF(a.${FornTables.pvPrevistoRecalculadoKg}, 0),
          NULLIF(a.${FornTables.pvPrevistoKg}, 0),
          0
        ) AS previstoRecalculadoKg,
        COALESCE(a.${FornTables.pvUltimoTrato}, 0) AS isUltimoTrato,
        COALESCE(a.${FornTables.pvIdRacao}, '')   AS idRacao,
        ${FornTables.sqlRealizadoKgLocal("a")}    AS realizadoKg,
        ${FornTables.sqlQtdSessoesLocal("a")}     AS qtdSessoes,
        substr(COALESCE(a.${FornTables.pvData}, ''), 1, 10) AS dataIso,
        COALESCE(db.${FornTables.dbRfid}, '')     AS rfid,
        a.${FornTables.pvIdBaia}                  AS idBaia,
        a.${FornTables.pvTrato}                   AS trato,
        ''                                        AS racaoNome
      FROM ${FornTables.previsao} a
      LEFT JOIN ${FornTables.detalhesBaias} db
        ON $joinOn
      ${where.toString()}
      ORDER BY
        a.${FornTables.pvTrato},
        COALESCE(db.${FornTables.dbOrderTrato}, 0),
        $linhaExpr,
        $nomeLocalExpr
      ''';

    if (kDebugMode) {
      debugPrint("PREV SQL (MAPA) => $sql");
      debugPrint("ARGS => $args");
    }

    return _dao.rawQuery(sql, args);
  }
}


