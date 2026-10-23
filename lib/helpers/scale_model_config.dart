import "../features/fornecimento/domain/fornecimento_models.dart";
import "scale_comm.dart";

/// Mapeamento único MODELO_BALANCA (config) → [ScaleModel].
ScaleModel scaleModelFromConfigInt(int v) {
  switch (v) {
    case 0:
      return ScaleModel.topcom;
    case 1:
      return ScaleModel.dg500;
    case 2:
      return ScaleModel.alfa;
    case 3:
      return ScaleModel.hook;
    case 4:
      return ScaleModel.ptm;
    default:
      return ScaleModel.raw;
  }
}

/// Mapeamento único MODELO_BALANCA (config) → [ModeloBalanca] (legado TCP).
ModeloBalanca modeloBalancaFromConfigInt(int v) {
  switch (v) {
    case 1:
      return ModeloBalanca.dinamica;
    case 2:
      return ModeloBalanca.alfa;
    case 3:
      return ModeloBalanca.hook;
    case 4:
      return ModeloBalanca.ptm;
    case 0:
      return ModeloBalanca.topcon;
    default:
      return ModeloBalanca.outro;
  }
}

ModeloBalanca modeloBalancaFromScaleModel(ScaleModel model) {
  switch (model) {
    case ScaleModel.dg500:
      return ModeloBalanca.dinamica;
    case ScaleModel.alfa:
      return ModeloBalanca.alfa;
    case ScaleModel.hook:
      return ModeloBalanca.hook;
    case ScaleModel.ptm:
      return ModeloBalanca.ptm;
    case ScaleModel.topcom:
      return ModeloBalanca.topcon;
    case ScaleModel.raw:
      return ModeloBalanca.outro;
  }
}
