const fs = require("fs");
const path = require("path");
const { pool } = require("./db");

async function runSqlFile(filePath, label) {
  if (!fs.existsSync(filePath)) {
    console.warn("Arquivo ausente:", filePath);
    return;
  }
  const sql = fs.readFileSync(filePath, "utf8");
  await pool.query(sql);
  console.log("OK:", label, "→", filePath);
}

async function main() {
  const sqlDir = path.join(__dirname, "..", "..", "sql");
  await runSqlFile(path.join(sqlDir, "schema.sql"), "schema");
  await runSqlFile(path.join(sqlDir, "migrate_tenant.sql"), "migrate_tenant");
  await pool.end();
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
