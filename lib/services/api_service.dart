// lib/services/api_service.dart
import "dart:convert";

import "package:dio/dio.dart";

import "../constants/config_options.dart";

/// HTTP 409 no TGC e conflito de conteudo: a fabricacao continua pendente.
/// Nos demais backends, 409 segue o contrato antigo (conta como sync).
bool fabricacaoPostContaComoSincronizado({
  required int? statusCode,
  required bool isTgc,
}) {
  if (statusCode == null) return false;
  if (isTgc && statusCode == 409) return false;
  if (statusCode >= 200 && statusCode < 300) return true;
  if (!isTgc && statusCode == 409) return true;
  return false;
}

class ApiService {
  final Dio _dio;
  final int _backend;

  bool get isFieldpec => ConfigOptions.isFieldPecBackend(_backend);
  bool get isTgc => ConfigOptions.isTgcBackend(_backend);
  bool get isPlanilha => ConfigOptions.isPlanilhaBackend(_backend);
  int get backend => _backend;
  bool get _usesOpenApiLists => ConfigOptions.usesOpenApiLists(_backend);
  bool get ignoresFazendaId => ConfigOptions.ignoresFazendaId(_backend);
  bool get requiresNumericFazendaId =>
      ConfigOptions.requiresNumericFazendaId(_backend);
  bool get usesFabricacaoPacote => ConfigOptions.usesFabricacaoPacote(_backend);
  bool get usesIndependentFornecimentoSync =>
      ConfigOptions.usesIndependentFornecimentoSync(_backend);

  bool _isHttpSuccess(int? statusCode) {
    if (statusCode == null) return false;
    return statusCode >= 200 && statusCode < 300;
  }

  String _responseText(dynamic data) {
    if (data == null) return "";
    if (data is String) return data;
    try {
      return jsonEncode(data);
    } catch (_) {
      return data.toString();
    }
  }

  bool _isFieldpecGravaTagFalseNegative500(dynamic data) {
    final t = _responseText(data).toLowerCase();
    if (t.isEmpty) return false;

    return t.contains("não encontrado para atualização") ||
        t.contains("nao encontrado para atualizacao") ||
        t.contains("não encontrado para atualizacao") ||
        t.contains("nao encontrado para atualização");
  }

  ApiService({
    required String baseUrl,
    int backend = 0,
    String clientCode = "",
  })  : _backend = backend,
        _dio = Dio(
          BaseOptions(
            baseUrl: baseUrl,
            // Tablet em LAN/TGC: 2.5s falhava cedo demais e parecia que "nao saiu".
            connectTimeout: const Duration(milliseconds: 8000),
            receiveTimeout: const Duration(seconds: 30),
            sendTimeout: const Duration(seconds: 30),
            headers: {
              "Accept": "application/json",
              "Content-Type": "application/json",
              if (clientCode.trim().isNotEmpty)
                "X-Client-Code": clientCode.trim().toUpperCase(),
            },
          ),
        ) {
    _dio.interceptors.add(
      LogInterceptor(
        requestBody: false,
        responseBody: false,
        requestHeader: true,
        responseHeader: false,
        error: true,
      ),
    );
  }

  Future<bool> getTeste() async {
    final meta = await getTesteMeta();
    return meta["ok"] == true;
  }

  /// GET /GetTeste com o body (importacao_id no modo Planilha).
  Future<Map<String, dynamic>> getTesteMeta() async {
    try {
      final r = await _dio.get("/GetTeste");
      if (r.statusCode != 200) return {"ok": false};
      final out = <String, dynamic>{"ok": true};
      if (r.data is Map) {
        final m = Map<String, dynamic>.from(r.data as Map);
        out.addAll(m);
        for (final key in const [
          "importacao_id",
          "IMPORTACAO_ID",
          "importacaoId",
        ]) {
          final v = (m[key] ?? "").toString().trim();
          if (v.isNotEmpty) {
            out["importacao_id"] = v;
            break;
          }
        }
      }
      return out;
    } catch (_) {
      return {"ok": false};
    }
  }

