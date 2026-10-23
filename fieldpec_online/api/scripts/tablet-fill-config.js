const { execFileSync } = require("child_process");
const fs = require("fs");
const path = require("path");

const adb = process.env.LOCALAPPDATA + "\\Android\\Sdk\\platform-tools\\adb.exe";
const serial = "8pgy69vkhiy58hnb";
const outDir = path.join(__dirname, "..", "..", "homologacao", "fisico");

function sh(args, opts = {}) {
  return execFileSync(adb, ["-s", serial, ...args], {
    encoding: opts.binary ? null : "utf8",
    timeout: opts.timeout || 30000,
    maxBuffer: 20 * 1024 * 1024,
  });
}

function sleep(ms) {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
}

function tap(x, y) {
  sh(["shell", "input", "tap", String(x), String(y)]);
}

function key(code) {
  sh(["shell", "input", "keyevent", String(code)]);
}

function typeText(s) {
  const escaped = String(s)
    .replace(/\\/g, "\\\\")
    .replace(/ /g, "%s")
    .replace(/'/g, "")
    .replace(/\./g, "\\.");
  sh(["shell", "input", "text", escaped]);
}

function screenshot(name) {
  const buf = sh(["exec-out", "screencap", "-p"], { binary: true });
  const p = path.join(outDir, name);
  fs.writeFileSync(p, buf);
  console.log("shot", name, buf.length);
  return p;
}

function focusApp() {
  sh([
    "shell",
    "am",
    "start",
    "-n",
    "com.rfeed.fieldtrato/com.rfeed.rfeedx.MainActivity",
  ]);
  sleep(1500);
}

const step = process.argv[2] || "shot";

if (step === "shot") {
  screenshot(process.argv[3] || "now.png");
} else if (step === "focus") {
  focusApp();
  screenshot(process.argv[3] || "now.png");
} else if (step === "tap") {
  tap(process.argv[3], process.argv[4]);
} else if (step === "key") {
  key(process.argv[3]);
} else if (step === "text") {
  typeText(process.argv.slice(3).join(" "));
} else if (step === "swipe") {
  sh([
    "shell",
    "input",
    "swipe",
    process.argv[3],
    process.argv[4],
    process.argv[5],
    process.argv[6],
    process.argv[7] || "400",
  ]);
} else if (step === "fill-top") {
  focusApp();
  sleep(500);
  screenshot("01_before_fill.png");

  // IP Servidor Dados
  tap(606, 365);
  sleep(400);
  typeText("192.168.15.10");
  sleep(400);
  tap(800, 210); // title to dismiss kb
  sleep(400);
  screenshot("02_host.png");

  // Porta: clear 3001 -> 3111
  tap(1384, 365);
  sleep(400);
  key("123"); // MOVE_END
  for (let i = 0; i < 6; i++) key("67"); // DEL
  typeText("3111");
  sleep(400);
  tap(800, 210);
  sleep(400);
  screenshot("03_porta.png");

  // Código cliente
  tap(800, 540);
  sleep(400);
  typeText("TEST");
  sleep(400);
  tap(800, 210);
  sleep(400);
  screenshot("04_cliente.png");
} else if (step === "backend") {
  tap(411, 795);
  sleep(800);
  screenshot("05_backend_open.png");
} else if (step === "sim") {
  tap(1480, 1895);
  sleep(400);
  screenshot("06_sim.png");
} else {
  console.log("unknown", step);
}
