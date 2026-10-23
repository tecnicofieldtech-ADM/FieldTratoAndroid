class RedeEstacionario {
  RedeEstacionario({
    required this.id,
    required this.nome,
    required this.ssid,
    required this.senha,
    required this.hostEstacionario,
    required this.portaEstacionario,
    required this.ativo,
    this.stationId = "",
  });

  final String id;
  final String nome;
  final String ssid;
  final String senha;
  final String hostEstacionario;
  final int portaEstacionario;
  final int ativo;
  final String stationId;

  String get nomeExibicao {
    final n = nome.trim();
    if (n.isNotEmpty) return n;
    final s = ssid.trim();
    if (s.isNotEmpty) return s;
    return hostEstacionario;
  }

  factory RedeEstacionario.fromMap(Map<String, Object?> m) {
    int toInt(Object? v, [int def = 0]) {
      if (v == null) return def;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString()) ?? def;
    }

    return RedeEstacionario(
      id: (m["ID"] ?? "").toString(),
      nome: (m["NOME"] ?? "").toString(),
      ssid: (m["SSID"] ?? "").toString(),
      senha: (m["SENHA"] ?? "").toString(),
      hostEstacionario: (m["HOST_ESTACIONARIO"] ?? "").toString(),
      portaEstacionario: toInt(m["PORTA_ESTACIONARIO"], 8080),
      ativo: toInt(m["ATIVO"], 1),
      stationId: (m["STATION_ID"] ?? "").toString(),
    );
  }

  Map<String, Object?> toMap() => {
        "ID": id,
        "NOME": nome,
        "SSID": ssid,
        "SENHA": senha,
        "HOST_ESTACIONARIO": hostEstacionario,
        "PORTA_ESTACIONARIO": portaEstacionario,
        "STATION_ID": stationId,
        "ATIVO": ativo,
      };
}
