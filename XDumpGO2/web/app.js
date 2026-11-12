"use strict";

const gw = window.goWebView;

const $ = (s) => document.querySelector(s);
const $$ = (s) => Array.from(document.querySelectorAll(s));

// parseRet tolera que el bridge devuelva string JSON u objeto ya parseado.
function parseRet(v) {
  if (v === undefined || v === null) return v;
  if (typeof v === "object") return v;
  try { return JSON.parse(v); } catch (e) { return v; }
}

function call(name, ...args) {
  if (!gw || typeof gw[name] !== "function") {
    throw new Error("goWebView." + name + " no disponible (ejecuta xdumpgo2.exe)");
  }
  return gw[name](...args);
}
const callJSON = (name, obj) => parseRet(call(name, JSON.stringify(obj)));
const getJSON = (name) => parseRet(call(name));
const results = (kind) => parseRet(call("getResults", kind));

let toastTimer = null;
function toast(msg, kind = "info") {
  const t = $("#toast");
  t.textContent = msg;
  t.className = "show " + kind;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => (t.className = ""), 3500);
}

function lines(v) {
  return v.split(/\r?\n/).map((s) => s.trim()).filter(Boolean);
}

function esc(s) {
  return String(s == null ? "" : s).replace(/[&<>"']/g, (c) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
  }[c]));
}

function copyText(t) {
  if (!t) { toast("nada que copiar", "err"); return; }
  const done = () => toast("copiado al portapapeles", "ok");
  if (navigator.clipboard && navigator.clipboard.writeText) {
    navigator.clipboard.writeText(t).then(done, done);
  } else {
    const ta = document.createElement("textarea");
    ta.value = t; document.body.appendChild(ta); ta.select();
    document.execCommand("copy"); ta.remove(); done();
  }
}

function exportText(name, content) {
  if (!content) { toast("nada que exportar", "err"); return; }
  try {
    const r = parseRet(call("exportFile", name, content));
    if (r && r.ok) {
      toast("Guardado en tu PC: " + r.path, "ok");
      call("openFile", r.path);
    } else toast((r && r.error) || "error", "err");
  } catch (e) { toast(e.message, "err"); }
}

// ---------- Tabs ----------
let currentTab = "dorks";
$$(".tab").forEach((b) => b.addEventListener("click", () => {
  $$(".tab").forEach((x) => x.classList.remove("active"));
  $$(".panel").forEach((x) => x.classList.remove("active"));
  b.classList.add("active");
  $("#tab-" + b.dataset.tab).classList.add("active");
  currentTab = b.dataset.tab;
  renderTab(currentTab);
}));

function renderTab(tab) {
  if (tab === "dorks") renderDorks();
  if (tab === "parse") renderURLs();
  if (tab === "inject") renderInjects();
  if (tab === "dump") renderDumps();
  if (tab === "shell") renderShell();
  if (tab === "settings") renderLogs();
}

// ---------- Stats (polling) ----------
function updateStats(s) {
  const run = $("#st-run");
  if (s.running) {
    run.textContent = "● " + s.job.name;
    run.classList.add("on");
    const pct = s.job.total ? Math.round((s.job.done / s.job.total) * 100) : 0;
    $("#st-prog").textContent = s.job.done + "/" + s.job.total + " (" + pct + "%)";
    $("#st-speed").textContent = s.job.speed.toFixed(1) + "/s · " + s.elapsedSec.toFixed(0) + "s";
  } else {
    run.textContent = "idle";
    run.classList.remove("on");
    $("#st-prog").textContent = "";
    $("#st-speed").textContent = "";
  }
  $("#st-counts").textContent =
    "dorks " + s.dorks + " · urls " + s.urls +
    " · inject " + s.injects + " (" + s.reflected + " reflejo)" +
    " · dumps " + s.dumps;
}

setInterval(() => {
  try {
    const s = getJSON("getStats");
    if (!s || typeof s !== "object") return;
    updateStats(s);
    if (s.running) renderTab(currentTab);
  } catch (e) { /* UI aún cargando */ }
}, 900);

