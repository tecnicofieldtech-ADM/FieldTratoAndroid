const crypto = require("crypto");
const ExcelJS = require("exceljs");
const { query, withTransaction } = require("../db");
const master = require("./master");
const { toNum, parseDate } = require("../util/numbers");

function isNumericLike(raw) {
  const t = String(raw ?? "").trim();
  if (!t) return false;
  const n = toNum(t);
  if (!Number.isFinite(n)) return false;
  if (n === 0) return /^[+-]?0+([.,]0+)?$/.test(t);
  return true;
}
const {
  LAYOUT_VERSION,
  REQUIRED_SHEETS,
  SHEETS,
  normalizeHeader,
  cellStr,
} = require("./excelLayout");

function err(aba, linha, campo, mensagem) {
  return { aba, linha, campo, mensagem };
}

function isXlsxName(name) {
  return /\.xlsx$/i.test(String(name || ""));
}

async function workbookFromBuffer(buffer) {
  const wb = new ExcelJS.Workbook();
  await wb.xlsx.load(buffer);
  return wb;
}

function sheetByName(wb, name) {
  return (
    wb.getWorksheet(name) ||
    wb.worksheets.find(
      (w) => String(w.name || "").trim().toUpperCase() === name.toUpperCase(),
    )
  );
}

function readHeaderMap(ws) {
  const row = ws.getRow(1);
  const map = {};
  const headers = [];
  row.eachCell({ includeEmpty: false }, (cell, col) => {
    const h = normalizeHeader(cellStr(cell.value));
    if (!h) return;
    map[h] = col;
    headers.push(h);
  });
  return { map, headers };
}

function rowToObject(ws, rowNumber, headerMap) {
  const row = ws.getRow(rowNumber);
  const obj = {};
  let empty = true;
  for (const [key, col] of Object.entries(headerMap)) {
    const v = cellStr(row.getCell(col).value);
    obj[key] = v;
    if (v) empty = false;
  }
  return { obj, empty };
}

function parseConfigSheet(ws) {
  const cfg = {};
  if (!ws) return cfg;
  const { map } = readHeaderMap(ws);
  const chaveCol = map.chave || 1;
  const valorCol = map.valor || 2;
  ws.eachRow({ includeEmpty: false }, (row, n) => {
    if (n === 1) return;
    const k = normalizeHeader(cellStr(row.getCell(chaveCol).value)).toUpperCase();
    const v = cellStr(row.getCell(valorCol).value);
    if (k) cfg[k] = v;
  });
  return cfg;
}

function readTableSheet(wb, name) {
  const ws = sheetByName(wb, name);
  const spec = SHEETS[name];
  const result = {
    name,
    missingSheet: !ws,
    missingHeaders: [],
    rows: [],
  };
  if (!ws) return result;

  const { map, headers } = readHeaderMap(ws);
  for (const h of spec.headers) {
    if (!map[normalizeHeader(h)]) result.missingHeaders.push(h);
  }

  const last = ws.rowCount || 1;
  for (let n = 2; n <= last; n += 1) {
    const { obj, empty } = rowToObject(ws, n, map);
    if (empty) continue;
    result.rows.push({ linha: n, ...obj });
  }
  return result;
}

