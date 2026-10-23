/**
 * Homologação ponta a ponta do modo Planilha (API + Postgres).
 * Não altera produção: só gera XLSX, chama endpoints e consulta o banco.
 */
const fs = require("fs");
const path = require("path");
const http = require("http");
const ExcelJS = require("exceljs");
const { Client } = require("pg");
const { buildTemplateWorkbook } = require("../src/services/excelTemplate");
const { SHEETS, REQUIRED_SHEETS, LAYOUT_VERSION } = require("../src/services/excelLayout");

const PORT = Number(process.env.HOMOLOG_PORT || process.env.PORT || 3111);
const BASE = `http://127.0.0.1:${PORT}`;
const DATABASE_URL =
  process.env.DATABASE_URL ||
  "postgres://fieldpec:fieldpec@127.0.0.1:5432/fieldpec_online";
const TODAY = new Date().toISOString().slice(0, 10);
const OUT_DIR = path.join(__dirname, "..", "..", "homologacao");
const CLIENT_A = "TEST";
const CLIENT_B = "TESTE";
const FAZENDA = "FZ_TESTE_001";
const VAGAO = "VG_TESTE_001";

function log(title, data) {
  console.log("\n=== " + title + " ===");
  if (data !== undefined) console.log(typeof data === "string" ? data : JSON.stringify(data, null, 2));
}

function request(method, urlPath, { headers = {}, body, raw } = {}) {
  return new Promise((resolve, reject) => {
    const u = new URL(urlPath.startsWith("http") ? urlPath : BASE + urlPath);
    const opts = {
      hostname: u.hostname,
      port: u.port,
      path: u.pathname + u.search,
      method,
      headers: { ...headers },
    };
    const req = http.request(opts, (res) => {
      const chunks = [];
      res.on("data", (c) => chunks.push(c));
      res.on("end", () => {
        const buf = Buffer.concat(chunks);
        let json = null;
        try {
          json = JSON.parse(buf.toString("utf8"));
        } catch (_) {
          /* binary */
        }
        resolve({ status: res.statusCode, headers: res.headers, buf, json });
      });
    });
    req.on("error", reject);
    if (raw) req.write(raw);
    else if (body) req.write(typeof body === "string" ? body : JSON.stringify(body));
    req.end();
  });
}

function multipart(fileBuf, filename, extraHeaders = {}) {
  const boundary = "----HomologBoundary7MA4YWxkTrZu0gW";
  const head =
    `--${boundary}\r\n` +
    `Content-Disposition: form-data; name="file"; filename="${filename}"\r\n` +
    `Content-Type: application/vnd.openxmlformats-officedocument.spreadsheetml.sheet\r\n\r\n`;
  const tail = `\r\n--${boundary}--\r\n`;
  const raw = Buffer.concat([Buffer.from(head, "utf8"), fileBuf, Buffer.from(tail, "utf8")]);
  return {
    raw,
    headers: {
      "Content-Type": `multipart/form-data; boundary=${boundary}`,
      "Content-Length": String(raw.length),
      ...extraHeaders,
    },
  };
}

async function waitApi(timeoutMs = 25000) {
  const t0 = Date.now();
  while (Date.now() - t0 < timeoutMs) {
    try {
      const r = await request("GET", "/GetTeste");
      if (r.status === 200) return;
    } catch (_) {
      /* retry */
    }
    await new Promise((r) => setTimeout(r, 400));
  }
  throw new Error("API não respondeu em " + BASE);
}

function replaceSheetRows(ws, rows) {
  const remove = Math.max(ws.rowCount - 1, 0);
  ws.spliceRows(2, remove, ...rows);
}

