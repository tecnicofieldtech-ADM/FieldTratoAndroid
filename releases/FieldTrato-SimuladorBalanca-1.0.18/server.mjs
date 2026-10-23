#!/usr/bin/env node
/**
 * Simulador TCP da balança PTM AV40/AV50 (e dos outros protocolos do FieldTrato).
 * O tablet conecta no IP deste PC + porta TCP, como se fosse o USR-W610.
 *
 *   node tools/scale_simulator/server.mjs
 *   Painel: http://localhost:8787
 *   TCP padrão: 8899
 */
import http from "http";
import net from "net";
import fs from "fs";
import os from "os";
import path from "path";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const HTTP_PORT = Number(process.env.SCALE_SIM_HTTP || 8787);
const TCP_PORT = Number(process.env.SCALE_SIM_TCP || 8899);

const state = {
  protocol: "ptm",
  kg: 0,
  rampTarget: null,
  rampKgPerSec: 90,
  running: true,
  clients: 0,
};

const sockets = new Set();

function pad(n, w) {
  return String(Math.abs(n)).padStart(w, "0");
}

/** Pacote oficial AV40/AV50: 48 bytes, START 0x02 … STOP 0x03, checksum nibble+0x30. */
function encodePtmAv40Packet(kg) {
  const n = Math.max(-9999, Math.min(99999, Math.round(kg)));
  const buf = Buffer.alloc(48, 0x20);
  buf[0] = 0x02;
  buf[1] = 0x30;
  buf[2] = 0x30;
  Buffer.from("PESO TOTAL".padEnd(16).slice(0, 16)).copy(buf, 3);
  Buffer.from("R001:".padEnd(16).slice(0, 16)).copy(buf, 19);
  buf[35] = 0x20;
  Buffer.from(String(n).padStart(5, " ").slice(0, 5)).copy(buf, 36);
  buf[41] = 0x54; // contexto 'T' (peso total)
  buf[42] = 0x20;
  buf[43] = 0x80;
  buf[44] = 0x80;
  let sum = 0;
  for (let i = 0; i < 45; i++) sum += buf[i];
  const lsb = sum & 0xff;
  buf[45] = 0x30 + ((lsb >> 4) & 0x0f);
  buf[46] = 0x30 + (lsb & 0x0f);
  buf[47] = 0x03;
  return buf;
}

function encodeFrame(kg, protocol) {
  const n = Math.round(kg);
  if (protocol === "ptm") {
    return encodePtmAv40Packet(n);
  }
  if (protocol === "alfa") {
    const field =
      n < 0 ? `0-${String(Math.abs(n)).padStart(3, " ")}` : String(n).padStart(6, " ");
    return Buffer.from(`PB:${field.slice(0, 6)} T: 00000\r\n`);
  }
  if (protocol === "raw" || protocol === "hook") {
    return Buffer.from(`${n}\r\n`);
  }
  const sign = n < 0 ? "-" : "+";
  return Buffer.from(`ST,GS,${sign}${pad(Math.abs(n), 6)}kg\r\n`);
}

function localIps() {
  const out = [];
  for (const list of Object.values(os.networkInterfaces())) {
    for (const i of list || []) {
      if (i.family === "IPv4" && !i.internal) out.push(i.address);
    }
  }
  return out;
}

const tcp = net.createServer((sock) => {
  sockets.add(sock);
  state.clients = sockets.size;
  sock.on("close", () => {
    sockets.delete(sock);
    state.clients = sockets.size;
  });
  sock.on("error", () => {
    sockets.delete(sock);
    state.clients = sockets.size;
  });
});

tcp.listen(TCP_PORT, "0.0.0.0", () => {
  console.log(`TCP balança em 0.0.0.0:${TCP_PORT}`);
  for (const ip of localIps()) {
    console.log(`  FieldTrato → IP ${ip}  porta ${TCP_PORT}  modelo PTM AV40/AV50`);
  }
});

setInterval(() => {
  if (state.rampTarget != null) {
    const step = state.rampKgPerSec * 0.15;
    const diff = state.rampTarget - state.kg;
    if (Math.abs(diff) <= step) {
      state.kg = state.rampTarget;
      state.rampTarget = null;
    } else {
      state.kg += diff > 0 ? step : -step;
    }
  }
  if (!state.running) return;
  const buf = encodeFrame(state.kg, state.protocol);
  for (const s of sockets) {
    try {
      s.write(buf);
    } catch {
      sockets.delete(s);
    }
  }
  state.clients = sockets.size;
}, 150);

function publicFile(name) {
  return fs.readFileSync(path.join(__dirname, "public", name));
}

const httpServer = http.createServer((req, res) => {
  const url = new URL(req.url || "/", `http://${req.headers.host}`);

  if (req.method === "GET" && (url.pathname === "/" || url.pathname === "/index.html")) {
    res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
    res.end(publicFile("index.html"));
    return;
  }

  if (req.method === "GET" && url.pathname === "/api/state") {
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(
      JSON.stringify({
        ...state,
        tcpPort: TCP_PORT,
        ips: localIps(),
      }),
    );
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/state") {
    let body = "";
    req.on("data", (c) => (body += c));
    req.on("end", () => {
      try {
        const j = JSON.parse(body || "{}");
        if (typeof j.kg === "number") {
          state.kg = j.kg;
          state.rampTarget = null;
        }
        if (typeof j.rampTarget === "number" || j.rampTarget === null) {
          state.rampTarget = j.rampTarget;
        }
        if (typeof j.protocol === "string") state.protocol = j.protocol;
        if (typeof j.running === "boolean") state.running = j.running;
        if (typeof j.rampKgPerSec === "number") state.rampKgPerSec = j.rampKgPerSec;
        res.writeHead(200, { "Content-Type": "application/json" });
        res.end(JSON.stringify(state));
      } catch (e) {
        res.writeHead(400, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ error: String(e) }));
      }
    });
    return;
  }

  res.writeHead(404);
  res.end("not found");
});

httpServer.listen(HTTP_PORT, "0.0.0.0", () => {
  console.log(`Painel http://localhost:${HTTP_PORT}`);
});