  /// Confirma que o código do header X-Client-Code está cadastrado na API.
  /// Usa /fazenda/get (sempre presente). /cliente/validar só se a API já tiver a rota.
  Future<Map<String, dynamic>> validateClienteCodigo() async {
    try {
      final r = await _dio.get(
        "/cliente/validar",
        options: Options(validateStatus: (s) => s != null),
      );
      if (_isHttpSuccess(r.statusCode) && r.data is Map) {
        final data = Map<String, dynamic>.from(r.data as Map);
        if (data["ok"] == true || data["success"] == true) {
          return data;
        }
      }
      // 404 = rota ainda não deployada → cai no fallback abaixo
      if (r.statusCode != 404) {
        final err = _extractApiError(r.data);
        if (err.isNotEmpty &&
            !err.toLowerCase().contains("not found") &&
            !err.toLowerCase().contains("route")) {
          throw Exception(err);
        }
      }
    } catch (e) {
      // Rota ausente / rede: tenta validação compatível
      final s = e.toString().toLowerCase();
      final canFallback = s.contains("not found") ||
          s.contains("404") ||
          s.contains("route") ||
          s.contains("dioexception");
      if (!canFallback) rethrow;
    }

    return _validateClienteCodigoViaFazenda();
  }

  Future<Map<String, dynamic>> _validateClienteCodigoViaFazenda() async {
    final r = await _dio.get(
      "/fazenda/get",
      options: Options(validateStatus: (s) => s != null),
    );
    if (_isHttpSuccess(r.statusCode)) {
      return {
        "ok": true,
        "success": true,
        "via": "fazenda/get",
      };
    }
    final err = _extractApiError(r.data);
    throw Exception(
      err.isNotEmpty
          ? err
          : "Código do cliente não cadastrado na API (HTTP ${r.statusCode}).",
    );
  }

  Future<List<dynamic>> getVagoes() async {
    return _getListRequired("/vagao/get/");
  }

  Future<List<dynamic>> getFazendas() async {
    return _getListRequired("/fazenda/get");
  }

  Future<List<dynamic>> getUsuarios(String idFazenda) async {
    final id = idFazenda.trim();

    if (_usesOpenApiLists) {
      return _getFieldpecListNoId(
      label: "usuários",
      attempts: const [
        (path: "/usuarios/get", query: null),
      ],
    );
    }

    if (id.isEmpty) {
      throw Exception("ID da fazenda vazio para baixar usuários.");
    }
    return _getListRequired("/usuarios/get/$id");
  }

  Future<List<dynamic>> getBaias(String idFazenda) async {
    final id = idFazenda.trim();

    if (_usesOpenApiLists) {
      return _getFieldpecListNoId(
      label: "baias",
      attempts: const [
        (path: "/baias/get", query: null),
      ],
    );
    }

    if (id.isEmpty) {
      throw Exception("ID da fazenda vazio para baixar baias.");
    }
    return _getListRequired("/baias/get/$id");
  }

  Future<List<dynamic>> getDietas(String idFazenda) async {
    final id = idFazenda.trim();

    if (_usesOpenApiLists) {
      // TGC Horse: rota oficial e /dietas/get/:idfazenda. Tenta aberta e com id.
      final attempts = <({String path, Map<String, dynamic>? query})>[
        (path: "/dietas/get", query: null),
        if (id.isNotEmpty) (path: "/dietas/get/$id", query: null),
      ];
      return _getFieldpecListNoId(label: "dietas", attempts: attempts);
    }

    if (id.isEmpty) {
      throw Exception("ID da fazenda vazio para baixar dietas.");
    }
    return _getListRequired("/dietas/get/$id");
  }

  Future<List<dynamic>> getDietasDetalhes(String idFazenda) async {
    final id = idFazenda.trim();

    if (_usesOpenApiLists) {
      final attempts = <({String path, Map<String, dynamic>? query})>[
        (path: "/dietas_detalhes/get", query: null),
        if (id.isNotEmpty) (path: "/dietas_detalhes/get/$id", query: null),
      ];
      return _getFieldpecListNoId(
        label: "detalhes de dietas",
        attempts: attempts,
      );
    }

    if (id.isEmpty) {
      throw Exception("ID da fazenda vazio para baixar detalhes de dietas.");
    }
    return _getListRequired("/dietas_detalhes/get/$id");
  }

  Future<List<dynamic>> getPrevisaoTrato(String idFazenda, String dataYmd) async {
    final id = idFazenda.trim();
    final data = dataYmd.trim();

    if (_usesOpenApiLists) {
      return _getFieldpecListNoId(
      label: "previsão de trato",
      attempts: const [
        (path: "/previsao_trato/get", query: null),
      ],
    );
    }

    if (id.isEmpty) {
      throw Exception("ID da fazenda vazio para baixar previsão de trato.");
    }
    if (data.isEmpty) {
      throw Exception("Data vazia para baixar previsão de trato.");
    }
    return _getListRequired("/previsao_trato/get/$id/$data");
  }

  Future<List<dynamic>> _getListRequired(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    final r = await _dio.get(path, queryParameters: query);
    if (r.statusCode != 200) throw Exception(r.data.toString());

    final list = _extractList(r.data);
    if (list != null) return list;

    throw Exception("Resposta inválida em $path");
  }

