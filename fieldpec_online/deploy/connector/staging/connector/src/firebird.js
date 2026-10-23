/**
 * Lê cadastros do FieldPec (Firebird) com as mesmas queries do Horse UdmFieldPec.
 * Não depende de Delphi.
 */
const Firebird = require("node-firebird");
const config = require("./config");

function fbOptions() {
  return {
    host: config.fbHost || "127.0.0.1",
    port: config.fbPort || 3050,
    database: config.fbDatabase,
    user: config.fbUser || "SYSDBA",
    password: config.fbPassword || "masterkey",
    lowercase_keys: false,
    pageSize: 4096,
    encoding: "UTF8",
  };
}

function query(sql, params = []) {
  return new Promise((resolve, reject) => {
    if (!config.fbDatabase) {
      reject(new Error("FB_DATABASE nao configurado no .env"));
      return;
    }
    Firebird.attach(fbOptions(), (err, db) => {
      if (err) {
        reject(err);
        return;
      }
      db.query(sql, params, (qErr, result) => {
        db.detach();
        if (qErr) reject(qErr);
        else resolve(Array.isArray(result) ? result : []);
      });
    });
  });
}

function normalizeRows(rows) {
  return (rows || []).map((r) => {
    const out = {};
    for (const [k, v] of Object.entries(r || {})) {
      const key = String(k);
      if (Buffer.isBuffer(v)) out[key] = v.toString("utf8");
      else if (v instanceof Date) out[key] = v.toISOString().slice(0, 10);
      else out[key] = v;
    }
    return out;
  });
}