async function fillHomologWorkbook(wb, { client, descricao }) {
  replaceSheetRows(wb.getWorksheet("CONFIGURACAO"), [
    ["VERSAO_LAYOUT", String(LAYOUT_VERSION)],
    ["CLIENTE_CODIGO", client],
    ["FAZENDA_CODIGO", FAZENDA],
    ["DESCRICAO", descricao],
    ["DATA_GERACAO", TODAY],
  ]);

  replaceSheetRows(wb.getWorksheet("FAZENDAS"), [
    [FAZENDA, "Fazenda Homologação Planilha"],
  ]);
  replaceSheetRows(wb.getWorksheet("USUARIOS"), [
    ["USR_OP_001", "Operador Homolog", "operador", "123456", "Operador", FAZENDA],
    ["USR_MOT_001", "Motorista Homolog", "motorista", "123456", "Motorista", FAZENDA],
  ]);
  replaceSheetRows(wb.getWorksheet("VAGOES"), [
    [VAGAO, "Vagão Homologação"],
  ]);
  replaceSheetRows(wb.getWorksheet("BAIAS"), [
    ["BAIA_001", "LOTE_001", "Curral Norte", "1", 1, FAZENDA, "EPC_BAIA_001"],
    ["BAIA_002", "LOTE_001", "Curral Centro", "2", 2, FAZENDA, "EPC_BAIA_002"],
    ["BAIA_003", "LOTE_001", "Curral Sul", "3", 3, FAZENDA, "EPC_BAIA_003"],
  ]);
  replaceSheetRows(wb.getWorksheet("DIETAS"), [
    ["DIETA_001", "Dieta Crescimento Homolog", "Crescimento", 55.5, FAZENDA],
    ["DIETA_002", "Dieta Terminação Homolog", "Terminacao", 48.0, FAZENDA],
  ]);
  replaceSheetRows(wb.getWorksheet("DIETA_ITENS"), [
    ["IT_001", "DIETA_001", "INS_MILHO", "Milho moído", 60, 1, 88, 60, "N"],
    ["IT_002", "DIETA_001", "INS_SOJA", "Farelo de soja", 40, 2, 46, 40, "S"],
    ["IT_003", "DIETA_002", "INS_MILHO", "Milho moído", 70, 1, 88, 70, "N"],
    ["IT_004", "DIETA_002", "INS_POLPA", "Polpa cítrica", 30, 2, 82, 30, "N"],
  ]);
  replaceSheetRows(wb.getWorksheet("PREVISAO_TRATO"), [
    ["FORN_001", TODAY, "BAIA_001", 1, 1200, 0, "DIETA_001", FAZENDA],
    ["FORN_002", TODAY, "BAIA_002", 1, 1500, 0, "DIETA_001", FAZENDA],
    ["FORN_003", TODAY, "BAIA_003", 1, 900, 0, "DIETA_002", FAZENDA],
  ]);
  return wb;
}

async function inspectTemplate(buf) {
  const wb = new ExcelJS.Workbook();
  await wb.xlsx.load(buf);
  const report = { versao_layout: LAYOUT_VERSION, abas: [] };
  for (const name of REQUIRED_SHEETS) {
    const ws = wb.getWorksheet(name);
    const spec = SHEETS[name];
    const headers = [];
    if (ws) ws.getRow(1).eachCell((c) => headers.push(String(c.value)));
    report.abas.push({
      aba: name,
      presente: !!ws,
      colunas: headers,
      obrigatorias: spec.required || (name === "CONFIGURACAO" ? ["CHAVE", "VALOR"] : []),
      opcionais: (spec.headers || []).filter(
        (h) => !(spec.required || []).includes(h),
      ),
      exemplos: spec.example ? spec.example.length : 0,
    });
  }
  return report;
}

async function pgCounts(client, codigo) {
  const tables = [
    ["fazendas", "idfazenda"],
    ["usuarios", "id"],
    ["vagoes", "id"],
    ["baias", "id_baia"],
    ["dietas", "id"],
    ["dietas_detalhes", "id"],
    ["previsao_trato", "id_fornecimento"],
    ["fabricacoes", "id"],
    ["fornecimentos", "id"],
  ];
  const out = {};
  for (const [t] of tables) {
    const r = await client.query(
      `SELECT COUNT(*)::int AS n FROM ${t} WHERE cliente_codigo = $1`,
      [codigo],
    );
    out[t] = r.rows[0].n;
  }
  return out;
}

