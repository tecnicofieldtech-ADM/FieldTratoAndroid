const { query } = require("../db");
const { pickStr, toNum, parseDate } = require("../util/numbers");

function rowKey(obj, ...keys) {
  return pickStr(obj, keys);
}

function requireTenant(clienteCodigo) {
  const c = String(clienteCodigo || "").trim().toUpperCase();
  if (!c) throw new Error("cliente_codigo obrigatório");
  return c;
}

async function upsertFazendas(clienteCodigo, rows = []) {
  const cc = requireTenant(clienteCodigo);
  let n = 0;
  for (const r of rows) {
    const id = rowKey(r, "idfazenda", "IDFAZENDA", "id");
    const fazenda = rowKey(r, "fazenda", "FAZENDA", "nome") || id;
    if (!id) continue;
    await query(
      `INSERT INTO fazendas (cliente_codigo, idfazenda, fazenda, cliente, updated_at)
       VALUES ($1,$2,$3,$4,now())
       ON CONFLICT (cliente_codigo, idfazenda) DO UPDATE SET
         fazenda=EXCLUDED.fazenda, cliente=EXCLUDED.cliente, updated_at=now()`,
      [cc, id, fazenda, rowKey(r, "cliente", "CLIENTE") || null],
    );
    n++;
  }
  return n;
}

async function upsertUsuarios(clienteCodigo, rows = []) {
  const cc = requireTenant(clienteCodigo);
  let n = 0;
  for (const r of rows) {
    const id = rowKey(r, "id", "ID");
    if (!id) continue;
    await query(
      `INSERT INTO usuarios (cliente_codigo, id, nome, usuario, senha, cargo, idfazenda, updated_at)
       VALUES ($1,$2,$3,$4,$5,$6,$7,now())
       ON CONFLICT (cliente_codigo, id) DO UPDATE SET
         nome=EXCLUDED.nome, usuario=EXCLUDED.usuario, senha=EXCLUDED.senha,
         cargo=EXCLUDED.cargo, idfazenda=EXCLUDED.idfazenda, updated_at=now()`,
      [
        cc,
        id,
        rowKey(r, "nome", "NOME") || id,
        rowKey(r, "usuario", "USUARIO", "login", "LOGIN") || id,
        rowKey(r, "senha", "SENHA", "password", "PASSWORD"),
        rowKey(r, "cargo", "CARGO") || null,
        rowKey(r, "idfazenda", "ID_FAZENDA", "id_fazenda") || null,
      ],
    );
    n++;
  }
  return n;
}

async function upsertVagoes(clienteCodigo, rows = []) {
  const cc = requireTenant(clienteCodigo);
  let n = 0;
  for (const r of rows) {
    const id = rowKey(r, "id", "ID");
    if (!id) continue;
    await query(
      `INSERT INTO vagoes (cliente_codigo, id, nome, updated_at)
       VALUES ($1,$2,$3,now())
       ON CONFLICT (cliente_codigo, id) DO UPDATE SET nome=EXCLUDED.nome, updated_at=now()`,
      [cc, id, rowKey(r, "nome", "NOME") || id],
    );
    n++;
  }
  return n;
}

async function upsertBaias(clienteCodigo, rows = []) {
  const cc = requireTenant(clienteCodigo);
  let n = 0;
  for (const r of rows) {
    const id = rowKey(r, "id_baia", "ID_BAIA", "idbaia", "id");
    if (!id) continue;
    await query(
      `INSERT INTO baias (cliente_codigo, id_baia, id_lote, nome_local, linha, ordem_trato, id_fazenda, rfid, updated_at)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,now())
       ON CONFLICT (cliente_codigo, id_baia) DO UPDATE SET
         id_lote=EXCLUDED.id_lote, nome_local=EXCLUDED.nome_local, linha=EXCLUDED.linha,
         ordem_trato=EXCLUDED.ordem_trato, id_fazenda=EXCLUDED.id_fazenda,
         rfid=EXCLUDED.rfid, updated_at=now()`,
      [
        cc,
        id,
        rowKey(r, "id_lote", "ID_LOTE") || null,
        rowKey(r, "nome_local", "NOME_LOCAL", "nomelocal") || null,
        rowKey(r, "linha", "LINHA") || null,
        Math.trunc(toNum(pickStr(r, ["ordem_trato", "ORDEM_TRATO", "ordemtrato"], "0"))),
        rowKey(r, "id_fazenda", "ID_FAZENDA", "idfazenda") || null,
        rowKey(r, "rfid", "RFID") || null,
      ],
    );
    n++;
  }
  return n;
}