  String _extractApiError(dynamic data) {
    if (data is Map) {
      final m = Map<String, dynamic>.from(data);
      for (final key in const ["erro", "error", "Erro", "message", "msg"]) {
        final v = m[key];
        if (v != null && v.toString().trim().isNotEmpty) {
          return v.toString().trim();
        }
      }
    }
    final text = _responseText(data).trim();
    return text.length > 200 ? "${text.substring(0, 200)}..." : text;
  }

  Future<List<dynamic>> _getFieldpecListNoId({
    required String label,
    required List<({String path, Map<String, dynamic>? query})> attempts,
  }) async {
    final errors = <String>[];

    for (final t in attempts) {
      try {
        final r = await _dio.get(
          t.path,
          queryParameters: t.query,
          options: Options(validateStatus: (s) => s != null),
        );

        if (r.statusCode == 200) {
          final list = _extractList(r.data);
          if (list != null) return list;

          errors.add("${t.path} -> HTTP 200 sem lista no body");
          continue;
        }

        final apiErr = _extractApiError(r.data);
        if (apiErr.isNotEmpty) {
          errors.add("${t.path} -> HTTP ${r.statusCode}: $apiErr");
        } else {
          errors.add("${t.path} -> HTTP ${r.statusCode}");
        }
      } on DioException catch (e) {
        errors.add("${t.path} -> EXC ${e.type} HTTP ${e.response?.statusCode}");
      }
    }

    throw Exception(
      "Falha ao baixar $label (API aberta FieldPec/TGC/Planilha). "
      "Tentativas: ${errors.join(" | ")}",
    );
  }

  List<dynamic>? _extractList(dynamic data) {
    if (data is List) return data;

    if (data is String) {
      final s = data.trim();
      if (s.isEmpty) return null;
      final decoded = jsonDecode(s);
      return _extractList(decoded);
    }

    if (data is Map) {
      final m = Map<String, dynamic>.from(data);
      for (final key in const [
        "data",
        "items",
        "usuarios",
        "baias",
        "dietas",
        "detalhes",
        "previsao",
        "result",
        "results",
      ]) {
        final v = m[key];
        if (v is List) return v;
      }
      return null;
    }

    return null;
  }

  Future<bool> postGravaTag(Map<String, dynamic> body,
      {void Function(String)? log}) async {
    Future<bool> sendOnce({required int attempt}) async {
      final r = await _dio.post(
        "/Post/GravaTag",
        data: body,
        options: Options(
          validateStatus: (s) => s != null,
          contentType: Headers.jsonContentType,
          responseType: ResponseType.plain,
          receiveTimeout: const Duration(milliseconds: 25000),
          sendTimeout: const Duration(milliseconds: 12000),
        ),
      );

      if (_isHttpSuccess(r.statusCode)) return true;

      if (isFieldpec &&
          r.statusCode == 500 &&
          _isFieldpecGravaTagFalseNegative500(r.data)) {
        log?.call(
          "⚠️ /Post/GravaTag HTTP 500 com indicio de falso negativo (RowsAffected). Assumindo sucesso no Fieldpec.",
        );
        return true;
      }

      log?.call("❌ /Post/GravaTag tentativa=$attempt HTTP ${r.statusCode}");
      return false;
    }

    try {
      final ok1 = await sendOnce(attempt: 1);
      if (ok1) return true;
      return false;
    } on DioException catch (e1) {
      log?.call(
        "❌ /Post/GravaTag EXC tentativa=1 tipo=${e1.type} HTTP ${e1.response?.statusCode}",
      );

      if (e1.response?.statusCode != null) {
        return false;
      }

      log?.call("↻ /Post/GravaTag sem resposta HTTP, tentando novamente...");

      try {
        final ok2 = await sendOnce(attempt: 2);
        return ok2;
      } on DioException catch (e2) {
        log?.call(
          "❌ /Post/GravaTag EXC tentativa=2 tipo=${e2.type} HTTP ${e2.response?.statusCode}",
        );
        return false;
      } catch (e2) {
        log?.call("❌ /Post/GravaTag ERRO tentativa=2: $e2");
        return false;
      }
    } catch (e) {
      log?.call("❌ /Post/GravaTag ERRO: $e");
      return false;
    }
  }