async function main() {
  fs.mkdirSync(OUT_DIR, { recursive: true });
  const evidence = { base: BASE, today: TODAY, client_a: CLIENT_A, client_b: CLIENT_B };

  log("1. TEMPLATE", "baixando via exceljs (mesmo gerador do GET /planilha/template)");
  const tplWb = await buildTemplateWorkbook();
  const tplBuf = Buffer.from(await tplWb.xlsx.writeBuffer());
  fs.writeFileSync(path.join(OUT_DIR, "FieldTrato_Template.xlsx"), tplBuf);
  evidence.template = await inspectTemplate(tplBuf);
  evidence.template_vs_get = {
    fazenda: { excel: "idfazenda,fazenda", get: "IDFAZENDA,FAZENDA", sqlite: "ID,NOME", ok: true },
    usuarios: {
      excel: "id,nome,usuario,senha,cargo,idfazenda",
      get: "ID,NOME,USUARIO,SENHA,CARGO (SEM idfazenda)",
      sqlite: "ID,NOME,LOGIN,SENHA,CARGO,ID_FAZENDA — ID_FAZENDA cai do CONFIG se GET não trouxer",
      ok: true,
      nota: "GET /usuarios/get não devolve idfazenda; BootstrapSync usa ID_FAZENDA da Config",
    },
    vagao: { excel: "id,nome", get: "ID,NOME", sqlite: "ID,NOME", ok: true },
    baias: {
      excel: "idbaia,idlote,nomelocal,linha,ordemtrato,idfazenda,rfid",
      get: "ID_BAIA,ID_LOTE,NOME_LOCAL,LINHA,ORDEM_TRATO,ID_FAZENDA,RFID",
      sqlite: "ID,ID_LOTE,NOME_LOCAL,LINHA,ORDER_TRATO,ID_FAZENDA,RFID",
      ok: true,
    },
    dietas: {
      excel: "iddieta,nomedieta,tipodieta,msdieta,idfazenda",
      get: "ID,NOME_DIETA,TIPO_DIETA,MS_DIETA,ID_FAZENDA",
      sqlite: "ID,NOME,TIPO,MS,ID_FAZENDA",
      ok: true,
    },
    dieta_itens: {
      excel: "id,iddieta,idinsumo,ingrediente,mnperc,ordem,msinsumo,msinclusao,prepesagem",
      get: "ID,ID_DIETA,ID_INSUMO,INGREDIENTE,MN_PERC,ORDEM,MS_INSUMO,MS_INCLUSAO,PRE_PESAGEM",
      sqlite: "ID composto dieta::insumo::ordem, PRE_PESADO se S",
      ok: true,
    },
    previsao: {
      excel: "id_fornecimento,data,id_baia,trato,previsto_kg,realizado_kg,id_racao,id_fazenda",
      get: "ID_FORNECIMENTO,DATA,ID (alias da baia),TRATO,ID_DIETA,PREVISTO,PREVISTO_ORIGINAL,REALIZADO",
      sqlite: "ID_FORNECIMENTO,DATA,ID_BAIA (via chave ID),TRATO,PREVISTO_KG,ID_RACAO via ID_DIETA",
      ok: true,
      nota: "GET aberto /previsao_trato/get sem data filtra HOJE. Carga de homologação usa data de hoje.",
    },
  };

  log("2. CARGA HOMOLOGAÇÃO A");
  const wbA = await buildTemplateWorkbook();
  await fillHomologWorkbook(wbA, { client: CLIENT_A, descricao: "Homolog A" });
  const bufA = Buffer.from(await wbA.xlsx.writeBuffer());
  const pathA = path.join(OUT_DIR, "FieldTrato_Homolog_TEST.xlsx");
  fs.writeFileSync(pathA, bufA);

  log("3. AGUARDAR API", BASE);
  await waitApi();

  const tplHttp = await request("GET", "/planilha/template");
  evidence.template_http = {
    status: tplHttp.status,
    bytes: tplHttp.buf.length,
    content_type: tplHttp.headers["content-type"],
  };
  if (tplHttp.status === 200) {
    fs.writeFileSync(path.join(OUT_DIR, "FieldTrato_Template_HTTP.xlsx"), tplHttp.buf);
  }

  const pg = new Client({ connectionString: DATABASE_URL });
  await pg.connect();

  log("3. IMPORTAR A");
  const mp = multipart(bufA, "FieldTrato_Homolog_TEST.xlsx", { "X-Client-Code": CLIENT_A });
  const imp1 = await request("POST", "/planilha/importar", mp);
  evidence.import1 = { status: imp1.status, body: imp1.json };
  if (!imp1.json || !imp1.json.success) {
    throw new Error("Import A falhou: " + JSON.stringify(imp1.json));
  }
  const importacaoId = imp1.json.importacao_id;
  evidence.importacao_id = importacaoId;
  evidence.totais_import = imp1.json.totais;
  evidence.reused_1 = imp1.json.reused;

  const hashRow = await pg.query(
    `SELECT id, arquivo_hash, cliente_codigo, fazenda_codigo, status, totais
     FROM planilha_importacoes WHERE id = $1`,
    [importacaoId],
  );
  evidence.pg_importacao = hashRow.rows[0];
  evidence.pg_counts_a_after_import = await pgCounts(pg, CLIENT_A);
  log("Postgres A após import", evidence.pg_counts_a_after_import);

  log("4. IDEMPOTÊNCIA mesmo arquivo");
  const imp2 = await request("POST", "/planilha/importar", mp);
  evidence.import2_same_file = { status: imp2.status, body: imp2.json };
  const countImp = await pg.query(
    `SELECT COUNT(*)::int AS n FROM planilha_importacoes WHERE cliente_codigo = $1`,
    [CLIENT_A],
  );
  evidence.importacoes_count_after_same = countImp.rows[0].n;
  evidence.pg_counts_a_after_reimport = await pgCounts(pg, CLIENT_A);

  log("4b. ARQUIVO ALTERADO (nome dieta)");
  const wbA2 = await buildTemplateWorkbook();
  await fillHomologWorkbook(wbA2, { client: CLIENT_A, descricao: "Homolog A v2" });
  wbA2.getWorksheet("DIETAS").getCell("B2").value = "Dieta Crescimento Homolog v2";
  const bufA2 = Buffer.from(await wbA2.xlsx.writeBuffer());
  fs.writeFileSync(path.join(OUT_DIR, "FieldTrato_Homolog_TEST_v2.xlsx"), bufA2);
  const mp2 = multipart(bufA2, "FieldTrato_Homolog_TEST_v2.xlsx", { "X-Client-Code": CLIENT_A });
  const imp3 = await request("POST", "/planilha/importar", mp2);
  evidence.import3_modified = { status: imp3.status, body: imp3.json };
  const countImp2 = await pg.query(
    `SELECT COUNT(*)::int AS n FROM planilha_importacoes WHERE cliente_codigo = $1`,
    [CLIENT_A],
  );
  evidence.importacoes_count_after_modified = countImp2.rows[0].n;
  const dietaNome = await pg.query(
    `SELECT nome_dieta FROM dietas WHERE cliente_codigo = $1 AND id = 'DIETA_001'`,
    [CLIENT_A],
  );
  evidence.dieta_001_nome_apos_v2 = dietaNome.rows[0] && dietaNome.rows[0].nome_dieta;

  log("6. GETS contrato tablet (X-Client-Code=TEST)");
  const h = { "X-Client-Code": CLIENT_A };
  const gets = {};
  for (const p of [
    "/GetTeste",
    "/fazenda/get",
    "/usuarios/get",
    "/vagao/get",
    "/baias/get",
    "/dietas/get",
    "/dietas_detalhes/get",
    "/previsao_trato/get",
  ]) {
    const r = await request("GET", p, { headers: h });
    const n = Array.isArray(r.json) ? r.json.length : r.json && r.json.importacao_id ? 1 : null;
    gets[p] = {
      status: r.status,
      count: Array.isArray(r.json) ? r.json.length : n,
      importacao_id: r.json && r.json.importacao_id,
      cliente: r.json && r.json.cliente_codigo,
      sample_keys: Array.isArray(r.json) && r.json[0] ? Object.keys(r.json[0]) : Object.keys(r.json || {}),
    };
  }
  evidence.gets_a = gets;
  log("GETs A", gets);

  log("11. POST fabricação + fornecimento (simula outbox tablet)");
  const fabBody = {
    handoff_id: "handoff-homolog-001",
    id_local: "fab-local-001",
    id_fazenda: FAZENDA,
    ID_PROPRIEDADE: FAZENDA,
    id_dieta: "DIETA_001",
    data: TODAY.split("-").reverse().join("/"),
    id_usuario: "USR_MOT_001",
    id_operador: "USR_OP_001",
    id_vagao: VAGAO,
    qtde_prevista: "2700",
    qtde_realizada: "2680",
    ms_prevista: "55,50",
    ms_realizada: "55,20",
    hora_inicio: "08:00:00",
    hora_fim: "08:40:00",
    importacao_id: importacaoId,
    itens: [
      {
        id_local: "item-1",
        id_insumo: "INS_MILHO",
        qtde_prevista: "1620,000",
        qtd_realizada: "1610,000",
        ms_insumo: "88,000",
        hora_inicio: "08:00:00",
        hora_fim: "08:20:00",
      },
      {
        id_local: "item-2",
        id_insumo: "INS_SOJA",
        qtde_prevista: "1080,000",
        qtd_realizada: "1070,000",
        ms_insumo: "46,000",
        hora_inicio: "08:20:00",
        hora_fim: "08:40:00",
      },
    ],
  };
  const postFab1 = await request("POST", "/Post/Fabricacao", {
    headers: { ...h, "Content-Type": "application/json" },
    body: fabBody,
  });
  const postFab2 = await request("POST", "/Post/Fabricacao", {
    headers: { ...h, "Content-Type": "application/json" },
    body: fabBody,
  });
  evidence.post_fabricacao = {
    first: { status: postFab1.status, body: postFab1.json },
    retry: { status: postFab2.status, body: postFab2.json },
  };

  const fornBody = {
    id: "FORN_001",
    id_cadastro: "cad-forn-homolog-001",
    id_fornecimento: "FORN_001",
    id_fabricacao: "fab-local-001",
    id_baia: "BAIA_001",
    id_racao: "DIETA_001",
    trato: "1",
    data: TODAY.split("-").reverse().join("/"),
    realizado: "1180,000",
    ms_dieta_realizada: "55,20",
    hora_inicio: "09:00:00",
    hora_fim: "09:12:00",
    peso_inicio: "2680,000",
    peso_fim: "1500,000",
    importacao_id: importacaoId,
    id_usuario_lancamento: "USR_MOT_001",
    id_tratador: "USR_MOT_001",
    id_dieta_realizada: "DIETA_001",
  };
  const postF1 = await request("POST", "/Post/Fornecimento", {
    headers: { ...h, "Content-Type": "application/json" },
    body: fornBody,
  });
  const postF2 = await request("POST", "/Post/Fornecimento", {
    headers: { ...h, "Content-Type": "application/json" },
    body: fornBody,
  });
  evidence.post_fornecimento = {
    first: { status: postF1.status, body: postF1.json },
    retry: { status: postF2.status, body: postF2.json },
  };

  const fabCount = await pg.query(
    `SELECT COUNT(*)::int AS n FROM fabricacoes WHERE cliente_codigo = $1 AND handoff_id = $2`,
    [CLIENT_A, "handoff-homolog-001"],
  );
  const fornCount2 = await pg.query(
    `SELECT COUNT(*)::int AS n, MIN(importacao_id::text) AS importacao_id
     FROM fornecimentos WHERE cliente_codigo = $1 AND id_cadastro = $2`,
    [CLIENT_A, "cad-forn-homolog-001"],
  );
  const fabRow = await pg.query(
    `SELECT id, id_local, importacao_id, qtde_realizada FROM fabricacoes
     WHERE cliente_codigo = $1 AND handoff_id = $2`,
    [CLIENT_A, "handoff-homolog-001"],
  );
  evidence.pg_ops = {
    fabricacoes_mesmo_handoff: fabCount.rows[0].n,
    fornecimentos_mesmo_cadastro: fornCount2.rows[0].n,
    fab_importacao_id: fabRow.rows[0] && fabRow.rows[0].importacao_id,
    forn_importacao_id: fornCount2.rows[0].importacao_id,
  };

  await request("POST", "/Post/FabricacaoAudit", {
    headers: { ...h, "Content-Type": "application/json" },
    body: { device_id: VAGAO, origem: "homolog", total: 1 },
  });

  log("14. EXPORTAR");
  const exp = await request("GET", "/planilha/exportar/" + importacaoId, { headers: h });
  evidence.export = { status: exp.status, bytes: exp.buf.length, content_type: exp.headers["content-type"] };
  const expPath = path.join(OUT_DIR, `FieldTrato_Resultado_${importacaoId}.xlsx`);
  if (exp.status === 200) {
    fs.writeFileSync(expPath, exp.buf);
    const expWb = new ExcelJS.Workbook();
    await expWb.xlsx.load(exp.buf);
    evidence.export_abas = expWb.worksheets.map((w) => ({
      nome: w.name,
      linhas: w.rowCount,
      colunas: (() => {
        const hds = [];
        w.getRow(1).eachCell((c) => hds.push(String(c.value)));
        return hds;
      })(),
    }));
  }

  log("16. MULTI-TENANT B");
  const wbB = await buildTemplateWorkbook();
  await fillHomologWorkbook(wbB, { client: CLIENT_B, descricao: "Homolog B isolado" });
  wbB.getWorksheet("FAZENDAS").getCell("B2").value = "Fazenda Cliente B";
  const bufB = Buffer.from(await wbB.xlsx.writeBuffer());
  fs.writeFileSync(path.join(OUT_DIR, "FieldTrato_Homolog_TESTE.xlsx"), bufB);
  const mpB = multipart(bufB, "FieldTrato_Homolog_TESTE.xlsx", { "X-Client-Code": CLIENT_B });
  const impB = await request("POST", "/planilha/importar", mpB);
  evidence.import_b = { status: impB.status, body: impB.json };
  const listA = await request("GET", "/planilha/importacoes", { headers: { "X-Client-Code": CLIENT_A } });
  const listB = await request("GET", "/planilha/importacoes", { headers: { "X-Client-Code": CLIENT_B } });
  const fazA = await request("GET", "/fazenda/get", { headers: { "X-Client-Code": CLIENT_A } });
  const fazB = await request("GET", "/fazenda/get", { headers: { "X-Client-Code": CLIENT_B } });
  evidence.multi_tenant = {
    importacoes_a: (listA.json && listA.json.importacoes || []).map((r) => r.cliente_codigo),
    importacoes_b: (listB.json && listB.json.importacoes || []).map((r) => r.cliente_codigo),
    fazendas_a: fazA.json,
    fazendas_b: fazB.json,
    export_a_id_com_header_b: (await request("GET", "/planilha/exportar/" + importacaoId, {
      headers: { "X-Client-Code": CLIENT_B },
    })).status,
  };
  evidence.pg_counts_b = await pgCounts(pg, CLIENT_B);

  await pg.end();
  const reportPath = path.join(OUT_DIR, "RELATORIO_HOMOLOGACAO.json");
  fs.writeFileSync(reportPath, JSON.stringify(evidence, null, 2));
  log("EVIDÊNCIA GRAVADA", reportPath);
  console.log("\nimportacao_id A:", importacaoId);
  console.log("reused mesmo arquivo:", evidence.import2_same_file.body && evidence.import2_same_file.body.reused);
  console.log("nova importação após célula alterada:", evidence.import3_modified.body && evidence.import3_modified.body.importacao_id);
  console.log("fab duplicate retry:", evidence.post_fabricacao.retry.body);
  console.log("forn duplicate retry:", evidence.post_fornecimento.retry.body);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
