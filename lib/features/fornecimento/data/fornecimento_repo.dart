// lib/features/fornecimento/data/fornecimento_repo.dart
import "dart:convert";
import "dart:io";

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
    final car = await _carregDao.getAbertoHoje(data: data ?? DateTime.now());
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
    final car = await _carregDao.getAbertoHoje(data: data ?? DateTime.now());
    return car != null;
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

    // ✅ mantém idRacaoAtual consistente
    if (racaoFinal != null) setIdRacaoAtual(racaoFinal);

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
  // FORNECIMENTO (NOVO FLUXO)
  // ===========================

  /// ✅ Agora NÃO existe “cadastro aberto” no SQLite.
  /// Esta função só valida pré-condições e devolve um ID de sessão (local),
  /// se você quiser usar na UI (não grava no banco).
  Future<String> iniciarCadastroFornecimento({
    required String idFornecimento,
    required String idCurral,
    required DateTime data,
    required int trato,
    required double previstoKg,
    required double pesoInicio, // mantido por compat com sua UI, mas NÃO grava
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

    // ✅ id apenas para controle da UI (não salva em tabela)
    final sessionId = _dao.newId40();

    if (kDebugMode) {
      debugPrint(
        "🟦 iniciarCadastroFornecimento (SEM INSERT) sessionId=$sessionId "
        "idFornecimento=$idFornecimento idCurral=$idCurral trato=$trato data=${_ymd(data)} previsto=$previstoKg",
      );
    }

    return sessionId;
  }

  /// ✅ SALVA FINALIZADO: ÚNICO ponto onde insere no CADASTRO_FORNECIMENTO
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

    // ✅ ID_DIETA == ID_RACAO
    final idDieta = (car.idDieta ?? idRacaoAtual)?.trim();
    if (idDieta == null || idDieta.isEmpty) {
      // não impede salvar, mas é bom avisar
      if (kDebugMode) {
        debugPrint("⚠️ salvarCadastroFinalizado: idDieta/idRacaoAtual vazio.");
      }
    }

    // fabricação: prioriza do carregamento; se não tiver, pega “em aberto”
    final idFabricacao = (car.idFabricacao ?? "").trim();
    final fab = idFabricacao.isNotEmpty
        ? idFabricacao
        : ((await _dao.getFabricacaoEmAbertoId(data: data)) ?? "").trim();

    if (fab.isEmpty) {
      // dependendo da sua regra, aqui você pode BLOQUEAR. Por ora, apenas avisa.
      if (kDebugMode) {
        debugPrint(
            "⚠️ salvarCadastroFinalizado: ID_FABRICACAO vazio (vai salvar mesmo assim).");
      }
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
      idDieta: (idDieta != null && idDieta.isNotEmpty) ? idDieta : null,
      pesoFim: pesoFim,
      realizado: realizadoKg,
      previsto: previstoKg,
      mapa: origemMapa,
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
      idFazenda: idFazenda,
      idRacao: idRacao,
      racaoNome: racaoNome,
      linha: linha,
      curralNome: curralNome,
      realizadoMaiorZero: realizadoMaiorZero,
    );

    return rows.map((m) => CurralPrev.fromMap(m)).toList();
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
    String? idFazenda,
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

    final faz = (idFazenda ?? "").trim();
    if (faz.isNotEmpty) {
      final hasIdFaz = await _hasColumn(FornTables.detalhesBaias, "ID_FAZENDA");
      if (hasIdFaz) {
        where.write(" AND TRIM(db.ID_FAZENDA) = TRIM(?) ");
        args.add(faz);
      }
    }

    if (trato != null) {
      where.write(" AND a.${FornTables.pvTrato} = ? ");
      args.add(trato);
    }

    final racaoId = (idRacao ?? "").trim();
    if (racaoId.isNotEmpty) {
      where.write(" AND TRIM(a.${FornTables.pvIdRacao}) = TRIM(?) ");
      args.add(racaoId);
    }

    final curral = (curralNome ?? "").trim();
    if (curral.isNotEmpty) {
      where.write(" AND UPPER(db.${FornTables.dbNomeLocal}) LIKE UPPER(?) ");
      args.add("%$curral%");
    }

    final linhaTxt = (linha ?? "").trim();
    if (linhaTxt.isNotEmpty) {
      where.write(" AND TRIM(db.${FornTables.dbLinha}) = TRIM(?) ");
      args.add(linhaTxt);
    }

    if (realizadoMaiorZero == true) {
      where.write(" AND COALESCE(a.${FornTables.pvRealizadoKg},0) > 0 ");
    } else if (realizadoMaiorZero == false) {
      where.write(" AND COALESCE(a.${FornTables.pvRealizadoKg},0) = 0 ");
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

    String linhaText(String expr) => "COALESCE(CAST($expr AS TEXT), '')";

    final sql = hasDieta
        ? '''
      SELECT
        COALESCE(db.${FornTables.dbOrderTrato}, 0) AS ordemFornecimento,
        a.${FornTables.pvIdFornecimento}           AS idFornecimento,
        ${linhaText("db.${FornTables.dbLinha}")}   AS linha,
        CASE
          WHEN instr(db.${FornTables.dbNomeLocal}, '-') > 0 THEN
            substr(db.${FornTables.dbNomeLocal}, instr(db.${FornTables.dbNomeLocal}, '-') + 1)
          ELSE
            '1'
        END AS numero,
        db.${FornTables.dbNomeLocal}              AS nomeLocal,
        COALESCE(a.${FornTables.pvPrevistoKg}, 0) AS previstoKg,
        COALESCE(a.${FornTables.pvIdRacao}, '')   AS idRacao,
        COALESCE(a.${FornTables.pvRealizadoKg},0) AS realizadoKg,
        COALESCE(db.${FornTables.dbRfid}, '')     AS rfid,
        a.${FornTables.pvIdBaia}                  AS idBaia,
        a.${FornTables.pvTrato}                   AS trato,
        COALESCE(d.NOME, '')                      AS racaoNome
      FROM ${FornTables.previsao} a
      JOIN ${FornTables.detalhesBaias} db
        ON $joinOn
      LEFT JOIN DIETA d
        ON TRIM(CAST(d.ID AS TEXT)) = TRIM(CAST(a.${FornTables.pvIdRacao} AS TEXT))
      ${where.toString()}
      ORDER BY
        a.${FornTables.pvTrato},
        COALESCE(db.${FornTables.dbOrderTrato}, 0),
        ${linhaText("db.${FornTables.dbLinha}")},
        db.${FornTables.dbNomeLocal}
      '''
        : '''
      SELECT
        COALESCE(db.${FornTables.dbOrderTrato}, 0) AS ordemFornecimento,
        a.${FornTables.pvIdFornecimento}           AS idFornecimento,
        ${linhaText("db.${FornTables.dbLinha}")}   AS linha,
        CASE
          WHEN instr(db.${FornTables.dbNomeLocal}, '-') > 0 THEN
            substr(db.${FornTables.dbNomeLocal}, instr(db.${FornTables.dbNomeLocal}, '-') + 1)
          ELSE
            '1'
        END AS numero,
        db.${FornTables.dbNomeLocal}              AS nomeLocal,
        COALESCE(a.${FornTables.pvPrevistoKg}, 0) AS previstoKg,
        COALESCE(a.${FornTables.pvIdRacao}, '')   AS idRacao,
        COALESCE(a.${FornTables.pvRealizadoKg},0) AS realizadoKg,
        COALESCE(db.${FornTables.dbRfid}, '')     AS rfid,
        a.${FornTables.pvIdBaia}                  AS idBaia,
        a.${FornTables.pvTrato}                   AS trato,
        ''                                        AS racaoNome
      FROM ${FornTables.previsao} a
      JOIN ${FornTables.detalhesBaias} db
        ON $joinOn
      ${where.toString()}
      ORDER BY
        a.${FornTables.pvTrato},
        COALESCE(db.${FornTables.dbOrderTrato}, 0),
        ${linhaText("db.${FornTables.dbLinha}")},
        db.${FornTables.dbNomeLocal}
      ''';

    if (kDebugMode) {
      debugPrint("PREV SQL (MAPA) => $sql");
      debugPrint("ARGS => $args");
    }

    return _dao.rawQuery(sql, args);
  }
}


