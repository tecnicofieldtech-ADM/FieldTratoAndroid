const { execFileSync } = require("child_process");
const fs = require("fs");
const path = require("path");

const adb = process.env.LOCALAPPDATA + "\\Android\\Sdk\\platform-tools\\adb.exe";
const serial = "8pgy69vkhiy58hnb";
const dumpPath = path.join(__dirname, "..", "..", "homologacao", "fisico", "ui.xml");

function adbSh(args, opts = {}) {
  return execFileSync(adb, ["-s", serial, ...args], {
    encoding: opts.encoding || "utf8",
    stdio: opts.stdio,
    timeout: opts.timeout || 20000,
  });
}

function dumpUi() {
  adbSh(["shell", "uiautomator", "dump", "/sdcard/ui.xml"]);
  const xml = adbSh(["exec-out", "cat", "/sdcard/ui.xml"]);
  fs.writeFileSync(dumpPath, xml);
  return xml;
}

function nodes(xml) {
  const out = [];
  const re = /<node\b([^>]*)\/?>(?=\s*(?:<|$))/g;
  let m;
  const xml2 = xml.replace(/\/>/g, "></node>");
  const re2 = /<node\b([^>]*)>/g;
  while ((m = re2.exec(xml2))) {
    const a = m[1];
    const get = (k) => {
      const mm = a.match(new RegExp(k + "=\"([^\"]*)\""));
      return mm ? mm[1] : "";
    };
    const b = get("bounds");
    const bm = b.match(/\[(\d+),(\d+)\]\[(\d+),(\d+)\]/);
    if (!bm) continue;
    const x1 = +bm[1], y1 = +bm[2], x2 = +bm[3], y2 = +bm[4];
    out.push({
      text: get("text"),
      hint: get("hint"),
      desc: get("content-desc"),
      cls: get("class"),
      clickable: get("clickable") === "true",
      x: Math.floor((x1 + x2) / 2),
      y: Math.floor((y1 + y2) / 2),
      bounds: b,
    });
  }
  return out;
}

function find(list, pred) {
  return list.find(pred);
}

function tap(x, y) {
  adbSh(["shell", "input", "tap", String(x), String(y)]);
}

function text(s) {
  const escaped = String(s).replace(/ /g, "%s").replace(/'/g, "");
  adbSh(["shell", "input", "text", escaped]);
}

function key(code) {
  adbSh(["shell", "input", "keyevent", String(code)]);
}

function swipeUp() {
  adbSh(["shell", "input", "swipe", "800", "2000", "800", "700", "400"]);
}

const cmd = process.argv[2] || "dump";
if (cmd === "dump") {
  const xml = dumpUi();
  const ns = nodes(xml);
  for (const n of ns) {
    if (n.text || n.hint || n.desc || n.clickable) {
      console.log(`${n.cls.split(".").pop()} click=${n.clickable} (${n.x},${n.y}) ${n.bounds} text=${JSON.stringify(n.text)} hint=${JSON.stringify(n.hint)} desc=${JSON.stringify(n.desc)}`);
    }
  }
} else if (cmd === "tap") {
  tap(process.argv[3], process.argv[4]);
} else if (cmd === "text") {
  text(process.argv.slice(3).join(" "));
} else if (cmd === "key") {
  key(process.argv[3]);
} else if (cmd === "swipe") {
  swipeUp();
} else if (cmd === "start") {
  adbSh(["shell", "am", "start", "-n", "com.rfeed.fieldtrato/com.rfeed.rfeedx.MainActivity"]);
} else {
  console.log("unknown", cmd);
}

module.exports = { dumpUi, nodes, find, tap, text, key, swipeUp, adbSh };
