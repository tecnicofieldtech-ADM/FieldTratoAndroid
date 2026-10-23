/**
 * Carga controlada para homologação física no tablet.
 * Cliente TEST. Data da previsão = hoje (GET aberto filtra o dia).
 */
const fs = require("fs");
const path = require("path");
const http = require("http");
const { Client } = require("pg");
const { buildTemplateWorkbook } = require("../src/services/excelTemplate");
const { LAYOUT_VERSION } = require("../src/services/excelLayout");

const PORT = Number(process.env.PORT || 3111);
const BASE = `http://127.0.0.1:${PORT}`;
const DATABASE_URL =
  process.env.DATABASE_URL ||
  "postgres://fieldpec:fieldpec@127.0.0.1:5432/fieldpec_online";
const TODAY = new Date().toISOString().slice(0, 10);
const OUT = path.join(__dirname, "..", "..", "homologacao", "fisico");
const CLIENT = "TEST";
const FAZENDA = "FZ_FISICO_001";
const VAGAO = "VG_FISICO_001";

function replaceSheetRows(ws, rows) {
  const remove = Math.max(ws.rowCount - 1, 0);
  ws.spliceRows(2, remove, ...rows);
}

function fill(wb, { descricao, dietaNomeSuffix = "" }) {
  replaceSheetRows(wb.getWorksheet("CONFIGURACAO"), [
    ["VERSAO_LAYOUT", String(LAYOUT_VERSION)],
    ["CLIENTE_CODIGO", CLIENT],
    ["FAZENDA_CODIGO", FAZENDA],
    ["DESCRICAO", descricao],
    ["DATA_GERACAO", TODAY],
  ]);
  replaceSheetRows(wb.getWorksheet("FAZENDAS"), [
    [FAZENDA, "Fazenda Homologação Física"],
  ]);
  replaceSheetRows(wb.getWorksheet("USUARIOS"), [
    ["USR_OP_F01", "Operador Físico", "operador", "123456", "Operador", FAZENDA],
    ["USR_MOT_F01", "Motorista Físico", "motorista", "123456", "Motorista", FAZENDA],
  ]);
  replaceSheetRows(wb.getWorksheet("VAGOES"), [[VAGAO, "Vagão Homologação Física"]]);
  replaceSheetRows(wb.getWorksheet("BAIAS"), [
    ["BAIA_F01", "LOTE_F01", "Curral Norte Físico", "1", 1, FAZENDA, "EPC_F01"],
    ["BAIA_F02", "LOTE_F01", "Curral Centro Físico", "2", 2, FAZENDA, "EPC_F02"],
    ["BAIA_F03", "LOTE_F01", "Curral Sul Físico", "3", 3, FAZENDA, "EPC_F03"],
  ]);
  replaceSheetRows(wb.getWorksheet("DIETAS"), [
    ["DIETA_F01", "Dieta Crescimento Física" + dietaNomeSuffix, "Crescimento", 55.5, FAZENDA],
    ["DIETA_F02", "Dieta Terminação Física", "Terminacao", 48.0, FAZENDA],
  ]);
  replaceSheetRows(wb.getWorksheet("DIETA_ITENS"), [
    ["IT_F01", "DIETA_F01", "INS_MILHO", "Milho moído", 60, 1, 88, 60, "N"],
    ["IT_F02", "DIETA_F01", "INS_SOJA", "Farelo de soja", 40, 2, 46, 40, "S"],
    ["IT_F03", "DIETA_F02", "INS_MILHO", "Milho moído", 70, 1, 88, 70, "N"],
    ["IT_F04", "DIETA_F02", "INS_POLPA", "Polpa cítrica", 30, 2, 82, 30, "N"],
  ]);
  replaceSheetRows(wb.getWorksheet("PREVISAO_TRATO"), [
    ["FORN_F01", TODAY, "BAIA_F01", 1, 1200, 0, "DIETA_F01", FAZENDA],
    ["FORN_F02", TODAY, "BAIA_F02", 1, 1500, 0, "DIETA_F01", FAZENDA],
    ["FORN_F03", TODAY, "BAIA_F03", 1, 900, 0, "DIETA_F02", FAZENDA],
  ]);
  return wb;
}

