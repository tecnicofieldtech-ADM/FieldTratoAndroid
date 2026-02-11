// lib/services/api_service.dart
import "dart:convert";
import "package:dio/dio.dart";

class ApiService {
  final Dio _dio;

  ApiService({required String baseUrl})
      : _dio = Dio(
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
    // ✅ log completo no console (ajuda MUITO a achar 500 com {erro:"..."})
    _dio.interceptors.add(
      LogInterceptor(
        requestBody: true,
        responseBody: true,
        requestHeader: true,
        responseHeader: false,
        error: true,
      ),
    );
  }

  /// equivalente ao QuickPing + /GetTeste
  Future<bool> getTeste() async {
    try {
      final r = await _dio.get("/GetTeste");
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<List<dynamic>> getVagoes() async {
    final r = await _dio.get("/vagao/get/");
    if (r.statusCode != 200) throw Exception(r.data.toString());
    if (r.data is List) return r.data as List;
    return jsonDecode(r.data.toString()) as List;
  }

  Future<List<dynamic>> getFazendas() async {
    final r = await _dio.get("/fazenda/get");
    if (r.statusCode != 200) throw Exception(r.data.toString());
    if (r.data is List) return r.data as List;
    return jsonDecode(r.data.toString()) as List;
  }

  Future<List<dynamic>> getUsuarios(String idFazenda) async {
    final r = await _dio.get("/usuarios/get/$idFazenda");
    if (r.statusCode != 200) throw Exception(r.data.toString());
    if (r.data is List) return r.data as List;
    return jsonDecode(r.data.toString()) as List;
  }

  Future<List<dynamic>> getBaias(String idFazenda) async {
    final r = await _dio.get("/baias/get/$idFazenda");
    if (r.statusCode != 200) throw Exception(r.data.toString());
    if (r.data is List) return r.data as List;
    return jsonDecode(r.data.toString()) as List;
  }

  Future<List<dynamic>> getDietas(String idFazenda) async {
    final r = await _dio.get("/dietas/get/$idFazenda");
    if (r.statusCode != 200) throw Exception(r.data.toString());
    if (r.data is List) return r.data as List;
    return jsonDecode(r.data.toString()) as List;
  }

  Future<List<dynamic>> getDietasDetalhes(String idFazenda) async {
    final r = await _dio.get("/dietas_detalhes/get/$idFazenda");
    if (r.statusCode != 200) throw Exception(r.data.toString());
    if (r.data is List) return r.data as List;
    return jsonDecode(r.data.toString()) as List;
  }

  Future<List<dynamic>> getPrevisaoTrato(
      String idFazenda, String dataYmd) async {
    final r = await _dio.get("/previsao_trato/get/$idFazenda/$dataYmd");
    if (r.statusCode != 200) throw Exception(r.data.toString());
    if (r.data is List) return r.data as List;
    return jsonDecode(r.data.toString()) as List;
  }

  Future<bool> postGravaTag(Map<String, dynamic> body,
      {void Function(String)? log}) async {
    try {
      final r = await _dio.post(
        "/Post/GravaTag",
        data: body,
        options: Options(
          validateStatus: (s) => s != null, // ✅ não lança em 500
          contentType: Headers.jsonContentType,
        ),
      );

      if (r.statusCode == 200) return true;

      log?.call("❌ /Post/GravaTag HTTP ${r.statusCode}");
      log?.call("📤 Req: $body");
      log?.call("📥 Resp: ${r.data}");
      return false;
    } on DioException catch (e) {
      log?.call("❌ /Post/GravaTag EXC HTTP ${e.response?.statusCode}");
      log?.call("📤 Req: $body");
      log?.call("📥 Resp: ${e.response?.data ?? e.message}");
      return false;
    } catch (e) {
      log?.call("❌ /Post/GravaTag ERRO: $e");
      log?.call("📤 Req: $body");
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
          validateStatus: (s) => s != null, // ✅ não lança em 500
          contentType: Headers.jsonContentType,
        ),
      );

      if (r.statusCode == 200) return true;

      log?.call("❌ /Post/Fabricacao HTTP ${r.statusCode}");
      log?.call("📤 Req: $body");
      log?.call("📥 Resp: ${r.data}");
      return false;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final data = e.response?.data;

      log?.call("❌ /Post/Fabricacao EXCEPTION HTTP $status");
      log?.call("📤 Req: $body");
      log?.call("📥 Resp: ${data ?? e.message}");
      return false;
    } catch (e) {
      log?.call("❌ /Post/Fabricacao ERRO: $e");
      log?.call("📤 Req: $body");
      return false;
    }
  }

  Future<bool> postFabricacaoInsumo(
    Map<String, dynamic> body, {
    void Function(String)? log,
  }) async {
    try {
      // 🔥 garante que o payload final (string) é exatamente o que vai pra API
      final jsonBody = jsonEncode(body);

      log?.call("🚀 /Post/Fabricacao_Insumo JSON = $jsonBody");

      final r = await _dio.post(
        "/Post/Fabricacao_Insumo",
        data: jsonBody, // ✅ envia string pronta, Dio não “re-encoda”
        options: Options(
          validateStatus: (s) => s != null,
          headers: {
            "Accept": "application/json",
            "Content-Type": "application/json; charset=utf-8",
          },
          responseType: ResponseType.plain,
        ),
      );

      if (r.statusCode == 200) return true;

      log?.call("❌ /Post/Fabricacao_Insumo HTTP ${r.statusCode}");
      log?.call("📥 Resp: ${r.data}");
      return false;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final data = e.response?.data;

      log?.call("❌ /Post/Fabricacao_Insumo EXCEPTION HTTP $status");
      log?.call("📥 Resp: ${data ?? e.message}");
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
          validateStatus: (s) => s != null, // ✅ não lança em 500
          contentType: Headers.jsonContentType,
        ),
      );

      if (r.statusCode == 200) return true;

      log?.call("❌ /Post/Fornecimento HTTP ${r.statusCode}");
      log?.call("📤 Req: $body");
      log?.call("📥 Resp: ${r.data}");
      return false;
    } on DioException catch (e) {
      log?.call("❌ /Post/Fornecimento EXC HTTP ${e.response?.statusCode}");
      log?.call("📤 Req: $body");
      log?.call("📥 Resp: ${e.response?.data ?? e.message}");
      return false;
    } catch (e) {
      log?.call("❌ /Post/Fornecimento ERRO: $e");
      log?.call("📤 Req: $body");
      return false;
    }
  }
}