  /// POST /Post/Fabricacao com pacote completo; retorna true se a API Field
  /// respondeu com [id_servidor] (insumos gravados no mesmo request).
  Future<bool> postFabricacaoPacoteFieldpec(
    Map<String, dynamic> body, {
    void Function(String)? log,
  }) async {
    try {
      final r = await _dio.post(
        "/Post/Fabricacao",
        data: body,
        options: Options(
          validateStatus: (s) => s != null,
          contentType: Headers.jsonContentType,
          receiveTimeout: const Duration(seconds: 120),
          sendTimeout: const Duration(seconds: 120),
        ),
      );

      final okStatus = _isHttpSuccess(r.statusCode) || r.statusCode == 201;
      if (!okStatus) {
        log?.call(
          "❌ /Post/Fabricacao (pacote Fieldpec) HTTP ${r.statusCode} "
          "${_responseText(r.data)}",
        );
        return false;
      }

      final data = r.data;
      if (data is Map) {
        final idSrv = data["id_servidor"];
        if (idSrv != null && idSrv.toString().trim().isNotEmpty) {
          log?.call("✅ Fieldpec pacote OK id_servidor=$idSrv");
          return true;
        }
      }
      return false;
    } on DioException catch (e) {
      log?.call(
        "❌ /Post/Fabricacao pacote Fieldpec EXC tipo=${e.type.name} "
        "HTTP ${e.response?.statusCode} msg=${e.message ?? ''}",
      );
      return false;
    } catch (e) {
      log?.call("❌ /Post/Fabricacao pacote Fieldpec ERRO: $e");
      return false;
    }
  }

  Future<bool> postFabricacao(Map<String, dynamic> body,
      {void Function(String)? log}) async {
    try {
      final r = await _dio.post(
        "/Post/Fabricacao",
        data: body,
        options: Options(
          validateStatus: (s) => s != null,
          contentType: Headers.jsonContentType,
          receiveTimeout: Duration(seconds: usesFabricacaoPacote ? 120 : 30),
          sendTimeout: Duration(seconds: usesFabricacaoPacote ? 120 : 30),
        ),
      );

      if (fabricacaoPostContaComoSincronizado(
        statusCode: r.statusCode,
        isTgc: isTgc,
      )) {
        if (isTgc && r.data is Map && r.data["alreadySynced"] == true) {
          log?.call(
            "Fabricacao TGC ja existia no servidor "
            "id=${r.data["id_servidor"] ?? r.data["Ok"] ?? ""}",
          );
        }
        return true;
      }

      if (isTgc && r.statusCode == 409) {
        log?.call(
          "❌ /Post/Fabricacao TGC conflito 409 "
          "(mesmo id, conteudo diferente). Pendente. "
          "${_extractApiError(r.data)}",
        );
        return false;
      }

      final errBody = _extractApiError(r.data);
      log?.call("❌ /Post/Fabricacao HTTP ${r.statusCode} $errBody");
      return false;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final body = _extractApiError(e.response?.data);

      log?.call(
        "❌ /Post/Fabricacao EXC tipo=${e.type.name} HTTP $status "
        "msg=${e.message ?? ''}",
      );
      if (body.isNotEmpty) {
        log?.call("❌ /Post/Fabricacao API: $body");
      }
      return false;
    } catch (e) {
      log?.call("❌ /Post/Fabricacao ERRO: $e");
      return false;
    }
  }

  Future<bool> postFabricacaoInsumo(
    Map<String, dynamic> body, {
    void Function(String)? log,
  }) async {
    try {
      final jsonBody = jsonEncode(body);

      final r = await _dio.post(
        "/Post/Fabricacao_Insumo",
        data: jsonBody,
        options: Options(
          validateStatus: (s) => s != null,
          headers: {
            "Accept": "application/json",
            "Content-Type": "application/json; charset=utf-8",
          },
          responseType: ResponseType.plain,
        ),
      );

      if (_isHttpSuccess(r.statusCode)) return true;

      if (r.statusCode == 404) {
        log?.call(
          "❌ /Post/Fabricacao_Insumo HTTP 404 — rota inexistente. "
          "No Fieldpec use BACKEND=Fieldpec (1): insumos vão em POST /Post/Fabricacao.",
        );
        return false;
      }

      log?.call("❌ /Post/Fabricacao_Insumo HTTP ${r.statusCode} ${_extractApiError(r.data)}");
      return false;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final body = _extractApiError(e.response?.data);

      log?.call("❌ /Post/Fabricacao_Insumo EXCEPTION HTTP $status");
      if (body.isNotEmpty) {
        log?.call("❌ /Post/Fabricacao_Insumo API: $body");
      }
      return false;
    } catch (e) {
      log?.call("❌ /Post/Fabricacao_Insumo ERRO: $e");
      return false;
    }
  }

