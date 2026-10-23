const { Pool } = require("pg");
const { AsyncLocalStorage } = require("async_hooks");
const config = require("./config");

const txStore = new AsyncLocalStorage();

let pool = new Pool({
  connectionString: config.databaseUrl,
});

async function query(text, params) {
  const client = txStore.getStore();
  if (client) return client.query(text, params);
  return pool.query(text, params);
}

async function withTransaction(fn) {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const result = await txStore.run(client, () => fn(client));
    await client.query("COMMIT");
    return result;
  } catch (e) {
    try {
      await client.query("ROLLBACK");
    } catch (_) {
      /* ignore */
    }
    throw e;
  } finally {
    client.release();
  }
}

async function reconnect(connectionString) {
  const url = String(connectionString || "").trim();
  if (!url) throw new Error("DATABASE_URL vazia");
  const old = pool;
  pool = new Pool({ connectionString: url });
  try {
    await pool.query("SELECT 1 AS ok");
  } catch (e) {
    await pool.end().catch(() => {});
    pool = old;
    throw e;
  }
  config.databaseUrl = url;
  await old.end().catch(() => {});
  return true;
}

/** Testa uma connection string sem alterar o pool atual. */
async function testConnection(connectionString) {
  const url = String(connectionString || "").trim();
  if (!url) throw new Error("DATABASE_URL vazia");
  const testPool = new Pool({
    connectionString: url,
    connectionTimeoutMillis: 8000,
    max: 1,
  });
  try {
    const r = await testPool.query(
      "SELECT current_database() AS db, current_user AS usr, version() AS version",
    );
    return { ok: true, ...r.rows[0] };
  } finally {
    await testPool.end().catch(() => {});
  }
}

module.exports = {
  get pool() {
    return pool;
  },
  query,
  withTransaction,
  reconnect,
  testConnection,
};
