const { query } = require("../db");
const { pickStr, toNum, parseDate } = require("../util/numbers");

function requireTenant(clienteCodigo) {
  const c = String(clienteCodigo || "").trim().toUpperCase();
  if (!c) throw new Error("cliente_codigo obrigatório");
  return c;
}

async function saveFabricacao(clienteCodigo, body = {}) {
  const cc = requireTenant(clienteCodigo);
  const idLocal = pickStr(body, ["id_local", "id", "ID"]);
  const handoffId = pickStr(body, ["handoff_id", "HANDOFF_ID"]);
  const idFazenda = pickStr(body, [
    "id_fazenda",
    "ID_PROPRIEDADE",
    "id_propriedade",
    "ID_FAZENDA",
  ]);
  const idDieta = pickStr(body, ["id_dieta", "ID_DIETA"]);
  const dataFab = parseDate(pickStr(body, ["data", "DATA", "data_fabricacao"]));
  const lote = pickStr(body, ["lote_fabricacao", "LOTE_FABRICACAO"]);

  if (handoffId) {
    const existing = await query(
      `SELECT id FROM fabricacoes
       WHERE cliente_codigo = $1 AND handoff_id = $2 LIMIT 1`,
      [cc, handoffId],
    );
    if (existing.rows[0]) {
      return {
        success: true,
        id_local: idLocal,
        handoff_id: handoffId,
        id_servidor: existing.rows[0].id,
        lote_fabricacao: lote,
        itens_processados: 0,
        fornecimentos_processados: 0,
        duplicate: true,
        cliente_codigo: cc,
      };
    }
  }

  const ins = await query(
    `INSERT INTO fabricacoes (
       cliente_codigo, id_local, handoff_id, id_fazenda, id_dieta, data_fab,
       id_usuario, id_operador, id_vagao, qtde_prevista, qtde_realizada,
       ms_prevista, ms_realizada, hora_inicio, hora_fim, lote_fabricacao, payload
     ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17)
     RETURNING id`,
    [
      cc,
      idLocal || null,
      handoffId || null,
      idFazenda || null,
      idDieta || null,
      dataFab,
      pickStr(body, ["id_usuario", "ID_USUARIO"]) || null,
      pickStr(body, ["id_operador", "ID_OPERADOR"]) || null,
      pickStr(body, ["id_vagao", "ID_VAGAO"]) || null,
      toNum(pickStr(body, ["qtde_prevista", "QTDE_PREVISTA"])),
      toNum(pickStr(body, ["qtde_realizada", "QTDE_REALIZADA"])),
      toNum(pickStr(body, ["ms_prevista", "MS_PREVISTA"])),
      toNum(pickStr(body, ["ms_realizada", "MS_REALIZADA"])),
      pickStr(body, ["hora_inicio", "HORA_INICIO"]) || null,
      pickStr(body, ["hora_fim", "HORA_FIM"]) || null,
      lote || null,
      JSON.stringify({ ...body, cliente_codigo: cc }),
    ],
  );
  const fabId = ins.rows[0].id;

  const itens = Array.isArray(body.itens) ? body.itens : [];
  let itensProcessados = 0;
  for (const item of itens) {
    await query(
      `INSERT INTO fabricacao_itens (
         fabricacao_id, id_local, id_insumo, qtde_prevista, qtde_realizada,
         ms_insumo, hora_ini, hora_fim, payload
       ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)`,
      [
        fabId,
        pickStr(item, ["id_local", "id", "ID"]) || null,
        pickStr(item, ["id_insumo", "ID_INSUMO"]) || null,
        toNum(pickStr(item, ["qtde_prevista", "QTDE_PREVISTA"])),
        toNum(pickStr(item, ["qtd_realizada", "qtde_realizada", "QTDE_REALIZADA"])),
        toNum(pickStr(item, ["ms_insumo", "MS_INSUMO"])),
        pickStr(item, ["hora_ini", "HORA_INI", "hora_inicio"]) || null,
        pickStr(item, ["hora_fim", "HORA_FIM"]) || null,
        JSON.stringify(item),
      ],
    );
    itensProcessados++;
  }

  const fornecimentos = Array.isArray(body.fornecimentos) ? body.fornecimentos : [];
  let fornProcessados = 0;
  for (const f of fornecimentos) {
    await saveFornecimento(cc, {
      ...f,
      id_fabricacao: idLocal || f.id_fabricacao,
      handoff_id_fabricacao: handoffId || f.handoff_id_fabricacao,
    });
    fornProcessados++;
  }

  return {
    success: true,
    id_local: idLocal,
    handoff_id: handoffId,
    id_servidor: fabId,
    lote_fabricacao: lote,
    itens_processados: itensProcessados,
    fornecimentos_processados: fornProcessados,
    cliente_codigo: cc,
  };
}

