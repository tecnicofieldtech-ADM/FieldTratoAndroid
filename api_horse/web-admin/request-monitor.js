/**
 * Monitor de requisições do tablet (polling /api/request-logs).
 * Uso: RFeedRequestMonitor.init({ prefix: "mon" });
 */
(function (global) {
  function esc(s) {
    return String(s ?? "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;");
  }

  function el(id) {
    return document.getElementById(id);
  }

  function init(opts) {
    const prefix = opts && opts.prefix ? opts.prefix + "-" : "";
    const tbody = el(prefix + "tbody");
    const countBadge = el(prefix + "countBadge");
    const filePath = el(prefix + "filePath");
    const onlyErrors = el(prefix + "onlyErrors");
    const btnClear = el(prefix + "btnClear");

    if (!tbody || !countBadge) return;

    function render(items) {
      const filtered = onlyErrors && onlyErrors.checked ? items.filter((x) => !x.ok) : items;
      countBadge.textContent = filtered.length + " evento(s)";
      tbody.innerHTML = filtered
        .map(
          (it) => `
        <tr class="border-t border-slate-100 align-top">
          <td class="px-3 py-2 whitespace-nowrap text-slate-600">${esc(new Date(it.at).toLocaleString("pt-BR"))}</td>
          <td class="px-3 py-2 font-semibold">${esc(it.method)}</td>
          <td class="px-3 py-2 font-mono text-xs">${esc(it.route)}</td>
          <td class="px-3 py-2 text-xs text-slate-600">${esc(it.clientIp || "-")}</td>
          <td class="px-3 py-2">
            <span class="rounded px-2 py-0.5 text-xs font-semibold ${it.ok ? "bg-emerald-100 text-emerald-800" : "bg-rose-100 text-rose-800"}">${esc(it.statusCode)}</span>
          </td>
          <td class="px-3 py-2">${esc(it.durationMs)}</td>
          <td class="max-w-[360px] px-3 py-2 font-mono text-xs text-slate-600">${esc(it.requestPreview || "-")}</td>
          <td class="max-w-[240px] px-3 py-2 text-xs text-rose-700">${esc(it.error || "-")}</td>
        </tr>`
        )
        .join("");
      if (!filtered.length) {
        tbody.innerHTML =
          '<tr><td colspan="8" class="px-3 py-8 text-center text-slate-500">Nenhum evento ainda. Use o tablet para sincronizar.</td></tr>';
      }
    }

    async function load() {
      try {
        const res = await fetch("/api/request-logs?limit=300", { cache: "no-store" });
        const data = await res.json();
        const items = Array.isArray(data.items) ? data.items : [];
        if (filePath && data.filePath) filePath.textContent = "Arquivo: " + data.filePath;
        render(items);
      } catch {
        countBadge.textContent = "Falha ao carregar";
      }
    }

    if (btnClear) {
      btnClear.addEventListener("click", async () => {
        if (!confirm("Limpar todos os logs?")) return;
        await fetch("/api/request-logs", { method: "DELETE" });
        await load();
      });
    }
    if (onlyErrors) onlyErrors.addEventListener("change", load);

    load();
    setInterval(load, 2000);
  }

  function initNav(active) {
    document.querySelectorAll("[data-admin-nav]").forEach((a) => {
      const page = a.getAttribute("data-admin-nav");
      const on = page === active;
      a.classList.toggle("bg-slate-900", on);
      a.classList.toggle("text-white", on);
      a.classList.toggle("shadow-sm", on);
      a.classList.toggle("text-slate-700", !on);
      a.classList.toggle("hover:bg-slate-100", !on);
    });
  }

  global.RFeedRequestMonitor = { init, initNav };
})(window);
