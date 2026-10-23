require("dotenv").config();

const sourceMode = String(process.env.SOURCE_MODE || "firebird").toLowerCase();

/** Corrige URLs comuns: http://IP/:3111 → http://IP:3111 */
function normalizeCloudApiUrl(raw) {
  let s = String(raw || "").trim().replace(/\/+$/, "");
  if (!s) return "http://127.0.0.1:3111";
  // http://host/:3111  ou  http://host/3111
  s = s.replace(/^(https?:\/\/[^/:]+)\/:(\d+)$/i, "$1:$2");
  s = s.replace(/^(https?:\/\/[^/:]+)\/(\d+)$/i, "$1:$2");
  s = s.replace(/\/+$/, "");
  return s;
}

module.exports = {
  port: Number(process.env.CONNECTOR_PORT || 3080),
  /** firebird = lê .FDB direto (sem Delphi) | horse = usa API Horse local */
  sourceMode: sourceMode === "horse" ? "horse" : "firebird",
  localHorseBase: process.env.LOCAL_HORSE_URL || "http://127.0.0.1:3001",
  cloudApiBase: normalizeCloudApiUrl(
    process.env.CLOUD_API_URL || "http://127.0.0.1:3111",
  ),
  /** Código único do cliente na API multi-tenant (obrigatório) */
  clientCode: String(process.env.CLIENT_CODE || "DEMO")
    .trim()
    .toUpperCase(),
  adminToken: process.env.ADMIN_TOKEN || "open",
  syncIntervalSec: Number(process.env.SYNC_INTERVAL_SEC || 120),
  idFazenda: process.env.ID_FAZENDA || "",
  pushMaster: String(process.env.PUSH_MASTER || "1") !== "0",
  pullOps: String(process.env.PULL_OPS || "1") !== "0",
  // 1 = gravar ops no Field ao Baixar (Firebird se SOURCE_MODE=firebird; Horse se horse)
  replayToLocalHorse: String(process.env.REPLAY_TO_LOCAL || "0") !== "0",

  // Firebird FieldPec
  fbHost: process.env.FB_HOST || "127.0.0.1",
  fbPort: Number(process.env.FB_PORT || 3050),
  fbDatabase: process.env.FB_DATABASE || "",
  fbUser: process.env.FB_USER || "SYSDBA",
  fbPassword: process.env.FB_PASSWORD || "masterkey",

  normalizeCloudApiUrl,
};
