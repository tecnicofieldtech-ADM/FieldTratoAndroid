const fs = require("fs");
const path = require("path");

const LABEL = {
  fazendas: "Fazendas",
  usuarios: "Usuários",
  vagoes: "Vagões",
  baias: "Baias",
  dietas: "Dietas",
  dietas_detalhes: "Ingredientes das dietas",
  previsao_trato: "Previsão de trato",
};

function logPath() {
  return path.join(__dirname, "..", "sync-log.txt");
}

function fmtWhen(iso) {
  if (!iso) return "—";
  try {
    return new Date(iso).toLocaleString("pt-BR");
  } catch {
    return String(iso);
  }
}

function countsLines(counts, indent = "  ") {
  if (!counts || typeof counts !== "object") return `${indent}(sem contagem)\n`;
  let out = "";
  for (const [k, label] of Object.entries(LABEL)) {
    if (counts[k] == null) continue;
    out += `${indent}- ${label}: ${counts[k]}\n`;
  }
  return out || `${indent}(sem contagem)\n`;
}

function formatPushText(data) {
  const ok =
    data &&
    data.ok !== false &&
    data.cloud &&
    data.cloud.success !== false &&
    !data.error;
  const counts =
    (data && data.local_counts) ||
    (data && data.cloud && data.cloud.counts) ||
    {};
  let t = ok
    ? "RESULTADO: Subida concluída com sucesso\n"
    : "RESULTADO: Falha ao subir dados\n";
  if (ok) {
    t += "Os cadastros do FieldPec foram enviados para a nuvem.\n";
    t += "Quantidade enviada:\n" + countsLines(counts);
  } else {
    t +=
      "Erro: " +
      ((data && (data.error || (data.cloud && data.cloud.error))) ||
        "desconhecido") +
      "\n";
  }
  t += "Horário: " + fmtWhen(data && (data.finished || data.started)) + "\n";
  return t;
}

function formatPullText(data) {
  const ok = data && data.ok !== false && !data.error;
  const fab = (data && data.pending_fab) || 0;
  const forn = (data && data.pending_forn) || 0;
  const ackedFab = (data && data.acked_fab) || 0;
  const ackedForn = (data && data.acked_forn) || 0;
  let t = ok
    ? "RESULTADO: Download da nuvem concluído\n"
    : "RESULTADO: Falha ao baixar da nuvem\n";
  if (!ok) {
    t += "Erro: " + ((data && data.error) || "desconhecido") + "\n";
  } else if (fab === 0 && forn === 0) {
    t +=
      "Não havia fabricação nem fornecimento pendente na nuvem.\n" +
      "(Normal se o tablet ainda não enviou operações novas.)\n";
  } else {
    t += `Pendentes na nuvem: ${fab} fab / ${forn} forn\n`;
    t += `Gravados no Field: ${ackedFab} fab / ${ackedForn} forn\n`;
    if (data && data.mode) t += `Modo: ${data.mode}\n`;
  }
  if (data && Array.isArray(data.logs) && data.logs.length) {
    t += "Detalhes:\n";
    for (const line of data.logs) t += "  - " + line + "\n";
  }
  if (data && data.note) t += data.note + "\n";
  t += "Horário: " + fmtWhen(data && (data.finished || data.started)) + "\n";
  return t;
}

function formatFullText(data) {
  const errs = (data && data.errors) || [];
  const ok = errs.length === 0 && data && !data.error;
  let t = "========================================\n";
  t += ok
    ? "SINCRONIZAÇÃO CONCLUÍDA\n"
    : "SINCRONIZAÇÃO COM PROBLEMAS\n";
  t += "Início: " + fmtWhen(data && data.started) + "\n";
  t += "Fim:    " + fmtWhen(data && data.finished) + "\n";
  t += "----------------------------------------\n";
  if (data && data.push) {
    t += "1) SUBIR CADASTROS\n";
    t += formatPushText(data.push);
    t += "----------------------------------------\n";
  }
  if (data && data.pull) {
    t += "2) BAIXAR OPERAÇÕES\n";
    t += formatPullText(data.pull);
  }
  if (errs.length) {
    t += "ERROS:\n";
    errs.forEach((e) => {
      t += "  - " + (typeof e === "string" ? e : JSON.stringify(e)) + "\n";
    });
  }
  t += "========================================\n\n";
  return t;
}

function appendHumanLog(kind, data) {
  let block = "\n";
  if (kind === "full") block += formatFullText(data);
  else if (kind === "push") {
    block += "========================================\n";
    block += "SUBIR DADOS\n";
    block += formatPushText(data);
    block += "========================================\n\n";
  } else if (kind === "pull") {
    block += "========================================\n";
    block += "BAIXAR DADOS\n";
    block += formatPullText(data);
    block += "========================================\n\n";
  } else {
    block += String(kind) + "\n" + JSON.stringify(data, null, 2) + "\n\n";
  }
  try {
    const p = logPath();
    if (!fs.existsSync(p)) {
      fs.writeFileSync(p, "\uFEFFLog do Conector FieldPec Online\n", "utf8");
    }
    fs.appendFileSync(p, block, "utf8");
  } catch (e) {
    console.error("Falha ao gravar sync-log.txt:", e.message);
  }
  return block;
}

module.exports = {
  appendHumanLog,
  formatFullText,
  formatPushText,
  formatPullText,
  logPath,
};
