const test = require("node:test");
const assert = require("node:assert/strict");
const ExcelJS = require("exceljs");
const { REQUIRED_SHEETS, SHEETS, LAYOUT_VERSION } = require("../src/services/excelLayout");
const { buildTemplateWorkbook, buildTemplateBuffer } = require("../src/services/excelTemplate");
const { validateBuffer, isXlsxName } = require("../src/services/excelImport");
const { buildResultBufferFromData } = require("../src/services/excelExport");

async function bufferFromWorkbook(wb) {
  return Buffer.from(await wb.xlsx.writeBuffer());
}

async function validWorkbook(overrides = {}) {
  const wb = await buildTemplateWorkbook();
  if (overrides.config) {
    const ws = wb.getWorksheet("CONFIGURACAO");
    ws.spliceRows(2, ws.rowCount, ...overrides.config.map((r) => r));
  }
  if (overrides.dropSheet) {
    const ws = wb.getWorksheet(overrides.dropSheet);
    if (ws) wb.removeWorksheet(ws.id);
  }
  if (overrides.dropHeader) {
    const ws = wb.getWorksheet(overrides.dropHeader.sheet);
    const row = ws.getRow(1);
    row.eachCell((cell) => {
      if (String(cell.value).toLowerCase() === overrides.dropHeader.col) {
        cell.value = "outra";
      }
    });
  }
  if (overrides.extraFazenda) {
    wb.getWorksheet("FAZENDAS").addRow(overrides.extraFazenda);
  }
  if (overrides.patch) await overrides.patch(wb);
  return wb;
}

test("template tem abas e colunas do layout", async () => {
  const wb = await buildTemplateWorkbook();
  for (const name of REQUIRED_SHEETS) {
    const ws = wb.getWorksheet(name);
    assert.ok(ws, `aba ${name}`);
    const headers = [];
    ws.getRow(1).eachCell((c) => headers.push(String(c.value)));
    assert.deepEqual(headers, SHEETS[name].headers);
  }
  const buf = await buildTemplateBuffer();
  assert.ok(buf.length > 100);
});

test("extensão xlsx", () => {
  assert.equal(isXlsxName("a.xlsx"), true);
  assert.equal(isXlsxName("a.xls"), false);
});

test("arquivo válido", async () => {
  const buf = await bufferFromWorkbook(await validWorkbook());
  const r = await validateBuffer(buf, { filename: "ok.xlsx" });
  assert.equal(r.success, true, JSON.stringify(r.erros));
  assert.equal(r.config.CLIENTE_CODIGO, "CLIENTE01");
});

test("aba faltando", async () => {
  const buf = await bufferFromWorkbook(await validWorkbook({ dropSheet: "PREVISAO_TRATO" }));
  const r = await validateBuffer(buf, { filename: "x.xlsx" });
  assert.equal(r.success, false);
  assert.ok(r.erros.some((e) => e.aba === "PREVISAO_TRATO"));
});

test("coluna faltando", async () => {
  const buf = await bufferFromWorkbook(
    await validWorkbook({ dropHeader: { sheet: "FAZENDAS", col: "idfazenda" } }),
  );
  const r = await validateBuffer(buf, { filename: "x.xlsx" });
  assert.equal(r.success, false);
  assert.ok(r.erros.some((e) => e.campo === "idfazenda"));
});

test("ID duplicado", async () => {
  const buf = await bufferFromWorkbook(
    await validWorkbook({ extraFazenda: ["F001", "Outra"] }),
  );
  const r = await validateBuffer(buf, { filename: "x.xlsx" });
  assert.equal(r.success, false);
  assert.ok(r.erros.some((e) => /duplicado/i.test(e.mensagem)));
});

test("relacionamento inexistente", async () => {
  const buf = await bufferFromWorkbook(
    await validWorkbook({
      patch: async (wb) => {
        wb.getWorksheet("PREVISAO_TRATO").addRow([
          "FORN002",
          "2026-09-05",
          "B001",
          "1",
          "100",
          "0",
          "D999",
          "F001",
        ]);
      },
    }),
  );
  const r = await validateBuffer(buf, { filename: "x.xlsx" });
  assert.equal(r.success, false);
  assert.ok(r.erros.some((e) => /Dieta 12|D999/.test(e.mensagem)));
});

test("linha inválida (número)", async () => {
  const buf = await bufferFromWorkbook(
    await validWorkbook({
      patch: async (wb) => {
        const ws = wb.getWorksheet("PREVISAO_TRATO");
        ws.getCell("E2").value = "abc";
      },
    }),
  );
  const r = await validateBuffer(buf, { filename: "x.xlsx" });
  assert.equal(r.success, false);
  assert.ok(r.erros.some((e) => e.campo === "previsto_kg"));
});

test("versão incompatível", async () => {
  const buf = await bufferFromWorkbook(
    await validWorkbook({
      patch: async (wb) => {
        const ws = wb.getWorksheet("CONFIGURACAO");
        ws.eachRow((row, n) => {
          if (n === 1) return;
          if (String(row.getCell(1).value).toUpperCase() === "VERSAO_LAYOUT") {
            row.getCell(2).value = 99;
          }
        });
      },
    }),
  );
  const r = await validateBuffer(buf, { filename: "x.xlsx" });
  assert.equal(r.success, false);
  assert.ok(r.erros.some((e) => e.campo === "VERSAO_LAYOUT"));
  assert.equal(LAYOUT_VERSION, 1);
});

test("exportação gera abas", async () => {
  const buf = await buildResultBufferFromData({
    resumoRows: [["Cliente", "CLIENTE01"], ["Peso total fabricado", 1500]],
    fabHeaders: ["id_local", "qtde_realizada"],
    fabRows: [["FAB1", 1500]],
    itemHeaders: ["id_insumo", "qtde_realizada"],
    itemRows: [["I001", 900]],
    fornHeaders: ["id_cadastro", "realizado"],
    fornRows: [["C1", 400]],
    auditRows: [["fabricacao", "{}"]],
  });
  const wb = new ExcelJS.Workbook();
  await wb.xlsx.load(buf);
  for (const name of ["RESUMO", "FABRICACOES", "FABRICACAO_ITENS", "FORNECIMENTOS", "AUDITORIA"]) {
    assert.ok(wb.getWorksheet(name), name);
  }
  assert.equal(wb.getWorksheet("FABRICACOES").getCell("B2").value, 1500);
});
