import "package:flutter_test/flutter_test.dart";
import "package:field_trato/constants/config_options.dart";

void main() {
  test("backends 0 e 2 permanecem FieldPec e TGC", () {
    expect(ConfigOptions.backendFieldPec, 0);
    expect(ConfigOptions.backendTgc, 2);
    expect(ConfigOptions.isFieldPecBackend(0), isTrue);
    expect(ConfigOptions.isFieldPecBackend(1), isTrue);
    expect(ConfigOptions.isTgcBackend(2), isTrue);
    expect(ConfigOptions.ignoresFazendaId(2), isTrue);
    expect(ConfigOptions.ignoresFazendaId(0), isFalse);
    expect(ConfigOptions.requiresNumericFazendaId(0), isTrue);
    expect(ConfigOptions.requiresNumericFazendaId(2), isFalse);
    expect(ConfigOptions.normalizeBackend(0), 0);
    expect(ConfigOptions.normalizeBackend(1), 0);
    expect(ConfigOptions.normalizeBackend(2), 2);
  });

  test("backend 3 é Planilha sem virar FieldPec", () {
    expect(ConfigOptions.backendPlanilha, 3);
    expect(ConfigOptions.normalizeBackend(3), 3);
    expect(ConfigOptions.isPlanilhaBackend(3), isTrue);
    expect(ConfigOptions.isFieldPecBackend(3), isFalse);
    expect(ConfigOptions.isTgcBackend(3), isFalse);
    expect(ConfigOptions.usesOpenApiLists(3), isTrue);
    expect(ConfigOptions.usesFabricacaoPacote(3), isTrue);
    expect(ConfigOptions.usesFieldPecSyncOrder(3), isTrue);
    expect(ConfigOptions.usesIndependentFornecimentoSync(3), isTrue);
    expect(ConfigOptions.requiresNumericFazendaId(3), isFalse);
    expect(ConfigOptions.ignoresFazendaId(3), isFalse);
    expect(ConfigOptions.backends[3], "Planilha");
  });

  test("normalizeBackend desconhecido continua FieldPec", () {
    expect(ConfigOptions.normalizeBackend(99), 0);
    expect(ConfigOptions.normalizeBackend(null), 0);
  });
}