const SQL = {
  fazendas: `
    SELECT
      ID IDFAZENDA,
      p.NOME CLIENTE,
      P.NOME FAZENDA
    FROM PROPRIEDADES p
    WHERE p.PROPRIA = 1
      AND p.STATUS = 1
  `,
  usuarios: `
    SELECT
      u.id,
      u.name NOME,
      u.LOGIN USUARIO,
      u.PASSWORD SENHA,
      CASE
        WHEN ac.NOME = 'OPERADOR DE PA' THEN '1'
        ELSE '0'
      END CARGO
    FROM USERS u
    JOIN AUX_CARGO ac ON u.ID_CARGO = ac.ID
    WHERE U.STATUS = 1
  `,
  dietas: `
    SELECT
      ID,
      1 ID_FAZENDA,
      R.NOME NOME_DIETA,
      CASE
        WHEN R.TIPO = 1 THEN 'ADAPTAÇÃO'
        WHEN R.TIPO = 2 THEN 'CRESCIMENTO'
        WHEN R.TIPO = 3 THEN 'TERMINAÇÃO'
      END TIPO_DIETA,
      CASE
        WHEN R.STATUS = 1 THEN 'A'
        WHEN R.STATUS = -1 THEN 'I'
        WHEN R.STATUS = 0 THEN 'I'
      END STATUS,
      1 LIBERADO,
      r.IDUSUARIO ID_USUARIO,
      100 MN_TOTAL,
      R.DATAREGISTRO DATA_REGISTRO,
      R.MATERIASECA MS_DIETA
    FROM RACAO r
    WHERE STATUS = 1
  `,
  dietas_detalhes: `
    SELECT
      A.ID,
      IDRACAO ID_DIETA,
      R.NOME NOME_DIETA,
      CASE
        WHEN R.TIPO = 1 THEN 'ADAPTAÇÃO'
        WHEN R.TIPO = 2 THEN 'CRESCIMENTO'
        WHEN R.TIPO = 3 THEN 'TERMINAÇÃO'
      END TIPO_DIETA,
      COALESCE(IDINSUMOALIMENTO, ID_PREMISTURA) ID_INSUMO,
      COALESCE(a2.nome, a3.nome) INGREDIENTE,
      COALESCE(a2.MS, a3.MS) MS_INSUMO,
      A.PERCENTMATERIASECA MS_INCLUSAO,
      A.INCLUSAOMATERIANATURAL MN_PERC,
      A.ORDEM_FABRICACAO ORDEM,
      ID_PREMISTURA
    FROM RACAOINSUMOS A
    JOIN RACAO R ON R.ID = A.IDRACAO
    LEFT JOIN ALIMENTO a2 ON a2.id = a.IDINSUMOALIMENTO
    LEFT JOIN ALIMENTO a3 ON a3.id = a.ID_PREMISTURA
    WHERE A.STATUS = 1 AND R.STATUS = 1
  `,
  baias: `
    SELECT
      A.ID ID_BAIA,
      0 ID_LOTE,
      CODIGO NOME_LOCAL,
      CASE
        WHEN POSITION('-' IN CODIGO) > 0 THEN
          SUBSTRING(codigo FROM 1 FOR (POSITION('-' IN CODIGO) - 1))
        ELSE ''
      END LINHA,
      A.ORDERM_FORN ORDEM_TRATO,
      A.TAG_INICIO RFID,
      '0' ID_FAZENDA
    FROM CURRAIS A
    JOIN LOTE_NUTRICIONAL L ON L.ID_LOCAL = A.ID
    WHERE A.STATUS = 1
  `,
  vagoes: `
    SELECT FIRST 1 'VAGAO' NOME, 1 ID FROM USERS u
  `,
  previsao: `
    SELECT
      forn.ID ID_FORNECIMENTO,
      forn.DATA,
      forn.IDCURRAL ID,
      forn.TRATO,
      forn.IDRACAO ID_DIETA,
      CASE
        WHEN forn.TRATO = forn.UltimoTrato THEN forn.TotalPrev - forn.TotalReal + forn.Realizado
        ELSE forn.KGPREVISTO
      END PREVISTO_ORIGINAL,
      CASE
        WHEN forn.TRATO = forn.UltimoTrato THEN forn.TotalPrev - forn.TotalReal
        ELSE forn.KGPREVISTO
      END PREVISTO_RECALCULADO,
      CASE
        WHEN forn.TRATO = forn.UltimoTrato THEN forn.TotalPrev - forn.TotalReal
        ELSE forn.KGPREVISTO
      END PREVISTO,
      forn.Realizado REALIZADO,
      IIF(forn.TRATO = forn.UltimoTrato, 1, 0) ULTIMO_TRATO
    FROM (
      SELECT
        A.ID,
        DATA_FORN DATA,
        ID_LOCAL IDCURRAL,
        ID_RACAO IDRACAO,
        STATUS,
        TRATO,
        1 TIPO,
        PREVISTO_MN_KG KGPREVISTO,
        (SELECT COALESCE(SUM(REALIZADO_MN_KG), 0) FROM FORNECIMENTO_CONF
         WHERE STATUS = 1 AND ID_LOCAL = A.ID_LOCAL AND ID_LOTE = A.ID_LOTE
           AND DATA_FORN = A.DATA_FORN AND TRATO = A.TRATO) Realizado,
        (SELECT COALESCE(SUM(REALIZADO_MN_KG), 0) FROM FORNECIMENTO_CONF
         WHERE STATUS = 1 AND ID_LOCAL = A.ID_LOCAL AND ID_LOTE = A.ID_LOTE
           AND DATA_FORN = A.DATA_FORN) TotalReal,
        (SELECT SUM(PREVISTO_MN_KG) FROM FORNECIMENTO_CONF
         WHERE STATUS = 1 AND ID_LOCAL = A.ID_LOCAL AND ID_LOTE = A.ID_LOTE
           AND DATA_FORN = A.DATA_FORN) TotalPrev,
        (SELECT MAX(TRATO) FROM FORNECIMENTO_CONF
         WHERE STATUS = 1 AND ID_LOCAL = A.ID_LOCAL AND ID_LOTE = A.ID_LOTE
           AND DATA_FORN = A.DATA_FORN) UltimoTrato
      FROM FORNECIMENTO_CONF A
      WHERE STATUS = 1 AND DATA_FORN = CURRENT_DATE
    ) Forn
  `,
};

