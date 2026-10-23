const fs = require("fs");
const path = require("path");
const http = require("http");

const PORT = Number(process.env.PORT || 3111);
const CLIENT = "TEST";
const file = path.join(
  __dirname,
  "..",
  "..",
  "homologacao",
  "fisico",
  "FieldTrato_Fisico_CargaB.xlsx",
);

function request(method, urlPath, { headers = {}, raw } = {}) {
  return new Promise((resolve, reject) => {
    const u = new URL(`http://127.0.0.1:${PORT}${urlPath}`);
    const req = http.request(
      {
        hostname: u.hostname,
        port: u.port,
        path: u.pathname + u.search,
        method,
        headers,
      },
      (res) => {
        const chunks = [];
        res.on("data", (c) => chunks.push(c));
        res.on("end", () => {
          const buf = Buffer.concat(chunks);
          let json = null;
          try {
            json = JSON.parse(buf.toString("utf8"));
          } catch (_) {}
          resolve({ status: res.statusCode, json });
        });
      },
    );
    req.on("error", reject);
    if (raw) req.write(raw);
    req.end();
  });
}

(async () => {
  const fileBuf = fs.readFileSync(file);
  const boundary = "----FisicoBoundaryB";
  const head =
    `--${boundary}\r\n` +
    `Content-Disposition: form-data; name="file"; filename="FieldTrato_Fisico_CargaB.xlsx"\r\n` +
    `Content-Type: application/vnd.openxmlformats-officedocument.spreadsheetml.sheet\r\n\r\n`;
  const tail = `\r\n--${boundary}--\r\n`;
  const raw = Buffer.concat([Buffer.from(head), fileBuf, Buffer.from(tail)]);
  const imp = await request("POST", "/planilha/importar", {
    raw,
    headers: {
      "Content-Type": `multipart/form-data; boundary=${boundary}`,
      "Content-Length": String(raw.length),
      "X-Client-Code": CLIENT,
    },
  });
  console.log("import status", imp.status);
  console.log(JSON.stringify(imp.json, null, 2));
  const t = await request("GET", "/GetTeste", {
    headers: { "X-Client-Code": CLIENT },
  });
  console.log("GetTeste", t.status, JSON.stringify(t.json));
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