function validateParsed(parsed) {
  const erros = [];
  const cfg = parsed.config || {};

  for (const name of REQUIRED_SHEETS) {
    const sheet = parsed.sheets[name];
    if (!sheet || sheet.missingSheet) {
      erros.push(err(name, 0, "", `Aba obrigatória ausente: ${name}.`));
    }
  }
  if (erros.some((e) => e.mensagem.includes("ausente"))) {
    return { erros, config: cfg, tables: {} };
  }

  const versao = Number(cfg.VERSAO_LAYOUT);
  if (!Number.isFinite(versao) || versao !== LAYOUT_VERSION) {
    erros.push(
      err(
        "CONFIGURACAO",
        0,
        "VERSAO_LAYOUT",
        `Versão de template incompatível. Esperado ${LAYOUT_VERSION}, recebido '${cfg.VERSAO_LAYOUT || ""}'.`,
      ),
    );
  }

  const cliente = String(cfg.CLIENTE_CODIGO || "").trim().toUpperCase();
  if (!cliente) {
    erros.push(
      err("CONFIGURACAO", 0, "CLIENTE_CODIGO", "CLIENTE_CODIGO é obrigatório."),
    );
  }

  for (const name of REQUIRED_SHEETS) {
    if (name === "CONFIGURACAO") continue;
    const sheet = parsed.sheets[name];
    for (const h of sheet.missingHeaders || []) {
      erros.push(err(name, 1, h, `Coluna obrigatória ausente: ${h}.`));
    }
  }

  const fazendas = parsed.sheets.FAZENDAS.rows;
  const usuarios = parsed.sheets.USUARIOS.rows;
  const vagoes = parsed.sheets.VAGOES.rows;
  const baias = parsed.sheets.BAIAS.rows;
  const dietas = parsed.sheets.DIETAS.rows;
  const itens = parsed.sheets.DIETA_ITENS.rows;
  const previsao = parsed.sheets.PREVISAO_TRATO.rows;

  const fazIds = new Set();
  for (const r of fazendas) {
    const id = r.idfazenda;
    if (!id) {
      erros.push(err("FAZENDAS", r.linha, "idfazenda", "Célula obrigatória vazia."));
      continue;
    }
    if (fazIds.has(id.toUpperCase())) {
      erros.push(err("FAZENDAS", r.linha, "idfazenda", `ID duplicado: ${id}.`));
    }
    fazIds.add(id.toUpperCase());
    if (!r.fazenda) {
      erros.push(err("FAZENDAS", r.linha, "fazenda", "Célula obrigatória vazia."));
    }
  }

  const fazendaCodigo = String(cfg.FAZENDA_CODIGO || "").trim();
  if (fazendaCodigo && fazIds.size && !fazIds.has(fazendaCodigo.toUpperCase())) {
    erros.push(
      err(
        "CONFIGURACAO",
        0,
        "FAZENDA_CODIGO",
        `Fazenda ${fazendaCodigo} não encontrada na aba FAZENDAS.`,
      ),
    );
  }

  const userIds = new Set();
  for (const r of usuarios) {
    if (!r.id) erros.push(err("USUARIOS", r.linha, "id", "Célula obrigatória vazia."));
    else if (userIds.has(r.id.toUpperCase())) {
      erros.push(err("USUARIOS", r.linha, "id", `ID duplicado: ${r.id}.`));
    } else userIds.add(r.id.toUpperCase());
    if (!r.nome) erros.push(err("USUARIOS", r.linha, "nome", "Célula obrigatória vazia."));
    if (!r.usuario) {
      erros.push(err("USUARIOS", r.linha, "usuario", "Célula obrigatória vazia."));
    }
    if (!r.senha) erros.push(err("USUARIOS", r.linha, "senha", "Célula obrigatória vazia."));
    if (r.idfazenda && fazIds.size && !fazIds.has(r.idfazenda.toUpperCase())) {
      erros.push(
        err("USUARIOS", r.linha, "idfazenda", `Fazenda ${r.idfazenda} não encontrada.`),
      );
    }
  }

  const vagIds = new Set();
  for (const r of vagoes) {
    if (!r.id) erros.push(err("VAGOES", r.linha, "id", "Célula obrigatória vazia."));
    else if (vagIds.has(r.id.toUpperCase())) {
      erros.push(err("VAGOES", r.linha, "id", `ID duplicado: ${r.id}.`));
    } else vagIds.add(r.id.toUpperCase());
    if (!r.nome) erros.push(err("VAGOES", r.linha, "nome", "Célula obrigatória vazia."));
  }

  const baiaIds = new Set();
  for (const r of baias) {
    if (!r.idbaia) {
      erros.push(err("BAIAS", r.linha, "idbaia", "Célula obrigatória vazia."));
    } else if (baiaIds.has(r.idbaia.toUpperCase())) {
      erros.push(err("BAIAS", r.linha, "idbaia", `Baia duplicada: ${r.idbaia}.`));
    } else baiaIds.add(r.idbaia.toUpperCase());
    for (const campo of ["idlote", "nomelocal", "linha", "idfazenda"]) {
      if (!r[campo]) erros.push(err("BAIAS", r.linha, campo, "Célula obrigatória vazia."));
    }
    const ordemRaw = r.ordemtrato;
    if (ordemRaw !== "" && !isNumericLike(ordemRaw)) {
      erros.push(err("BAIAS", r.linha, "ordemtrato", "Valor numérico inválido."));
    }
    if (r.idfazenda && fazIds.size && !fazIds.has(r.idfazenda.toUpperCase())) {
      erros.push(
        err("BAIAS", r.linha, "idfazenda", `Fazenda ${r.idfazenda} não encontrada.`),
      );
    }
  }

  const dietaIds = new Set();
  for (const r of dietas) {
    if (!r.iddieta) {
      erros.push(err("DIETAS", r.linha, "iddieta", "Célula obrigatória vazia."));
    } else if (dietaIds.has(r.iddieta.toUpperCase())) {
      erros.push(err("DIETAS", r.linha, "iddieta", `ID duplicado: ${r.iddieta}.`));
    } else dietaIds.add(r.iddieta.toUpperCase());
    if (!r.nomedieta) {
      erros.push(err("DIETAS", r.linha, "nomedieta", "Célula obrigatória vazia."));
    }
    if (r.msdieta && !isNumericLike(r.msdieta)) {
      erros.push(err("DIETAS", r.linha, "msdieta", "Valor numérico inválido."));
    }
    if (r.idfazenda && fazIds.size && !fazIds.has(r.idfazenda.toUpperCase())) {
      erros.push(
        err("DIETAS", r.linha, "idfazenda", `Fazenda ${r.idfazenda} não encontrada.`),
      );
    }
  }

  const itemKeys = new Set();
  for (const r of itens) {
    if (!r.iddieta) {
      erros.push(err("DIETA_ITENS", r.linha, "iddieta", "Célula obrigatória vazia."));
    } else if (dietaIds.size && !dietaIds.has(r.iddieta.toUpperCase())) {
      erros.push(
        err(
          "DIETA_ITENS",
          r.linha,
          "iddieta",
          `Dieta ${r.iddieta} não encontrada.`,
        ),
      );
    }
    if (!r.idinsumo) {
      erros.push(err("DIETA_ITENS", r.linha, "idinsumo", "Célula obrigatória vazia."));
    }
    if (!r.ingrediente) {
      erros.push(err("DIETA_ITENS", r.linha, "ingrediente", "Célula obrigatória vazia."));
    }
    if (r.mnperc === "" || !isNumericLike(r.mnperc)) {
      erros.push(err("DIETA_ITENS", r.linha, "mnperc", "Valor numérico inválido."));
    }
    if (r.ordem === "" || !isNumericLike(r.ordem)) {
      erros.push(err("DIETA_ITENS", r.linha, "ordem", "Valor numérico inválido."));
    }
    const key = `${(r.iddieta || "").toUpperCase()}::${(r.idinsumo || "").toUpperCase()}::${r.ordem}`;
    if (itemKeys.has(key)) {
      erros.push(err("DIETA_ITENS", r.linha, "id", `Item duplicado: ${key}.`));
    } else itemKeys.add(key);
  }

  const prevKeys = new Set();
  for (const r of previsao) {
    if (!r.id_fornecimento) {
      erros.push(
        err("PREVISAO_TRATO", r.linha, "id_fornecimento", "Célula obrigatória vazia."),
      );
    }
    if (!parseDate(r.data)) {
      erros.push(
        err(
          "PREVISAO_TRATO",
          r.linha,
          "data",
          "Data inválida. Use YYYY-MM-DD ou DD/MM/YYYY.",
        ),
      );
    }
    if (!r.id_baia) {
      erros.push(err("PREVISAO_TRATO", r.linha, "id_baia", "Célula obrigatória vazia."));
    } else if (baiaIds.size && !baiaIds.has(r.id_baia.toUpperCase())) {
      erros.push(
        err(
          "PREVISAO_TRATO",
          r.linha,
          "id_baia",
          `Baia ${r.id_baia} não encontrada.`,
        ),
      );
    }
    if (!isNumericLike(r.trato) || Number(r.trato) <= 0) {
      erros.push(err("PREVISAO_TRATO", r.linha, "trato", "Trato deve ser inteiro > 0."));
    }
    if (r.previsto_kg === "" || !isNumericLike(r.previsto_kg)) {
      erros.push(
        err("PREVISAO_TRATO", r.linha, "previsto_kg", "Valor numérico inválido."),
      );
    }
    if (!r.id_racao) {
      erros.push(err("PREVISAO_TRATO", r.linha, "id_racao", "Célula obrigatória vazia."));
    } else if (dietaIds.size && !dietaIds.has(r.id_racao.toUpperCase())) {
      erros.push(
        err(
          "PREVISAO_TRATO",
          r.linha,
          "id_racao",
          `Dieta ${r.id_racao} não encontrada.`,
        ),
      );
    }
    const pk = `${r.id_fornecimento}|${parseDate(r.data) || r.data}|${r.id_baia}|${r.trato}`;
    if (prevKeys.has(pk.toUpperCase())) {
      erros.push(
        err("PREVISAO_TRATO", r.linha, "id_fornecimento", `Previsão duplicada: ${pk}.`),
      );
    } else prevKeys.add(pk.toUpperCase());
  }

  return {
    erros,
    config: {
      ...cfg,
      CLIENTE_CODIGO: cliente,
      FAZENDA_CODIGO: fazendaCodigo,
    },
    tables: { fazendas, usuarios, vagoes, baias, dietas, itens, previsao },
  };
}

