// lib/features/fornecimento/data/fornecimento_tables.dart

class FornTables {
  // tabelas
  static const String previsao = "FORNECIMENTO_CONF"; // ajuste se o nome real for outro
  static const String detalhesBaias = "DETALHES_BAIAS";
  static const String cadastroFornecimento = "CADASTRO_FORNECIMENTO";

  // ✅ faltavam (erros de compile)
  static const String ultimoLogin = "ULTIMO_LOGIN";
  static const String cadastroFabrica = "CADASTRO_FABRICA_RACAO";

  // previsao cols
  static const String pv_idFornecimento = "ID_FORNECIMENTO";
  static const String pv_data = "DATA_LEITURA";
  static const String pv_trato = "TRATO";
  static const String pv_idBaia = "ID_BAIA";
  static const String pv_previstoKg = "PREVISTO_MN_KG";
  static const String pv_realizadoKg = "REALIZADO_MN_KG";
  static const String pv_idRacao = "ID_RACAO";

  // baias cols
  static const String db_id = "ID";
  static const String db_nomeLocal = "NOME_LOCAL";
  static const String db_linha = "LINHA";
  static const String db_orderTrato = "ORDER_TRATO";
  static const String db_rfid = "RFID";
  static const String db_idLote = "ID_LOTE";
  static const String db_idFazenda = "ID_FAZENDA";

  // cadastro fornecimento cols
  static const String cf_id = "ID";
  static const String cf_idFornecimento = "ID_FORNECIMENTO";
  static const String cf_idFabricacao = "ID_FABRICACAO";
  static const String cf_idBaia = "ID_BAIA";
  static const String cf_data = "DATA";
  static const String cf_horaInicio = "HORA_INICIO";
  static const String cf_horaFim = "HORA_FIM";
  static const String cf_pesoInicio = "PESO_INICIO";
  static const String cf_pesoFim = "PESO_FIM";
  static const String cf_previsto = "PREVISTO";
  static const String cf_realizado = "REALIZADO";
  static const String cf_flagSync = "FLAG_SYNC";
  static const String cf_trato = "TRATO";
  static const String cf_idUsuario = "ID_USUARIO";
  static const String cf_idDieta = "ID_DIETA";
}
