const test = require("node:test");
const assert = require("node:assert/strict");

test("idempotencia de fornecimento usa id_cadastro no schema", () => {
  const fs = require("fs");
  const path = require("path");
  const schema = fs.readFileSync(
    path.join(__dirname, "..", "..", "sql", "schema.sql"),
    "utf8",
  );
  assert.match(schema, /uq_forn_cliente_id_cadastro/);
  assert.match(schema, /planilha_importacoes/);
  assert.match(schema, /id_cadastro TEXT/);
});

test("ops.saveFornecimento consulta id_cadastro", () => {
  const fs = require("fs");
  const path = require("path");
  const src = fs.readFileSync(
    path.join(__dirname, "..", "src", "services", "ops.js"),
    "utf8",
  );
  assert.match(src, /id_cadastro/);
  assert.match(src, /duplicate: true/);
  assert.match(src, /handoff_id/);
});
