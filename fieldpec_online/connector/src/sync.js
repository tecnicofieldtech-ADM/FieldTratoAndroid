const config = require("./config");
const fb = require("./firebird");

async function httpJson(url, opts = {}) {
  const headers = {
    Accept: "application/json",
    ...(opts.headers || {}),
  };
  if (opts.body != null) {
    headers["Content-Type"] = "application/json";
  }
  let res;
  try {
    res = await fetch(url, {
      method: opts.method || "GET",
      headers,
      body: opts.body != null ? JSON.stringify(opts.body) : undefined,
      signal: AbortSignal.timeout(15000),
    });
  } catch (e) {
    const cause = e.cause ? ` (${e.cause.code || e.cause.message || e.cause})` : "";
    throw new Error(`fetch failed${cause}: ${url} — ${e.message}`);
  }
  const text = await res.text();
  let data = null;
  try {
    data = text ? JSON.parse(text) : null;
  } catch {
    data = text;
  }
  if (!res.ok) {
    const err = new Error(
      `HTTP ${res.status} ${url}: ${typeof data === "string" ? data : JSON.stringify(data)}`,
    );
    err.status = res.status;
    err.data = data;
    throw err;
  }
  return data;
}

function localUrl(path) {
  return `${config.localHorseBase.replace(/\/$/, "")}${path}`;
}

function cloudUrl(path) {
  return `${config.cloudApiBase.replace(/\/$/, "")}${path}`;
}

function requireClientCode() {
  const code = String(config.clientCode || "")
    .trim()
    .toUpperCase();
  if (!code) {
    throw new Error(
      "CLIENT_CODE vazio. Em Configuração do conector, informe o código da licença (ex.: 2411141) e Salve.",
    );
  }
  return code;
}

function adminHeaders() {
  const code = requireClientCode();
  const h = {
    "X-Client-Code": code,
  };
  if (config.adminToken && config.adminToken !== "open") {
    h.Authorization = `Bearer ${config.adminToken}`;
  }
  return h;
}

function clientBody(extra = {}) {
  const code = requireClientCode();
  return {
    ...extra,
    client_code: code,
    cliente_codigo: code,
    CLIENT_CODE: code,
  };
}

/** Garante client_code também na query (mais confiável que só header/body). */
function cloudAdminUrl(path) {
  const code = encodeURIComponent(requireClientCode());
  const base = cloudUrl(path);
  const sep = base.includes("?") ? "&" : "?";
  return `${base}${sep}client_code=${code}`;
}

async function getLocalArray(path) {
  const data = await httpJson(localUrl(path));
  return Array.isArray(data) ? data : [];
}

async function pushMasterFromHorse() {
  const idF = (config.idFazenda || "").trim();
  const suffix = idF ? `/${encodeURIComponent(idF)}` : "";

  const [
    fazendas,
    usuarios,
    vagoes,
    baias,
    dietas,
    dietas_detalhes,
    previsao_trato,
  ] = await Promise.all([
    getLocalArray("/fazenda/get"),
    getLocalArray(`/usuarios/get${suffix}`),
    getLocalArray("/vagao/get"),
    getLocalArray(`/baias/get${suffix}`),
    getLocalArray(`/dietas/get${suffix}`),
    getLocalArray(`/dietas_detalhes/get${suffix}`),
    getLocalArray(
      idF
        ? `/previsao_trato/get/${encodeURIComponent(idF)}/${new Date().toISOString().slice(0, 10)}`
        : "/previsao_trato/get",
    ),
  ]);

  const previsaoTagged = previsao_trato.map((p) => ({
    ...p,
    id_fazenda: p.id_fazenda || p.ID_FAZENDA || idF || null,
    data: p.data || p.DATA || new Date().toISOString().slice(0, 10),
  }));

  return {
    id_fazenda: idF || undefined,
    fazendas,
    usuarios,
    vagoes,
    baias,
    dietas,
    dietas_detalhes,
    previsao_trato: previsaoTagged,
  };
}

