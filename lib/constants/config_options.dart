class ConfigOptions {
  static const int backendFieldPec = 0;
  static const int backendFieldPecLegacy = 1;
  static const int backendTgc = 2;

  /// TGC: CFORN_LOTE_FABRICACAO aceita no maximo 20 caracteres.
  static const int tgcLoteFabricacaoMaxLen = 20;

  static const int defaultApiPort = 3001;

  static const backends = <int, String>{
    backendFieldPec: "FieldPec",
    backendTgc: "Outros (TGC)",
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

  /// FieldPec e TGC: GETs/POSTs sem idFazenda na URL nem no body.
  static bool usesOpenApiLists(int backend) =>
      isFieldPecBackend(backend) || isTgcBackend(backend);

  static bool ignoresFazendaId(int backend) => usesOpenApiLists(backend);

  /// Fabricação em pacote único (POST /Post/Fabricacao com itens).
  static bool usesFabricacaoPacote(int backend) =>
      isFieldPecBackend(backend) || isTgcBackend(backend);

  /// Normaliza valor salvo no SQLite para o dropdown atual.
  static int normalizeBackend(int? backend) {
    final b = backend ?? backendFieldPec;
    if (b == backendFieldPecLegacy) return backendFieldPec;
    if (b == backendFieldPec || b == backendTgc) return b;
    return backendFieldPec;
  }
}
