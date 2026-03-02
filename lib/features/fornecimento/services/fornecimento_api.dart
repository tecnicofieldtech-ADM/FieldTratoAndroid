import "dart:convert";
import "package:http/http.dart" as http;

class FornecimentoApi {
  FornecimentoApi({
    required this.baseUrl,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  Uri _u(String path) => Uri.parse("$baseUrl$path");

  Future<List<dynamic>> getPrevisaoTrato({
    required String idFazenda,
    required String dataPrev, // yyyy-mm-dd
  }) async {
    final res = await _client.get(
      _u("/previsao_trato/get/$idFazenda/$dataPrev"),
      headers: {"Accept": "application/json"},
    );

    if (res.statusCode != 200) {
      throw Exception("Erro ao obter previsão de trato: ${res.body}");
    }

    final jsonVal = jsonDecode(res.body);
    if (jsonVal is! List) {
      throw Exception("Formato inválido de resposta para previsão de trato.");
    }
    return jsonVal;
  }

  Future<List<dynamic>> getDietasDetalhes({
    required String idFazenda,
  }) async {
    final res = await _client.get(
      _u("/dietas_detalhes/get/$idFazenda"),
      headers: {"Accept": "application/json"},
    );

    if (res.statusCode != 200) {
      throw Exception("Erro ao buscar detalhes das dietas: ${res.body}");
    }

    final jsonVal = jsonDecode(res.body);
    if (jsonVal is! List) {
      throw Exception("Formato inválido no retorno de detalhes das dietas.");
    }
    return jsonVal;
  }
}


