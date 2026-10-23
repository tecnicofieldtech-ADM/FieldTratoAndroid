import "package:flutter_test/flutter_test.dart";
import "package:field_trato/constants/config_options.dart";
import "package:field_trato/services/planilha_importacao.dart";

void main() {
  const cargaA = "ca7331e7-1ec3-459b-b392-435491830068";
  const cargaB = "49999407-d8b9-466f-98f4-efad6986fe88";

  test("criação Planilha congela CONFIG.IMPORTACAO_ID", () {
    expect(
      PlanilhaImportacao.freezeFromConfig(
        backend: ConfigOptions.backendPlanilha,
        configImportacaoId: cargaA,
      ),
      cargaA,
    );
  });

  test("criação FieldPec/TGC não grava IMPORTACAO_ID", () {
    expect(
      PlanilhaImportacao.freezeFromConfig(
        backend: ConfigOptions.backendFieldPec,
        configImportacaoId: cargaA,
      ),
      isNull,
    );
    expect(
      PlanilhaImportacao.freezeFromConfig(
        backend: ConfigOptions.backendTgc,
        configImportacaoId: cargaA,
      ),
      isNull,
    );
  });

  test("outbox usa o registro, não a carga ativa atual", () {
    final enviado = PlanilhaImportacao.forOutbox(
      backend: ConfigOptions.backendPlanilha,
      registroImportacaoId: cargaA,
    );
    expect(enviado, cargaA);
    expect(enviado, isNot(cargaB));
  });

  test("troca da carga ativa não reclassifica operação antiga", () {
    const registroCriadoComA = cargaA;
    const configAgoraB = cargaB;
    final post = PlanilhaImportacao.forOutbox(
      backend: ConfigOptions.backendPlanilha,
      registroImportacaoId: registroCriadoComA,
    );
    final seUsasseConfig = PlanilhaImportacao.freezeFromConfig(
      backend: ConfigOptions.backendPlanilha,
      configImportacaoId: configAgoraB,
    );
    expect(post, cargaA);
    expect(seUsasseConfig, cargaB);
    expect(post, isNot(seUsasseConfig));
  });
}