async function parseWorkbookBuffer(buffer) {
  const wb = await workbookFromBuffer(buffer);
  const sheets = {};
  for (const name of REQUIRED_SHEETS) {
    if (name === "CONFIGURACAO") continue;
    sheets[name] = readTableSheet(wb, name);
  }
  sheets.CONFIGURACAO = {
    missingSheet: !sheetByName(wb, "CONFIGURACAO"),
    missingHeaders: [],
    rows: [],
  };
  const config = parseConfigSheet(sheetByName(wb, "CONFIGURACAO"));
  return { sheets, config };
}

async function validateBuffer(buffer, { filename } = {}) {
  if (filename && !isXlsxName(filename)) {
    return {
      success: false,
      erros: [err("", 0, "", "Arquivo deve ser .xlsx.")],
    };
  }
  const parsed = await parseWorkbookBuffer(buffer);
  const { erros, config, tables } = validateParsed(parsed);
  return { success: erros.length === 0, erros, config, tables };
}

function fileHash(buffer) {
  return crypto.createHash("sha256").update(buffer).digest("hex");
}

async function getActiveImportacaoId(clienteCodigo) {
  const cc = String(clienteCodigo || "").trim().toUpperCase();
  if (!cc) return "";
  const { rows } = await query(
    `SELECT value FROM sync_meta WHERE key = $1`,
    [`active_importacao:${cc}`],
  );
  return (rows[0] && rows[0].value) || "";
}

