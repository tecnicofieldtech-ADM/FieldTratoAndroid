const fs = require("fs");
const path = require("path");
const http = require("http");
const ExcelJS = require("exceljs");

const PORT = 3111;
const A = "5217ecc2-f068-4682-9363-25b83f5d57b4";
const B = "5bab78e3-daa3-475d-bbd7-04a6b7f4188f";

function get(urlPath) {
  return new Promise((resolve, reject) => {
    const req = http.request(
      {
        hostname: "127.0.0.1",
        port: PORT,
        path: urlPath,
        method: "GET",
        headers: { "X-Client-Code": "TEST" },
      },
      (res) => {
        const chunks = [];
        res.on("data", (c) => chunks.push(c));
        res.on("end", () =>
          resolve({ status: res.statusCode, buf: Buffer.concat(chunks) }),
        );
      },
    );
    req.on("error", reject);
    req.end();
  });
}

async function summarize(id, label) {
  const r = await get(`/planilha/exportar/${id}`);
  console.log(label, "HTTP", r.status, "bytes", r.buf.length);
  if (r.status !== 200) {
    console.log(r.buf.toString("utf8").slice(0, 400));
    return;
  }
  const out = path.join(
    __dirname,
    "..",
    "..",
    "homologacao",
    "fisico",
    `export_${label}.xlsx`,
  );
  fs.writeFileSync(out, r.buf);
  const wb = new ExcelJS.Workbook();
  await wb.xlsx.load(r.buf);
  for (const ws of wb.worksheets) {
    console.log(`  ${ws.name}: ${Math.max(ws.rowCount - 1, 0)} data rows`);
  }
}

(async () => {
  await summarize(A, "A");
  await summarize(B, "B");
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