// ---------- Dorks ----------
function renderDorks() {
  let ds = results("dorks");
  if (!Array.isArray(ds)) ds = [];
  $("#d-count").textContent = ds.length;
  const el = $("#dork-list");
  if (!ds.length) { el.innerHTML = '<div class="empty">Sin dorks todavía.</div>'; return; }
  const MAX = 400;
  el.innerHTML = ds.slice(0, MAX).map((d) =>
    '<div class="row-item"><code>' + esc(d.text) + "</code></div>"
  ).join("") + (ds.length > MAX ? '<div class="empty">…y ' + (ds.length - MAX) + " más</div>" : "");
}

$("#btn-dorks").addEventListener("click", () => {
  try {
    const modes = [];
    if ($("#d-mode-site").checked) modes.push("site");
    if ($("#d-mode-inurl").checked) modes.push("inurl");
    const r = callJSON("genDorks", {
      keywords: lines($("#d-words").value),
      domains: lines($("#d-domains").value),
      params: $("#d-params").value.split(/\s+/).filter(Boolean),
      max: +$("#d-max").value || 300,
      modes: modes,
    });
    if (r.ok) { toast(r.count + " dorks generadas", "ok"); renderDorks(); }
    else toast(r.error || "error", "err");
  } catch (e) { toast(e.message, "err"); }
});

$("#btn-copy-dorks").addEventListener("click", () => {
  const ds = results("dorks");
  copyText(Array.isArray(ds) ? ds.map((d) => d.text).join("\n") : "");
});

$("#btn-export-dorks").addEventListener("click", () => {
  const ds = results("dorks");
  exportText("dorks.txt", Array.isArray(ds) ? ds.map((d) => d.text).join("\n") : "");
});

// ---------- Parse / URLs ----------
function renderURLs() {
  let us = results("urls");
  if (!Array.isArray(us)) us = [];
  const onlyP = $("#u-only-params").checked;
  const view = onlyP ? us.filter((u) => u.params && u.params.length) : us;
  $("#u-count").textContent = view.length;
  const el = $("#url-list");
  if (!view.length) { el.innerHTML = '<div class="empty">Sin URLs todavía.</div>'; return; }
  const MAX = 300;
  el.innerHTML =
    '<table><thead><tr><th>ID</th><th>Host</th><th>Path</th><th>Params</th><th>Source</th></tr></thead><tbody>' +
    view.slice(0, MAX).map((u) =>
      "<tr><td>" + u.id + "</td><td>" + esc(u.host) + "</td><td>" + esc(u.path) +
      "</td><td>" + esc((u.params || []).join(",")) +
      "</td><td class='dim'>" + esc(u.source) + "</td></tr>"
    ).join("") +
    "</tbody></table>" +
    (view.length > MAX ? '<div class="empty">…y ' + (view.length - MAX) + " más</div>" : "");
}

$("#u-only-params").addEventListener("change", renderURLs);

$("#btn-parse").addEventListener("click", () => {
  try {
    const r = callJSON("startParse", {
      dorks: lines($("#p-dorks").value),
      engine: $("#p-engine").value,
      workers: +$("#p-workers").value || 8,
      perDork: +$("#p-perdork").value || 10,
    });
    if (r.ok) toast("Parse iniciado (" + r.count + " dorks)", "ok");
    else toast(r.error || "error", "err");
  } catch (e) { toast(e.message, "err"); }
});

$("#btn-copy-urls").addEventListener("click", () => {
  const us = results("urls");
  copyText(Array.isArray(us) ? us.map((u) => u.raw).join("\n") : "");
});

$("#btn-export-urls").addEventListener("click", () => {
  const us = results("urls");
  exportText("urls.txt", Array.isArray(us) ? us.map((u) => u.raw).join("\n") : "");
});

