const { Client } = require("pg");

(async () => {
  const c = new Client({
    connectionString:
      "postgres://fieldpec:fieldpec@127.0.0.1:5432/fieldpec_online",
  });
  await c.connect();
  const fab = await c.query(
    "SELECT id, importacao_id, payload FROM fabricacoes ORDER BY id DESC LIMIT 5",
  );
  console.log("--- fabricacoes ---");
  for (const r of fab.rows) {
    const p = r.payload || {};
    console.log({
      id: r.id,
      importacao_id: r.importacao_id,
      payload_importacao: p.importacao_id || p.IMPORTACAO_ID,
      dieta: p.id_dieta || p.ID_DIETA,
    });
  }
  const forn = await c.query(
    "SELECT id, importacao_id, payload FROM fornecimentos ORDER BY id DESC LIMIT 5",
  );
  console.log("--- fornecimentos ---");
  for (const r of forn.rows) {
    const p = r.payload || {};
    console.log({
      id: r.id,
      importacao_id: r.importacao_id,
      payload_importacao: p.importacao_id || p.IMPORTACAO_ID,
      baia: p.id_baia || p.ID_BAIA,
    });
  }
  await c.end();
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
