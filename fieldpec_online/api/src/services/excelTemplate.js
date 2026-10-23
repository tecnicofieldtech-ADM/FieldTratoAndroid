const ExcelJS = require("exceljs");
const { LAYOUT_VERSION, SHEETS, REQUIRED_SHEETS } = require("./excelLayout");

async function buildTemplateWorkbook() {
  const wb = new ExcelJS.Workbook();
  wb.creator = "FieldTrato";
  wb.created = new Date();
  wb.properties.date1904 = false;

  for (const name of REQUIRED_SHEETS) {
    const spec = SHEETS[name];
    const ws = wb.addWorksheet(name);
    ws.addRow(spec.headers);
    const header = ws.getRow(1);
    header.font = { bold: true };
    header.fill = {
      type: "pattern",
      pattern: "solid",
      fgColor: { argb: "FF25A7CF" },
    };
    header.font = { bold: true, color: { argb: "FFFFFFFF" } };
    for (const row of spec.example || []) {
      ws.addRow(row);
    }
    spec.headers.forEach((_, i) => {
      ws.getColumn(i + 1).width = Math.max(14, String(spec.headers[i]).length + 4);
    });
  }

  const meta = wb.getWorksheet("CONFIGURACAO");
  if (meta) {
    meta.getCell("A1").note = `VERSAO_LAYOUT obrigatória = ${LAYOUT_VERSION}`;
  }
  return wb;
}

async function buildTemplateBuffer() {
  const wb = await buildTemplateWorkbook();
  return Buffer.from(await wb.xlsx.writeBuffer());
}

module.exports = { buildTemplateWorkbook, buildTemplateBuffer };
