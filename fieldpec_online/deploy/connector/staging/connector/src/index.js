const path = require("path");
const Fastify = require("fastify");
const fastifyStatic = require("@fastify/static");
const formbody = require("@fastify/formbody");
const config = require("./config");
const sync = require("./sync");
const settings = require("./settings");
const humanLog = require("./humanLog");

let lastSync = null;
let lastPush = null;
let lastPull = null;
let lastHumanLog = "";
let running = false;
let timer = null;

function scheduleTimer() {
  if (timer) {
    clearInterval(timer);
    timer = null;
  }
  if (config.syncIntervalSec > 0) {
    timer = setInterval(() => {
      doFull("interval").catch((e) => console.error(e));
    }, config.syncIntervalSec * 1000);
  }
}

async function withLock(fn) {
  if (running) return { skipped: true, reason: "already_running" };
  running = true;
  try {
    return await fn();
  } finally {
    running = false;
  }
}

async function doFull(trigger) {
  return withLock(async () => {
    lastSync = await sync.runFullSync();
    lastSync.trigger = trigger;
    if (lastSync.push) lastPush = lastSync.push;
    if (lastSync.pull) lastPull = lastSync.pull;
    lastHumanLog = humanLog.appendHumanLog("full", lastSync);
    return { ...lastSync, human_log: lastHumanLog, log_file: humanLog.logPath() };
  });
}

async function doPush(trigger) {
  return withLock(async () => {
    const started = new Date().toISOString();
    try {
      lastPush = await sync.pushMasterFromLocal();
      lastPush.trigger = trigger;
      lastPush.started = started;
      lastPush.finished = new Date().toISOString();
      lastHumanLog = humanLog.appendHumanLog("push", lastPush);
      return {
        ok: true,
        ...lastPush,
        human_log: lastHumanLog,
        log_file: humanLog.logPath(),
      };
    } catch (e) {
      lastPush = { ok: false, error: e.message, trigger, started };
      lastHumanLog = humanLog.appendHumanLog("push", lastPush);
      return { ...lastPush, human_log: lastHumanLog };
    }
  });
}

async function doPull(trigger) {
  return withLock(async () => {
    const started = new Date().toISOString();
    try {
      lastPull = await sync.pullOpsToLocal();
      lastPull.trigger = trigger;
      lastPull.started = started;
      lastPull.finished = new Date().toISOString();
      lastHumanLog = humanLog.appendHumanLog("pull", lastPull);
      return {
        ok: true,
        ...lastPull,
        human_log: lastHumanLog,
        log_file: humanLog.logPath(),
      };
    } catch (e) {
      lastPull = { ok: false, error: e.message, trigger, started };
      lastHumanLog = humanLog.appendHumanLog("pull", lastPull);
      return { ...lastPull, human_log: lastHumanLog };
    }
  });
}

async function main() {
  // carrega .env salvo pelo painel
  settings.getPublicConfig();

  const app = Fastify({ logger: true });
  await app.register(formbody);
  await app.register(fastifyStatic, {
    root: path.join(__dirname, "..", "public"),
    prefix: "/",
  });

  app.get("/api/status", async () => ({
    config: settings.getPublicConfig(),
    running,
    lastSync,
    lastPush,
    lastPull,
    last_human_log: lastHumanLog,
    log_file: humanLog.logPath(),
  }));

  app.get("/api/config", async () => settings.getPublicConfig());

  app.post("/api/config", async (req, reply) => {
    try {
      const saved = settings.saveConfig(req.body || {});
      scheduleTimer();
      return { success: true, config: saved };
    } catch (e) {
      return reply.code(500).send({ success: false, error: e.message });
    }
  });

  app.get("/api/probe", async () => sync.probe());
  app.get("/api/stats", async () => {
    try {
      return await sync.cloudStats();
    } catch (e) {
      return { error: e.message };
    }
  });

  app.get("/api/ops", async (req) => {
    try {
      const status = (req.query && req.query.status) || "all";
      const limit = (req.query && req.query.limit) || 100;
      return await sync.listCloudOps({ status, limit });
    } catch (e) {
      return { success: false, error: e.message };
    }
  });

  app.post("/api/sync", async () => doFull("manual"));
  app.post("/api/sync/push", async () => doPush("manual"));
  app.post("/api/sync/pull", async () => doPull("manual"));

  await app.listen({ port: config.port, host: "0.0.0.0" });
  app.log.info(`Conector web: http://0.0.0.0:${config.port}`);
  app.log.info(`Modo: ${config.sourceMode} → nuvem ${config.cloudApiBase}`);

  scheduleTimer();
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
