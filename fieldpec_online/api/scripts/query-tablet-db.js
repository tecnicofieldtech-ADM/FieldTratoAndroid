const fs = require("fs");
const path = require("path");
const initSqlJs = require("../../homologacao/fisico/sqljs/node_modules/sql.js");

const dbPath =
  process.argv[2] ||
  path.join(__dirname, "..", "..", "homologacao", "fisico", "rfeed_app.db");

function print(sql, db) {
  const r = db.exec(sql);
  console.log("\n---", sql);
  if (!r.length) {
    console.log("(empty)");
    return;
  }
  console.log(r[0].columns.join(" | "));
  for (const row of r[0].values) {
    console.log(row.map((v) => (v === null ? "NULL" : String(v))).join(" | "));
  }
}

(async () => {
  const SQL = await initSqlJs();
  const buf = fs.readFileSync(dbPath);
  const db = new SQL.Database(buf);
  print("PRAGMA user_version", db);
  print(
    "SELECT HOST, PORTA, BACKEND, CLIENTE_CODIGO, ID_FAZENDA, ID_VAGAO, NOME_VAGAO, IMPORTACAO_ID, BALANCA_SIMULADOR FROM CONFIG",
    db,
  );
  print("SELECT ID, NOME FROM CADASTRO_FAZENDAS", db);
  print("SELECT ID, NOME FROM VAGAO", db);
  print("SELECT ID, LOGIN, NOME, ID_FAZENDA FROM CADASTRO_USUARIO", db);
  print("PRAGMA table_info(CADASTRO_FABRICA_RACAO)", db);
  print("PRAGMA table_info(CADASTRO_FORNECIMENTO)", db);
  print("SELECT COUNT(*) AS n FROM DIETA", db);
  print("SELECT COUNT(*) AS n FROM DETALHES_BAIAS", db);
  print("SELECT COUNT(*) AS n FROM PREVISAO", db);
  print(
    "SELECT ID, ID_DIETA, QTD_PREVISTA, QTD_REALIZADA, FINALIZADA, FLAG_SYNC, ID_FAZENDA, IMPORTACAO_ID FROM CADASTRO_FABRICA_RACAO",
    db,
  );
  print("SELECT COUNT(*) AS n FROM DETALHES_FABRICA_RACAO", db);
  print(
    "SELECT ID, ID_BAIA, PREVISTO, REALIZADO, FLAG_SYNC, IMPORTACAO_ID FROM CADASTRO_FORNECIMENTO",
    db,
  );
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