async function saveFornecimento(clienteCodigo, body = {}) {
  const cc = requireTenant(clienteCodigo);
  const idForn = pickStr(body, ["id", "ID", "id_fornecimento", "ID_FORNECIMENTO"]);
  const dataForn = parseDate(
    pickStr(body, ["data", "DATA", "DATA_FORN", "data_forn"]),
  );
  const trato = Math.trunc(toNum(pickStr(body, ["trato", "TRATO"])));
  const idBaia = pickStr(body, ["id_baia", "ID_BAIA", "IDCURRAL", "idcurral"]);

  if (idForn && dataForn && trato > 0) {
    const ex = await query(
      `SELECT id FROM fornecimentos
       WHERE cliente_codigo = $1
         AND id_fornecimento = $2 AND data_forn = $3 AND trato = $4
         AND coalesce(id_baia,'') = coalesce($5,'')
       LIMIT 1`,
      [cc, idForn, dataForn, trato, idBaia || null],
    );
    if (ex.rows[0]) {
      return { success: true, id: ex.rows[0].id, duplicate: true, cliente_codigo: cc };
    }
  }

  const ins = await query(
    `INSERT INTO fornecimentos (
       cliente_codigo, id_fornecimento, id_fabricacao_local, handoff_id_fabricacao,
       id_baia, id_racao, data_forn, trato, realizado, ms_dieta_realizada,
       id_usuario_lancamento, id_tratador, id_dieta_realizada, hora_inicio,
       hora_fim, lote_fabricacao, payload
     ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17)
     RETURNING id`,
    [
      cc,
      idForn || null,
      pickStr(body, ["id_fabricacao", "ID_FABRICACAO"]) || null,
      pickStr(body, ["handoff_id_fabricacao", "HANDOFF_ID_FABRICACAO"]) || null,
      idBaia || null,
      pickStr(body, ["id_racao", "ID_RACAO", "id_dieta"]) || null,
      dataForn,
      trato || null,
      toNum(pickStr(body, ["realizado", "REALIZADO"])),
      toNum(pickStr(body, ["ms_dieta_realizada", "MS_DIETA_REALIZADA"])),
      pickStr(body, ["id_usuario_lancamento", "ID_USUARIO_LANCAMENTO"]) || null,
      pickStr(body, ["id_tratador", "ID_TRATADOR"]) || null,
      pickStr(body, ["id_dieta_realizada", "ID_DIETA_REALIZADA"]) || null,
      pickStr(body, ["hora_inicio", "HORA_INICIO"]) || null,
      pickStr(body, ["hora_fim", "HORA_FIM"]) || null,
      pickStr(body, ["lote_fabricacao", "CFORN_LOTE_FABRICACAO"]) || null,
      JSON.stringify({ ...body, cliente_codigo: cc }),
    ],
  );

  if (idForn && dataForn && idBaia && trato > 0) {
    await query(
      `UPDATE previsao_trato SET realizado = $1, updated_at = now()
       WHERE cliente_codigo = $2 AND id_fornecimento = $3 AND data = $4
         AND id_baia = $5 AND trato = $6`,
      [
        toNum(pickStr(body, ["realizado", "REALIZADO"])),
        cc,
        idForn,
        dataForn,
        idBaia,
        trato,
      ],
    );
  }

  return { success: true, id: ins.rows[0].id, cliente_codigo: cc };
}

