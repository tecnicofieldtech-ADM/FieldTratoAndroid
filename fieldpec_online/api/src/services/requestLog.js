const { query } = require("../db");

const MEMORY_MAX = 300;
const memory = [];
let persistEnabled = true;

function pushMemory(entry) {
  memory.unshift(entry);
  if (memory.length > MEMORY_MAX) memory.length = MEMORY_MAX;
}

async function record(entry) {
  const row = {
    id: `mem-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`,
    cliente_codigo: entry.clienteCodigo || entry.cliente_codigo || null,
    method: entry.method,
    path: entry.path,
    status_code: entry.statusCode ?? null,
    duration_ms: entry.durationMs ?? null,
    remote_ip: entry.remoteIp ?? null,
    request_body: entry.requestBody ?? null,
    response_preview: entry.responsePreview ?? null,
    error_message: entry.errorMessage ?? null,
    created_at: new Date().toISOString(),
  };
  pushMemory(row);

  if (!persistEnabled) return row;
  try {
    const body =
      row.request_body == null ? null : JSON.stringify(row.request_body);
    await query(
      `INSERT INTO request_logs
         (cliente_codigo, method, path, status_code, duration_ms, remote_ip, request_body, response_preview, error_message)
       VALUES ($1,$2,$3,$4,$5,$6,$7::jsonb,$8,$9)`,
      [
        row.cliente_codigo,
        row.method,
        row.path,
        row.status_code,
        row.duration_ms,
        row.remote_ip,
        body,
        row.response_preview,
        row.error_message,
      ],
    );
  } catch (e) {
    // fallback sem coluna cliente_codigo
    try {
      const body =
        row.request_body == null ? null : JSON.stringify(row.request_body);
      await query(
        `INSERT INTO request_logs
           (method, path, status_code, duration_ms, remote_ip, request_body, response_preview, error_message)
         VALUES ($1,$2,$3,$4,$5,$6::jsonb,$7,$8)`,
        [
          row.method,
          row.path,
          row.status_code,
          row.duration_ms,
          row.remote_ip,
          body,
          row.response_preview,
          row.error_message,
        ],
      );
    } catch (e2) {
      if (String(e2.message || "").includes("request_logs")) {
        persistEnabled = false;
      }
    }
  }
  return row;
}

async function list({ limit = 100, pathContains = "", clienteCodigo = "" } = {}) {
  const lim = Math.min(Math.max(Number(limit) || 100, 1), 500);
  const cc = String(clienteCodigo || "").trim().toUpperCase();
  try {
    const clauses = [];
    const params = [];
    if (pathContains) {
      params.push(`%${pathContains}%`);
      clauses.push(`path ILIKE $${params.length}`);
    }
    if (cc) {
      params.push(cc);
      clauses.push(`cliente_codigo = $${params.length}`);
    }
    params.push(lim);
    const where = clauses.length ? `WHERE ${clauses.join(" AND ")}` : "";
    const { rows } = await query(
      `SELECT id, cliente_codigo, method, path, status_code, duration_ms, remote_ip,
              request_body, response_preview, error_message, created_at
       FROM request_logs
       ${where}
       ORDER BY id DESC
       LIMIT $${params.length}`,
      params,
    );
    return rows;
  } catch {
    return memory
      .filter((r) => {
        if (
          pathContains &&
          !String(r.path).toLowerCase().includes(pathContains.toLowerCase())
        ) {
          return false;
        }
        if (cc && String(r.cliente_codigo || "").toUpperCase() !== cc) {
          return false;
        }
        return true;
      })
      .slice(0, lim);
  }
}

async function clear() {
  memory.length = 0;
  try {
    await query(`TRUNCATE request_logs RESTART IDENTITY`);
  } catch {
    /* ignore */
  }
  return { ok: true };
}

function listMemory(limit = 50) {
  return memory.slice(0, limit);
}

module.exports = { record, list, clear, listMemory };