async function loadMasterFromFirebird() {
  const [
    fazendas,
    usuarios,
    vagoes,
    baias,
    dietas,
    dietas_detalhes,
    previsao_trato,
  ] = await Promise.all([
    query(SQL.fazendas).then(normalizeRows),
    query(SQL.usuarios).then(normalizeRows),
    query(SQL.vagoes).then(normalizeRows).catch(() => [{ ID: 1, NOME: "VAGAO" }]),
    query(SQL.baias).then(normalizeRows),
    query(SQL.dietas).then(normalizeRows),
    query(SQL.dietas_detalhes).then(normalizeRows),
    query(SQL.previsao).then(normalizeRows),
  ]);

  const idF = (config.idFazenda || "").trim();
  const previsaoTagged = previsao_trato.map((p) => ({
    ...p,
    id_fazenda: p.id_fazenda || p.ID_FAZENDA || idF || "1",
    data: p.data || p.DATA || new Date().toISOString().slice(0, 10),
  }));

  return {
    id_fazenda: idF || "1",
    fazendas,
    usuarios,
    vagoes,
    baias,
    dietas,
    dietas_detalhes,
    previsao_trato: previsaoTagged,
  };
}

async function probeFirebird() {
  try {
    const rows = await query("SELECT 1 AS OK FROM RDB$DATABASE");
    return {
      ok: true,
      database: config.fbDatabase,
      host: config.fbHost,
      sample: rows[0] || null,
    };
  } catch (e) {
    return {
      ok: false,
      database: config.fbDatabase,
      host: config.fbHost,
      error: e.message,
    };
  }
}

// ---------------------------------------------------------------------------
// Escrita de fab/forn (espelho Controllers.Post.Field)
// ---------------------------------------------------------------------------

function pickStr(obj, keys, def = "") {
  if (!obj || typeof obj !== "object") return def;
  for (const k of keys) {
    if (obj[k] == null) continue;
    const s = String(obj[k]).trim();
    if (s !== "" && s.toLowerCase() !== "null") return s;
  }
  return def;
}

function toNum(v, def = 0) {
  if (v == null || v === "") return def;
  if (typeof v === "number" && Number.isFinite(v)) return v;
  let s = String(v).trim().replace(/\s/g, "");
  if (!s) return def;
  if (s.includes(",") && s.includes(".")) {
    s = s.replace(/\./g, "").replace(",", ".");
  } else if (s.includes(",")) {
    s = s.replace(",", ".");
  }
  const n = Number(s);
  return Number.isFinite(n) ? n : def;
}

function toInt(v, def = 0) {
  const n = Math.trunc(toNum(v, def));
  return Number.isFinite(n) ? n : def;
}

/** Aceita ISO, yyyy-mm-dd, dd/mm/yyyy */
function parseDate(v) {
  if (v == null || v === "") return null;
  if (v instanceof Date && !Number.isNaN(v.getTime())) {
    return v.toISOString().slice(0, 10);
  }
  const s = String(v).trim();
  const br = s.match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})/);
  if (br) {
    const d = br[1].padStart(2, "0");
    const m = br[2].padStart(2, "0");
    return `${br[3]}-${m}-${d}`;
  }
  const iso = s.match(/^(\d{4})-(\d{2})-(\d{2})/);
  if (iso) return `${iso[1]}-${iso[2]}-${iso[3]}`;
  const t = Date.parse(s);
  if (!Number.isNaN(t)) return new Date(t).toISOString().slice(0, 10);
  return null;
}

function parseHora(v) {
  if (v == null || v === "") return null;
  const s = String(v).trim();
  const m = s.match(/^(\d{1,2}):(\d{2})(?::(\d{2}))?/);
  if (!m) return null;
  const hh = m[1].padStart(2, "0");
  const mm = m[2];
  const ss = (m[3] || "00").padStart(2, "0");
  return `${hh}:${mm}:${ss}`;
}

function withTransaction(fn) {
  return new Promise((resolve, reject) => {
    if (!config.fbDatabase) {
      reject(new Error("FB_DATABASE nao configurado no .env"));
      return;
    }
    Firebird.attach(fbOptions(), (err, db) => {
      if (err) {
        reject(err);
        return;
      }
      db.transaction(Firebird.ISOLATION_READ_COMMITTED, (txErr, transaction) => {
        if (txErr) {
          db.detach();
          reject(txErr);
          return;
        }
        const txQuery = (sql, params = []) =>
          new Promise((res, rej) => {
            transaction.query(sql, params, (qErr, result) => {
              if (qErr) rej(qErr);
              else res(Array.isArray(result) ? result : result != null ? [result] : []);
            });
          });
        Promise.resolve()
          .then(() => fn(txQuery))
          .then((out) => {
            transaction.commit((cErr) => {
              db.detach();
              if (cErr) reject(cErr);
              else resolve(out);
            });
          })
          .catch((e) => {
            transaction.rollback(() => {
              db.detach();
              reject(e);
            });
          });
      });
    });
  });
}