async function saveGravaTag(clienteCodigo, body) {
  const cc = requireTenant(clienteCodigo);
  await query(`INSERT INTO grava_tags (cliente_codigo, payload) VALUES ($1,$2)`, [
    cc,
    JSON.stringify(body || {}),
  ]);
  return { success: true, cliente_codigo: cc };
}

async function saveAudit(clienteCodigo, tipo, body) {
  const cc = requireTenant(clienteCodigo);
  await query(`INSERT INTO audits (cliente_codigo, tipo, payload) VALUES ($1,$2,$3)`, [
    cc,
    tipo,
    JSON.stringify(body || {}),
  ]);
  return { success: true, cliente_codigo: cc };
}

async function saveGps(clienteCodigo, body) {
  const cc = requireTenant(clienteCodigo);
  await query(`INSERT INTO gps_tracks (cliente_codigo, payload) VALUES ($1,$2)`, [
    cc,
    JSON.stringify(body || {}),
  ]);
  return { success: true, cliente_codigo: cc };
}

async function listPendingOps(clienteCodigo) {
  const data = await listOps(clienteCodigo, { status: "pending", limit: 200 });
  // Compatível com conector antigo: payload com itens embutidos
  return {
    cliente_codigo: data.cliente_codigo,
    fabricacoes: data.fabricacoes.map((f) => ({
      id: f.id,
      id_local: f.id_local,
      handoff_id: f.handoff_id,
      created_at: f.created_at,
      payload: {
        ...(typeof f.payload === "object" && f.payload ? f.payload : {}),
        itens: f.itens || [],
      },
    })),
    fornecimentos: data.fornecimentos.map((f) => ({
      id: f.id,
      id_fornecimento: f.id_fornecimento,
      created_at: f.created_at,
      payload: f.payload,
    })),
  };
}

/**
 * Lista fab/forn do cliente com filtro de status.
 * status: pending | done | all
 */