async function setActiveImportacaoId(clienteCodigo, id) {
  const cc = String(clienteCodigo || "").trim().toUpperCase();
  await query(
    `INSERT INTO sync_meta (key, value, updated_at) VALUES ($1, $2, now())
     ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now()`,
    [`active_importacao:${cc}`, id],
  );
}

async function persistValidated({ config, tables, filename, hash }) {
  const cc = config.CLIENTE_CODIGO;
  const existing = await query(
    `SELECT id, status, totais FROM planilha_importacoes
     WHERE cliente_codigo = $1 AND arquivo_hash = $2
     LIMIT 1`,
    [cc, hash],
  );
  if (existing.rows[0]) {
    await setActiveImportacaoId(cc, existing.rows[0].id);
    return {
      success: true,
      reused: true,
      importacao_id: existing.rows[0].id,
      totais: existing.rows[0].totais || {},
    };
  }

  return withTransaction(async () => {
    const fazendas = tables.fazendas.map((r) => ({
      idfazenda: r.idfazenda,
      fazenda: r.fazenda,
    }));
    const usuarios = tables.usuarios.map((r) => ({
      id: r.id,
      nome: r.nome,
      usuario: r.usuario,
      senha: r.senha,
      cargo: r.cargo,
      idfazenda: r.idfazenda,
    }));
    const vagoes = tables.vagoes.map((r) => ({ id: r.id, nome: r.nome }));
    const baias = tables.baias.map((r) => ({
      id_baia: r.idbaia,
      id_lote: r.idlote,
      nome_local: r.nomelocal,
      linha: r.linha,
      ordem_trato: r.ordemtrato,
      id_fazenda: r.idfazenda,
      rfid: r.rfid,
    }));
    const dietas = tables.dietas.map((r) => ({
      id: r.iddieta,
      nome_dieta: r.nomedieta,
      tipo_dieta: r.tipodieta,
      ms_dieta: r.msdieta,
      id_fazenda: r.idfazenda,
    }));
    const detalhes = tables.itens.map((r) => ({
      id: r.id || `${r.iddieta}::${r.idinsumo}::${r.ordem}`,
      id_dieta: r.iddieta,
      id_insumo: r.idinsumo,
      ingrediente: r.ingrediente,
      mn_perc: r.mnperc,
      ordem: r.ordem,
      ms_insumo: r.msinsumo,
      ms_inclusao: r.msinclusao,
      pre_pesagem: (r.prepesagem || "N").toUpperCase().startsWith("S") ? "S" : "N",
    }));
    const previsao = tables.previsao.map((r) => ({
      id_fornecimento: r.id_fornecimento,
      data: r.data,
      id_baia: r.id_baia,
      trato: r.trato,
      previsto: r.previsto_kg,
      previsto_original: r.previsto_kg,
      previsto_recalculado: r.previsto_kg,
      previsto_cadastro: r.previsto_kg,
      realizado: r.realizado_kg || 0,
      id_dieta: r.id_racao,
      id_fazenda: r.id_fazenda || config.FAZENDA_CODIGO,
    }));

    const totais = {
      fazendas: await master.upsertFazendas(cc, fazendas),
      usuarios: await master.upsertUsuarios(cc, usuarios),
      vagoes: await master.upsertVagoes(cc, vagoes),
      baias: await master.upsertBaias(cc, baias),
      dietas: await master.upsertDietas(cc, dietas),
      dieta_itens: await master.upsertDietasDetalhes(cc, detalhes),
      previsao: await master.upsertPrevisao(cc, previsao, config.FAZENDA_CODIGO),
    };

    const ins = await query(
      `INSERT INTO planilha_importacoes (
         cliente_codigo, versao_layout, arquivo_nome, arquivo_hash,
         fazenda_codigo, descricao, status, totais, erros
       ) VALUES ($1,$2,$3,$4,$5,$6,'ok',$7,'[]'::jsonb)
       RETURNING id`,
      [
        cc,
        LAYOUT_VERSION,
        filename || null,
        hash,
        config.FAZENDA_CODIGO || null,
        config.DESCRICAO || null,
        JSON.stringify(totais),
      ],
    );
    const importacaoId = ins.rows[0].id;
    await setActiveImportacaoId(cc, importacaoId);
    return { success: true, reused: false, importacao_id: importacaoId, totais };
  });
}

