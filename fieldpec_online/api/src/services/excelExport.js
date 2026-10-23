const ExcelJS = require("exceljs");
const { query } = require("../db");
const { getImportacao } = require("./excelImport");

function ymd(v) {
  if (!v) return "";
  if (v instanceof Date) return v.toISOString().slice(0, 10);
  return String(v).slice(0, 10);
}

function addSheet(wb, name, headers, rows) {
  const ws = wb.addWorksheet(name);
  ws.addRow(headers);
  const header = ws.getRow(1);
  header.font = { bold: true, color: { argb: "FFFFFFFF" } };
  header.fill = {
    type: "pattern",
    pattern: "solid",
    fgColor: { argb: "FF25A7CF" },
  };
  for (const row of rows) ws.addRow(row);
  headers.forEach((h, i) => {
    ws.getColumn(i + 1).width = Math.max(14, String(h).length + 3);
  });
  return ws;
}

async function loadResultData(importacao) {
  // Operações Planilha: somente as da carga. Registros antigos com
  // importacao_id NULL não entram em nenhuma exportação (sem fallback).
  const cc = importacao.cliente_codigo;
  const id = importacao.id;

  const faz = await query(
    `SELECT idfazenda, fazenda FROM fazendas WHERE cliente_codigo = $1`,
    [cc],
  );
  const fabs = await query(
    `SELECT id, id_local, handoff_id, id_fazenda, id_dieta, data_fab,
            id_usuario, id_operador, id_vagao, qtde_prevista, qtde_realizada,
            ms_prevista, ms_realizada, hora_inicio, hora_fim, created_at, payload
     FROM fabricacoes
     WHERE cliente_codigo = $1
       AND importacao_id = $2
     ORDER BY id`,
    [cc, id],
  );
  const itens = await query(
    `SELECT i.fabricacao_id, i.id_local, i.id_insumo, i.qtde_prevista, i.qtde_realizada,
            i.ms_insumo, i.hora_ini, i.hora_fim, f.id_local AS fab_id_local
     FROM fabricacao_itens i
     JOIN fabricacoes f ON f.id = i.fabricacao_id
     WHERE f.cliente_codigo = $1
       AND f.importacao_id = $2
     ORDER BY i.fabricacao_id, i.id`,
    [cc, id],
  );
  const forns = await query(
    `SELECT id, id_cadastro, id_fornecimento, id_fabricacao_local, id_baia, id_racao,
            data_forn, trato, realizado, ms_dieta_realizada, id_usuario_lancamento,
            id_tratador, id_dieta_realizada, hora_inicio, hora_fim,
            peso_inicio, peso_fim, created_at, payload
     FROM fornecimentos
     WHERE cliente_codigo = $1
       AND importacao_id = $2
     ORDER BY id`,
    [cc, id],
  );
  const audits = await query(
    `SELECT tipo, payload, created_at FROM audits
     WHERE cliente_codigo = $1 ORDER BY id`,
    [cc],
  );

  const pesoFab = fabs.rows.reduce(
    (s, r) => s + Number(r.qtde_realizada || 0),
    0,
  );
  const pesoForn = forns.rows.reduce(
    (s, r) => s + Number(r.realizado || 0),
    0,
  );
  const datas = forns.rows
    .map((r) => ymd(r.data_forn))
    .filter(Boolean)
    .sort();

  return {
    fazendas: faz.rows,
    fabricacoes: fabs.rows,
    itens: itens.rows,
    fornecimentos: forns.rows,
    audits: audits.rows,
    resumo: {
      cliente: cc,
      fazenda: importacao.fazenda_codigo || (faz.rows[0] && faz.rows[0].fazenda) || "",
      importacao: id,
      data_importacao: importacao.created_at,
      data_inicial: datas[0] || "",
      data_final: datas[datas.length - 1] || "",
      qtd_fabricacoes: fabs.rows.length,
      qtd_fornecimentos: forns.rows.length,
      peso_fabricado: pesoFab,
      peso_fornecido: pesoForn,
    },
  };
}

