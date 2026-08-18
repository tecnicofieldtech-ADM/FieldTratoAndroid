/** Converte números no estilo BR ("1.234,56" / "12,5") para Number. */
function toNum(v) {
  if (v == null || v === "") return 0;
  if (typeof v === "number") return Number.isFinite(v) ? v : 0;
  let t = String(v).trim();
  if (!t || t.toLowerCase() === "null") return 0;
  const hasComma = t.includes(",");
  const hasDot = t.includes(".");
  if (hasComma && hasDot) t = t.replace(/\./g, "").replace(",", ".");
  else if (hasComma) t = t.replace(",", ".");
  const n = Number(t);
  return Number.isFinite(n) ? n : 0;
}

function pick(obj, keys, fallback = "") {
  if (!obj || typeof obj !== "object") return fallback;
  for (const k of keys) {
    if (obj[k] != null && String(obj[k]).trim() !== "") return obj[k];
    const found = Object.keys(obj).find(
      (ok) => ok.toLowerCase() === String(k).toLowerCase(),
    );
    if (found != null && obj[found] != null && String(obj[found]).trim() !== "") {
      return obj[found];
    }
  }
  return fallback;
}

function pickStr(obj, keys, fallback = "") {
  return String(pick(obj, keys, fallback) ?? "").trim();
}

/** Aceita YYYY-MM-DD ou DD/MM/YYYY → Date ou null. */
function parseDate(v) {
  const t = String(v ?? "").trim();
  if (!t) return null;
  const base = t.length >= 10 ? t.slice(0, 10) : t;
  if (/^\d{4}-\d{2}-\d{2}$/.test(base)) return base;
  const m = /^(\d{2})\/(\d{2})\/(\d{4})$/.exec(base);
  if (m) return `${m[3]}-${m[2]}-${m[1]}`;
  return null;
}

function todayYmd() {
  return new Date().toISOString().slice(0, 10);
}

module.exports = { toNum, pick, pickStr, parseDate, todayYmd };