  Future<bool> postFornecimento(Map<String, dynamic> body,
      {void Function(String)? log}) async {
    try {
      final r = await _dio.post(
        "/Post/Fornecimento",
        data: body,
        options: Options(
          validateStatus: (s) => s != null,
          contentType: Headers.jsonContentType,
          receiveTimeout: const Duration(seconds: 60),
          sendTimeout: const Duration(seconds: 60),
        ),
      );

      if (_isHttpSuccess(r.statusCode)) {
        final data = r.data;
        if (data is Map) {
          final m = Map<String, dynamic>.from(data);
          final err = (m["Erro"] ?? m["erro"] ?? m["error"] ?? "").toString();
          if (err.trim().isNotEmpty) {
            log?.call("❌ /Post/Fornecimento HTTP ${r.statusCode} $err");
            return false;
          }
          if (m["ok"] == false || m["Ok"] == false) {
            log?.call(
              "❌ /Post/Fornecimento HTTP ${r.statusCode} ${_extractApiError(data)}",
            );
            return false;
          }
          if (m["ignorado_ponto_corte"] == true) {
            final kg = m["realizado_recebido"] ?? m["realizado"];
            final corte = m["ponto_corte_kg"];
            log?.call(
              "Fornecimento ignorado (ponto de corte $corte kg): recebido=$kg — sync confirmado",
            );
          }
        }
        return true;
      }

      log?.call(
        "❌ /Post/Fornecimento HTTP ${r.statusCode} ${_extractApiError(r.data)}",
      );
      return false;
    } on DioException catch (e) {
      log?.call(
        "❌ /Post/Fornecimento EXC HTTP ${e.response?.statusCode} "
        "${_extractApiError(e.response?.data)}",
      );
      return false;
    } catch (e) {
      log?.call("❌ /Post/Fornecimento ERRO: $e");
      return false;
    }
  }

  /// Envia snapshot completo de CADASTRO_FORNECIMENTO para auditoria no servidor.
  Future<Map<String, dynamic>?> postFornecimentoAudit(
    Map<String, dynamic> body, {
    void Function(String)? log,
  }) async {
    try {
      final r = await _dio.post(
        "/Post/FornecimentoAudit",
        data: body,
        options: Options(
          validateStatus: (s) => s != null,
          contentType: Headers.jsonContentType,
          receiveTimeout: const Duration(seconds: 120),
          sendTimeout: const Duration(seconds: 120),
        ),
      );

      if (!_isHttpSuccess(r.statusCode)) {
        log?.call(
          "❌ /Post/FornecimentoAudit HTTP ${r.statusCode} ${_extractApiError(r.data)}",
        );
        return null;
      }

      final data = r.data;
      if (data is Map<String, dynamic>) return data;
      if (data is Map) return Map<String, dynamic>.from(data);
      if (data is String && data.trim().isNotEmpty) {
        final decoded = jsonDecode(data);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      }
      return {"ok": true};
    } on DioException catch (e) {
      log?.call(
        "❌ /Post/FornecimentoAudit EXC HTTP ${e.response?.statusCode} "
        "${_extractApiError(e.response?.data)}",
      );
      return null;
    } catch (e) {
      log?.call("❌ /Post/FornecimentoAudit ERRO: $e");
      return null;
    }
  }

  /// Envia snapshot completo de CADASTRO_FABRICA_RACAO para auditoria no servidor.
  Future<Map<String, dynamic>?> postFabricacaoAudit(
    Map<String, dynamic> body, {
    void Function(String)? log,
  }) async {
    try {
      final r = await _dio.post(
        "/Post/FabricacaoAudit",
        data: body,
        options: Options(
          validateStatus: (s) => s != null,
          contentType: Headers.jsonContentType,
          receiveTimeout: const Duration(seconds: 120),
          sendTimeout: const Duration(seconds: 120),
        ),
      );

      if (!_isHttpSuccess(r.statusCode)) {
        log?.call(
          "❌ /Post/FabricacaoAudit HTTP ${r.statusCode} ${_extractApiError(r.data)}",
        );
        return null;
      }

      final data = r.data;
      if (data is Map<String, dynamic>) return data;
      if (data is Map) return Map<String, dynamic>.from(data);
      if (data is String && data.trim().isNotEmpty) {
        final decoded = jsonDecode(data);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      }
      return {"ok": true};
    } on DioException catch (e) {
      log?.call(
        "❌ /Post/FabricacaoAudit EXC HTTP ${e.response?.statusCode} "
        "${_extractApiError(e.response?.data)}",
      );
      return null;
    } catch (e) {
      log?.call("❌ /Post/FabricacaoAudit ERRO: $e");
      return null;
    }
  }
}