async function pushMasterFromLocal() {
  const body =
    config.sourceMode === "firebird"
      ? await fb.loadMasterFromFirebird()
      : await pushMasterFromHorse();

  const result = await httpJson(cloudAdminUrl("/admin/sync/master"), {
    method: "POST",
    headers: adminHeaders(),
    body: clientBody(body),
  });

  return {
    source: config.sourceMode,
    cliente_codigo: config.clientCode,
    local_counts: {
      fazendas: (body.fazendas || []).length,
      usuarios: (body.usuarios || []).length,
      vagoes: (body.vagoes || []).length,
      baias: (body.baias || []).length,
      dietas: (body.dietas || []).length,
      dietas_detalhes: (body.dietas_detalhes || []).length,
      previsao_trato: (body.previsao_trato || []).length,
    },
    cloud: result,
  };
}

async function pullOpsToLocal() {
  const pending = await httpJson(cloudAdminUrl("/admin/sync/pending"), {
    headers: adminHeaders(),
  });

  const fabIds = [];
  const fornIds = [];
  const logs = [];
  const writeEnabled = !!config.replayToLocalHorse;
  const useFirebird = config.sourceMode === "firebird";

  if (!writeEnabled) {
    logs.push(
      "REPLAY_TO_LOCAL=0 — só consulta a nuvem (não grava no Field).",
    );
    return {
      cliente_codigo: config.clientCode,
      pending_fab: (pending.fabricacoes || []).length,
      pending_forn: (pending.fornecimentos || []).length,
      acked_fab: 0,
      acked_forn: 0,
      ack: null,
      logs,
      note:
        "Ative REPLAY_TO_LOCAL=1 na Configuração para gravar no Firebird (ou Horse se mode=horse).",
    };
  }

  if (useFirebird) {
    logs.push("Gravando no Firebird FieldPec (sem Horse)…");
    for (const fab of pending.fabricacoes || []) {
      try {
        const payload =
          fab.payload && typeof fab.payload === "object" ? fab.payload : {};
        // Itens podem vir embutidos no pending
        if (!Array.isArray(payload.itens) || payload.itens.length === 0) {
          if (Array.isArray(fab.itens)) payload.itens = fab.itens;
        }
        const r = await fb.insertFabricacaoFromPayload(payload);
        fabIds.push(fab.id);
        logs.push(
          `fab OK nuvem=#${fab.id} → FABRICACAO.ID=${r.id_servidor} lote=${r.lote_fabricacao} itens=${r.itens_processados}`,
        );
      } catch (e) {
        logs.push(`fab FAIL nuvem=#${fab.id}: ${e.message}`);
      }
    }

    for (const forn of pending.fornecimentos || []) {
      try {
        const payload =
          forn.payload && typeof forn.payload === "object"
            ? forn.payload
            : {};
        // Garante campos tipados da nuvem no payload
        if (forn.id_fornecimento && !payload.id && !payload.id_fornecimento) {
          payload.id_fornecimento = forn.id_fornecimento;
        }
        const r = await fb.updateFornecimentoFromPayload(payload);
        fornIds.push(forn.id);
        logs.push(
          `forn OK nuvem=#${forn.id} → CONF.ID=${r.id} realizado ${r.realizado_anterior}→${r.realizado_gravado}`,
        );
      } catch (e) {
        logs.push(`forn FAIL nuvem=#${forn.id}: ${e.message}`);
      }
    }
  } else {
    logs.push("Gravando via Horse local (SOURCE_MODE=horse)…");
    for (const fab of pending.fabricacoes || []) {
      try {
        await httpJson(localUrl("/Post/Fabricacao"), {
          method: "POST",
          body: fab.payload,
        });
        fabIds.push(fab.id);
        logs.push(`fab ok id=${fab.id} local=${fab.id_local || ""}`);
      } catch (e) {
        logs.push(`fab FAIL id=${fab.id}: ${e.message}`);
      }
    }

    for (const forn of pending.fornecimentos || []) {
      try {
        await httpJson(localUrl("/Post/Fornecimento"), {
          method: "POST",
          body: forn.payload,
        });
        fornIds.push(forn.id);
        logs.push(`forn ok id=${forn.id}`);
      } catch (e) {
        logs.push(`forn FAIL id=${forn.id}: ${e.message}`);
      }
    }
  }

  let ack = null;
  if (fabIds.length || fornIds.length) {
    ack = await httpJson(cloudAdminUrl("/admin/sync/ack"), {
      method: "POST",
      headers: adminHeaders(),
      body: clientBody({
        fabricacao_ids: fabIds,
        fornecimento_ids: fornIds,
      }),
    });
    logs.push(
      `Ack nuvem: ${fabIds.length} fab + ${fornIds.length} forn marcados como baixados.`,
    );
  }

  return {
    cliente_codigo: config.clientCode,
    mode: useFirebird ? "firebird" : "horse",
    pending_fab: (pending.fabricacoes || []).length,
    pending_forn: (pending.fornecimentos || []).length,
    acked_fab: fabIds.length,
    acked_forn: fornIds.length,
    ack,
    logs,
  };
}

