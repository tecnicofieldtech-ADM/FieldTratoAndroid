(function (global) {
  /** Versão esperada do pacote web + exe (atualize junto com UApiVersion.pas). */
  const EXPECTED = {
    version: "1.0.18",
    build: 2032,
    label: "1.0.18+2032",
  };

  async function fetchRunning(configFallback) {
    try {
      const res = await fetch("/api/version");
      const data = await res.json();
      if (res.ok) return { ...data, source: "version" };
    } catch (_) {
      /* tenta /api/config */
    }
    if (configFallback && (configFallback.version || configFallback.label)) {
      return {
        version: configFallback.version,
        build: configFallback.build,
        label: configFallback.label || `${configFallback.version}+${configFallback.build}`,
        exeModified: configFallback.exeModified,
        source: "config",
      };
    }
    const res = await fetch("/api/config");
    const data = await res.json();
    if (!res.ok) throw new Error(data.erro || "Falha ao consultar versão (/api/version e /api/config)");
    if (!data.version && !data.label) {
      throw new Error("Servidor sem UApiVersion — recompile e reinicie ApiRFeedWindows.exe");
    }
    return {
      version: data.version,
      build: data.build,
      label: data.label || `${data.version}+${data.build}`,
      exeModified: data.exeModified,
      source: "config",
    };
  }

  function isUpToDate(running) {
    return (
      String(running.version) === EXPECTED.version &&
      Number(running.build) === EXPECTED.build
    );
  }

  function formatRunning(running) {
    const label = running.label || `${running.version}+${running.build}`;
    const mod = running.exeModified ? ` · exe ${running.exeModified}` : "";
    return `${label}${mod}`;
  }

  async function renderBadge(elementId, configFallback) {
    const el = document.getElementById(elementId);
    if (!el) return null;

    el.textContent = "Verificando versão da API…";
    el.className =
      "mt-3 inline-flex rounded-full px-3 py-1 text-xs font-medium ring-1 bg-slate-100 text-slate-700 ring-slate-300";

    try {
      const running = await fetchRunning(configFallback);
      const ok = isUpToDate(running);
      const srcNote = running.source === "config" ? " (via /api/config)" : "";
      el.textContent = ok
        ? `API atualizada · ${formatRunning(running)}${srcNote}`
        : `API desatualizada · rodando ${formatRunning(running)}${srcNote} · esperado ${EXPECTED.label}`;
      el.className = ok
        ? "mt-3 inline-flex rounded-full bg-emerald-900/40 px-3 py-1 text-xs font-semibold text-emerald-100 ring-1 ring-emerald-600"
        : "mt-3 inline-flex rounded-full bg-amber-900/50 px-3 py-1 text-xs font-semibold text-amber-100 ring-1 ring-amber-500";
      el.title = ok
        ? "Versão da API coincide com o pacote web instalado."
        : "Recompile e reinicie ApiRFeedWindows.exe (Win32) e copie web-admin.";
      return { ok, running, expected: EXPECTED };
    } catch (e) {
      el.textContent = "Versão da API indisponível";
      el.className =
        "mt-3 inline-flex rounded-full bg-red-900/40 px-3 py-1 text-xs font-semibold text-red-100 ring-1 ring-red-600";
      el.title = e.message || String(e);
      return { ok: false, error: e };
    }
  }

  global.RFeedApiVersion = {
    EXPECTED,
    fetchRunning,
    isUpToDate,
    renderBadge,
  };
})(window);
