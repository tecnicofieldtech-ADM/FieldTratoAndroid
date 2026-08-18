require("dotenv").config();

const rawToken = process.env.ADMIN_TOKEN;
// Vazio / "open" / "none" / "false" = API admin aberta (sem Bearer)
const adminToken =
  rawToken == null ||
  String(rawToken).trim() === "" ||
  ["open", "none", "false", "0", "off"].includes(
    String(rawToken).trim().toLowerCase(),
  )
    ? ""
    : String(rawToken).trim();

module.exports = {
  port: Number(process.env.PORT || 3001),
  host: process.env.HOST || "0.0.0.0",
  databaseUrl:
    process.env.DATABASE_URL ||
    "postgres://postgres@127.0.0.1:5432/postgres",
  adminToken,
  adminOpen: adminToken === "",

  /** API GeLicenca — valida código do cliente no cadastro */
  licenseApiBase: String(
    process.env.LICENSE_API_URL || "http://15.229.92.98:8888",
  ).replace(/\/+$/, ""),
  licenseUser: process.env.LICENSE_API_USER || "fuelmanage",
  licensePassword: process.env.LICENSE_API_PASSWORD || "991528798",
  /** Sempre 1 = FIELD PEC */
  licenseSistemaId: String(process.env.LICENSE_SISTEMA_ID || "1"),
  /** Se 1, cadastro/uso valida na API de licença */
  licenseValidate:
    String(process.env.LICENSE_VALIDATE || "1").trim() !== "0",
};