async function listOps(clienteCodigo, { status = "all", limit = 100 } = {}) {
  const cc = requireTenant(clienteCodigo);
  const lim = Math.min(Math.max(Number(limit) || 100, 1), 500);
  const st = String(status || "all").toLowerCase();
  let pullSql = "";
  if (st === "pending" || st === "pendente") {
    pullSql = " AND pulled_to_fieldpec = FALSE";
  } else if (st === "done" || st === "pulled" || st === "baixado") {
    pullSql = " AND pulled_to_fieldpec = TRUE";
  }

  const fabs = await query(
    `SELECT id, id_local, handoff_id, id_fazenda, id_dieta, data_fab,
            qtde_prevista, qtde_realizada, lote_fabricacao, payload,
            pulled_to_fieldpec, pulled_at, created_at
     FROM fabricacoes
     WHERE cliente_codigo = $1${pullSql}
     ORDER BY id DESC
     LIMIT $2`,
    [cc, lim],
  );

  const fabIds = fabs.rows.map((r) => r.id);
  const itensByFab = new Map();
  if (fabIds.length) {
    const itens = await query(
      `SELECT fabricacao_id, id_local, id_insumo, qtde_prevista, qtde_realizada,
              ms_insumo, hora_ini, hora_fim, payload
       FROM fabricacao_itens
       WHERE fabricacao_id = ANY($1::bigint[])
       ORDER BY id ASC`,
      [fabIds],
    );
    for (const it of itens.rows) {
      if (!itensByFab.has(it.fabricacao_id)) itensByFab.set(it.fabricacao_id, []);
      const fromPayload =
        it.payload && typeof it.payload === "object" ? it.payload : {};
      itensByFab.get(it.fabricacao_id).push({
        id_local: it.id_local,
        id_insumo: it.id_insumo,
        qtde_prevista: it.qtde_prevista,
        qtde_realizada: it.qtde_realizada,
        ms_insumo: it.ms_insumo,
        hora_ini: it.hora_ini,
        hora_fim: it.hora_fim,
        ...fromPayload,
      });
    }
  }

  const forns = await query(
    `SELECT id, id_fornecimento, id_fabricacao_local, handoff_id_fabricacao,
            id_baia, id_racao, data_forn, trato, realizado, lote_fabricacao,
            payload, pulled_to_fieldpec, pulled_at, created_at
     FROM fornecimentos
     WHERE cliente_codigo = $1${pullSql}
     ORDER BY id DESC
     LIMIT $2`,
    [cc, lim],
  );

  const [fabPend, fabDone, fornPend, fornDone] = await Promise.all([
    query(
      `SELECT count(*)::int AS n FROM fabricacoes
       WHERE cliente_codigo = $1 AND pulled_to_fieldpec = FALSE`,
      [cc],
    ),
    query(
      `SELECT count(*)::int AS n FROM fabricacoes
       WHERE cliente_codigo = $1 AND pulled_to_fieldpec = TRUE`,
      [cc],
    ),
    query(
      `SELECT count(*)::int AS n FROM fornecimentos
       WHERE cliente_codigo = $1 AND pulled_to_fieldpec = FALSE`,
      [cc],
    ),
    query(
      `SELECT count(*)::int AS n FROM fornecimentos
       WHERE cliente_codigo = $1 AND pulled_to_fieldpec = TRUE`,
      [cc],
    ),
  ]);

  return {
    cliente_codigo: cc,
    status: st === "pending" || st === "pendente"
      ? "pending"
      : st === "done" || st === "pulled" || st === "baixado"
        ? "done"
        : "all",
    limit: lim,
    summary: {
      fabricacoes_pendentes: fabPend.rows[0].n,
      fabricacoes_no_field: fabDone.rows[0].n,
      fornecimentos_pendentes: fornPend.rows[0].n,
      fornecimentos_no_field: fornDone.rows[0].n,
    },
    fabricacoes: fabs.rows.map((f) => ({
      id: f.id,
      id_local: f.id_local,
      handoff_id: f.handoff_id,
      id_fazenda: f.id_fazenda,
      id_dieta: f.id_dieta,
      data_fab: f.data_fab,
      qtde_prevista: f.qtde_prevista,
      qtde_realizada: f.qtde_realizada,
      lote_fabricacao: f.lote_fabricacao,
      pulled_to_fieldpec: !!f.pulled_to_fieldpec,
      pulled_at: f.pulled_at,
      created_at: f.created_at,
      itens: itensByFab.get(f.id) || [],
      payload: f.payload,
    })),
    fornecimentos: forns.rows.map((f) => ({
      id: f.id,
      id_fornecimento: f.id_fornecimento,
      id_fabricacao_local: f.id_fabricacao_local,
      handoff_id_fabricacao: f.handoff_id_fabricacao,
      id_baia: f.id_baia,
      id_racao: f.id_racao,
      data_forn: f.data_forn,
      trato: f.trato,
      realizado: f.realizado,
      lote_fabricacao: f.lote_fabricacao,
      pulled_to_fieldpec: !!f.pulled_to_fieldpec,
      pulled_at: f.pulled_at,
      created_at: f.created_at,
      payload: f.payload,
    })),
  };
}

async function ackOps(clienteCodigo, { fabricacao_ids = [], fornecimento_ids = [] }) {
  const cc = requireTenant(clienteCodigo);
  if (fabricacao_ids.length) {
    await query(
      `UPDATE fabricacoes SET pulled_to_fieldpec = TRUE, pulled_at = now()
       WHERE cliente_codigo = $1 AND id = ANY($2::bigint[])`,
      [cc, fabricacao_ids],
    );
  }
  if (fornecimento_ids.length) {
    await query(
      `UPDATE fornecimentos SET pulled_to_fieldpec = TRUE, pulled_at = now()
       WHERE cliente_codigo = $1 AND id = ANY($2::bigint[])`,
      [cc, fornecimento_ids],
    );
  }
  return {
    cliente_codigo: cc,
    fabricacoes_acked: fabricacao_ids.length,
    fornecimentos_acked: fornecimento_ids.length,
  };
}

module.exports = {
  saveFabricacao,
  saveFornecimento,
  saveGravaTag,
  saveAudit,
  saveGps,
  listPendingOps,
  listOps,
  ackOps,
};