async function upsertDietas(clienteCodigo, rows = []) {
  const cc = requireTenant(clienteCodigo);
  let n = 0;
  for (const r of rows) {
    const id = rowKey(r, "id", "ID", "iddieta", "id_dieta");
    if (!id) continue;
    const dataReg = parseDate(pickStr(r, ["data_registro", "DATA_REGISTRO"]));
    await query(
      `INSERT INTO dietas (
         cliente_codigo, id, id_fazenda, nome_dieta, tipo_dieta, status, liberado,
         id_usuario, mn_total, data_registro, ms_dieta, updated_at
       ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,now())
       ON CONFLICT (cliente_codigo, id) DO UPDATE SET
         id_fazenda=EXCLUDED.id_fazenda, nome_dieta=EXCLUDED.nome_dieta,
         tipo_dieta=EXCLUDED.tipo_dieta, status=EXCLUDED.status,
         liberado=EXCLUDED.liberado, id_usuario=EXCLUDED.id_usuario,
         mn_total=EXCLUDED.mn_total, data_registro=EXCLUDED.data_registro,
         ms_dieta=EXCLUDED.ms_dieta, updated_at=now()`,
      [
        cc,
        id,
        rowKey(r, "id_fazenda", "ID_FAZENDA", "idfazenda") || null,
        rowKey(r, "nome_dieta", "NOME_DIETA", "nomedieta") || id,
        rowKey(r, "tipo_dieta", "TIPO_DIETA") || null,
        rowKey(r, "status", "STATUS") || null,
        rowKey(r, "liberado", "LIBERADO") || null,
        rowKey(r, "id_usuario", "ID_USUARIO") || null,
        toNum(pickStr(r, ["mn_total", "MN_TOTAL"], "0")) || null,
        dataReg,
        toNum(pickStr(r, ["ms_dieta", "MS_DIETA", "msdieta"], "0")) || null,
      ],
    );
    n++;
  }
  return n;
}

async function upsertDietasDetalhes(clienteCodigo, rows = []) {
  const cc = requireTenant(clienteCodigo);
  let n = 0;
  for (const r of rows) {
    let id = rowKey(r, "id", "ID");
    const idDieta = rowKey(r, "id_dieta", "ID_DIETA", "iddieta");
    const idInsumo = rowKey(r, "id_insumo", "ID_INSUMO", "idinsumo");
    if (!id) id = `${idDieta}:${idInsumo}:${rowKey(r, "ordem", "ORDEM") || "0"}`;
    if (!idDieta) continue;
    await query(
      `INSERT INTO dietas_detalhes (
         cliente_codigo, id, id_dieta, id_insumo, nome_dieta, tipo_dieta, ingrediente,
         ms_insumo, ms_inclusao, mn_perc, ordem, pre_pesagem, updated_at
       ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,now())
       ON CONFLICT (cliente_codigo, id) DO UPDATE SET
         id_dieta=EXCLUDED.id_dieta, id_insumo=EXCLUDED.id_insumo,
         nome_dieta=EXCLUDED.nome_dieta, tipo_dieta=EXCLUDED.tipo_dieta,
         ingrediente=EXCLUDED.ingrediente, ms_insumo=EXCLUDED.ms_insumo,
         ms_inclusao=EXCLUDED.ms_inclusao, mn_perc=EXCLUDED.mn_perc,
         ordem=EXCLUDED.ordem, pre_pesagem=EXCLUDED.pre_pesagem, updated_at=now()`,
      [
        cc,
        id,
        idDieta,
        idInsumo || null,
        rowKey(r, "nome_dieta", "NOME_DIETA") || null,
        rowKey(r, "tipo_dieta", "TIPO_DIETA") || null,
        rowKey(r, "ingrediente", "INGREDIENTE") || null,
        toNum(pickStr(r, ["ms_insumo", "MS_INSUMO"], "0")) || null,
        toNum(pickStr(r, ["ms_inclusao", "MS_INCLUSAO"], "0")) || null,
        toNum(pickStr(r, ["mn_perc", "MN_PERC", "mnperc"], "0")) || null,
        Math.trunc(toNum(pickStr(r, ["ordem", "ORDEM"], "0"))),
        rowKey(r, "pre_pesagem", "PRE_PESAGEM", "prepesagem") || null,
      ],
    );
    n++;
  }
  return n;
}

