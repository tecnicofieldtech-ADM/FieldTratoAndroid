import "package:flutter_test/flutter_test.dart";
import "package:field_trato/services/api_service.dart";

void main() {
  test("TGC 200 novo e alreadySynced contam como sucesso", () {
    expect(
      fabricacaoPostContaComoSincronizado(statusCode: 200, isTgc: true),
      isTrue,
    );
  });

  test("TGC 409 conflito permanece pendente", () {
    expect(
      fabricacaoPostContaComoSincronizado(statusCode: 409, isTgc: true),
      isFalse,
    );
  });

  test("TGC timeout e 500 e 503 permanecem pendentes", () {
    expect(
      fabricacaoPostContaComoSincronizado(statusCode: null, isTgc: true),
      isFalse,
    );
    expect(
      fabricacaoPostContaComoSincronizado(statusCode: 500, isTgc: true),
      isFalse,
    );
    expect(
      fabricacaoPostContaComoSincronizado(statusCode: 503, isTgc: true),
      isFalse,
    );
  });

  test("FieldPec e planilha preservam 409 como sync concluida", () {
    expect(
      fabricacaoPostContaComoSincronizado(statusCode: 409, isTgc: false),
      isTrue,
    );
    expect(
      fabricacaoPostContaComoSincronizado(statusCode: 200, isTgc: false),
      isTrue,
    );
    expect(
      fabricacaoPostContaComoSincronizado(statusCode: 500, isTgc: false),
      isFalse,
    );
  });
}