async function nextId(txQuery, tableName) {
  const rows = await txQuery(
    `SELECT COALESCE(MAX(ID), 0) + 1 AS NX FROM ${tableName}`,
  );
  return toInt(rows[0] && (rows[0].NX ?? rows[0].nx), 1);
}

async function getRacaoValorKg(txQuery, idRacao) {
  const id = toInt(idRacao);
  if (id <= 0) return 0;
  try {
    const rows = await txQuery(
      `SELECT VALORKG FROM RACAO WHERE ID = ?`,
      [id],
    );
    return toNum(rows[0] && (rows[0].VALORKG ?? rows[0].valorkg), 0);
  } catch {
    return 0;
  }
}

async function getInsumoValorKg(txQuery, idRacao, idAlimento) {
  const idA = toInt(idAlimento);
  const idR = toInt(idRacao);
  if (idA <= 0) return 0;
  try {
    if (idR > 0) {
      const rows = await txQuery(
        `SELECT FIRST 1 COALESCE(VALORKG, 0) AS VK
         FROM RACAOINSUMOS
         WHERE IDRACAO = ? AND (IDINSUMOALIMENTO = ? OR ID_PREMISTURA = ?) AND STATUS = 1`,
        [idR, idA, idA],
      );
      if (rows[0]) return toNum(rows[0].VK ?? rows[0].vk, 0);
    }
  } catch {
    /* ignore */
  }
  return 0;
}

/**
 * Grava FABRICACAO + FABRICACAO_INSUMOS a partir do payload do tablet/nuvem.
 * Não aplica fornecimentos aninhados (evita duplicar com linhas pending).
 */