async function upsertPrevisao(clienteCodigo, rows = [], defaultFazenda = null) {
  const cc = requireTenant(clienteCodigo);
  let n = 0;
  for (const r of rows) {
    const idForn = rowKey(r, "id_fornecimento", "ID_FORNECIMENTO");
    const data = parseDate(pickStr(r, ["data", "DATA", "data_forn", "DATA_FORN"]));
    const idBaia = rowKey(r, "id_baia", "ID_BAIA", "id", "ID", "idcurral", "IDCURRAL");
    const trato = Math.trunc(toNum(pickStr(r, ["trato", "TRATO"], "0")));
    if (!idForn || !data || !idBaia || trato <= 0) continue;

    const previsto = toNum(
      pickStr(r, ["previsto", "PREVISTO", "previsto_kg", "PREVISAO_KG"], "0"),
    );
    await query(
      `INSERT INTO previsao_trato (
         cliente_codigo, id_fornecimento, data, id_baia, trato, id_dieta,
         previsto, previsto_original, previsto_recalculado, previsto_cadastro, realizado,
         ultimo_trato, id_fazenda, updated_at
       ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,now())
       ON CONFLICT (cliente_codigo, id_fornecimento, data, id_baia, trato) DO UPDATE SET
         id_dieta=EXCLUDED.id_dieta, previsto=EXCLUDED.previsto,
         previsto_original=EXCLUDED.previsto_original,
         previsto_recalculado=EXCLUDED.previsto_recalculado,
         previsto_cadastro=EXCLUDED.previsto_cadastro,
         realizado=EXCLUDED.realizado, ultimo_trato=EXCLUDED.ultimo_trato,
         id_fazenda=EXCLUDED.id_fazenda, updated_at=now()`,
      [
        cc,
        idForn,
        data,
        idBaia,
        trato,
        rowKey(r, "id_dieta", "ID_DIETA", "id_racao", "IDRACAO") || null,
        previsto,
        toNum(pickStr(r, ["previsto_original", "PREVISTO_ORIGINAL"], String(previsto))) || null,
        toNum(pickStr(r, ["previsto_recalculado", "PREVISTO_RECALCULADO"], String(previsto))) || null,
        toNum(pickStr(r, ["previsto_cadastro", "PREVISTO_CADASTRO"], "0")) || null,
        toNum(pickStr(r, ["realizado", "REALIZADO", "realizado_kg"], "0")),
        Math.trunc(toNum(pickStr(r, ["ultimo_trato", "ULTIMO_TRATO"], "0"))),
        rowKey(r, "id_fazenda", "ID_FAZENDA", "idfazenda") || defaultFazenda,
      ],
    );
    n++;
  }
  return n;
}

async function pushMaster(clienteCodigo, body = {}) {
  const cc = requireTenant(clienteCodigo);
  const counts = {
    fazendas: await upsertFazendas(cc, body.fazendas || body.FAZENDAS || []),
    usuarios: await upsertUsuarios(cc, body.usuarios || body.USUARIOS || []),
    vagoes: await upsertVagoes(cc, body.vagoes || body.VAGOES || []),
    baias: await upsertBaias(cc, body.baias || body.BAIAS || []),
    dietas: await upsertDietas(cc, body.dietas || body.DIETAS || []),
    dietas_detalhes: await upsertDietasDetalhes(
      cc,
      body.dietas_detalhes || body.DIETAS_DETALHES || [],
    ),
    previsao_trato: await upsertPrevisao(
      cc,
      body.previsao_trato || body.PREVISAO_TRATO || [],
      body.id_fazenda || body.idfazenda || null,
    ),
  };
  await query(
    `INSERT INTO sync_meta (key, value, updated_at) VALUES ($1, $2, now())
     ON CONFLICT (key) DO UPDATE SET value=EXCLUDED.value, updated_at=now()`,
    [`last_master_push:${cc}`, new Date().toISOString()],
  );
  return counts;
}

async function listFazendas(clienteCodigo) {
  const cc = requireTenant(clienteCodigo);
  const { rows } = await query(
    `SELECT idfazenda AS "IDFAZENDA", coalesce(cliente, fazenda) AS "CLIENTE",
            fazenda AS "FAZENDA" FROM fazendas
     WHERE cliente_codigo = $1 ORDER BY fazenda`,
    [cc],
  );
  return rows;
}

async function listUsuarios(clienteCodigo, idFazenda) {
  const cc = requireTenant(clienteCodigo);
  let sql = `SELECT id AS "ID", nome AS "NOME", usuario AS "USUARIO",
                    senha AS "SENHA", coalesce(cargo,'0') AS "CARGO"
             FROM usuarios WHERE cliente_codigo = $1`;
  const params = [cc];
  if (idFazenda) {
    params.push(String(idFazenda));
    sql += ` AND (idfazenda IS NULL OR idfazenda = $2 OR idfazenda = '0')`;
  }
  sql += ` ORDER BY nome`;
  const { rows } = await query(sql, params);
  return rows;
}

async function listVagoes(clienteCodigo) {
  const cc = requireTenant(clienteCodigo);
  const { rows } = await query(
    `SELECT id AS "ID", nome AS "NOME" FROM vagoes
     WHERE cliente_codigo = $1 ORDER BY nome`,
    [cc],
  );
  return rows;
}