async function runFullSync() {
  const started = new Date().toISOString();
  const out = {
    started,
    source: config.sourceMode,
    push: null,
    pull: null,
    errors: [],
  };

  if (config.pushMaster) {
    try {
      out.push = await pushMasterFromLocal();
    } catch (e) {
      out.errors.push(`push: ${e.message}`);
    }
  }

  if (config.pullOps) {
    try {
      out.pull = await pullOpsToLocal();
    } catch (e) {
      out.errors.push(`pull: ${e.message}`);
    }
  }

  out.finished = new Date().toISOString();
  return out;
}

async function cloudStats() {
  return httpJson(cloudAdminUrl("/admin/stats"), { headers: adminHeaders() });
}

function normalizeFabRow(row) {
  const payload =
    row.payload && typeof row.payload === "object" ? row.payload : {};
  const itens = Array.isArray(row.itens)
    ? row.itens
    : Array.isArray(payload.itens)
      ? payload.itens
      : [];
  return {
    id: row.id,
    id_local: row.id_local,
    handoff_id: row.handoff_id,
    id_fazenda: row.id_fazenda || payload.id_fazenda || null,
    id_dieta: row.id_dieta || payload.id_dieta || payload.ID_DIETA || null,
    data_fab: row.data_fab || payload.data || null,
    qtde_prevista: row.qtde_prevista ?? payload.qtde_prevista ?? null,
    qtde_realizada: row.qtde_realizada ?? payload.qtde_realizada ?? null,
    lote_fabricacao: row.lote_fabricacao || payload.lote_fabricacao || null,
    pulled_to_fieldpec: !!row.pulled_to_fieldpec,
    pulled_at: row.pulled_at || null,
    created_at: row.created_at || null,
    itens,
    payload,
  };
}

function normalizeFornRow(row) {
  const payload =
    row.payload && typeof row.payload === "object" ? row.payload : {};
  return {
    id: row.id,
    id_fornecimento: row.id_fornecimento || payload.id || payload.ID || null,
    id_fabricacao_local: row.id_fabricacao_local || null,
    handoff_id_fabricacao: row.handoff_id_fabricacao || null,
    id_baia: row.id_baia || payload.id_baia || payload.ID_BAIA || null,
    id_racao: row.id_racao || payload.id_racao || null,
    data_forn: row.data_forn || payload.data || null,
    trato: row.trato ?? payload.trato ?? payload.TRATO ?? null,
    realizado: row.realizado ?? payload.realizado ?? payload.REALIZADO ?? null,
    lote_fabricacao: row.lote_fabricacao || null,
    pulled_to_fieldpec: !!row.pulled_to_fieldpec,
    pulled_at: row.pulled_at || null,
    created_at: row.created_at || null,
    payload,
  };
}

