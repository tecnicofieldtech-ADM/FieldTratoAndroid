const { dumpUi, nodes, tap, sleep, screenshot, list, key, swipeUp } = (() => {
  const { execFileSync } = require("child_process");
  const fs = require("fs");
  const path = require("path");
  const adb =
    process.env.LOCALAPPDATA + "\\Android\\Sdk\\platform-tools\\adb.exe";
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
  function key(c) {
    sh(["shell", "input", "keyevent", String(c)]);
  }
  function swipeUp() {
    sh(["shell", "input", "swipe", "800", "2100", "800", "700", "350"]);
  }
  function screenshot(name) {
    const buf = sh(["exec-out", "screencap", "-p"], { binary: true });
    fs.writeFileSync(path.join(outDir, name), buf);
    console.log("shot", name, buf.length);
  }
  function dumpUi() {
    sh(["shell", "uiautomator", "dump", "/sdcard/ui.xml"]);
    return sh(["exec-out", "cat", "/sdcard/ui.xml"]);
  }
  function nodes(xml) {
    const out = [];
    const re2 = /<node\b([^>]*)>/g;
    let m;
    while ((m = re2.exec(xml))) {
      const a = m[1];
      const get = (k) => {
        const mm = a.match(new RegExp(k + "=\"([^\"]*)\""));
        return mm ? mm[1] : "";
      };
      const b = get("bounds");
      const bm = b.match(/\[(\d+),(\d+)\]\[(\d+),(\d+)\]/);
      if (!bm) continue;
      const x1 = +bm[1],
        y1 = +bm[2],
        x2 = +bm[3],
        y2 = +bm[4];
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
  function list(ns) {
    for (const n of ns) {
      if (n.text || n.hint || n.desc) {
        console.log(
          `${n.cls.split(".").pop()} (${n.x},${n.y}) text=${JSON.stringify(n.text)} hint=${JSON.stringify(n.hint)} desc=${JSON.stringify(n.desc)}`,
        );
      }
    }
  }
  return { dumpUi, nodes, tap, sleep, screenshot, list, key, swipeUp };
})();

function findDesc(ns, re) {
  return ns.find((n) => re.test(n.desc) || re.test(n.text));
}

const step = process.argv[2];

if (step === "select-planilha") {
  tap(411, 795);
  sleep(700);
  screenshot("07_dropdown.png");
  const xml = dumpUi();
  const ns = nodes(xml);
  list(ns);
  const plan = ns.find(
    (n) =>
      (n.desc && n.desc.includes("Planilha") && !n.desc.includes("Homolog")) ||
      n.text === "Planilha",
  );
  if (!plan) {
    console.log("Planilha item not in dump — tapping estimated 3rd item");
    tap(411, 1100);
  } else {
    console.log("tapping Planilha at", plan.x, plan.y, plan.desc || plan.text);
    tap(plan.x, plan.y);
  }
  sleep(600);
  screenshot("08_backend_planilha.png");
} else if (step === "sim-on") {
  tap(800, 1895);
  sleep(400);
  screenshot("09_sim.png");
} else if (step === "dump") {
  list(nodes(dumpUi()));
} else {
  console.log("unknown", step);
}