async function importBuffer(buffer, { filename, clienteCodigo } = {}) {
  const hash = fileHash(buffer);
  const validated = await validateBuffer(buffer, { filename });
  if (!validated.success) {
    return {
      success: false,
      erros: validated.erros,
    };
  }

  const sheetCliente = validated.config.CLIENTE_CODIGO;
  const headerCliente = String(clienteCodigo || "").trim().toUpperCase();
  if (headerCliente && sheetCliente && headerCliente !== sheetCliente) {
    return {
      success: false,
      erros: [
        err(
          "CONFIGURACAO",
          0,
          "CLIENTE_CODIGO",
          `CLIENTE_CODIGO da planilha (${sheetCliente}) difere do cliente da requisição (${headerCliente}).`,
        ),
      ],
    };
  }

  const cc = headerCliente || sheetCliente;
  validated.config.CLIENTE_CODIGO = cc;

  await query(
    `INSERT INTO clientes (codigo, nome, ativo)
     VALUES ($1, $2, TRUE)
     ON CONFLICT (codigo) DO NOTHING`,
    [cc, validated.config.DESCRICAO || cc],
  );

  const persisted = await persistValidated({
    config: validated.config,
    tables: validated.tables,
    filename,
    hash,
  });
  return {
    success: true,
    importacao_id: persisted.importacao_id,
    reused: persisted.reused,
    totais: persisted.totais,
    cliente_codigo: cc,
    erros: [],
  };
}

