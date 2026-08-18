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
  //   PREVISTO_KG, PREVISTO_ORIGINAL_KG, PREVISTO_RECALCULADO_KG,
  //   PREVISTO_CADASTRO_KG, REALIZADO_KG, ID_RACAO, ULTIMO_TRATO
  // )
  // =========================
  static const String pvIdFornecimento = "ID_FORNECIMENTO";
  static const String pvData = "DATA";
  static const String pvTrato = "TRATO";
  static const String pvIdBaia = "ID_BAIA";
  static const String pvPrevistoKg = "PREVISTO_KG";
  static const String pvPrevistoOriginalKg = "PREVISTO_ORIGINAL_KG";
  static const String pvPrevistoRecalculadoKg = "PREVISTO_RECALCULADO_KG";
  static const String pvPrevistoCadastroKg = "PREVISTO_CADASTRO_KG";
  static const String pvRealizadoKg = "REALIZADO_KG";
  static const String pvIdRacao = "ID_RACAO";
  static const String pvUltimoTrato = "ULTIMO_TRATO";

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

  /// LINHA: banco (<=3 chars) ou ate 3 letras antes de '-'/'_' no nome.
  static const int linhaCurralMaxLen = 3;

  static String sqlLinhaResolvida(String nomeCol, String linhaCol) => """
CASE
  WHEN NULLIF(TRIM($linhaCol), '') IS NOT NULL
       AND length(TRIM($linhaCol)) <= $linhaCurralMaxLen THEN
    upper(TRIM($linhaCol))
  ELSE upper(substr(
    CASE
      WHEN instr(replace($nomeCol, ' ', ''), '-') > 0 THEN
        substr(replace($nomeCol, ' ', ''), 1, instr(replace($nomeCol, ' ', ''), '-') - 1)
      WHEN instr(replace($nomeCol, ' ', ''), '_') > 0 THEN
        substr(replace($nomeCol, ' ', ''), 1, instr(replace($nomeCol, ' ', ''), '_') - 1)
      ELSE replace(trim($nomeCol), ' ', '')
    END,
    1, $linhaCurralMaxLen
  ))
END""";

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
  static const String cfMapa = "MAPA";

  /// Soma dos realizados locais por baia+trato+data+dieta; se não houver linhas, usa PREVISAO.
  static String sqlChaveCadastroMatchPrevisao(
    String aliasPrevisao,
    String aliasCadastro,
  ) {
    final a = aliasPrevisao;
    final cf = aliasCadastro;
    return """
TRIM(COALESCE($cf.$cfIdBaia, '')) = TRIM(COALESCE($a.$pvIdBaia, ''))
AND $cf.$cfTrato = $a.$pvTrato
AND substr(COALESCE($cf.$cfData, ''), 1, 10) = substr(COALESCE($a.$pvData, ''), 1, 10)
AND (
  TRIM(COALESCE($cf.$cfIdDieta, '')) = TRIM(COALESCE($a.$pvIdRacao, ''))
  OR TRIM(COALESCE($cf.$cfIdFornecimento, '')) = TRIM(COALESCE($a.$pvIdFornecimento, ''))
)""";
  }

  /// Realizado do curral = acumulado da API/TGC (PREVISAO) + sessões locais
  /// ainda não sincronizadas. Não substitui o TGC pela automação.
  static String sqlRealizadoKgLocal(String aliasPrevisao) {
    final a = aliasPrevisao;
    final match = sqlChaveCadastroMatchPrevisao(a, "cf");
    return """
(
  COALESCE($a.$pvRealizadoKg, 0)
  + COALESCE((
      SELECT SUM(COALESCE(cf.$cfRealizado, 0))
      FROM $cadastroFornecimento cf
      WHERE $match
        AND COALESCE(cf.$cfRealizado, 0) > 0
        AND IFNULL(cf.$cfFlagSync, 0) = 0
    ), 0)
)""";
  }

  static String sqlQtdSessoesLocal(String aliasPrevisao) {
    final a = aliasPrevisao;
    final match = sqlChaveCadastroMatchPrevisao(a, "cf2");
    return """
(
  SELECT COUNT(*)
  FROM $cadastroFornecimento cf2
  WHERE $match
    AND COALESCE(cf2.$cfRealizado, 0) > 0
)""";
  }
}


