const test = require("node:test");
const assert = require("node:assert/strict");
const path = require("path");
const crypto = require("crypto");
require("dotenv").config({ path: path.join(__dirname, "..", ".env") });

const { query } = require("../src/db");
const ops = require("../src/services/ops");
const excelImport = require("../src/services/excelImport");
const excelExport = require("../src/services/excelExport");

test("exportação Planilha não usa fallback NULL", () => {
  const fs = require("fs");
  const src = fs.readFileSync(
    path.join(__dirname, "..", "src", "services", "excelExport.js"),
    "utf8",
  );
  assert.doesNotMatch(src, /importacao_id IS NULL/);
  assert.match(src, /importacao_id = \$2/);
});

test("rotas de export exigem cliente e comparam tenant", () => {
  const fs = require("fs");
  const src = fs.readFileSync(
    path.join(__dirname, "..", "src", "routes", "planilha.js"),
    "utf8",
  );
  assert.match(src, /exportar\/:id/);
  assert.match(src, /required: true/);
  assert.match(src, /cliente_codigo/);
  assert.match(src, /404/);
});

const hasDb = !!process.env.DATABASE_URL;

test("Carga A → Carga B: operações permanecem A; export isolado; tenant", async (t) => {
  if (!hasDb) {
    t.skip("DATABASE_URL ausente");
    return;
  }

  const suffix = Date.now().toString(36).toUpperCase().slice(-6);
  const clientA = `HA${suffix}`;
  const clientB = `HB${suffix}`;
  const idA = crypto.randomUUID();
  const idB = crypto.randomUUID();
  const idBOther = crypto.randomUUID();

  async function cleanup() {
    await query(`DELETE FROM fabricacao_itens WHERE fabricacao_id IN (SELECT id FROM fabricacoes WHERE cliente_codigo IN ($1,$2))`, [clientA, clientB]);
    await query(`DELETE FROM fabricacoes WHERE cliente_codigo IN ($1,$2)`, [clientA, clientB]);
    await query(`DELETE FROM fornecimentos WHERE cliente_codigo IN ($1,$2)`, [clientA, clientB]);
    await query(`DELETE FROM planilha_importacoes WHERE cliente_codigo IN ($1,$2)`, [clientA, clientB]);
    await query(`DELETE FROM clientes WHERE codigo IN ($1,$2)`, [clientA, clientB]);
  }

  try {
    await query(
      `INSERT INTO clientes (codigo, nome, ativo) VALUES ($1,$2,TRUE), ($3,$4,TRUE)`,
      [clientA, "Harden A", clientB, "Harden B"],
    );
    await query(
      `INSERT INTO planilha_importacoes (id, cliente_codigo, versao_layout, arquivo_hash, status)
       VALUES ($1,$2,1,'hash-a','ok'), ($3,$2,1,'hash-b','ok'), ($4,$5,1,'hash-bx','ok')`,
      [idA, clientA, idB, idBOther, clientB],
    );
    await excelImport.setActiveImportacaoId(clientA, idA);

    const fabA = await ops.saveFabricacao(clientA, {
      handoff_id: `h-${suffix}-a`,
      id_local: `fab-${suffix}-a`,
      id_fazenda: "FZ_TESTE_001",
      id_dieta: "DIETA_001",
      data: "05/09/2026",
      qtde_prevista: "100",
      qtde_realizada: "100",
      importacao_id: idA,
      itens: [{ id_insumo: "INS_MILHO", qtde_prevista: "100", qtd_realizada: "100" }],
    });
    assert.equal(fabA.success, true);
    assert.equal(fabA.duplicate, undefined);

    const fornA = await ops.saveFornecimento(clientA, {
      id_cadastro: `cad-${suffix}-a`,
      id: "FORN_001",
      id_baia: "BAIA_001",
      trato: "1",
      data: "05/09/2026",
      realizado: "50",
      importacao_id: idA,
    });
    assert.equal(fornA.success, true);

    await excelImport.setActiveImportacaoId(clientA, idB);

    const fabRetry = await ops.saveFabricacao(clientA, {
      handoff_id: `h-${suffix}-a`,
      id_local: `fab-${suffix}-a`,
      importacao_id: idA,
      qtde_realizada: "100",
    });
    assert.equal(fabRetry.duplicate, true);

    const fornRetry = await ops.saveFornecimento(clientA, {
      id_cadastro: `cad-${suffix}-a`,
      importacao_id: idA,
      realizado: "50",
    });
    assert.equal(fornRetry.duplicate, true);

    const { rows: fabs } = await query(
      `SELECT importacao_id::text AS importacao_id FROM fabricacoes
       WHERE cliente_codigo = $1 AND handoff_id = $2`,
      [clientA, `h-${suffix}-a`],
    );
    const { rows: forns } = await query(
      `SELECT importacao_id::text AS importacao_id FROM fornecimentos
       WHERE cliente_codigo = $1 AND id_cadastro = $2`,
      [clientA, `cad-${suffix}-a`],
    );
    assert.equal(fabs.length, 1);
    assert.equal(forns.length, 1);
    assert.equal(fabs[0].importacao_id, idA);
    assert.equal(forns[0].importacao_id, idA);
    assert.notEqual(fabs[0].importacao_id, idB);

    await ops.saveFabricacao(clientA, {
      handoff_id: `h-${suffix}-b`,
      id_local: `fab-${suffix}-b`,
      id_fazenda: "FZ_TESTE_001",
      qtde_realizada: "10",
      importacao_id: idB,
    });

    const dataA = await excelExport.loadResultData(
      await excelImport.getImportacao(idA),
    );
    const dataB = await excelExport.loadResultData(
      await excelImport.getImportacao(idB),
    );
    assert.equal(dataA.fabricacoes.length, 1);
    assert.equal(dataA.fornecimentos.length, 1);
    assert.equal(dataA.itens.length, 1);
    assert.equal(dataB.fabricacoes.length, 1);
    assert.equal(dataB.fornecimentos.length, 0);
    assert.equal(dataA.fabricacoes[0].id_local, `fab-${suffix}-a`);
    assert.equal(dataB.fabricacoes[0].id_local, `fab-${suffix}-b`);

    const expWrong = await excelExport.exportImportacao(idA, {
      clienteCodigo: clientB,
    });
    assert.equal(expWrong, null);

    const expOk = await excelExport.exportImportacao(idA, {
      clienteCodigo: clientA,
    });
    assert.ok(expOk && expOk.buffer && expOk.buffer.length > 100);

    await assert.rejects(
      () => ops.saveFabricacao(clientA, {
        handoff_id: `h-${suffix}-null`,
        qtde_realizada: "1",
      }),
      (e) => e.code === "PLANILHA_IMPORTACAO",
    );

    await assert.rejects(
      () => ops.saveFabricacao(clientA, {
        handoff_id: `h-${suffix}-cross`,
        qtde_realizada: "1",
        importacao_id: idBOther,
      }),
      (e) => e.code === "PLANILHA_IMPORTACAO",
    );

    const listB = await excelImport.listImportacoes(clientB);
    assert.ok(listB.importacoes.every((r) => r.cliente_codigo === clientB));
    assert.ok(!listB.importacoes.some((r) => r.id === idA));
  } finally {
    await cleanup();
  }
});