async function listImportacoes(clienteCodigo) {
  const cc = String(clienteCodigo || "").trim().toUpperCase();
  const params = [];
  let sql = `SELECT id, cliente_codigo, versao_layout, arquivo_nome, fazenda_codigo,
                    descricao, status, totais, created_at
             FROM planilha_importacoes`;
  if (cc) {
    params.push(cc);
    sql += ` WHERE cliente_codigo = $1`;
  }
  sql += ` ORDER BY created_at DESC LIMIT 100`;
  const { rows } = await query(sql, params);
  const active = cc ? await getActiveImportacaoId(cc) : "";
  return { importacoes: rows, ativa_id: active };
}

async function getImportacao(id) {
  try {
    const { rows } = await query(
      `SELECT * FROM planilha_importacoes WHERE id = $1 LIMIT 1`,
      [id],
    );
    return rows[0] || null;
  } catch (_) {
    return null;
  }
}

function planilhaError(message) {
  const err = new Error(message);
  err.code = "PLANILHA_IMPORTACAO";
  return err;
}

async function clientHasPlanilha(clienteCodigo) {
  const cc = String(clienteCodigo || "").trim().toUpperCase();
  if (!cc) return false;
  const { rows } = await query(
    `SELECT 1 FROM planilha_importacoes WHERE cliente_codigo = $1 LIMIT 1`,
    [cc],
  );
  return !!rows[0];
}

async function assertImportacaoOwned(clienteCodigo, importacaoId) {
  const cc = String(clienteCodigo || "").trim().toUpperCase();
  const id = String(importacaoId || "").trim();
  if (!id) {
    throw planilhaError("importacao_id obrigatório.");
  }
  let row = null;
  try {
    row = await getImportacao(id);
  } catch (_) {
    throw planilhaError("importacao_id inválido para este cliente.");
  }
  if (!row || String(row.cliente_codigo || "").toUpperCase() !== cc) {
    throw planilhaError("importacao_id inválido para este cliente.");
  }
  const status = String(row.status || "").toLowerCase();
  if (status && status !== "ok") {
    throw planilhaError(`Importação em estado inválido (${row.status}).`);
  }
  return row;
}

/** Clientes com carga Planilha: importacao_id obrigatório e pertencente ao tenant. */
async function resolveImportacaoForOps(clienteCodigo, importacaoId) {
  const id = String(importacaoId || "").trim();
  if (id) {
    return assertImportacaoOwned(clienteCodigo, id);
  }
  if (await clientHasPlanilha(clienteCodigo)) {
    throw planilhaError(
      "importacao_id obrigatório para cliente com carga Planilha.",
    );
  }
  return null;
}

module.exports = {
  isXlsxName,
  validateBuffer,
  importBuffer,
  listImportacoes,
  getImportacao,
  getActiveImportacaoId,
  setActiveImportacaoId,
  fileHash,
  clientHasPlanilha,
  assertImportacaoOwned,
  resolveImportacaoForOps,
};
