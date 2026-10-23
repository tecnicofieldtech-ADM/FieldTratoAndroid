/**
 * Homologacao local Firebird 2.5 da idempotencia.
 * Nao aponta para o TGC de producao.
 *
 * node homolog_fabricacao_sync.js <caminho.fdb>
 */
const Firebird = require("node-firebird");

const database = process.argv[2];
if (!database) {
  console.error("Uso: node homolog_fabricacao_sync.js <arquivo.fdb>");
  process.exit(1);
}

const options = {
  host: "127.0.0.1",
  port: 3050,
  database,
  user: "SYSDBA",
  password: "masterkey",
  lowercase_keys: true,
};

function attach() {
  return new Promise((resolve, reject) => {
    Firebird.attach(options, (err, db) => (err ? reject(err) : resolve(db)));
  });
}

function query(db, sql, params = []) {
  return new Promise((resolve, reject) => {
    db.query(sql, params, (err, rows) => (err ? reject(err) : resolve(rows || [])));
  });
}

const READ_COMMITTED_REC_VERSION = [
  3, 9, 6, 15, 17, 21, 1, 4,
];

function withTx(db, fn) {
  return new Promise((resolve, reject) => {
    db.transaction(READ_COMMITTED_REC_VERSION, (err, tx) => {
      if (err) return reject(err);
      const q = (sql, params = []) =>
        new Promise((res, rej) => {
          tx.query(sql, params, (e, rows) => (e ? rej(e) : res(rows || [])));
        });
      fn(q)
        .then((value) => {
          tx.commit((e) => (e ? reject(e) : resolve(value)));
        })
        .catch((e) => {
          tx.rollback(() => reject(e));
        });
    });
  });
}

function isContention(err) {
  const msg = String(err && (err.message || err));
  const code = err && err.gdscode;
  return (
    code === 335544665 ||
    code === 335544336 ||
    code === 335544345 ||
    code === 335544349 ||
    code === 335544451 ||
    code === 335544510 ||
    msg.includes("335544665") ||
    msg.includes("335544336") ||
    msg.includes("335544345") ||
    msg.includes("335544349") ||
    msg.includes("335544451") ||
    msg.includes("335544510") ||
    /unique|PRIMARY|deadlock|lock conflict|update conflict|lock time-?out/i.test(msg)
  );
}

async function countBatida(db) {
  const rows = await query(db, "SELECT COUNT(*) AS N FROM CAD_BATIDA");
  return Number(rows[0].N ?? rows[0].n);
}

async function genValue(db) {
  const rows = await query(db, "SELECT GEN_ID(GEN_CAD_BATIDA, 0) AS G FROM RDB\$DATABASE");
  return Number(rows[0].G ?? rows[0].g);
}

async function syncOnce(db, idEvento, handoff, hash) {
  try {
    return await withTx(db, async (q) => {
      const found = await q(
        "SELECT FIRST 1 ID_FABRICACAO_TGC AS CBT, HASH_PAYLOAD AS HASH " +
          "FROM RFEED_FABRICACAO_SYNC WHERE ORIGEM_SISTEMA = ? " +
          "AND (ID_EVENTO_SYNC = ? OR HANDOFF_ID = ?)",
        ["FIELDTRATO", idEvento, handoff],
      );
      if (found.length) {
        if (String(found[0].HASH ?? found[0].hash) !== hash) {
          const err = new Error("conflict");
          err.code = 409;
          throw err;
        }
        return {
          created: false,
          cbt: Number(found[0].CBT ?? found[0].cbt),
        };
      }
      await q(
        "INSERT INTO RFEED_FABRICACAO_SYNC " +
          "(ORIGEM_SISTEMA, ID_EVENTO_SYNC, HANDOFF_ID, ID_FABRICACAO_TGC, DATA_SINCRONIZACAO, HASH_PAYLOAD) " +
          "VALUES (?, ?, ?, NULL, CURRENT_TIMESTAMP, ?)",
        ["FIELDTRATO", idEvento, handoff, hash],
      );
      const gen = await q("SELECT GEN_ID(GEN_CAD_BATIDA, 1) AS N FROM RDB\$DATABASE");
      const cbt = Number(gen[0].N ?? gen[0].n);
      await q(
        "INSERT INTO CAD_BATIDA (CBT_CODIGO, CBT_CODRACAOPROD, CBT_QTDEBATIDA) VALUES (?, ?, ?)",
        [cbt, 10921, 6945],
      );
      await q(
        "INSERT INTO DET_BATIDA (DBT_CODIGO, DBT_CODBATIDA, DBT_CODALIMENTO, DBT_QTDE) VALUES (?, ?, ?, ?)",
        [cbt, cbt, 6, 400],
      );
      await q(
        "UPDATE RFEED_FABRICACAO_SYNC SET ID_FABRICACAO_TGC = ? " +
          "WHERE ORIGEM_SISTEMA = ? AND ID_EVENTO_SYNC = ?",
        [cbt, "FIELDTRATO", idEvento],
      );
      return { created: true, cbt };
    });
  } catch (err) {
    if (err && err.code === 409) throw err;
    if (!isContention(err)) throw err;
    for (let i = 0; i < 8; i++) {
      const rows = await query(
        db,
        "SELECT ID_FABRICACAO_TGC AS CBT, HASH_PAYLOAD AS HASH FROM RFEED_FABRICACAO_SYNC " +
          "WHERE ORIGEM_SISTEMA = ? AND (ID_EVENTO_SYNC = ? OR HANDOFF_ID = ?)",
        ["FIELDTRATO", idEvento, handoff],
      );
      if (rows.length && Number(rows[0].CBT ?? rows[0].cbt) > 0) {
        if (String(rows[0].HASH ?? rows[0].hash) !== hash) {
          const conflict = new Error("conflict");
          conflict.code = 409;
          throw conflict;
        }
        return { created: false, cbt: Number(rows[0].CBT ?? rows[0].cbt) };
      }
      await new Promise((r) => setTimeout(r, 30 * (i + 1)));
    }
    const later = new Error("not-visible");
    later.code = 503;
    throw later;
  }
}