function request(method, urlPath, { headers = {}, raw } = {}) {
  return new Promise((resolve, reject) => {
    const u = new URL(BASE + urlPath);
    const req = http.request(
      {
        hostname: u.hostname,
        port: u.port,
        path: u.pathname + u.search,
        method,
        headers,
      },
      (res) => {
        const chunks = [];
        res.on("data", (c) => chunks.push(c));
        res.on("end", () => {
          const buf = Buffer.concat(chunks);
          let json = null;
          try {
            json = JSON.parse(buf.toString("utf8"));
          } catch (_) {}
          resolve({ status: res.statusCode, buf, json });
        });
      },
    );
    req.on("error", reject);
    if (raw) req.write(raw);
    req.end();
  });
}

function multipart(fileBuf, filename) {
  const boundary = "----FisicoBoundary7MA4YWxk";
  const head =
    `--${boundary}\r\n` +
    `Content-Disposition: form-data; name="file"; filename="${filename}"\r\n` +
    `Content-Type: application/vnd.openxmlformats-officedocument.spreadsheetml.sheet\r\n\r\n`;
  const tail = `\r\n--${boundary}--\r\n`;
  const raw = Buffer.concat([Buffer.from(head), fileBuf, Buffer.from(tail)]);
  return {
    raw,
    headers: {
      "Content-Type": `multipart/form-data; boundary=${boundary}`,
      "Content-Length": String(raw.length),
      "X-Client-Code": CLIENT,
    },
  };
}

async function main() {
  fs.mkdirSync(OUT, { recursive: true });
  const wbA = await buildTemplateWorkbook();
  fill(wbA, { descricao: "Homologacao fisica tablet Carga A " + TODAY });
  const bufA = Buffer.from(await wbA.xlsx.writeBuffer());
  fs.writeFileSync(path.join(OUT, "FieldTrato_Fisico_CargaA.xlsx"), bufA);

  const wbB = await buildTemplateWorkbook();
  fill(wbB, {
    descricao: "Homologacao fisica tablet Carga B " + TODAY,
    dietaNomeSuffix: " B",
  });
  const bufB = Buffer.from(await wbB.xlsx.writeBuffer());
  fs.writeFileSync(path.join(OUT, "FieldTrato_Fisico_CargaB.xlsx"), bufB);

  const imp = await request("POST", "/planilha/importar", multipart(bufA, "FieldTrato_Fisico_CargaA.xlsx"));
  if (!imp.json || !imp.json.success) {
    throw new Error("Import A falhou: " + JSON.stringify(imp.json));
  }

  const teste = await request("GET", "/GetTeste", { headers: { "X-Client-Code": CLIENT } });
  const pg = new Client({ connectionString: DATABASE_URL });
  await pg.connect();
  const detail = {
    fazendas: (await pg.query(`SELECT idfazenda, fazenda FROM fazendas WHERE cliente_codigo=$1 AND idfazenda=$2`, [CLIENT, FAZENDA])).rows,
    usuarios: (await pg.query(`SELECT id, usuario, nome FROM usuarios WHERE cliente_codigo=$1 AND id LIKE 'USR_%F01'`, [CLIENT])).rows,
    vagoes: (await pg.query(`SELECT id, nome FROM vagoes WHERE cliente_codigo=$1 AND id=$2`, [CLIENT, VAGAO])).rows,
    baias: (await pg.query(`SELECT id_baia, nome_local FROM baias WHERE cliente_codigo=$1 AND id_baia LIKE 'BAIA_F%' ORDER BY id_baia`, [CLIENT])).rows,
    dietas: (await pg.query(`SELECT id, nome_dieta FROM dietas WHERE cliente_codigo=$1 AND id LIKE 'DIETA_F%' ORDER BY id`, [CLIENT])).rows,
    previsao: (await pg.query(`SELECT id_fornecimento, data, id_baia, previsto FROM previsao_trato WHERE cliente_codigo=$1 AND id_fornecimento LIKE 'FORN_F%' ORDER BY id_fornecimento`, [CLIENT])).rows,
  };
  await pg.end();

  const report = {
    today: TODAY,
    cliente: CLIENT,
    fazenda: FAZENDA,
    vagao: VAGAO,
    host_sugerido: "192.168.15.10",
    porta: PORT,
    backend: 3,
    login: { usuario: "operador ou motorista", senha: "123456" },
    carga_a: {
      arquivo: "FieldTrato_Fisico_CargaA.xlsx",
      importacao_id: imp.json.importacao_id,
      reused: imp.json.reused,
      totais: imp.json.totais,
    },
    carga_b_arquivo: "FieldTrato_Fisico_CargaB.xlsx",
    getteste: teste.json,
    postgres: detail,
  };
  fs.writeFileSync(path.join(OUT, "CARGA_FISICA.json"), JSON.stringify(report, null, 2));
  console.log(JSON.stringify(report, null, 2));
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
