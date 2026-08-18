const fs = require("fs");
const path = require("path");
const Fastify = require("fastify");
const cors = require("@fastify/cors");
const fastifyStatic = require("@fastify/static");
const config = require("./config");
const { registerHorseRoutes } = require("./routes/horse");
const { registerAdminRoutes } = require("./routes/admin");
const requestLog = require("./services/requestLog");
const { query } = require("./db");

const publicDir = path.join(__dirname, "..", "public");
const adminHtmlPath = path.join(publicDir, "index.html");

async function ensureRequestLogTable() {
  try {
    await query(`
      CREATE TABLE IF NOT EXISTS request_logs (
        id BIGSERIAL PRIMARY KEY,
        cliente_codigo TEXT,
        method TEXT NOT NULL,
        path TEXT NOT NULL,
        status_code INTEGER,
        duration_ms DOUBLE PRECISION,
        remote_ip TEXT,
        request_body JSONB,
        response_preview TEXT,
        error_message TEXT,
        created_at TIMESTAMPTZ NOT NULL DEFAULT now()
      )
    `);
    await query(
      `ALTER TABLE request_logs ADD COLUMN IF NOT EXISTS cliente_codigo TEXT`,
    );
  } catch (e) {
    console.warn("[request_logs] tabela nao criada:", e.message);
  }
}

function sendAdminHtml(reply) {
  if (!fs.existsSync(adminHtmlPath)) {
    return reply.code(500).type("text/plain").send(
      "Painel nao encontrado: falta api/public/index.html no servidor.\n" +
        "Atualize o pacote da API (copie a pasta api/public e reinicie).",
    );
  }
  const html = fs.readFileSync(adminHtmlPath, "utf8");
  return reply.type("text/html; charset=utf-8").send(html);
}

async function main() {
  const app = Fastify({
    logger: true,
    bodyLimit: 20 * 1024 * 1024,
  });

  await app.register(cors, { origin: true });

  app.addHook("onRequest", async (req) => {
    req.startTime = Date.now();
  });

  app.addHook("onResponse", async (req, reply) => {
    const p = req.url.split("?")[0];
    if (
      p.startsWith("/admin/ui") ||
      p === "/favicon.ico" ||
      p.endsWith(".css") ||
      p.endsWith(".js") ||
      p.endsWith(".map")
    ) {
      return;
    }
    const tenant = require("./services/tenant");
    await requestLog.record({
      clienteCodigo:
        req.clienteCodigo || tenant.extractClientCode(req) || null,
      method: req.method,
      path: p,
      statusCode: reply.statusCode,
      durationMs: Date.now() - (req.startTime || Date.now()),
      remoteIp: req.ip,
      requestBody:
        req.method !== "GET" && req.method !== "HEAD" && req.body != null
          ? req.body
          : null,
      responsePreview: null,
      errorMessage: reply.statusCode >= 400 ? `HTTP ${reply.statusCode}` : null,
    });
  });

  registerHorseRoutes(app);
  registerAdminRoutes(app);

  // Rotas explícitas do painel (não dependem só do static)
  app.get("/admin/ui", async (_req, reply) => sendAdminHtml(reply));
  app.get("/admin/ui/", async (_req, reply) => sendAdminHtml(reply));
  app.get("/admin/ui/index.html", async (_req, reply) => sendAdminHtml(reply));

  if (fs.existsSync(publicDir)) {
    await app.register(fastifyStatic, {
      root: publicDir,
      prefix: "/admin/ui/static/",
      decorateReply: false,
    });
  } else {
    console.warn("[admin] pasta public ausente:", publicDir);
  }

  app.get("/admin", async (_req, reply) => {
    return reply.redirect("/admin/ui/");
  });

  app.get("/", async (_req, reply) => {
    return reply.redirect("/admin/ui/");
  });

  await ensureRequestLogTable();

  await app.listen({ port: config.port, host: config.host });
  app.log.info(`FieldPec Online API em http://${config.host}:${config.port}`);
  app.log.info(
    `Painel: http://127.0.0.1:${config.port}/admin/ui/  (html=${fs.existsSync(adminHtmlPath)})`,
  );
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
