const fs = require("fs");
const path = require("path");
const config = require("../config");
const db = require("../db");

function maskDatabaseUrl(url) {
  if (!url) return "";
  return String(url).replace(/:([^:@/]+)@/, ":****@");
}

function envPath() {
  return path.join(__dirname, "..", "..", ".env");
}

function readEnvFile() {
  const p = envPath();
  if (!fs.existsSync(p)) return {};
  const out = {};
  for (const line of fs.readFileSync(p, "utf8").split(/\r?\n/)) {
    const t = line.trim();
    if (!t || t.startsWith("#")) continue;
    const i = t.indexOf("=");
    if (i < 0) continue;
    out[t.slice(0, i).trim()] = t.slice(i + 1).trim();
  }
  return out;
}

function parseDatabaseUrl(url) {
  const raw = String(url || "").trim();
  const empty = {
    db_host: "127.0.0.1",
    db_port: 5432,
    db_user: "postgres",
    db_password: "",
    db_name: "",
  };
  if (!raw) return empty;
  try {
    const u = new URL(raw);
    const name = decodeURIComponent(
      (u.pathname || "/").replace(/^\//, "") || "",
    );
    return {
      db_host: u.hostname || "127.0.0.1",
      db_port: Number(u.port || 5432),
      db_user: decodeURIComponent(u.username || "postgres"),
      db_password: decodeURIComponent(u.password || ""),
      db_name: name,
    };
  } catch {
    return empty;
  }
}

function buildDatabaseUrl({ db_host, db_port, db_user, db_password, db_name }) {
  const user = encodeURIComponent(String(db_user || "postgres"));
  const pass = encodeURIComponent(String(db_password ?? ""));
  const host = String(db_host || "127.0.0.1").trim();
  const port = Number(db_port || 5432);
  const name = String(db_name || "").trim().replace(/^\//, "");
  return `postgres://${user}:${pass}@${host}:${port}/${name}`;
}

function writeEnvFile(updates) {
  const p = envPath();
  const current = readEnvFile();
  Object.assign(current, updates);
  const lines = [
    `# FieldPec Online API — gerado pelo painel /admin`,
    `# ${new Date().toISOString()}`,
    `PORT=${current.PORT || config.port}`,
    `HOST=${current.HOST || "0.0.0.0"}`,
    `DATABASE_URL=${current.DATABASE_URL || config.databaseUrl}`,
    `ADMIN_TOKEN=${current.ADMIN_TOKEN ?? "open"}`,
    ``,
    `# Licença GeLicenca`,
    `LICENSE_API_URL=${current.LICENSE_API_URL || config.licenseApiBase}`,
    `LICENSE_API_USER=${current.LICENSE_API_USER || config.licenseUser}`,
    `LICENSE_API_PASSWORD=${current.LICENSE_API_PASSWORD || config.licensePassword}`,
    `LICENSE_SISTEMA_ID=${current.LICENSE_SISTEMA_ID || config.licenseSistemaId}`,
    `LICENSE_VALIDATE=${current.LICENSE_VALIDATE ?? (config.licenseValidate ? "1" : "0")}`,
    "",
  ];
  fs.writeFileSync(p, lines.join("\n"), "utf8");

  const tokenRaw = current.ADMIN_TOKEN;
  const open =
    tokenRaw == null ||
    String(tokenRaw).trim() === "" ||
    ["open", "none", "false", "0", "off"].includes(
      String(tokenRaw).trim().toLowerCase(),
    );
  config.adminToken = open ? "" : String(tokenRaw).trim();
  config.adminOpen = open;
  if (current.PORT) config.port = Number(current.PORT);
  if (current.HOST) config.host = current.HOST;
  if (current.DATABASE_URL) config.databaseUrl = current.DATABASE_URL;
  if (current.LICENSE_API_URL) {
    config.licenseApiBase = String(current.LICENSE_API_URL).replace(/\/+$/, "");
  }
  if (current.LICENSE_API_USER != null) {
    config.licenseUser = String(current.LICENSE_API_USER);
  }
  if (current.LICENSE_API_PASSWORD != null) {
    config.licensePassword = String(current.LICENSE_API_PASSWORD);
  }
  if (current.LICENSE_SISTEMA_ID) {
    config.licenseSistemaId = String(current.LICENSE_SISTEMA_ID);
  }
  if (current.LICENSE_VALIDATE != null) {
    config.licenseValidate = String(current.LICENSE_VALIDATE).trim() !== "0";
  }
  return current;
}

async function getPublicConfig() {
  const env = readEnvFile();
  const url = env.DATABASE_URL || config.databaseUrl;
  const parts = parseDatabaseUrl(url);

  let dbOk = false;
  let dbError = null;
  try {
    await db.query("SELECT 1 AS ok");
    dbOk = true;
  } catch (e) {
    dbError = e.message;
  }

  let tableCounts = null;
  try {
    const q = async (sql) => (await db.query(sql)).rows[0].n;
    tableCounts = {
      fazendas: await q("SELECT count(*)::int AS n FROM fazendas"),
      usuarios: await q("SELECT count(*)::int AS n FROM usuarios"),
      baias: await q("SELECT count(*)::int AS n FROM baias"),
      dietas: await q("SELECT count(*)::int AS n FROM dietas"),
      dietas_detalhes: await q("SELECT count(*)::int AS n FROM dietas_detalhes"),
      previsao: await q("SELECT count(*)::int AS n FROM previsao_trato"),
      fabricacoes: await q("SELECT count(*)::int AS n FROM fabricacoes"),
      fornecimentos: await q("SELECT count(*)::int AS n FROM fornecimentos"),
    };
  } catch (e) {
    tableCounts = { error: e.message };
  }

  return {
    port: Number(env.PORT || config.port),
    host: env.HOST || config.host || "0.0.0.0",
    admin_token: env.ADMIN_TOKEN ?? (config.adminOpen ? "open" : "****"),
    admin_open: config.adminOpen,
    db_host: parts.db_host,
    db_port: parts.db_port,
    db_user: parts.db_user,
    db_name: parts.db_name,
    db_password_set: Boolean(parts.db_password),
    database_url_masked: maskDatabaseUrl(url),
    db_ok: dbOk,
    db_error: dbError,
    table_counts: tableCounts,
    fieldtrato: {
      backend: "FieldPec",
      host_hint: "<IP ou domínio deste servidor>",
      porta: Number(env.PORT || config.port),
    },
  };
}

/** Monta partes DB a partir do formulário — NÃO mistura user/host/banco com o .env antigo. */
function resolveDbPartsFromBody(body = {}, { requireTypedPassword }) {
  const env = readEnvFile();
  const current = parseDatabaseUrl(env.DATABASE_URL || config.databaseUrl);

  const db_host = String(body.db_host ?? "").trim();
  const db_port = Number(body.db_port || 5432);
  const db_user = String(body.db_user ?? "").trim();
  const db_name = String(body.db_name ?? "").trim();
  const typedPassword = String(body.db_password ?? "");

  if (!db_host) throw new Error("Informe o Host do Postgres.");
  if (!db_user) throw new Error("Informe o Usuário do Postgres.");
  if (!db_name) throw new Error("Informe o Nome do banco.");

  let db_password = typedPassword;
  if (!db_password) {
    if (requireTypedPassword) {
      throw new Error("Digite a Senha no formulário para testar.");
    }
    // salvar: pode reaproveitar senha já gravada no .env
    db_password = current.db_password;
  }
  if (!db_password) {
    throw new Error("Informe a Senha do Postgres.");
  }

  return { db_host, db_port, db_user, db_name, db_password };
}

async function saveFromUi(body = {}) {
  const parts = resolveDbPartsFromBody(body, { requireTypedPassword: true });
  const DATABASE_URL = buildDatabaseUrl(parts);

  // Testa ANTES de gravar o .env (evita misturar usuário antigo do pool com URL nova)
  try {
    await db.testConnection(DATABASE_URL);
  } catch (e) {
    throw new Error(
      `Conexão falhou como '${parts.db_user}' / '${parts.db_name}': ${e.message}`,
    );
  }

  const updates = {
    DATABASE_URL,
    HOST: "0.0.0.0",
  };
  if (body.PORT != null && String(body.PORT).trim() !== "") {
    updates.PORT = String(body.PORT);
  }
  if (body.ADMIN_TOKEN != null) updates.ADMIN_TOKEN = String(body.ADMIN_TOKEN);

  writeEnvFile(updates);
  await db.reconnect(DATABASE_URL);

  const cfg = await getPublicConfig();
  return {
    ...cfg,
    saved_as: {
      db_host: parts.db_host,
      db_port: parts.db_port,
      db_user: parts.db_user,
      db_name: parts.db_name,
    },
  };
}

async function testFromUi(body = {}) {
  const parts = resolveDbPartsFromBody(body, { requireTypedPassword: true });
  const DATABASE_URL = buildDatabaseUrl(parts);
  try {
    const result = await db.testConnection(DATABASE_URL);
    return {
      ok: true,
      message: "Conexão com Postgres OK",
      tested_as: {
        host: parts.db_host,
        port: parts.db_port,
        user: parts.db_user,
        database: parts.db_name,
      },
      server_db: result.db,
      server_user: result.usr,
      version: String(result.version || "").split(",")[0],
    };
  } catch (e) {
    const err = new Error(
      `Falha como usuário '${parts.db_user}' no banco '${parts.db_name}': ${e.message}`,
    );
    throw err;
  }
}

async function checklist(clienteCodigo = null) {
  const cfg = await getPublicConfig();
  const items = [];
  const cc = clienteCodigo
    ? String(clienteCodigo).trim().toUpperCase()
    : null;

  items.push({
    id: "api_up",
    ok: true,
    title: "API no ar",
    detail: `Porta ${cfg.port}`,
  });
  items.push({
    id: "db",
    ok: cfg.db_ok,
    title: "Postgres conectado",
    detail: cfg.db_ok ? "SELECT 1 OK" : cfg.db_error || "falha",
  });

  let tableCounts = cfg.table_counts || {};
  if (cc) {
    try {
      const q = async (sql, params) => (await db.query(sql, params)).rows[0].n;
      tableCounts = {
        fazendas: await q(
          "SELECT count(*)::int AS n FROM fazendas WHERE cliente_codigo=$1",
          [cc],
        ),
        usuarios: await q(
          "SELECT count(*)::int AS n FROM usuarios WHERE cliente_codigo=$1",
          [cc],
        ),
        baias: await q(
          "SELECT count(*)::int AS n FROM baias WHERE cliente_codigo=$1",
          [cc],
        ),
        dietas: await q(
          "SELECT count(*)::int AS n FROM dietas WHERE cliente_codigo=$1",
          [cc],
        ),
        dietas_detalhes: await q(
          "SELECT count(*)::int AS n FROM dietas_detalhes WHERE cliente_codigo=$1",
          [cc],
        ),
        previsao: await q(
          "SELECT count(*)::int AS n FROM previsao_trato WHERE cliente_codigo=$1",
          [cc],
        ),
        fabricacoes: await q(
          "SELECT count(*)::int AS n FROM fabricacoes WHERE cliente_codigo=$1",
          [cc],
        ),
        fornecimentos: await q(
          "SELECT count(*)::int AS n FROM fornecimentos WHERE cliente_codigo=$1",
          [cc],
        ),
      };
    } catch (e) {
      tableCounts = { error: e.message };
    }
  }

  const c = tableCounts || {};
  items.push({
    id: "cliente",
    ok: !!cc,
    title: cc ? `Cliente: ${cc}` : "Cliente não filtrado",
    detail: cc
      ? "Checklist filtrado por cliente_codigo"
      : "Passe ?client_code=CODIGO para filtrar",
  });
  items.push({
    id: "fazendas",
    ok: (c.fazendas || 0) > 0,
    title: "Cadastro: fazendas",
    detail: `${c.fazendas ?? "?"} registro(s) — suba via conector`,
  });
  items.push({
    id: "usuarios",
    ok: (c.usuarios || 0) > 0,
    title: "Cadastro: usuarios",
    detail: `${c.usuarios ?? "?"} registro(s)`,
  });
  items.push({
    id: "dietas",
    ok: (c.dietas || 0) > 0,
    title: "Cadastro: dietas",
    detail: `${c.dietas ?? "?"} registro(s)`,
  });
  items.push({
    id: "detalhes",
    ok: (c.dietas_detalhes || 0) > 0,
    title: "Cadastro: ingredientes (dietas_detalhes)",
    detail: `${c.dietas_detalhes ?? "?"} registro(s)`,
  });
  items.push({
    id: "baias",
    ok: (c.baias || 0) > 0,
    title: "Cadastro: baias",
    detail: `${c.baias ?? "?"} registro(s)`,
  });
  items.push({
    id: "previsao",
    ok: (c.previsao || 0) > 0,
    title: "Previsão de trato",
    detail: `${c.previsao ?? "?"} registro(s)`,
  });
  items.push({
    id: "admin_open",
    ok: true,
    title: config.adminOpen ? "Admin aberto (sem token)" : "Admin com token",
    detail: config.adminOpen
      ? "ADMIN_TOKEN=open — ok para homologação"
      : "Bearer token exigido em /admin/*",
  });

  const ready = items
    .filter((i) => !["admin_open", "cliente"].includes(i.id))
    .every((i) => i.ok);
  return {
    ready_for_fieldtrato: ready,
    cliente_codigo: cc,
    items,
    config: cfg,
  };
}

module.exports = {
  getPublicConfig,
  saveFromUi,
  testFromUi,
  writeEnvFile,
  readEnvFile,
  checklist,
  maskDatabaseUrl,
  parseDatabaseUrl,
  buildDatabaseUrl,
  envPath,
};
