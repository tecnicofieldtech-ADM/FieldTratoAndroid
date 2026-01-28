class ConfigOptions {
  static const backends = <int, String>{
    0: "CG Pec",
    1: "Fieldpec",
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
}