async function main() {
  const db = await attach();
  const results = [];
  const ok = (name) => {
    results.push(name);
    console.log("OK", name);
  };

  const beforeGen = await genValue(db);
  const first = await syncOnce(db, "local-a", "handoff-a", "hash-a");
  if (!first.created) throw new Error("primeiro envio deveria criar");
  if ((await countBatida(db)) !== 1) throw new Error("count apos primeiro");
  ok("1 primeiro POST cria uma fabricacao");

  const second = await syncOnce(db, "local-a", "handoff-a", "hash-a");
  if (second.created || second.cbt !== first.cbt) throw new Error("retry mudou cbt");
  if ((await countBatida(db)) !== 1) throw new Error("count apos retry");
  ok("2 retry identico devolve o mesmo CBT");

  for (let i = 0; i < 10; i++) {
    const again = await syncOnce(db, "local-a", "handoff-a", "hash-a");
    if (again.cbt !== first.cbt) throw new Error("retry " + i);
  }
  if ((await countBatida(db)) !== 1) throw new Error("count apos 10");
  ok("3 dez retries nao criam batida nova");

  const two = await Promise.all([
    syncOnce(db, "local-b", "handoff-b", "hash-b"),
    syncOnce(db, "local-b", "handoff-b", "hash-b"),
  ]);
  const cbtB = two[0].cbt;
  if (two[1].cbt !== cbtB) throw new Error("concorrencia 2");
  ok("4 dois POSTs concorrentes geram uma batida");

  const burst = await Promise.allSettled(
    Array.from({ length: 20 }, async () => {
      const conn = await attach();
      try {
        return await syncOnce(conn, "local-c", "handoff-c", "hash-c");
      } finally {
        conn.detach();
      }
    }),
  );
  const hardFail = burst.find(
    (item) => item.status === "rejected" && item.reason && item.reason.code !== 503,
  );
  if (hardFail && hardFail.status === "rejected") throw hardFail.reason;
  const settled = await syncOnce(db, "local-c", "handoff-c", "hash-c");
  for (const item of burst) {
    if (item.status === "fulfilled" && item.value.cbt !== settled.cbt) {
      throw new Error("concorrencia 20 devolveu CBT diferente");
    }
  }
  const rowsC = await query(
    db,
    "SELECT COUNT(*) AS N FROM CAD_BATIDA B " +
      "JOIN RFEED_FABRICACAO_SYNC S ON S.ID_FABRICACAO_TGC = B.CBT_CODIGO " +
      "WHERE S.ID_EVENTO_SYNC = ?",
    ["local-c"],
  );
  if (Number(rowsC[0].N ?? rowsC[0].n) !== 1) throw new Error("concorrencia 20");
  ok("5 vinte POSTs concorrentes geram uma batida");

  const genBeforeFail = await genValue(db);
  try {
    await withTx(db, async (q) => {
      await q(
        "INSERT INTO RFEED_FABRICACAO_SYNC " +
          "(ORIGEM_SISTEMA, ID_EVENTO_SYNC, HANDOFF_ID, ID_FABRICACAO_TGC, DATA_SINCRONIZACAO, HASH_PAYLOAD) " +
          "VALUES (?, ?, ?, NULL, CURRENT_TIMESTAMP, ?)",
        ["FIELDTRATO", "local-fail-h", "handoff-fail-h", "hash-fail"],
      );
      const gen = await q("SELECT GEN_ID(GEN_CAD_BATIDA, 1) AS N FROM RDB\$DATABASE");
      const cbt = Number(gen[0].N ?? gen[0].n);
      await q(
        "INSERT INTO CAD_BATIDA (CBT_CODIGO, CBT_CODRACAOPROD, CBT_QTDEBATIDA) VALUES (?, ?, ?)",
        [cbt, 1, 1],
      );
      throw new Error("falha apos cabecalho");
    });
    throw new Error("rollback cabecalho nao disparou");
  } catch (err) {
    if (!String(err.message).includes("falha apos cabecalho")) throw err;
  }
  const leaked = await query(
    db,
    "SELECT COUNT(*) AS N FROM RFEED_FABRICACAO_SYNC WHERE ID_EVENTO_SYNC = ?",
    ["local-fail-h"],
  );
  if (Number(leaked[0].N ?? leaked[0].n) !== 0) throw new Error("rollback cabecalho vazou vinculo");
  ok("6 falha apos cabecalho faz rollback");

  try {
    await withTx(db, async (q) => {
      await q(
        "INSERT INTO RFEED_FABRICACAO_SYNC " +
          "(ORIGEM_SISTEMA, ID_EVENTO_SYNC, HANDOFF_ID, ID_FABRICACAO_TGC, DATA_SINCRONIZACAO, HASH_PAYLOAD) " +
          "VALUES (?, ?, ?, NULL, CURRENT_TIMESTAMP, ?)",
        ["FIELDTRATO", "local-fail-i", "handoff-fail-i", "hash-fail-i"],
      );
      const gen = await q("SELECT GEN_ID(GEN_CAD_BATIDA, 1) AS N FROM RDB\$DATABASE");
      const cbt = Number(gen[0].N ?? gen[0].n);
      await q(
        "INSERT INTO CAD_BATIDA (CBT_CODIGO, CBT_CODRACAOPROD, CBT_QTDEBATIDA) VALUES (?, ?, ?)",
        [cbt, 1, 1],
      );
      await q(
        "INSERT INTO DET_BATIDA (DBT_CODIGO, DBT_CODBATIDA, DBT_CODALIMENTO, DBT_QTDE) VALUES (?, ?, ?, ?)",
        [cbt, cbt, 1, 1],
      );
      throw new Error("falha nos ingredientes");
    });
    throw new Error("rollback ingrediente nao disparou");
  } catch (err) {
    if (!String(err.message).includes("falha nos ingredientes")) throw err;
  }
  const leakedI = await query(
    db,
    "SELECT COUNT(*) AS N FROM CAD_BATIDA WHERE CBT_CODRACAOPROD = 1",
  );
  if (Number(leakedI[0].N ?? leakedI[0].n) !== 0) throw new Error("rollback ingrediente vazou");
  const genAfterFail = await genValue(db);
  if (genAfterFail < genBeforeFail) throw new Error("generator retrocedeu");
  ok("7 falha nos ingredientes faz rollback e nao retrocede generator");

  const afterCommit = await syncOnce(db, "local-a", "handoff-a", "hash-a");
  if (afterCommit.cbt !== first.cbt) throw new Error("retry apos commit");
  ok("8 retry apos commit devolve a batida existente");

  let conflict = false;
  try {
    await syncOnce(db, "local-a", "handoff-a", "hash-diferente");
  } catch (err) {
    conflict = err.code === 409;
  }
  if (!conflict) throw new Error("esperava conflito");
  if ((await countBatida(db)) < 2) throw new Error("conflito nao pode apagar batidas");
  ok("9 mesmo id com hash diferente retorna conflito");

  const other = await syncOnce(db, "local-d", "handoff-d", "hash-d");
  if (!other.created || other.cbt === first.cbt) throw new Error("ids diferentes");
  ok("10 ids diferentes criam fabricacoes distintas");

  const truck = await syncOnce(db, "local-truck", "handoff-a", "hash-a");
  if (truck.cbt !== first.cbt) throw new Error("handoff compartilhado duplicou");
  ok("11 mesmo HANDOFF_ID de outro dispositivo nao duplica");

  const restart = await syncOnce(db, "local-a", "handoff-a", "hash-a");
  if (restart.cbt !== first.cbt) throw new Error("reinicio mudou identidade");
  ok("12 mesma identidade apos nova conexao");

  const genEnd = await genValue(db);
  if (genEnd < beforeGen) throw new Error("generator final menor que o inicial");
  console.log("generator inicio=" + beforeGen + " fim=" + genEnd + " (lacunas apos rollback sao esperadas)");
  console.log("TODOS OS TESTES FIREBIRD PASSARAM (" + results.length + ")");
  db.detach();
}

main().catch((err) => {
  console.error("FALHA", err);
  process.exit(1);
});
