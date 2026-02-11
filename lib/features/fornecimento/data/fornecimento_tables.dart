// lib/features/fornecimento/data/fornecimento_tables.dart

class FornTables {
  // =========================
  // TABELAS (SQLite)
  // =========================
  // ✅ A previsão é gravada pelo BootstrapSync em "PREVISAO"
  static const String previsao = "PREVISAO";

  static const String detalhesBaias = "DETALHES_BAIAS";
  static const String cadastroFornecimento = "CADASTRO_FORNECIMENTO";

  // ✅ usadas no DAO
  static const String ultimoLogin = "ULTIMO_LOGIN";
  static const String cadastroFabrica = "CADASTRO_FABRICA_RACAO";

  // =========================
  // PREVISAO (cols)
  //
  // CREATE TABLE PREVISAO (
  //   ID_FORNECIMENTO, DATA, ID_BAIA, TRATO,
  //   PREVISTO_KG, REALIZADO_KG, ID_RACAO
  // )
  // =========================
  static const String pvIdFornecimento = "ID_FORNECIMENTO";
  static const String pvData = "DATA";
  static const String pvTrato = "TRATO";
  static const String pvIdBaia = "ID_BAIA";
  static const String pvPrevistoKg = "PREVISTO_KG";
  static const String pvRealizadoKg = "REALIZADO_KG";
  static const String pvIdRacao = "ID_RACAO";

  // =========================
  // DETALHES_BAIAS (cols)
  //
  // CREATE TABLE DETALHES_BAIAS (
  //   ID, ID_LOTE, NOME_LOCAL, LINHA, ORDER_TRATO,
  //   RFID, ID_FAZENDA, ...
  // )
  // =========================
  static const String dbId = "ID";
  static const String dbNomeLocal = "NOME_LOCAL";
  static const String dbLinha = "LINHA";
  static const String dbOrderTrato = "ORDER_TRATO";
  static const String dbRfid = "RFID";
  static const String dbIdLote = "ID_LOTE";
  static const String dbIdFazenda = "ID_FAZENDA";

  // =========================
  // CADASTRO_FORNECIMENTO (cols)
  //
  // CREATE TABLE CADASTRO_FORNECIMENTO (
  //   ID, ID_FORNECIMENTO, ID_FABRICACAO, ID_BAIA, DATA,
  //   HORA_INICIO, HORA_FIM,
  //   PESO_INICIO, PESO_FIM,
  //   PREVISTO, REALIZADO,
  //   FLAG_SYNC, TRATO, ID_USUARIO, ID_DIETA
  // )
  // =========================
  static const String cfId = "ID";
  static const String cfIdFornecimento = "ID_FORNECIMENTO";
  static const String cfIdFabricacao = "ID_FABRICACAO";
  static const String cfIdBaia = "ID_BAIA";
  static const String cfData = "DATA";
  static const String cfHoraInicio = "HORA_INICIO";
  static const String cfHoraFim = "HORA_FIM";
  static const String cfPesoInicio = "PESO_INICIO";
  static const String cfPesoFim = "PESO_FIM";
  static const String cfPrevisto = "PREVISTO";
  static const String cfRealizado = "REALIZADO";
  static const String cfFlagSync = "FLAG_SYNC";
  static const String cfTrato = "TRATO";
  static const String cfIdUsuario = "ID_USUARIO";
  static const String cfIdDieta = "ID_DIETA";

  
}
