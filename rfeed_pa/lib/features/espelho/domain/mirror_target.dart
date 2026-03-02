class MirrorTarget {
  final int id;
  final String nome;
  final String host;
  final int porta;
  final bool ativo;

  const MirrorTarget({
    required this.id,
    required this.nome,
    required this.host,
    required this.porta,
    required this.ativo,
  });

  factory MirrorTarget.fromMap(Map<String, dynamic> m) {
    return MirrorTarget(
      id: (m["id"] as num).toInt(),
      nome: (m["nome"] ?? "").toString(),
      host: (m["host"] ?? "").toString(),
      porta: (m["porta"] as num?)?.toInt() ?? 9000,
      ativo: ((m["ativo"] as num?)?.toInt() ?? 0) == 1,
    );
  }

  Map<String, dynamic> toMap() => {
        "id": id,
        "nome": nome,
        "host": host,
        "porta": porta,
        "ativo": ativo ? 1 : 0,
      };

  MirrorTarget copyWith({
    int? id,
    String? nome,
    String? host,
    int? porta,
    bool? ativo,
  }) {
    return MirrorTarget(
      id: id ?? this.id,
      nome: nome ?? this.nome,
      host: host ?? this.host,
      porta: porta ?? this.porta,
      ativo: ativo ?? this.ativo,
    );
  }
}