async function listBaias(clienteCodigo, idFazenda) {
  const cc = requireTenant(clienteCodigo);
  let sql = `SELECT id_baia AS "ID_BAIA", coalesce(id_lote,'0') AS "ID_LOTE",
                    nome_local AS "NOME_LOCAL", coalesce(linha,'') AS "LINHA",
                    coalesce(ordem_trato,0) AS "ORDEM_TRATO",
                    coalesce(id_fazenda,'0') AS "ID_FAZENDA",
                    coalesce(rfid,'') AS "RFID"
             FROM baias WHERE cliente_codigo = $1`;
  const params = [cc];
  if (idFazenda) {
    params.push(String(idFazenda));
    sql += ` AND (id_fazenda IS NULL OR id_fazenda = $2 OR id_fazenda = '0')`;
  }
  sql += ` ORDER BY ordem_trato, nome_local`;
  const { rows } = await query(sql, params);
  return rows;
}

async function listDietas(clienteCodigo, idFazenda) {
  const cc = requireTenant(clienteCodigo);
  let sql = `SELECT id AS "ID", coalesce(id_fazenda,'1') AS "ID_FAZENDA",
                    nome_dieta AS "NOME_DIETA", tipo_dieta AS "TIPO_DIETA",
                    status AS "STATUS", liberado AS "LIBERADO",
                    id_usuario AS "ID_USUARIO", mn_total AS "MN_TOTAL",
                    data_registro AS "DATA_REGISTRO", ms_dieta AS "MS_DIETA"
             FROM dietas WHERE cliente_codigo = $1`;
  const params = [cc];
  if (idFazenda) {
    params.push(String(idFazenda));
    sql += ` AND (id_fazenda IS NULL OR id_fazenda = $2 OR id_fazenda IN ('0','1'))`;
  }
  sql += ` ORDER BY nome_dieta`;
  const { rows } = await query(sql, params);
  return rows;
}

async function listDietasDetalhes(clienteCodigo, idFazenda) {
  const cc = requireTenant(clienteCodigo);
  let sql = `SELECT d.id AS "ID", d.id_dieta AS "ID_DIETA", d.nome_dieta AS "NOME_DIETA",
                    d.tipo_dieta AS "TIPO_DIETA", d.id_insumo AS "ID_INSUMO",
                    d.ingrediente AS "INGREDIENTE", d.ms_insumo AS "MS_INSUMO",
                    d.ms_inclusao AS "MS_INCLUSAO", d.mn_perc AS "MN_PERC",
                    d.ordem AS "ORDEM", coalesce(d.pre_pesagem,'N') AS "PRE_PESAGEM"
             FROM dietas_detalhes d
             LEFT JOIN dietas di ON di.cliente_codigo = d.cliente_codigo AND di.id = d.id_dieta
             WHERE d.cliente_codigo = $1`;
  const params = [cc];
  if (idFazenda) {
    params.push(String(idFazenda));
    sql += ` AND (di.id_fazenda IS NULL OR di.id_fazenda = $2 OR di.id_fazenda IN ('0','1'))`;
  }
  sql += ` ORDER BY d.id_dieta, d.ordem`;
  const { rows } = await query(sql, params);
  return rows;
}

async function listPrevisao(clienteCodigo, idFazenda, dataYmd) {
  const cc = requireTenant(clienteCodigo);
  const data = parseDate(dataYmd) || require("../util/numbers").todayYmd();
  const params = [cc, data];
  let sql = `SELECT id_fornecimento AS "ID_FORNECIMENTO", data AS "DATA",
                    id_baia AS "ID", trato AS "TRATO", id_dieta AS "ID_DIETA",
                    coalesce(previsto_original, previsto) AS "PREVISTO_ORIGINAL",
                    coalesce(previsto_recalculado, previsto) AS "PREVISTO_RECALCULADO",
                    coalesce(previsto_cadastro, previsto) AS "PREVISTO_CADASTRO",
                    previsto AS "PREVISTO",
                    coalesce(realizado,0) AS "REALIZADO",
                    coalesce(ultimo_trato,0) AS "ULTIMO_TRATO"
             FROM previsao_trato
             WHERE cliente_codigo = $1 AND data = $2`;
  if (idFazenda) {
    params.push(String(idFazenda));
    sql += ` AND (id_fazenda IS NULL OR id_fazenda = $3 OR id_fazenda IN ('0','1'))`;
  }
  sql += ` ORDER BY trato, id_baia`;
  const { rows } = await query(sql, params);
  return rows;
}

module.exports = {
  pushMaster,
  listFazendas,
  listUsuarios,
  listVagoes,
  listBaias,
  listDietas,
  listDietasDetalhes,
  listPrevisao,
  upsertFazendas,
  upsertUsuarios,
  upsertVagoes,
  upsertBaias,
  upsertDietas,
  upsertDietasDetalhes,
  upsertPrevisao,
};