async function buildResultWorkbook(importacao) {
  const data = await loadResultData(importacao);
  const wb = new ExcelJS.Workbook();
  wb.creator = "FieldTrato";
  wb.created = new Date();

  const r = data.resumo;
  addSheet(
    wb,
    "RESUMO",
    ["CHAVE", "VALOR"],
    [
      ["Cliente", r.cliente],
      ["Fazenda", r.fazenda],
      ["Importacao", r.importacao],
      ["Data da importacao", r.data_importacao],
      ["Data inicial das operacoes", r.data_inicial],
      ["Data final das operacoes", r.data_final],
      ["Quantidade de fabricacoes", r.qtd_fabricacoes],
      ["Quantidade de fornecimentos", r.qtd_fornecimentos],
      ["Peso total fabricado", r.peso_fabricado],
      ["Peso total fornecido", r.peso_fornecido],
    ],
  );

  addSheet(
    wb,
    "FABRICACOES",
    [
      "id_servidor",
      "id_local",
      "handoff_id",
      "id_fazenda",
      "id_dieta",
      "data",
      "id_usuario",
      "id_operador",
      "id_vagao",
      "qtde_prevista",
      "qtde_realizada",
      "ms_prevista",
      "ms_realizada",
      "hora_inicio",
      "hora_fim",
    ],
    data.fabricacoes.map((f) => [
      f.id,
      f.id_local,
      f.handoff_id,
      f.id_fazenda,
      f.id_dieta,
      ymd(f.data_fab),
      f.id_usuario,
      f.id_operador,
      f.id_vagao,
      f.qtde_prevista,
      f.qtde_realizada,
      f.ms_prevista,
      f.ms_realizada,
      f.hora_inicio,
      f.hora_fim,
    ]),
  );

  addSheet(
    wb,
    "FABRICACAO_ITENS",
    [
      "id_fabricacao_local",
      "id_local",
      "id_insumo",
      "qtde_prevista",
      "qtde_realizada",
      "ms_insumo",
      "hora_inicio",
      "hora_fim",
    ],
    data.itens.map((i) => [
      i.fab_id_local,
      i.id_local,
      i.id_insumo,
      i.qtde_prevista,
      i.qtde_realizada,
      i.ms_insumo,
      i.hora_ini,
      i.hora_fim,
    ]),
  );

  addSheet(
    wb,
    "FORNECIMENTOS",
    [
      "id_cadastro",
      "id_fornecimento",
      "id_fabricacao",
      "data",
      "hora_inicio",
      "hora_fim",
      "id_baia",
      "id_dieta",
      "trato",
      "previsto",
      "realizado",
      "peso_inicio",
      "peso_fim",
      "id_usuario",
    ],
    data.fornecimentos.map((f) => {
      const payload = f.payload && typeof f.payload === "object" ? f.payload : {};
      return [
        f.id_cadastro,
        f.id_fornecimento,
        f.id_fabricacao_local,
        ymd(f.data_forn),
        f.hora_inicio,
        f.hora_fim,
        f.id_baia,
        f.id_dieta_realizada || f.id_racao,
        f.trato,
        payload.previsto || "",
        f.realizado,
        f.peso_inicio,
        f.peso_fim,
        f.id_usuario_lancamento || f.id_tratador,
      ];
    }),
  );

  addSheet(
    wb,
    "AUDITORIA",
    ["tipo", "created_at", "payload"],
    data.audits.map((a) => [
      a.tipo,
      a.created_at,
      JSON.stringify(a.payload || {}),
    ]),
  );

  return wb;
}

async function buildResultBufferFromData(data) {
  const wb = new ExcelJS.Workbook();
  addSheet(wb, "RESUMO", ["CHAVE", "VALOR"], data.resumoRows || []);
  addSheet(wb, "FABRICACOES", data.fabHeaders || ["id"], data.fabRows || []);
  addSheet(wb, "FABRICACAO_ITENS", data.itemHeaders || ["id"], data.itemRows || []);
  addSheet(wb, "FORNECIMENTOS", data.fornHeaders || ["id"], data.fornRows || []);
  addSheet(wb, "AUDITORIA", ["tipo", "payload"], data.auditRows || []);
  return Buffer.from(await wb.xlsx.writeBuffer());
}

async function exportImportacao(id, { clienteCodigo } = {}) {
  const imp = await getImportacao(id);
  if (!imp) return null;
  const cc = String(clienteCodigo || "").trim().toUpperCase();
  if (!cc) return { missingClient: true };
  if (String(imp.cliente_codigo || "").toUpperCase() !== cc) return null;
  const wb = await buildResultWorkbook(imp);
  const buf = Buffer.from(await wb.xlsx.writeBuffer());
  const fname = `FieldTrato_Resultado_${imp.id}.xlsx`;
  return { buffer: buf, filename: fname, importacao: imp };
}

module.exports = {
  exportImportacao,
  buildResultWorkbook,
  buildResultBufferFromData,
  loadResultData,
};
