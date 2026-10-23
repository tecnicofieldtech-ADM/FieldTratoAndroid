const LAYOUT_VERSION = 1;
const TEMPLATE_FILENAME = "FieldTrato_Template.xlsx";

const REQUIRED_SHEETS = [
  "CONFIGURACAO",
  "FAZENDAS",
  "USUARIOS",
  "VAGOES",
  "BAIAS",
  "DIETAS",
  "DIETA_ITENS",
  "PREVISAO_TRATO",
];

const SHEETS = {
  CONFIGURACAO: {
    headers: ["CHAVE", "VALOR"],
    example: [
      ["VERSAO_LAYOUT", String(LAYOUT_VERSION)],
      ["CLIENTE_CODIGO", "CLIENTE01"],
      ["FAZENDA_CODIGO", "F001"],
      ["DESCRICAO", "Fazenda Teste"],
      ["DATA_GERACAO", "2026-09-05"],
    ],
  },
  FAZENDAS: {
    headers: ["idfazenda", "fazenda"],
    required: ["idfazenda", "fazenda"],
    example: [["F001", "Fazenda Modelo"]],
  },
  USUARIOS: {
    headers: ["id", "nome", "usuario", "senha", "cargo", "idfazenda"],
    required: ["id", "nome", "usuario", "senha", "idfazenda"],
    example: [["U001", "Operador 1", "operador1", "123456", "Operador", "F001"]],
  },
  VAGOES: {
    headers: ["id", "nome"],
    required: ["id", "nome"],
    example: [["V001", "Vagao 01"]],
  },
  BAIAS: {
    headers: [
      "idbaia",
      "idlote",
      "nomelocal",
      "linha",
      "ordemtrato",
      "idfazenda",
      "rfid",
    ],
    required: ["idbaia", "idlote", "nomelocal", "linha", "ordemtrato", "idfazenda"],
    example: [["B001", "L001", "Curral 01", "L1", "1", "F001", "EPC001"]],
  },
  DIETAS: {
    headers: ["iddieta", "nomedieta", "tipodieta", "msdieta", "idfazenda"],
    required: ["iddieta", "nomedieta", "idfazenda"],
    example: [["D001", "Dieta Crescimento", "Crescimento", "35.5", "F001"]],
  },
  DIETA_ITENS: {
    headers: [
      "id",
      "iddieta",
      "idinsumo",
      "ingrediente",
      "mnperc",
      "ordem",
      "msinsumo",
      "msinclusao",
      "prepesagem",
    ],
    required: ["iddieta", "idinsumo", "ingrediente", "mnperc", "ordem"],
    example: [
      ["DD001", "D001", "I001", "Milho", "60", "1", "88", "60", "N"],
      ["DD002", "D001", "I002", "Farelo de Soja", "40", "2", "46", "40", "S"],
    ],
  },
  PREVISAO_TRATO: {
    headers: [
      "id_fornecimento",
      "data",
      "id_baia",
      "trato",
      "previsto_kg",
      "realizado_kg",
      "id_racao",
      "id_fazenda",
    ],
    required: [
      "id_fornecimento",
      "data",
      "id_baia",
      "trato",
      "previsto_kg",
      "id_racao",
    ],
    example: [
      ["FORN001", "2026-09-05", "B001", "1", "2500", "0", "D001", "F001"],
    ],
  },
};

function normalizeHeader(v) {
  return String(v ?? "")
    .trim()
    .toLowerCase()
    .replace(/\s+/g, "_");
}

function cellStr(v) {
  if (v == null) return "";
  if (v instanceof Date) {
    const y = v.getFullYear();
    const m = String(v.getMonth() + 1).padStart(2, "0");
    const d = String(v.getDate()).padStart(2, "0");
    return `${y}-${m}-${d}`;
  }
  if (typeof v === "object" && v.text) return String(v.text).trim();
  if (typeof v === "object" && v.result != null) return String(v.result).trim();
  return String(v).trim();
}

module.exports = {
  LAYOUT_VERSION,
  TEMPLATE_FILENAME,
  REQUIRED_SHEETS,
  SHEETS,
  normalizeHeader,
  cellStr,
};