async function insertFabricacaoFromPayload(payload) {
  const body = payload && typeof payload === "object" ? payload : {};
  const idFazenda = toInt(
    pickStr(body, ["id_fazenda", "ID_PROPRIEDADE", "id_propriedade", "ID_FAZENDA"]),
  );
  const idDieta = toInt(
    pickStr(body, ["id_dieta", "IDRACAO", "ID_RACAO", "id_racao", "ID_DIETA"]),
  );
  const idUsuario = toInt(
    pickStr(body, ["id_usuario", "ID_USUARIO"]),
  );
  let idOperador = toInt(
    pickStr(body, ["id_operador", "ID_OPERADOR"]),
  );
  if (idOperador <= 0) idOperador = idUsuario;

  const dataFab = parseDate(
    pickStr(body, ["data", "DATA", "DATA_FAB", "data_fab", "data_fabricacao"]),
  );
  const qtdePrev = toNum(
    pickStr(body, ["qtde_prevista", "QTDE_PREVISTA", "KG_PREVISTO", "kg_previsto"]),
  );
  const qtdeReal = toNum(
    pickStr(body, ["qtde_realizada", "QTDE_REALIZADA", "KG_REALIZADO", "kg_realizado"]),
  );
  const horaIni = parseHora(
    pickStr(body, ["hora_inicio", "HORA_INICIO"]),
  );
  const horaFim = parseHora(
    pickStr(body, ["hora_fim", "HORA_FIM"]),
  );

  if (idFazenda <= 0) throw new Error("id_fazenda/ID_PROPRIEDADE inválido");
  if (idDieta <= 0) throw new Error("id_dieta/IDRACAO inválido");
  if (idUsuario <= 0) throw new Error("id_usuario inválido");
  if (!dataFab) throw new Error("data da fabricação inválida");

  const itensRaw = Array.isArray(body.itens)
    ? body.itens
    : Array.isArray(body.FABRICACAO_INSUMOS)
      ? body.FABRICACAO_INSUMOS
      : Array.isArray(body.insumos)
        ? body.insumos
        : [];

  return withTransaction(async (txQuery) => {
    const valorKg = await getRacaoValorKg(txQuery, idDieta);
    const custoTotal = qtdeReal * valorKg;

    let idFab = 0;
    let lastErr = null;
    for (let attempt = 0; attempt < 4; attempt++) {
      try {
        idFab = await nextId(txQuery, "FABRICACAO");
        await txQuery(
          `INSERT INTO FABRICACAO (
             ID, IDRACAO, DATA_FAB, KG_PREVISTO, KG_REALIZADO, CUSTO_TOTAL,
             ID_USUARIO, ID_OPERADOR, ID_PROPRIEDADE, ORIGEM_DADOS, STATUS, DATAREG
           ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 1, 1, CURRENT_DATE)`,
          [
            idFab,
            idDieta,
            dataFab,
            qtdePrev,
            qtdeReal,
            custoTotal,
            idUsuario,
            idOperador,
            idFazenda,
          ],
        );
        lastErr = null;
        break;
      } catch (e) {
        lastErr = e;
        const msg = String(e.message || e).toUpperCase();
        if (!msg.includes("PRIMARY") && !msg.includes("UNIQUE") && !msg.includes("PK_")) {
          throw e;
        }
      }
    }
    if (lastErr || idFab <= 0) {
      throw lastErr || new Error("Falha ao inserir FABRICACAO (PK)");
    }

    const lote = String(idFab);
    if (horaIni || horaFim) {
      await txQuery(
        `UPDATE FABRICACAO SET LOTE_FABRICACAO = ?, HORA_INICIO = ?, HORA_FIM = ? WHERE ID = ?`,
        [lote, horaIni, horaFim, idFab],
      );
    } else {
      await txQuery(
        `UPDATE FABRICACAO SET LOTE_FABRICACAO = ? WHERE ID = ?`,
        [lote, idFab],
      );
    }

    await txQuery(`DELETE FROM FABRICACAO_INSUMOS WHERE ID_FABRICACAO = ?`, [idFab]);

    let itensOk = 0;
    for (const item of itensRaw) {
      if (!item || typeof item !== "object") continue;
      const idAlimento = toInt(
        pickStr(item, ["id_insumo", "ID_INSUMO", "ID_ALIMENTO", "id_alimento"]),
      );
      if (idAlimento <= 0) continue;
      const idUserItem =
        toInt(pickStr(item, ["id_usuario", "ID_USUARIO"]), idUsuario) || idUsuario;
      const kgPrev = toNum(
        pickStr(item, ["qtde_prevista", "QTDE_PREVISTA", "KG_PREVISTO"]),
      );
      const kgFab = toNum(
        pickStr(item, [
          "qtde_realizada",
          "qtd_realizada",
          "QTDE_REALIZADA",
          "KG_FABRICADO",
        ]),
      );
      let ms = toNum(pickStr(item, ["ms_insumo", "MS_INSUMO"]));
      if (ms < 0 || ms > 1000) ms = 0;
      const vk = await getInsumoValorKg(txQuery, idDieta, idAlimento);
      const hIni = parseHora(pickStr(item, ["hora_ini", "HORA_INI", "hora_inicio"]));
      const hFim = parseHora(pickStr(item, ["hora_fim", "HORA_FIM"]));

      let inserted = false;
      for (let attempt = 0; attempt < 4; attempt++) {
        try {
          const idItem = await nextId(txQuery, "FABRICACAO_INSUMOS");
          if (hIni || hFim) {
            await txQuery(
              `INSERT INTO FABRICACAO_INSUMOS (
                 ID, ID_FABRICACAO, ID_ALIMENTO, DATA_FAB, MS_INSUMO,
                 KG_PREVISTO, KG_FABRICADO, ID_USUARIO, STATUS, DATAREG, VALOR_KG,
                 HORA_INI, HORA_FIM
               ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, CURRENT_DATE, ?, ?, ?)`,
              [
                idItem,
                idFab,
                idAlimento,
                dataFab,
                ms,
                kgPrev,
                kgFab,
                idUserItem,
                vk,
                hIni,
                hFim,
              ],
            );
          } else {
            await txQuery(
              `INSERT INTO FABRICACAO_INSUMOS (
                 ID, ID_FABRICACAO, ID_ALIMENTO, DATA_FAB, MS_INSUMO,
                 KG_PREVISTO, KG_FABRICADO, ID_USUARIO, STATUS, DATAREG, VALOR_KG
               ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, CURRENT_DATE, ?)`,
              [
                idItem,
                idFab,
                idAlimento,
                dataFab,
                ms,
                kgPrev,
                kgFab,
                idUserItem,
                vk,
              ],
            );
          }
          inserted = true;
          itensOk++;
          break;
        } catch (e) {
          const msg = String(e.message || e).toUpperCase();
          if (!msg.includes("PRIMARY") && !msg.includes("UNIQUE") && !msg.includes("PK_")) {
            throw e;
          }
        }
      }
      if (!inserted) {
        throw new Error(`Falha ao inserir FABRICACAO_INSUMOS alimento=${idAlimento}`);
      }
    }

    return {
      ok: true,
      id_servidor: idFab,
      lote_fabricacao: lote,
      itens_processados: itensOk,
    };
  });
}

