const fs = require("fs");
const path = require("path");
const config = require("./config");

function envPath() {
  return path.join(__dirname, "..", ".env");
}

function readEnvFile() {
  const p = envPath();
  const out = {};
  if (!fs.existsSync(p)) return out;
  for (const line of fs.readFileSync(p, "utf8").split(/\r?\n/)) {
    const t = line.trim();
    if (!t || t.startsWith("#")) continue;
    const i = t.indexOf("=");
    if (i < 0) continue;
    out[t.slice(0, i).trim()] = t.slice(i + 1).trim();
  }
  return out;
}

function applyRuntime(env) {
  const mode = String(env.SOURCE_MODE || "firebird").toLowerCase();
  config.sourceMode = mode === "horse" ? "horse" : "firebird";
  config.localHorseBase = env.LOCAL_HORSE_URL || config.localHorseBase;
  config.cloudApiBase = config.normalizeCloudApiUrl(
    env.CLOUD_API_URL || config.cloudApiBase,
  );
  if (env.CLIENT_CODE != null && String(env.CLIENT_CODE).trim() !== "") {
    config.clientCode = String(env.CLIENT_CODE).trim().toUpperCase();
  } else if (!config.clientCode) {
    config.clientCode = "DEMO";
  }
  config.adminToken = env.ADMIN_TOKEN != null ? env.ADMIN_TOKEN : config.adminToken;
  config.syncIntervalSec = Number(env.SYNC_INTERVAL_SEC ?? config.syncIntervalSec);
  config.idFazenda = env.ID_FAZENDA != null ? env.ID_FAZENDA : config.idFazenda;
  config.pushMaster = String(env.PUSH_MASTER ?? "1") !== "0";
  config.pullOps = String(env.PULL_OPS ?? "1") !== "0";
  config.replayToLocalHorse = String(env.REPLAY_TO_LOCAL ?? "0") !== "0";
  config.fbHost = env.FB_HOST || config.fbHost;
  config.fbPort = Number(env.FB_PORT || config.fbPort);
  config.fbDatabase = env.FB_DATABASE != null ? env.FB_DATABASE : config.fbDatabase;
  config.fbUser = env.FB_USER || config.fbUser;
  config.fbPassword = env.FB_PASSWORD != null ? env.FB_PASSWORD : config.fbPassword;
  if (env.CONNECTOR_PORT) config.port = Number(env.CONNECTOR_PORT);
}

function getPublicConfig() {
  const env = readEnvFile();
  applyRuntime({ ...env });
  return {
    SOURCE_MODE: config.sourceMode,
    CLOUD_API_URL: config.cloudApiBase,
    CLIENT_CODE: config.clientCode || "DEMO",
    ADMIN_TOKEN: config.adminToken || "open",
    LOCAL_HORSE_URL: config.localHorseBase,
    ID_FAZENDA: config.idFazenda || "",
    SYNC_INTERVAL_SEC: config.syncIntervalSec,
    PUSH_MASTER: config.pushMaster ? "1" : "0",
    PULL_OPS: config.pullOps ? "1" : "0",
    REPLAY_TO_LOCAL: config.replayToLocalHorse ? "1" : "0",
    FB_HOST: config.fbHost,
    FB_PORT: config.fbPort,
    FB_DATABASE: config.fbDatabase,
    FB_USER: config.fbUser,
    FB_PASSWORD: config.fbPassword,
    CONNECTOR_PORT: config.port,
  };
}

function saveConfig(body = {}) {
  const current = getPublicConfig();
  const next = { ...current, ...body };
  // normalize
  next.SOURCE_MODE =
    String(next.SOURCE_MODE || "firebird").toLowerCase() === "horse"
      ? "horse"
      : "firebird";
  next.PUSH_MASTER = String(next.PUSH_MASTER) === "0" ? "0" : "1";
  next.PULL_OPS = String(next.PULL_OPS) === "0" ? "0" : "1";
  next.REPLAY_TO_LOCAL = String(next.REPLAY_TO_LOCAL) === "1" ? "1" : "0";
  next.CLOUD_API_URL = config.normalizeCloudApiUrl(next.CLOUD_API_URL);
  next.CLIENT_CODE = String(next.CLIENT_CODE || "DEMO")
    .trim()
    .toUpperCase();

  const lines = [
    `# Conector FieldPec Online — salvo pelo painel web`,
    `# ${new Date().toISOString()}`,
    `CONNECTOR_PORT=${next.CONNECTOR_PORT}`,
    `SOURCE_MODE=${next.SOURCE_MODE}`,
    ``,
    `# API na AWS`,
    `CLOUD_API_URL=${next.CLOUD_API_URL}`,
    `CLIENT_CODE=${next.CLIENT_CODE}`,
    `ADMIN_TOKEN=${next.ADMIN_TOKEN}`,
    ``,
    `# Firebird FieldPec (maquina do cliente)`,
    `FB_HOST=${next.FB_HOST}`,
    `FB_PORT=${next.FB_PORT}`,
    `FB_DATABASE=${next.FB_DATABASE}`,
    `FB_USER=${next.FB_USER}`,
    `FB_PASSWORD=${next.FB_PASSWORD}`,
    ``,
    `ID_FAZENDA=${next.ID_FAZENDA}`,
    `LOCAL_HORSE_URL=${next.LOCAL_HORSE_URL}`,
    `SYNC_INTERVAL_SEC=${next.SYNC_INTERVAL_SEC}`,
    `PUSH_MASTER=${next.PUSH_MASTER}`,
    `PULL_OPS=${next.PULL_OPS}`,
    `REPLAY_TO_LOCAL=${next.REPLAY_TO_LOCAL}`,
    ``,
  ];
  fs.writeFileSync(envPath(), lines.join("\n"), "utf8");
  applyRuntime(next);
  return getPublicConfig();
}

module.exports = { getPublicConfig, saveConfig, readEnvFile, envPath };