// ---------- Inject ----------
function renderInjects() {
  let js = results("injects");
  if (!Array.isArray(js)) js = [];
  const onlyRef = $("#inj-only-ref").checked;
  const view = onlyRef ? js.filter((x) => x.reflected) : js;
  $("#inj-count").textContent = view.length;
  const el = $("#inject-list");
  if (!view.length) { el.innerHTML = '<div class="empty">Sin inyecciones todavía.</div>'; return; }
  const MAX = 200;
  el.innerHTML = view.slice(0, MAX).map((x) =>
    '<div class="inj">' +
      '<div class="inj-head"><span class="badge ' + (x.reflected ? "ok" : "no") + '">' +
        (x.reflected ? "REFLEJADO" : "no reflejo") + "</span> <b>" + esc(x.param) +
        "</b> · HTTP " + (x.status || "-") + "</div>" +
      '<code class="inj-url">' + esc(x.url) + "</code>" +
      (x.snippet ? '<pre class="snippet">' + esc(x.snippet) + "</pre>" : "") +
    "</div>"
  ).join("");
}

$("#inj-only-ref").addEventListener("change", renderInjects);

$("#btn-inject").addEventListener("click", () => {
  try {
    const r = callJSON("startInject", {
      workers: +$("#i-workers").value || 8,
      maxUrls: +$("#i-maxurls").value || 200,
      maxParams: +$("#i-maxparams").value || 3,
      payloads: lines($("#i-payloads").value),
    });
    if (r.ok) toast("Inyección iniciada (" + r.count + " URLs)", "ok");
    else toast(r.error || "error", "err");
  } catch (e) { toast(e.message, "err"); }
});

$("#btn-export-injects").addEventListener("click", () => {
  const js = results("injects");
  if (!Array.isArray(js) || !js.length) { toast("nada que exportar", "err"); return; }
  const txt = js.filter((x) => x.reflected).map((x) =>
    "REFLEJADO | " + x.param + " | " + x.url + "\n  contexto: " + x.snippet
  ).join("\n");
  exportText("injections.txt", txt || "(sin reflejos)");
});

// ---------- Dump ----------
function renderDumps() {
  let ds = results("dumps");
  if (!Array.isArray(ds)) ds = [];
  $("#dump-count").textContent = ds.length;
  const el = $("#dump-list");
  if (!ds.length) { el.innerHTML = '<div class="empty">Sin dumps todavía.</div>'; return; }
  const MAX = 100;
  el.innerHTML = ds.slice(0, MAX).map((d) => {
    const items = [];
    if (d.emails && d.emails.length) items.push("<b>Emails:</b> " + esc(d.emails.join(", ")));
    if (d.secrets && d.secrets.length) items.push("<b>Secretos:</b> " + esc(d.secrets.join(" | ")));
    if (d.forms && d.forms.length) items.push("<b>Forms:</b> " + esc(d.forms.slice(0, 3).join(" | ")));
    if (d.jsFiles && d.jsFiles.length) items.push("<b>JS:</b> " + esc(d.jsFiles.slice(0, 5).join(" | ")));
    if (d.links && d.links.length) items.push("<b>Links:</b> " + d.links.length + " (ver export)");
    if (d.comments && d.comments.length) items.push("<b>Comentarios:</b> " + esc(d.comments.slice(0, 2).join(" | ")));
    return (
      '<details class="dump">' +
        "<summary>" + esc(d.title || d.url) +
        ' <span class="dim">HTTP ' + d.status + " · " + d.size + "B · " + d.durationMs + "ms</span></summary>" +
        '<div class="dim small">' + esc(d.url) + "</div>" +
        '<div class="dump-body">' + (items.join("<br>") || "<span class='dim'>sin datos extraídos</span>") + "</div>" +
      "</details>"
    );
  }).join("");
}

function dumpCfg() {
  return {
    workers: +$("#dm-workers").value || 8,
    maxUrls: +$("#dm-maxurls").value || 100,
  };
}

