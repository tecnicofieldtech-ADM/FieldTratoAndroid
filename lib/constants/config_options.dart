class ConfigOptions {
  static const int backendFieldPec = 0;
  static const int backendFieldPecLegacy = 1;
  static const int backendTgc = 2;
  static const int backendPlanilha = 3;

  /// TGC: CFORN_LOTE_FABRICACAO aceita no maximo 20 caracteres.
  static const int tgcLoteFabricacaoMaxLen = 20;

  static const int defaultApiPort = 3001;

  static const backends = <int, String>{
    backendFieldPec: "FieldPec",
    backendTgc: "Outros (TGC)",
    backendPlanilha: "Planilha",
  };

  static const operacoes = <int, String>{
    0: "Rotormix",
    1: "Estacionário",
    2: "Distribuidor",
  };

  static const modelosBalanca = <int, String>{
    0: "Topcon",
    1: "Dinâmica Generale",
    2: "Alfa",
    3: "Hook",
    4: "PTM AV40/AV50",
  };

  static const modelosRfid = <int, String>{
    0: "Via Onda",
  };

  static const saidaFabricacao = <int, String>{
    0: "Espelhamento da pá",
    1: "LED via conversor BS1C (Bluetooth)",
  };

  static bool isFieldPecBackend(int backend) =>
      backend == backendFieldPec || backend == backendFieldPecLegacy;

  static bool isTgcBackend(int backend) => backend == backendTgc;

  static bool isPlanilhaBackend(int backend) => backend == backendPlanilha;

  /// FieldPec, TGC e Planilha: GETs de lista sem idFazenda na URL.
  static bool usesOpenApiLists(int backend) =>
      isFieldPecBackend(backend) ||
      isTgcBackend(backend) ||
      isPlanilhaBackend(backend);

  /// TGC nao usa ID_PROPRIEDADE no POST.
  /// FieldPec POST /Post/Fabricacao exige id_fazenda/ID_PROPRIEDADE numerico.
  /// Planilha envia id_fazenda como texto.
  static bool ignoresFazendaId(int backend) => isTgcBackend(backend);

  /// FieldPec exige ID_FAZENDA numerico no POST de fabricação.
  static bool requiresNumericFazendaId(int backend) =>
      isFieldPecBackend(backend);

  /// Fabricação em pacote único (POST /Post/Fabricacao com itens).
  static bool usesFabricacaoPacote(int backend) =>
      isFieldPecBackend(backend) ||
      isTgcBackend(backend) ||
      isPlanilhaBackend(backend);

  /// Ordem da sync: fornecimento antes da fabricação (FieldPec e Planilha).
  static bool usesFieldPecSyncOrder(int backend) =>
      isFieldPecBackend(backend) || isPlanilhaBackend(backend);

  /// Fornecimento sobe independente da fabricação ter FLAG_SYNC=1.
  static bool usesIndependentFornecimentoSync(int backend) =>
      isFieldPecBackend(backend) || isPlanilhaBackend(backend);

  /// Previsão com previsto original/recalculado e último trato.
  static bool usesDualPrevisao(int backend) =>
      isFieldPecBackend(backend) ||
      isTgcBackend(backend) ||
      isPlanilhaBackend(backend);

  /// Normaliza valor salvo no SQLite para o dropdown atual.
  static int normalizeBackend(int? backend) {
    final b = backend ?? backendFieldPec;
    if (b == backendFieldPecLegacy) return backendFieldPec;
    if (b == backendFieldPec || b == backendTgc || b == backendPlanilha) {
      return b;
    }
    return backendFieldPec;
  }
}
