const config = require("../config");
const master = require("../services/master");
const ops = require("../services/ops");
const settings = require("../services/settings");
const requestLog = require("../services/requestLog");
const tenant = require("../services/tenant");
const { query } = require("../db");

function assertAdmin(req, reply) {
  if (config.adminOpen) return true;
  const hdr = req.headers.authorization || "";
  const token = hdr.startsWith("Bearer ") ? hdr.slice(7) : hdr;
  const alt = req.headers["x-admin-token"];
  if (token !== config.adminToken && alt !== config.adminToken) {
    reply.code(401).send({ error: "Unauthorized" });
    return false;
  }
  return true;
}

async function resolveAdminClient(req, { required = true } = {}) {
  let code = tenant.extractClientCode(req);
  // fallback extra: headers em variantes / body aninhado
  if (!code && req.headers) {
    code = tenant.normalizeClientCode(
      req.headers["x-client-code"] ||
        req.headers["X-Client-Code"] ||
        req.headers["client_code"] ||
        "",
    );
  }
  if (!code) {
    if (required) {
      throw new Error(
        "Informe client_code (header X-Client-Code ou query/body).",
      );
    }
    return null;
  }
  await tenant.ensureClienteExists(code);
  return code;
}

function registerAdminRoutes(app) {
  app.get("/admin/health", async (_req, reply) => {
    try {
      await query("SELECT 1");
      return reply.send({
        ok: true,
        service: "fieldpec-online-api",
        admin_open: config.adminOpen,
        multi_tenant: true,
      });
    } catch (e) {
      return reply.code(500).send({ ok: false, error: e.message });
    }
  });

  app.get("/admin/config", async (req, reply) => {
    if (!assertAdmin(req, reply)) return;
    return reply.send(await settings.getPublicConfig());
  });

  app.post("/admin/config", async (req, reply) => {
    if (!assertAdmin(req, reply)) return;
    try {
      const body = req.body || {};
      if (body.action === "test" || body.test_only === true) {
        const result = await settings.testFromUi(body);
        return reply.send(result);
      }
      const configResult = await settings.saveFromUi(body);
      return reply.send({
        success: true,
        restart_required: false,
        config: configResult,
        note: "Salvo no .env e pool Postgres reconectado.",
      });
    } catch (e) {
      return reply.code(500).send({
        success: false,
        ok: false,
        error: e.message,
        hint: "Confira host/porta/usuario/senha/banco. O mesmo que funciona no DBeaver.",
      });
    }
  });

  app.post("/admin/config/test-db", async (req, reply) => {
    if (!assertAdmin(req, reply)) return;
    try {
      const result = await settings.testFromUi(req.body || {});
      return reply.send(result);
    } catch (e) {
      return reply.code(400).send({ ok: false, error: e.message });
    }
  });

  app.get("/admin/checklist", async (req, reply) => {
    if (!assertAdmin(req, reply)) return;
    try {
      const cc = await resolveAdminClient(req, { required: false });
      return reply.send(await settings.checklist(cc));
    } catch (e) {
      return reply.code(400).send({ error: e.message });
    }
  });

  // ---- Clientes (tenants) ----
  app.get("/admin/clientes", async (req, reply) => {
    if (!assertAdmin(req, reply)) return;
    try {
      return reply.send({ rows: await tenant.listClientes() });
    } catch (e) {
      return reply.code(500).send({ error: e.message });
    }
  });

  app.post("/admin/clientes", async (req, reply) => {
    if (!assertAdmin(req, reply)) return;
    try {
      const body = req.body || {};
      const row = await tenant.upsertCliente({
        codigo: body.codigo || body.code || body.CLIENT_CODE,
        nome: body.nome || body.name,
        ativo: body.ativo !== false,
        token: body.token || null,
      });
      return reply.send({
        success: true,
        cliente: row,
        note: row.licenca && row.licenca.validado
          ? "Cliente validado na GeLicenca e salvo."
          : undefined,
      });
    } catch (e) {
      return reply.code(400).send({ success: false, error: e.message });
    }
  });

  app.post("/admin/clientes/validar", async (req, reply) => {
    if (!assertAdmin(req, reply)) return;
    try {
      const body = req.body || {};
      const codigo = body.codigo || body.code || body.CLIENT_CODE;
      const result = await tenant.previewLicenca(codigo);
      return reply.send({
        success: true,
        ok: result.ok !== false,
        codigo: result.codigo,
        nome: result.nome,
        sistema: result.sistema,
        vencimento: result.vencimento,
        statuslicencastr: result.statuslicencastr || result.message,
        numversao: result.numversao,
        local: !!result.local,
        message: result.local
          ? result.message
          : `Licença ${result.statuslicencastr || "Ativa"} · vencimento ${result.vencimento || "—"}`,
      });
    } catch (e) {
      return reply.code(400).send({
        success: false,
        ok: false,
        error: e.message,
        code: e.code || null,
      });
    }
  });

  app.patch("/admin/clientes/:codigo", async (req, reply) => {
    if (!assertAdmin(req, reply)) return;
    try {
      const body = req.body || {};
      if (body.ativo != null && body.nome == null && body.token == null) {
        const row = await tenant.setClienteAtivo(req.params.codigo, body.ativo);
        return reply.send({ success: true, cliente: row });
      }
      const row = await tenant.upsertCliente({
        codigo: req.params.codigo,
        nome: body.nome,
        ativo: body.ativo !== false,
        token: body.token,
      });
      return reply.send({ success: true, cliente: row });
    } catch (e) {
      return reply.code(400).send({ success: false, error: e.message });
    }
  });

  app.post("/admin/sync/master", async (req, reply) => {
    if (!assertAdmin(req, reply)) return;
    try {
      const cc = await resolveAdminClient(req, { required: true });
      const counts = await master.pushMaster(cc, req.body || {});
      return reply.send({ success: true, cliente_codigo: cc, counts });
    } catch (e) {
      req.log.error(e);
      return reply.code(500).send({ success: false, error: e.message });
    }
  });

  app.get("/admin/sync/pending", async (req, reply) => {
    if (!assertAdmin(req, reply)) return;
    try {
      const cc = await resolveAdminClient(req, { required: true });
      const data = await ops.listPendingOps(cc);
      return reply.send({ success: true, ...data });
    } catch (e) {
      return reply.code(500).send({ success: false, error: e.message });
    }
  });

  app.get("/admin/sync/ops", async (req, reply) => {
    if (!assertAdmin(req, reply)) return;
    try {
      const cc = await resolveAdminClient(req, { required: true });
      const status = (req.query && req.query.status) || "all";
      const limit = (req.query && req.query.limit) || 100;
      const data = await ops.listOps(cc, { status, limit });
      return reply.send({ success: true, ...data });
    } catch (e) {
      return reply.code(500).send({ success: false, error: e.message });
    }
  });

  app.post("/admin/sync/ack", async (req, reply) => {
    if (!assertAdmin(req, reply)) return;
    try {
      const cc = await resolveAdminClient(req, { required: true });
      const result = await ops.ackOps(cc, req.body || {});
      return reply.send({ success: true, ...result });
    } catch (e) {
      return reply.code(500).send({ success: false, error: e.message });
    }
  });

  app.get("/admin/stats", async (req, reply) => {
    if (!assertAdmin(req, reply)) return;
    try {
      const cc = await resolveAdminClient(req, { required: false });
      const q = async (sql, params = []) => (await query(sql, params)).rows[0];
      const filter = cc ? " WHERE cliente_codigo = $1" : "";
      const params = cc ? [cc] : [];
      const pendFilter = cc
        ? " WHERE cliente_codigo = $1 AND pulled_to_fieldpec=FALSE"
        : " WHERE pulled_to_fieldpec=FALSE";

      const [faz, usr, diet, prev, fabPend, fornPend, fabTot, fornTot, logs, clientes] =
        await Promise.all([
          q(`SELECT count(*)::int AS n FROM fazendas${filter}`, params),
          q(`SELECT count(*)::int AS n FROM usuarios${filter}`, params),
          q(`SELECT count(*)::int AS n FROM dietas${filter}`, params),
          q(`SELECT count(*)::int AS n FROM previsao_trato${filter}`, params),
          q(`SELECT count(*)::int AS n FROM fabricacoes${pendFilter}`, params),
          q(`SELECT count(*)::int AS n FROM fornecimentos${pendFilter}`, params),
          q(`SELECT count(*)::int AS n FROM fabricacoes${filter}`, params),
          q(`SELECT count(*)::int AS n FROM fornecimentos${filter}`, params),
          q(
            cc
              ? "SELECT count(*)::int AS n FROM request_logs WHERE cliente_codigo = $1"
              : "SELECT count(*)::int AS n FROM request_logs",
            params,
          ).catch(() => ({ n: 0 })),
          q("SELECT count(*)::int AS n FROM clientes").catch(() => ({ n: 0 })),
        ]);
      return reply.send({
        cliente_codigo: cc || null,
        clientes: clientes.n,
        fazendas: faz.n,
        usuarios: usr.n,
        dietas: diet.n,
        previsao: prev.n,
        fabricacoes_total: fabTot.n,
        fabricacoes_pendentes_fieldpec: fabPend.n,
        fornecimentos_total: fornTot.n,
        fornecimentos_pendentes_fieldpec: fornPend.n,
        request_logs: logs.n,
      });
    } catch (e) {
      return reply.code(400).send({ error: e.message });
    }
  });

  app.get("/admin/data/:table", async (req, reply) => {
    if (!assertAdmin(req, reply)) return;
    const table = String(req.params.table || "").toLowerCase();
    const limit = Math.min(Number(req.query.limit) || 100, 500);
    let cc = null;
    try {
      cc = await resolveAdminClient(req, { required: false });
    } catch (e) {
      return reply.code(400).send({ error: e.message });
    }

    const withTenant = (sqlBase) => {
      if (!cc) return { sql: `${sqlBase} LIMIT $1`, params: [limit] };
      // Insere filtro antes de ORDER BY
      const m = sqlBase.match(/\bORDER\s+BY\b/i);
      let sql;
      if (m) {
        const idx = m.index;
        const head = sqlBase.slice(0, idx).trim();
        const order = sqlBase.slice(idx);
        const hasWhere = /\bWHERE\b/i.test(head);
        sql = hasWhere
          ? `${head} AND cliente_codigo = $1 ${order} LIMIT $2`
          : `${head} WHERE cliente_codigo = $1 ${order} LIMIT $2`;
      } else {
        const hasWhere = /\bWHERE\b/i.test(sqlBase);
        sql = hasWhere
          ? `${sqlBase} AND cliente_codigo = $1 LIMIT $2`
          : `${sqlBase} WHERE cliente_codigo = $1 LIMIT $2`;
      }
      return { sql, params: [cc, limit] };
    };

    const map = {
      clientes: {
        sql: "SELECT * FROM clientes ORDER BY codigo LIMIT $1",
        params: [limit],
      },
      fazendas: withTenant(
        "SELECT * FROM fazendas ORDER BY updated_at DESC NULLS LAST",
      ),
      usuarios: withTenant(
        "SELECT id, cliente_codigo, nome, usuario, cargo, idfazenda, updated_at FROM usuarios ORDER BY updated_at DESC NULLS LAST",
      ),
      vagoes: withTenant(
        "SELECT * FROM vagoes ORDER BY updated_at DESC NULLS LAST",
      ),
      baias: withTenant(
        "SELECT * FROM baias ORDER BY updated_at DESC NULLS LAST",
      ),
      dietas: withTenant(
        "SELECT * FROM dietas ORDER BY updated_at DESC NULLS LAST",
      ),
      dietas_detalhes: withTenant(
        "SELECT * FROM dietas_detalhes ORDER BY updated_at DESC NULLS LAST",
      ),
      previsao: withTenant(
        "SELECT * FROM previsao_trato ORDER BY data DESC, trato, id_baia",
      ),
      previsao_trato: withTenant(
        "SELECT * FROM previsao_trato ORDER BY data DESC, trato, id_baia",
      ),
      fabricacoes: withTenant(
        "SELECT id, cliente_codigo, id_local, handoff_id, id_fazenda, id_dieta, data_fab, qtde_realizada, lote_fabricacao, pulled_to_fieldpec, created_at, payload FROM fabricacoes ORDER BY id DESC",
      ),
      fornecimentos: withTenant(
        "SELECT id, cliente_codigo, id_fornecimento, id_fabricacao_local, id_baia, data_forn, trato, realizado, pulled_to_fieldpec, created_at, payload FROM fornecimentos ORDER BY id DESC",
      ),
      audits: withTenant(
        "SELECT id, cliente_codigo, tipo, payload, created_at FROM audits ORDER BY id DESC",
      ),
      grava_tags: withTenant(
        "SELECT id, cliente_codigo, payload, created_at FROM grava_tags ORDER BY id DESC",
      ),
    };
    const entry = map[table];
    if (!entry) {
      return reply.code(400).send({
        error: "Tabela inválida",
        allowed: Object.keys(map),
      });
    }
    try {
      const { rows } = await query(entry.sql, entry.params);
      return reply.send({
        table,
        cliente_codigo: cc,
        count: rows.length,
        rows,
      });
    } catch (e) {
      return reply.code(500).send({ error: e.message });
    }
  });

  app.get("/admin/logs", async (req, reply) => {
    if (!assertAdmin(req, reply)) return;
    const rows = await requestLog.list({
      limit: req.query.limit,
      pathContains: req.query.q || "",
      clienteCodigo: req.query.client_code || req.query.cliente_codigo || "",
    });
    return reply.send({ count: rows.length, rows });
  });

  app.delete("/admin/logs", async (req, reply) => {
    if (!assertAdmin(req, reply)) return;
    await requestLog.clear();
    return reply.send({ success: true });
  });

  app.post("/admin/probe", async (req, reply) => {
    if (!assertAdmin(req, reply)) return;
    const {
      method = "GET",
      path: p = "/GetTeste",
      body = null,
      client_code = null,
    } = req.body || {};
    const pathClean = String(p).startsWith("/") ? p : `/${p}`;
    const base = `http://127.0.0.1:${config.port}`;
    const started = Date.now();
    const cc =
      client_code ||
      tenant.extractClientCode(req) ||
      (body && (body.client_code || body.cliente_codigo));
    try {
      const headers = {};
      if (body != null) headers["Content-Type"] = "application/json";
      if (cc) headers["X-Client-Code"] = String(cc).toUpperCase();
      const res = await fetch(`${base}${pathClean}`, {
        method: String(method).toUpperCase(),
        headers,
        body: body != null ? JSON.stringify(body) : undefined,
      });
      const text = await res.text();
      let data = text;
      try {
        data = JSON.parse(text);
      } catch {
        /* keep text */
      }
      return reply.send({
        ok: res.ok,
        status: res.status,
        duration_ms: Date.now() - started,
        path: pathClean,
        method: String(method).toUpperCase(),
        client_code: cc || null,
        data,
      });
    } catch (e) {
      return reply.code(500).send({
        ok: false,
        error: e.message,
        duration_ms: Date.now() - started,
      });
    }
  });
}

module.exports = { registerAdminRoutes, assertAdmin, resolveAdminClient };