/**
 * Atualiza FORNECIMENTO_CONF existente (não cria linha).
 */
async function updateFornecimentoFromPayload(payload) {
  const body = payload && typeof payload === "object" ? payload : {};
  const idFornStr = pickStr(body, ["id", "ID", "id_fornecimento", "ID_FORNECIMENTO"]);
  const idBaia = toInt(
    pickStr(body, ["id_baia", "IDCURRAL", "id_curral", "ID_LOCAL", "id_local"]),
  );
  let idRacao = toInt(
    pickStr(body, [
      "id_racao",
      "ID_RACAO",
      "IDRACAO",
      "id_dieta",
      "id_dieta_prevista",
      "id_dieta_realizada",
      "ID_DIETA_REALIZADA",
    ]),
  );
  const trato = toInt(pickStr(body, ["trato", "TRATO"]));
  const dataForn = parseDate(
    pickStr(body, ["data", "DATA", "DATA_FORN", "data_forn", "DATA_FAB"]),
  );
  const realizadoNum = toNum(
    pickStr(body, ["realizado", "REALIZADO", "REALIZADO_MN_KG"]),
  );
  const ms = toNum(
    pickStr(body, ["ms_dieta_realizada", "MS_RACAO", "MS_DIETA", "ms_racao"]),
  );
  let idMotorista = toInt(
    pickStr(body, ["id_tratador", "ID_MOTORISTA", "id_motorista"]),
  );
  const idUsuario = toInt(
    pickStr(body, ["id_usuario_lancamento", "ID_USUARIO", "id_usuario"]),
  );
  if (idMotorista <= 0) idMotorista = idUsuario;
  let loteFab = pickStr(body, ["lote_fabricacao", "LOTE_FABRICACAO"]);
  const horaForn = parseHora(
    pickStr(body, ["hora_forn", "HORA_FORN", "hora_fim", "HORA_FIM"]),
  );

  return withTransaction(async (txQuery) => {
    let conf = null;
    const idForn = toInt(idFornStr);
    if (idForn > 0) {
      const rows = await txQuery(
        `SELECT ID, ID_LOCAL, ID_LOTE, TRATO, DATA_FORN, REALIZADO_MN_KG,
                MEDIA_PESO, MS_RACAO, LOTE_FABRICACAO
         FROM FORNECIMENTO_CONF
         WHERE ID = ? AND STATUS = 1`,
        [idForn],
      );
      if (rows[0]) conf = rows[0];
    }

    if (!conf && idBaia > 0 && idRacao > 0 && trato > 0 && dataForn) {
      const rows = await txQuery(
        `SELECT ID, ID_LOCAL, ID_LOTE, TRATO, DATA_FORN, REALIZADO_MN_KG,
                MEDIA_PESO, MS_RACAO, LOTE_FABRICACAO
         FROM FORNECIMENTO_CONF
         WHERE STATUS = 1 AND ID_LOCAL = ? AND TRATO = ?
           AND DATA_FORN = ? AND ID_RACAO = ?`,
        [idBaia, trato, dataForn, idRacao],
      );
      if (rows[0]) conf = rows[0];
    }

    if (!conf) {
      throw new Error(
        "Nenhum FORNECIMENTO_CONF encontrado (envie id ou id_baia+id_racao+trato+data).",
      );
    }

    const confId = toInt(conf.ID ?? conf.id);
    const idLocal = toInt(conf.ID_LOCAL ?? conf.id_local, idBaia);
    const idLote = toInt(conf.ID_LOTE ?? conf.id_lote);
    const tratoFinal = toInt(conf.TRATO ?? conf.trato, trato);
    const dataFinal =
      parseDate(conf.DATA_FORN ?? conf.data_forn) || dataForn;
    const realizadoAtual = toNum(conf.REALIZADO_MN_KG ?? conf.realizado_mn_kg);
    let mediaPeso = toNum(conf.MEDIA_PESO ?? conf.media_peso);
    if (!loteFab) {
      loteFab = pickStr(conf, ["LOTE_FABRICACAO", "lote_fabricacao"]);
    }

    // Acumulativo (como Horse default)
    const realizadoGravar = realizadoAtual + realizadoNum;

    let qtdCab = 0;
    try {
      const ln = await txQuery(
        `SELECT QTDE_CAB FROM LOTE_NUTRICIONAL WHERE STATUS = 1 AND ID_LOCAL = ?`,
        [idLocal],
      );
      if (ln[0]) qtdCab = toNum(ln[0].QTDE_CAB ?? ln[0].qtde_cab);
    } catch {
      /* ignore */
    }

    const valorKgRacao = await getRacaoValorKg(txQuery, idRacao || 0);
    let valorKgFab = 0;
    if (loteFab) {
      try {
        const vf = await txQuery(
          `SELECT SUM(fi.CUSTO) / NULLIF(SUM(fi.KG_FABRICADO), 0) AS VALORFAB
           FROM FABRICACAO_INSUMOS fi
           JOIN FABRICACAO f ON f.ID = fi.ID_FABRICACAO
           WHERE f.LOTE_FABRICACAO = ?`,
          [loteFab],
        );
        if (vf[0]) valorKgFab = toNum(vf[0].VALORFAB ?? vf[0].valorfab);
      } catch {
        /* CUSTO pode ser calculado / inexistente */
      }
    }

    const valorKgUsar = valorKgFab > 0 ? valorKgFab : valorKgRacao;
    const custoTotal =
      valorKgFab > 0 ? realizadoNum * valorKgFab : realizadoNum * valorKgRacao;

    if (horaForn) {
      await txQuery(
        `UPDATE FORNECIMENTO_CONF SET
           LOTE_FABRICACAO = ?,
           ID_MOTORISTA = ?,
           HORA_FORN = ?,
           QTD_CAB = ?,
           REALIZADO_MN_KG = ?,
           MS_RACAO = ?,
           DATA_ALTERACAO = CURRENT_TIMESTAMP,
           ID_USUARIO_ALTERACAO = ?,
           MEDIA_PESO = ?,
           VALOR_KG_RACAO = ?,
           CUSTO_TOTAL_TRATO = ?
         WHERE ID = ?`,
        [
          loteFab || null,
          idMotorista || 0,
          horaForn,
          qtdCab,
          realizadoGravar,
          ms,
          idMotorista || idUsuario || 0,
          mediaPeso,
          valorKgUsar,
          custoTotal,
          confId,
        ],
      );
    } else {
      await txQuery(
        `UPDATE FORNECIMENTO_CONF SET
           LOTE_FABRICACAO = ?,
           ID_MOTORISTA = ?,
           QTD_CAB = ?,
           REALIZADO_MN_KG = ?,
           MS_RACAO = ?,
           DATA_ALTERACAO = CURRENT_TIMESTAMP,
           ID_USUARIO_ALTERACAO = ?,
           MEDIA_PESO = ?,
           VALOR_KG_RACAO = ?,
           CUSTO_TOTAL_TRATO = ?
         WHERE ID = ?`,
        [
          loteFab || null,
          idMotorista || 0,
          qtdCab,
          realizadoGravar,
          ms,
          idMotorista || idUsuario || 0,
          mediaPeso,
          valorKgUsar,
          custoTotal,
          confId,
        ],
      );
    }

    if (idLote > 0 && dataFinal && tratoFinal > 0) {
      try {
        await txQuery(
          `UPDATE DET_LOTE_PLANEJAMENTO SET UTILIZADO = 1
           WHERE DATA = ? AND TRATO = ? AND ID_LOTE = ?`,
          [dataFinal, tratoFinal, idLote],
        );
      } catch {
        /* tabela pode não existir em alguns bancos */
      }
    }

    return {
      ok: true,
      id: confId,
      realizado_anterior: realizadoAtual,
      realizado_gravado: realizadoGravar,
      id_local: idLocal,
      trato: tratoFinal,
    };
  });
}

module.exports = {
  loadMasterFromFirebird,
  probeFirebird,
  query,
  insertFabricacaoFromPayload,
  updateFornecimentoFromPayload,
};