$("#btn-dump").addEventListener("click", () => {
  try {
    const r = parseRet(call("startDump", $("#dm-id").value.trim(), JSON.stringify(dumpCfg())));
    if (r.ok) toast("Dump iniciado (" + r.count + " URLs)", "ok");
    else toast(r.error || "error", "err");
  } catch (e) { toast(e.message, "err"); }
});

$("#btn-dump-all").addEventListener("click", () => {
  try {
    const r = callJSON("startDumpAll", dumpCfg());
    if (r.ok) toast("Dump all iniciado (" + r.count + " URLs)", "ok");
    else toast(r.error || "error", "err");
  } catch (e) { toast(e.message, "err"); }
});

$("#btn-export-dumps").addEventListener("click", () => {
  const ds = results("dumps");
  if (!Array.isArray(ds) || !ds.length) { toast("nada que exportar", "err"); return; }
  exportText("dumps.json", JSON.stringify(ds, null, 2));
});

// ---------- Shell ----------
function renderShell() {
  let ss = results("shell");
  if (!Array.isArray(ss)) ss = [];
  $("#sh-count").textContent = ss.length;
  const el = $("#shell-list");
  if (!ss.length) { el.innerHTML = '<div class="empty">Sin salidas todavía.</div>'; return; }
  el.innerHTML = ss.slice(-20).reverse().map((s) =>
    '<div class="shell"><code class="sh-cmd">$ ' + esc(s.cmd) + " <span class='dim'>[exit " + s.exit + "]</span></code>" +
    '<pre class="sh-out">' + esc(s.out || s.err || "(sin salida)") + "</pre></div>"
  ).join("");
}

$("#btn-shell").addEventListener("click", () => {
  try {
    const r = callJSON("startShell", {
      cmd: $("#sh-cmd").value.trim(),
      args: $("#sh-args").value.split(/\s+/).filter(Boolean),
      cwd: $("#sh-cwd").value.trim(),
    });
    if (r.ok) toast("comando lanzado", "ok");
    else toast(r.error || "error", "err");
  } catch (e) { toast(e.message, "err"); }
});

// ---------- Settings / Log ----------
function renderSettings() {
  try {
    const s = getJSON("getSettings");
    if (document.activeElement !== $("#set-json") && s && typeof s === "object") {
      $("#set-json").value = JSON.stringify(s, null, 2);
    }
  } catch (e) { /* ignore */ }
}

$("#btn-save-settings").addEventListener("click", () => {
  try {
    const r = parseRet(call("saveSettings", $("#set-json").value));
    if (r.ok) toast("ajustes guardados", "ok");
    else toast(r.error || "error", "err");
  } catch (e) { toast(e.message, "err"); }
});

$("#btn-load-settings").addEventListener("click", () => {
  try {
    const s = getJSON("getSettings");
    $("#set-json").value = JSON.stringify(s, null, 2);
    toast("ajustes recargados", "ok");
  } catch (e) { toast(e.message, "err"); }
});

function renderLogs() {
  let ls = results("logs");
  if (!Array.isArray(ls)) ls = [];
  const el = $("#log-list");
  el.innerHTML = ls.slice(-150).reverse().map((l) =>
    '<div class="log ' + esc(l.kind) + '"><span class="dim">' + esc(l.ts) + "</span> " + esc(l.msg) + "</div>"
  ).join("");
}

// ---------- Stop ----------
$("#btn-stop").addEventListener("click", () => {
  try {
    parseRet(call("stopAll"));
    toast("stop enviado", "info");
  } catch (e) { toast(e.message, "err"); }
});

// ---------- Init ----------
if (!gw) {
  const d = document.createElement("div");
  d.style.cssText = "background:#d29922;color:#000;padding:8px 16px;font-size:12px";
  d.textContent = "Modo navegador: ejecuta xdumpgo2.exe para activar las funciones Go.";
  document.body.prepend(d);
}
renderSettings();
renderDorks();
renderURLs();
renderInjects();
renderDumps();
renderShell();
renderLogs();