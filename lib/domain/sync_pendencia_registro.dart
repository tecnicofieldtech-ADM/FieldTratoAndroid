enum SyncPendenciaTipo { gravaTag, fabricacao, fornecimento }

class SyncPendenciaRegistro {
  final SyncPendenciaTipo tipo;
  final String titulo;
  final String subtitulo;

  const SyncPendenciaRegistro({
    required this.tipo,
    required this.titulo,
    required this.subtitulo,
  });

  String get tipoLabel {
    switch (tipo) {
      case SyncPendenciaTipo.gravaTag:
        return "Grava TAG";
      case SyncPendenciaTipo.fabricacao:
        return "Fabricação";
      case SyncPendenciaTipo.fornecimento:
        return "Fornecimento";
    }
  }
}
