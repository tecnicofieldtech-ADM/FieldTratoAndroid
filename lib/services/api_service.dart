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
            headers: {"Accept": "application/json"},
          ),
        );

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

  Future<List<dynamic>> getPrevisaoTrato(String idFazenda, String dataYmd) async {
    final r = await _dio.get("/previsao_trato/get/$idFazenda/$dataYmd");
    if (r.statusCode != 200) throw Exception(r.data.toString());
    if (r.data is List) return r.data as List;
    return jsonDecode(r.data.toString()) as List;
  }

  Future<bool> postGravaTag(Map<String, dynamic> body) async {
    final r = await _dio.post("/Post/GravaTag", data: body);
    return r.statusCode == 200;
  }

  Future<bool> postFabricacao(Map<String, dynamic> body) async {
    final r = await _dio.post("/Post/Fabricacao", data: body);
    return r.statusCode == 200;
  }

  Future<bool> postFabricacaoInsumo(Map<String, dynamic> body) async {
    final r = await _dio.post("/Post/Fabricacao_Insumo", data: body);
    return r.statusCode == 200;
  }

  Future<bool> postFornecimento(Map<String, dynamic> body) async {
    final r = await _dio.post("/Post/Fornecimento", data: body);
    return r.statusCode == 200;
  }
}
