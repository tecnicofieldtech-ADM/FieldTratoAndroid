const { query } = require("../db");
const config = require("../config");
const license = require("./license");

/** Códigos locais de homologação — não passam pela GeLicenca */
const LOCAL_CODES = new Set(["DEMO", "LOCAL", "TEST", "TESTE"]);

const CODE_RE = /^[A-Z0-9][A-Z0-9_-]{0,63}$/;

function normalizeClientCode(raw) {
  let s = String(raw == null ? "" : raw).trim();
  // Se vier array (header/query duplicado) ou "2411141, 2411141", pega o 1º
  if (Array.isArray(raw)) {
    s = String(raw[0] || "").trim();
  } else if (s.includes(",")) {
    s = s.split(",")[0].trim();
  }
  s = s.toUpperCase().replace(/\s+/g, "_");
  // remove aspas acidentais
  s = s.replace(/^["']|["']$/g, "");
  return s;
}

function assertValidCode(code) {
  const c = normalizeClientCode(code);
  if (!c) throw new Error("Informe o Código do cliente (CLIENT_CODE).");
  // Licença FieldPec costuma ser só dígitos (ex.: 2411141)
  if (!/^[A-Z0-9][A-Z0-9_-]{0,63}$/.test(c)) {
    throw new Error(
      `Código do cliente inválido ('${c}'). Use o código da licença (ex.: 2411141).`,
    );
  }
  return c;
}

function isLocalCode(code) {
  return LOCAL_CODES.has(normalizeClientCode(code));
}

/** Extrai código de header / query / body. */
function extractClientCode(req) {
  const pick = (v) => {
    if (v == null || v === "") return "";
    if (Array.isArray(v)) return normalizeClientCode(v[0]);
    return normalizeClientCode(v);
  };

  const h = pick(
    req.headers["x-client-code"] ||
      req.headers["x-cliente-codigo"] ||
      req.headers["client-code"],
  );
  if (h) return h;

  const q = pick(
    req.query && (req.query.client_code || req.query.cliente_codigo),
  );
  if (q) return q;

  const b = pick(
    req.body &&
      (req.body.client_code ||
        req.body.cliente_codigo ||
        req.body.CLIENT_CODE ||
        req.body.CLIENTE_CODIGO),
  );
  return b;
}

/**
 * Valida na GeLicenca (exceto DEMO/LOCAL).
 * @returns {Promise<object|null>} dados da licença ou null se local/skip
 */
async function validateAgainstLicense(codigo, { requireActive = true } = {}) {
  const code = assertValidCode(codigo);
  if (isLocalCode(code)) return null;
  if (!config.licenseValidate) return null;

  const result = await license.validateClienteLicenca(code);
  if (requireActive && !result.ok) {
    throw new Error(`Licença inválida para '${code}'.`);
  }
  return result;
}

async function ensureClienteExists(codigo) {
  const code = assertValidCode(codigo);
  const { rows } = await query(
    `SELECT codigo, nome, ativo FROM clientes WHERE codigo = $1`,
    [code],
  );

  if (rows[0]) {
    if (rows[0].ativo === false) {
      throw new Error(`Cliente '${code}' está inativo.`);
    }
    return rows[0];
  }

  // Não cadastrado: tenta validar licença e cadastrar automaticamente
  if (isLocalCode(code)) {
    throw new Error(
      `Cliente '${code}' não cadastrado. Cadastre em /admin (Clientes).`,
    );
  }

  const lic = await validateAgainstLicense(code);
  const nome =
    (lic && lic.nome) ||
    `Cliente ${code}`;
  const created = await upsertCliente({
    codigo: code,
    nome,
    ativo: true,
    skipLicense: true, // já validou acima
    licenseMeta: lic,
  });
  return created;
}

/** Exige cliente já cadastrado em /admin (não auto-cadastra). */
async function requireRegisteredCliente(codigo) {
  const code = assertValidCode(codigo);
  const { rows } = await query(
    `SELECT codigo, nome, ativo FROM clientes WHERE codigo = $1`,
    [code],
  );
  if (!rows[0]) {
    throw new Error(
      `Cliente '${code}' não cadastrado na API. Cadastre em /admin (Clientes).`,
    );
  }
  if (rows[0].ativo === false) {
    throw new Error(`Cliente '${code}' está inativo.`);
  }
  return rows[0];
}

async function requireClientCode(req) {
  const code = extractClientCode(req);
  if (!code) {
    throw new Error(
      "Código do cliente obrigatório (header X-Client-Code ou client_code).",
    );
  }
  await requireRegisteredCliente(code);
  return code;
}

async function listClientes() {
  const { rows } = await query(
    `SELECT codigo, nome, ativo, created_at, updated_at
     FROM clientes ORDER BY codigo`,
  );
  return rows;
}

/**
 * Cadastra/atualiza cliente. Por padrão valida na GeLicenca.
 * skipLicense: true só quando já validou (auto-cadastro).
 */
async function upsertCliente({
  codigo,
  nome,
  ativo = true,
  token = null,
  skipLicense = false,
  licenseMeta = null,
} = {}) {
  const code = assertValidCode(codigo);

  let lic = licenseMeta;
  if (!skipLicense) {
    lic = await validateAgainstLicense(code);
  }

  const nomeFinal =
    String(nome || (lic && lic.nome) || code).trim() || code;

  // Se licença veio inativa e alguém forçou ativo, respeita validação
  let ativoFinal = ativo !== false;
  if (lic && lic.ok === false) ativoFinal = false;

  const { rows } = await query(
    `INSERT INTO clientes (codigo, nome, ativo, token, updated_at)
     VALUES ($1,$2,$3,$4,now())
     ON CONFLICT (codigo) DO UPDATE SET
       nome=EXCLUDED.nome,
       ativo=EXCLUDED.ativo,
       token=COALESCE(EXCLUDED.token, clientes.token),
       updated_at=now()
     RETURNING codigo, nome, ativo, created_at, updated_at`,
    [code, nomeFinal, ativoFinal, token || null],
  );

  return {
    ...rows[0],
    licenca: lic
      ? {
          sistema: lic.sistema,
          vencimento: lic.vencimento,
          status: lic.statuslicencastr,
          numversao: lic.numversao,
          validado: true,
        }
      : isLocalCode(code)
        ? { validado: false, motivo: "código local (DEMO)" }
        : config.licenseValidate
          ? null
          : { validado: false, motivo: "LICENSE_VALIDATE=0" },
  };
}

async function setClienteAtivo(codigo, ativo) {
  const code = assertValidCode(codigo);
  if (ativo && !isLocalCode(code) && config.licenseValidate) {
    await validateAgainstLicense(code);
  }
  const { rows } = await query(
    `UPDATE clientes SET ativo = $2, updated_at = now()
     WHERE codigo = $1
     RETURNING codigo, nome, ativo`,
    [code, !!ativo],
  );
  if (!rows[0]) throw new Error(`Cliente '${code}' não encontrado.`);
  return rows[0];
}

/** Só consulta licença sem gravar (botão Testar no admin). */
async function previewLicenca(codigo) {
  const code = assertValidCode(codigo);
  if (isLocalCode(code)) {
    return {
      ok: true,
      codigo: code,
      local: true,
      message: "Código local de homologação — sem consulta GeLicenca.",
    };
  }
  return license.validateClienteLicenca(code);
}

module.exports = {
  normalizeClientCode,
  assertValidCode,
  extractClientCode,
  ensureClienteExists,
  requireRegisteredCliente,
  requireClientCode,
  listClientes,
  upsertCliente,
  setClienteAtivo,
  validateAgainstLicense,
  previewLicenca,
  isLocalCode,
  CODE_RE,
};