/** Fallback quando a API ainda não tem GET /admin/sync/ops. */
async function listCloudOpsLegacy({ status = "all", limit = 100 } = {}) {
  const lim = Math.min(Math.max(Number(limit) || 100, 1), 500);
  const st = String(status || "all").toLowerCase();

  const [fabRes, fornRes, stats] = await Promise.all([
    httpJson(`${cloudAdminUrl("/admin/data/fabricacoes")}&limit=${lim}`, {
      headers: adminHeaders(),
    }),
    httpJson(`${cloudAdminUrl("/admin/data/fornecimentos")}&limit=${lim}`, {
      headers: adminHeaders(),
    }),
    cloudStats().catch(() => ({})),
  ]);

  let fabricacoes = (fabRes.rows || []).map(normalizeFabRow);
  let fornecimentos = (fornRes.rows || []).map(normalizeFornRow);

  if (st === "pending" || st === "pendente") {
    fabricacoes = fabricacoes.filter((f) => !f.pulled_to_fieldpec);
    fornecimentos = fornecimentos.filter((f) => !f.pulled_to_fieldpec);
  } else if (st === "done" || st === "pulled" || st === "baixado") {
    fabricacoes = fabricacoes.filter((f) => f.pulled_to_fieldpec);
    fornecimentos = fornecimentos.filter((f) => f.pulled_to_fieldpec);
  }

  return {
    success: true,
    cliente_codigo: requireClientCode(),
    status:
      st === "pending" || st === "pendente"
        ? "pending"
        : st === "done" || st === "pulled" || st === "baixado"
          ? "done"
          : "all",
    limit: lim,
    source: "legacy-admin-data",
    summary: {
      fabricacoes_pendentes: stats.fabricacoes_pendentes_fieldpec ?? 0,
      fabricacoes_no_field: Math.max(
        0,
        (stats.fabricacoes_total || 0) - (stats.fabricacoes_pendentes_fieldpec || 0),
      ),
      fornecimentos_pendentes: stats.fornecimentos_pendentes_fieldpec ?? 0,
      fornecimentos_no_field: Math.max(
        0,
        (stats.fornecimentos_total || 0) -
          (stats.fornecimentos_pendentes_fieldpec || 0),
      ),
    },
    fabricacoes,
    fornecimentos,
  };
}

async function listCloudOps({ status = "all", limit = 100 } = {}) {
  const st = encodeURIComponent(String(status || "all"));
  const lim = encodeURIComponent(String(limit || 100));
  const url = `${cloudAdminUrl("/admin/sync/ops")}&status=${st}&limit=${lim}`;
  try {
    return await httpJson(url, { headers: adminHeaders() });
  } catch (e) {
    const msg = String(e.message || e);
    if (e.status === 404 || /not found|404/i.test(msg)) {
      return listCloudOpsLegacy({ status, limit });
    }
    throw e;
  }
}

async function probe() {
  const result = {
    source_mode: config.sourceMode,
    client_code: config.clientCode,
    cloud_api_url: config.cloudApiBase,
    local: null,
    cloud: null,
  };

  if (config.sourceMode === "firebird") {
    result.local = await fb.probeFirebird();
  } else {
    try {
      result.local = await httpJson(localUrl("/GetTeste"));
    } catch (e) {
      result.local = { error: e.message };
    }
  }

  try {
    // GetTeste não exige tenant; confere API + cadastro do cliente
    result.cloud = await httpJson(cloudUrl("/GetTeste"));
    try {
      result.cliente = await httpJson(cloudAdminUrl("/admin/stats"), {
        headers: adminHeaders(),
      });
    } catch (e) {
      result.cliente = { error: e.message };
    }
  } catch (e) {
    result.cloud = {
      error: e.message,
      tip:
        "Use http://IP:3111 (sem barra antes da porta). Ex.: http://15.229.92.98:3111",
    };
  }
  return result;
}

module.exports = {
  runFullSync,
  pushMasterFromLocal,
  pullOpsToLocal,
  cloudStats,
  listCloudOps,
  probe,
  config,
};
