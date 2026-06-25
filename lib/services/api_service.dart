// lib/services/api_service.dart
import "dart:convert";

import "package:dio/dio.dart";

class ApiService {
  final Dio _dio;
  final int _backend;

  bool get _isFieldpec => _backend == 1;
  bool get isFieldpec => _isFieldpec;

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

  ApiService({required String baseUrl, int backend = 0})
      : _backend = backend,
        _dio = Dio(
          BaseOptions(
            baseUrl: baseUrl,
            connectTimeout: const Duration(milliseconds: 2500),
            receiveTimeout: const Duration(milliseconds: 8000),
            sendTimeout: const Duration(milliseconds: 8000),
            headers: {
              "Accept": "application/json",
              "Content-Type": "application/json",
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
    try {
      final r = await _dio.get("/GetTeste");
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<List<dynamic>> getVagoes() async {
    return _getListRequired("/vagao/get/");
  }

  Future<List<dynamic>> getFazendas() async {
    return _getListRequired("/fazenda/get");
  }

  Future<List<dynamic>> getUsuarios(String idFazenda) async {
    final id = idFazenda.trim();

    if (!_isFieldpec) {
      if (id.isEmpty) {
        throw Exception("ID da fazenda vazio para baixar usuários no CG Pec.");
      }
      return _getListRequired("/usuarios/get/$id");
    }

    return _getFieldpecListNoId(
      label: "usuários",
      attempts: const [
        (path: "/usuarios/get", query: null),
      ],
    );
  }

  Future<List<dynamic>> getBaias(String idFazenda) async {
    final id = idFazenda.trim();

    if (!_isFieldpec) {
      if (id.isEmpty) {
        throw Exception("ID da fazenda vazio para baixar baias no CG Pec.");
      }
      return _getListRequired("/baias/get/$id");
    }

    return _getFieldpecListNoId(
      label: "baias",
      attempts: const [
        (path: "/baias/get", query: null),
      ],
    );
  }

  Future<List<dynamic>> getDietas(String idFazenda) async {
    final id = idFazenda.trim();

    if (!_isFieldpec) {
      if (id.isEmpty) {
        throw Exception("ID da fazenda vazio para baixar dietas no CG Pec.");
      }
      return _getListRequired("/dietas/get/$id");
    }

    return _getFieldpecListNoId(
      label: "dietas",
      attempts: const [
        (path: "/dietas/get", query: null),
      ],
    );
  }

  Future<List<dynamic>> getDietasDetalhes(String idFazenda) async {
    final id = idFazenda.trim();

    if (!_isFieldpec) {
      if (id.isEmpty) {
        throw Exception(
          "ID da fazenda vazio para baixar detalhes de dietas no CG Pec.",
        );
      }
      return _getListRequired("/dietas_detalhes/get/$id");
    }

    return _getFieldpecListNoId(
      label: "detalhes de dietas",
      attempts: const [
        (path: "/dietas_detalhes/get", query: null),
      ],
    );
  }

  Future<List<dynamic>> getPrevisaoTrato(String idFazenda, String dataYmd) async {
    final id = idFazenda.trim();
    final data = dataYmd.trim();

    if (!_isFieldpec) {
      if (id.isEmpty) {
        throw Exception(
          "ID da fazenda vazio para baixar previsão de trato no CG Pec.",
        );
      }
      if (data.isEmpty) {
        throw Exception("Data vazia para baixar previsão de trato no CG Pec.");
      }
      return _getListRequired("/previsao_trato/get/$id/$data");
    }

    return _getFieldpecListNoId(
      label: "previsão de trato",
      attempts: const [
        (path: "/previsao_trato/get", query: null),
      ],
    );
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

        errors.add("${t.path} -> HTTP ${r.statusCode}");
      } on DioException catch (e) {
        errors.add("${t.path} -> EXC ${e.type} HTTP ${e.response?.statusCode}");
      }
    }

    throw Exception(
      "Falha ao baixar $label no Fieldpec (sem idFazenda). "
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

      if (_isFieldpec &&
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
          receiveTimeout: Duration(seconds: _isFieldpec ? 120 : 30),
          sendTimeout: Duration(seconds: _isFieldpec ? 120 : 30),
        ),
      );

      if (_isHttpSuccess(r.statusCode) ||
          r.statusCode == 201 ||
          r.statusCode == 208 ||
          r.statusCode == 409) {
        return true;
      }

      final errBody = _responseText(r.data);
      log?.call("❌ /Post/Fabricacao HTTP ${r.statusCode} $errBody");
      if (r.statusCode == 500 && errBody.contains("error")) {
        log?.call("❌ /Post/Fabricacao detalhe API: $errBody");
      }
      return false;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final body = _responseText(e.response?.data);

      log?.call(
        "❌ /Post/Fabricacao EXC tipo=${e.type.name} HTTP $status "
        "msg=${e.message ?? ''}",
      );
      if (body.isNotEmpty) {
        log?.call("❌ /Post/Fabricacao corpo: $body");
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

      log?.call("❌ /Post/Fabricacao_Insumo HTTP ${r.statusCode}");
      return false;
    } on DioException catch (e) {
      final status = e.response?.statusCode;

      log?.call("❌ /Post/Fabricacao_Insumo EXCEPTION HTTP $status");
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
        ),
      );

      if (_isHttpSuccess(r.statusCode)) {
        final data = r.data;
        if (data is Map) {
          final m = Map<String, dynamic>.from(data);
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

      log?.call("❌ /Post/Fornecimento HTTP ${r.statusCode}");
      return false;
    } on DioException catch (e) {
      log?.call("❌ /Post/Fornecimento EXC HTTP ${e.response?.statusCode}");
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
        log?.call("❌ /Post/FornecimentoAudit HTTP ${r.statusCode}");
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
        "❌ /Post/FornecimentoAudit EXC HTTP ${e.response?.statusCode}",
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
        log?.call("❌ /Post/FabricacaoAudit HTTP ${r.statusCode}");
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
        "❌ /Post/FabricacaoAudit EXC HTTP ${e.response?.statusCode}",
      );
      return null;
    } catch (e) {
      log?.call("❌ /Post/FabricacaoAudit ERRO: $e");
      return null;
    }
  }
}
