const config = require("../config");

/**
 * Consulta a API de licenças FieldPec:
 * GET {base}/GeLicenca/{codigoCliente}/{idSistema}
 * Basic Auth
 */
async function fetchLicenca(codigoCliente, { idSistema } = {}) {
  const code = String(codigoCliente || "").trim();
  if (!code) throw new Error("Código do cliente vazio para validar licença.");

  const sistema = String(idSistema || config.licenseSistemaId || "1");
  const base = String(config.licenseApiBase || "").replace(/\/+$/, "");
  if (!base) {
    throw new Error(
      "LICENSE_API_URL não configurada. Defina no .env (ex.: http://15.229.92.98:8888).",
    );
  }

  const url = `${base}/GeLicenca/${encodeURIComponent(code)}/${encodeURIComponent(sistema)}`;
  const user = config.licenseUser || "";
  const pass = config.licensePassword || "";
  const auth =
    user || pass
      ? "Basic " + Buffer.from(`${user}:${pass}`).toString("base64")
      : null;

  let res;
  try {
    res = await fetch(url, {
      method: "GET",
      headers: {
        Accept: "application/json",
        ...(auth ? { Authorization: auth } : {}),
      },
      signal: AbortSignal.timeout(12000),
    });
  } catch (e) {
    const cause = e.cause ? ` (${e.cause.code || e.cause.message || e.cause})` : "";
    throw new Error(`Falha ao consultar licença${cause}: ${e.message}`);
  }

  const text = await res.text();
  let data;
  try {
    data = text ? JSON.parse(text) : null;
  } catch {
    throw new Error(`Resposta inválida da API de licença (HTTP ${res.status}).`);
  }

  if (data && data.Erro) {
    const err = new Error(String(data.Erro));
    err.code = "LICENSE_NOT_FOUND";
    err.data = data;
    throw err;
  }

  if (!res.ok) {
    throw new Error(
      `API de licença HTTP ${res.status}: ${typeof data === "string" ? data : JSON.stringify(data)}`,
    );
  }

  const list = (data && data.SistemasClientes) || [];
  if (!Array.isArray(list) || list.length === 0) {
    const err = new Error("Cliente não encontrado na API de licença.");
    err.code = "LICENSE_NOT_FOUND";
    throw err;
  }

  // Preferência: sistema FIELD PEC / id_sistema = 1
  const item =
    list.find((x) => String(x.id_sistema) === sistema) ||
    list.find((x) => String(x.sistema || "").toUpperCase().includes("FIELD")) ||
    list[0];

  return { raw: data, item, url };
}

/**
 * Valida se o cliente existe e a licença está ativa.
 * Retorna { ok, codigo, nome, licenca, ... }
 */
async function validateClienteLicenca(codigoCliente) {
  const { item, raw, url } = await fetchLicenca(codigoCliente);

  const statusLicenca = String(item.status_licenca ?? item.status ?? "").trim();
  const statusStr = String(item.statuslicencastr || "").trim();
  const ativa =
    statusLicenca === "1" ||
    statusStr.toLowerCase() === "ativa" ||
    String(item.status) === "1";

  const codigo =
    String(item.id_cliente || codigoCliente).trim() || String(codigoCliente);
  const nome =
    String(item.sistema || "").trim() ||
    `Cliente ${codigo}`;

  if (!ativa) {
    const err = new Error(
      `Licença inativa para cliente '${codigo}'` +
        (statusStr ? ` (${statusStr})` : "") +
        (item.vencimento ? ` · vencimento ${item.vencimento}` : ""),
    );
    err.code = "LICENSE_INACTIVE";
    err.licenca = item;
    throw err;
  }

  return {
    ok: true,
    codigo,
    nome: nome.includes("FIELD") ? `FieldPec ${codigo}` : nome,
    sistema: item.sistema,
    vencimento: item.vencimento || null,
    statuslicencastr: statusStr || (ativa ? "Ativa" : ""),
    numversao: item.numversao || null,
    chave_key: item.chave_key || null,
    licenca: item,
    source_url: url,
    raw,
  };
}

module.exports = {
  fetchLicenca,
  validateClienteLicenca,
};
