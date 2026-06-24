#!/usr/bin/env node
// Graphical editor for shortcuts.json — starts a local web server at http://localhost:4173.
// Usage: node edit-shortcuts.js

const http = require("http");
const fs = require("fs");
const path = require("path");
const { exec } = require("child_process");

const ROOT = __dirname;
const DATA_DIR = path.join(ROOT, "_data");
const ICONS_DIR = path.join(ROOT, "icons");
const SHORTCUTS_PATH = path.join(DATA_DIR, "shortcuts.json");
const SECTIONS_PATH = path.join(DATA_DIR, "sections.json");
const UNITS_PATH = path.join(DATA_DIR, "units.json");
const PORT = 4173;

for (const p of [SHORTCUTS_PATH, SECTIONS_PATH, UNITS_PATH]) {
  if (!fs.existsSync(p)) {
    console.error(`Required file not found: ${p}`);
    process.exit(1);
  }
}

const readJson = (p) => JSON.parse(fs.readFileSync(p, "utf8"));

function listIconFiles() {
  if (!fs.existsSync(ICONS_DIR)) return [];
  const out = [];
  const walk = (dir) => {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) walk(full);
      else out.push(path.relative(ICONS_DIR, full).split(path.sep).join("/"));
    }
  };
  walk(ICONS_DIR);
  return out.sort((a, b) => a.localeCompare(b));
}

// Re-serialise an entry keeping a stable key order and dropping empties.
const KEY_ORDER = ["id", "href", "icon", "icon_src", "label", "bg", "only", "exclude"];
function normaliseEntry(raw) {
  const out = {};
  for (const key of KEY_ORDER) {
    if (!(key in raw)) continue;
    let v = raw[key];
    if (key === "only" || key === "exclude") {
      v = Array.isArray(v) ? v.filter((x) => `${x}`.trim() !== "") : [];
      if (v.length) out[key] = v;
    } else {
      v = `${v ?? ""}`.trim();
      if (v !== "") out[key] = v;
    }
  }
  return out;
}

function saveShortcuts(data) {
  const root = {};
  for (const section of Object.keys(data)) {
    root[section] = (data[section] || []).map(normaliseEntry);
  }
  fs.writeFileSync(SHORTCUTS_PATH, JSON.stringify(root, null, 2) + "\n", "utf8");
}

const ICON_MIME = {
  ".svg": "image/svg+xml",
  ".webp": "image/webp",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".gif": "image/gif",
  ".ico": "image/x-icon",
};

const server = http.createServer((req, res) => {
 try {
  const url = new URL(req.url, `http://localhost:${PORT}`);

  if (req.method === "GET" && url.pathname === "/") {
    res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
    res.end(PAGE);
    return;
  }

  if (req.method === "GET" && url.pathname === "/api/data") {
    const payload = {
      sections: readJson(SECTIONS_PATH),
      units: readJson(UNITS_PATH),
      shortcuts: readJson(SHORTCUTS_PATH),
      iconFiles: listIconFiles(),
    };
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify(payload));
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/save") {
    let body = "";
    req.on("data", (c) => (body += c));
    req.on("end", () => {
      try {
        saveShortcuts(JSON.parse(body));
        res.writeHead(200, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ ok: true }));
      } catch (err) {
        res.writeHead(500, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ ok: false, error: String(err) }));
      }
    });
    return;
  }

  // Serve icon files for preview (guarded against path traversal; files only).
  if (req.method === "GET" && url.pathname.startsWith("/icons/")) {
    const rel = decodeURIComponent(url.pathname.slice("/icons/".length));
    const full = path.join(ICONS_DIR, rel);
    let stat = null;
    try { stat = fs.statSync(full); } catch { /* not found */ }
    if (!full.startsWith(ICONS_DIR) || !stat || !stat.isFile()) {
      res.writeHead(404);
      res.end("Not found");
      return;
    }
    const mime = ICON_MIME[path.extname(full).toLowerCase()] || "application/octet-stream";
    res.writeHead(200, { "Content-Type": mime });
    const stream = fs.createReadStream(full);
    stream.on("error", () => res.destroy());   // never let a stream error crash the process
    stream.pipe(res);
    return;
  }

  res.writeHead(404);
  res.end("Not found");
 } catch (err) {
  // Any unexpected error stays contained to this request — the server keeps running.
  console.error("Request error:", err);
  if (!res.headersSent) res.writeHead(500, { "Content-Type": "text/plain" });
  res.end("Internal server error");
 }
});

// Last-resort guard: a crash in async code must not take the editor down mid-session.
process.on("uncaughtException", (err) => console.error("Uncaught exception:", err));

server.listen(PORT, () => {
  const addr = `http://localhost:${PORT}`;
  console.log(`AppLauncher Shortcuts Editor running at ${addr}`);
  console.log("Press Ctrl+C to stop.");
  const opener =
    process.platform === "win32" ? `start "" "${addr}"`
    : process.platform === "darwin" ? `open "${addr}"`
    : `xdg-open "${addr}"`;
  exec(opener, () => {});
});

// ============================================================
// FRONT-END (single embedded HTML document)
// ============================================================
const PAGE = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>AppLauncher Shortcuts Editor</title>
<style>
  :root { --accent:#0078d4; --green:#28a745; --border:#d0d0d0; --bg:#f3f3f3; }
  * { box-sizing: border-box; }
  body { margin:0; font:14px/1.4 "Segoe UI",system-ui,sans-serif; color:#222; background:var(--bg); height:100vh; display:flex; flex-direction:column; }
  header { background:#22325d; color:#fff; padding:10px 16px; font-size:16px; font-weight:600; display:flex; align-items:center; justify-content:space-between; }
  #save { background:var(--green); color:#fff; border:none; padding:8px 16px; border-radius:4px; font-size:14px; cursor:pointer; }
  #save:disabled { opacity:.55; cursor:default; }
  main { flex:1; display:flex; min-height:0; }
  #left { width:300px; border-right:1px solid var(--border); display:flex; flex-direction:column; background:#fafafa; }
  #left .pad { padding:10px; }
  label.fld { display:block; font-size:12px; color:#555; margin:0 0 3px; }
  select, input[type=text] { width:100%; padding:6px 8px; border:1px solid var(--border); border-radius:4px; font:inherit; }
  #list { flex:1; overflow:auto; border-top:1px solid var(--border); margin-top:8px; }
  #list .item { padding:7px 12px; cursor:pointer; border-bottom:1px solid #eee; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
  #list .item:hover { background:#eef4fb; }
  #list .item.sel { background:var(--accent); color:#fff; }
  #leftbtns { display:flex; gap:4px; padding:8px; border-top:1px solid var(--border); }
  #leftbtns button { flex:1; padding:6px 4px; border:1px solid var(--border); background:#fff; border-radius:4px; cursor:pointer; }
  #leftbtns button.narrow { flex:0 0 38px; }
  #right { flex:1; overflow:auto; padding:18px 22px; }
  .row { margin-bottom:14px; max-width:560px; }
  .hint { font-size:12px; color:#888; }
  fieldset { border:1px solid var(--border); border-radius:6px; padding:12px 14px; margin:0 0 14px; max-width:560px; }
  legend { font-size:12px; color:#555; padding:0 6px; }
  .radios label { margin-right:18px; font-size:14px; cursor:pointer; }
  .units { display:flex; gap:20px; max-width:560px; }
  .units fieldset { flex:1; }
  .units.disabled { opacity:.45; pointer-events:none; }
  .checklist { max-height:200px; overflow:auto; }
  .checklist label { display:block; font-size:13px; padding:1px 0; cursor:pointer; }
  #iconPreview { height:42px; margin-top:8px; display:flex; align-items:center; gap:10px; }
  #iconPreview img { max-height:40px; max-width:120px; border:1px solid var(--border); border-radius:4px; background:#fff; padding:2px; }
  .iconchip { display:inline-flex; align-items:center; justify-content:center; min-width:40px; height:40px; padding:0 8px; background:#22325d; color:#fff; border-radius:6px; font-weight:600; }
  #apply { background:var(--accent); color:#fff; border:none; padding:9px 22px; border-radius:4px; font-size:14px; cursor:pointer; }
  #status { padding:6px 16px; font-size:13px; color:#555; background:#e9e9e9; border-top:1px solid var(--border); min-height:28px; }
  .empty { color:#999; padding:40px 0; text-align:center; }
  .hidden { display:none !important; }
</style>
</head>
<body>
<header>
  <span>AppLauncher Shortcuts Editor</span>
  <button id="save" disabled>Save All to shortcuts.json</button>
</header>
<main>
  <div id="left">
    <div class="pad">
      <label class="fld" for="section">Section</label>
      <select id="section"></select>
    </div>
    <div id="list"></div>
    <div id="leftbtns">
      <button id="add">+ Add</button>
      <button id="del">Delete</button>
      <button id="up" class="narrow" title="Move up">&#9650;</button>
      <button id="down" class="narrow" title="Move down">&#9660;</button>
    </div>
  </div>
  <div id="right">
    <div id="editor" class="hidden">
      <div class="row">
        <label class="fld" for="f-id">ID</label>
        <input type="text" id="f-id">
      </div>
      <div class="row">
        <label class="fld" for="f-label">Label</label>
        <input type="text" id="f-label">
      </div>
      <div class="row">
        <label class="fld" for="f-href">URL (href)</label>
        <input type="text" id="f-href">
      </div>

      <fieldset>
        <legend>Icon</legend>
        <div class="radios row" style="margin-bottom:10px">
          <label><input type="radio" name="icontype" value="icon" checked> Text data-icon (<code>icon</code>)</label>
          <label><input type="radio" name="icontype" value="icon_src"> Image file (<code>icon_src</code>)</label>
        </div>
        <div id="iconTextWrap" class="row" style="margin-bottom:0">
          <label class="fld" for="f-icon">Icon text</label>
          <input type="text" id="f-icon" placeholder="e.g. MFA">
        </div>
        <div id="iconSrcWrap" class="row hidden" style="margin-bottom:0">
          <label class="fld" for="f-iconsrc">Image file</label>
          <input type="text" id="f-iconsrc" list="iconlist" placeholder="e.g. svg/teams.svg">
          <datalist id="iconlist"></datalist>
        </div>
        <div id="iconPreview"></div>
      </fieldset>

      <div class="row">
        <label class="fld" for="f-bg">Background (optional hex / CSS colour)</label>
        <input type="text" id="f-bg" style="max-width:220px" placeholder="#f4f4f4">
      </div>

      <div id="units" class="units">
        <fieldset>
          <legend>Show only for these units</legend>
          <div id="onlyList" class="checklist"></div>
        </fieldset>
        <fieldset>
          <legend>Exclude from these units</legend>
          <div id="excludeList" class="checklist"></div>
        </fieldset>
      </div>
      <p class="hint" id="unitsHint">Only / Exclude apply to school sections. Don't set both.</p>

      <button id="apply">Apply Changes</button>
    </div>
    <div id="placeholder" class="empty">Select a shortcut on the left, or click <b>+ Add</b> to create a new one.</div>
  </div>
</main>
<div id="status"></div>

<script>
const $ = (id) => document.getElementById(id);
let DATA = null;            // { sections, units, shortcuts, iconFiles }
let unitCodes = [];
let curSection = null;
let curIndex = -1;          // -1 = no selection (Apply will append a new entry)
let dirty = false;

function setStatus(msg) { $("status").textContent = msg || ""; }
function setDirty(v) {
  dirty = v;
  $("save").disabled = !v;
  $("save").textContent = "Save All to shortcuts.json" + (v ? " *" : "");
}

function sectionMeta(id) { return DATA.sections.find((s) => s.id === id); }
function isSchool(id) { const s = sectionMeta(id); return !!(s && s.only?.includes("school")); }

function init(data) {
  DATA = data;
  unitCodes = data.units.map((u) => u.code).sort();

  const sel = $("section");
  sel.innerHTML = "";
  const known = new Set();
  for (const s of data.sections) {
    sel.append(new Option(s.label + "  [" + s.id + "]", s.id));
    known.add(s.id);
  }
  // Any section present in shortcuts.json but missing from sections.json
  for (const key of Object.keys(data.shortcuts)) {
    if (!known.has(key)) { sel.append(new Option(key + "  [" + key + "]", key)); }
  }

  $("iconlist").innerHTML = "";
  for (const f of data.iconFiles) $("iconlist").append(new Option(f));

  // Build unit checklists once
  buildChecklist("onlyList", "only");
  buildChecklist("excludeList", "exclude");

  curSection = sel.value;
  renderList();
  selectSection();
}

function buildChecklist(containerId, name) {
  const box = $(containerId);
  box.innerHTML = "";
  for (const code of unitCodes) {
    const lbl = document.createElement("label");
    const cb = document.createElement("input");
    cb.type = "checkbox";
    cb.value = code;
    cb.dataset.group = name;
    lbl.append(cb, document.createTextNode(" " + code));
    box.append(lbl);
  }
}

function selectSection() {
  curSection = $("section").value;
  curIndex = -1;
  renderList();
  showEditor(false);
  updateUnitState();
  setStatus("");
}

function renderList() {
  const list = $("list");
  list.innerHTML = "";
  const items = DATA.shortcuts[curSection] || [];
  items.forEach((it, i) => {
    const div = document.createElement("div");
    div.className = "item" + (i === curIndex ? " sel" : "");
    div.textContent = it.label || it.id || "(untitled)";
    div.onclick = () => selectItem(i);
    list.append(div);
  });
}

function showEditor(show) {
  $("editor").classList.toggle("hidden", !show);
  $("placeholder").classList.toggle("hidden", show);
}

function updateUnitState() {
  const on = isSchool(curSection);
  $("units").classList.toggle("disabled", !on);
  $("unitsHint").textContent = on
    ? "Only / Exclude apply to school sections. Don't set both."
    : "Only / Exclude are not used for this (non-school) section.";
}

function setChecks(group, values) {
  values = values || [];
  document.querySelectorAll('input[data-group="' + group + '"]').forEach((cb) => {
    cb.checked = values.includes(cb.value);
  });
}
function getChecks(group) {
  return [...document.querySelectorAll('input[data-group="' + group + '"]:checked')].map((cb) => cb.value);
}

function loadItem(it) {
  $("f-id").value = it.id || "";
  $("f-label").value = it.label || "";
  $("f-href").value = it.href || "";
  $("f-bg").value = it.bg || "";
  const useSrc = "icon_src" in it;
  document.querySelector('input[name="icontype"][value="' + (useSrc ? "icon_src" : "icon") + '"]').checked = true;
  $("f-icon").value = useSrc ? "" : (it.icon || "");
  $("f-iconsrc").value = useSrc ? (it.icon_src || "") : "";
  syncIconType();
  setChecks("only", it.only);
  setChecks("exclude", it.exclude);
}

function clearForm() {
  $("f-id").value = $("f-label").value = $("f-href").value = $("f-bg").value = "";
  $("f-icon").value = $("f-iconsrc").value = "";
  document.querySelector('input[name="icontype"][value="icon"]').checked = true;
  syncIconType();
  setChecks("only", []);
  setChecks("exclude", []);
}

function selectItem(i) {
  curIndex = i;
  renderList();
  showEditor(true);
  updateUnitState();
  loadItem(DATA.shortcuts[curSection][i]);
  setStatus("");
}

function iconType() {
  return document.querySelector('input[name="icontype"]:checked').value;
}
function syncIconType() {
  const src = iconType() === "icon_src";
  $("iconTextWrap").classList.toggle("hidden", src);
  $("iconSrcWrap").classList.toggle("hidden", !src);
  renderPreview();
}
function renderPreview() {
  const box = $("iconPreview");
  box.innerHTML = "";
  if (iconType() === "icon_src") {
    const v = $("f-iconsrc").value.trim();
    if (v) {
      const img = document.createElement("img");
      img.src = "/icons/" + encodeURI(v);
      img.alt = v;
      img.onerror = () => { box.innerHTML = '<span class="hint">No preview (file not found under /icons)</span>'; };
      box.append(img);
    }
  } else {
    const v = $("f-icon").value.trim();
    if (v) {
      const chip = document.createElement("span");
      chip.className = "iconchip";
      chip.textContent = v;
      box.append(chip);
    }
  }
}

function applyChanges() {
  // Intent is derived from the list selection: no selection => append a new entry,
  // an existing selection => update that entry.
  if (!curSection) { setStatus("Select a section first."); return; }

  const id = $("f-id").value.trim();
  if (!id) { alert("ID is required."); return; }

  const item = { id, href: $("f-href").value.trim() };
  if (iconType() === "icon_src") {
    const v = $("f-iconsrc").value.trim();
    if (v) item.icon_src = v;
  } else {
    const v = $("f-icon").value.trim();
    if (v) item.icon = v;
  }
  const label = $("f-label").value.trim();
  if (label) item.label = label;
  const bg = $("f-bg").value.trim();
  if (bg) item.bg = bg;

  if (isSchool(curSection)) {
    const only = getChecks("only");
    const excl = getChecks("exclude");
    if (only.length) item.only = only;
    if (excl.length) item.exclude = excl;
  }

  if (!DATA.shortcuts[curSection]) DATA.shortcuts[curSection] = [];
  const list = DATA.shortcuts[curSection];
  const name = item.label || item.id;

  if (curIndex < 0) {
    // No selection -> append the freshly composed entry.
    list.push(item);
    curIndex = list.length - 1;
    setStatus("Added '" + name + "'. Click Save All to write to disk.");
  } else {
    list[curIndex] = item;
    setStatus("Changes applied to '" + name + "'. Click Save All to write to disk.");
  }
  renderList();
  setDirty(true);
}

// ---- button wiring ----
$("section").onchange = selectSection;

$("add").onclick = () => {
  if (!curSection) { setStatus("Select a section first."); return; }
  curIndex = -1;   // no selection => Apply will append a new entry
  renderList();
  showEditor(true);
  updateUnitState();
  clearForm();
  $("f-id").focus();
  setStatus("New shortcut for '" + curSection + "'. Fill in the fields, then click Apply Changes.");
};

$("del").onclick = () => {
  if (curIndex < 0) { setStatus("Select a shortcut to delete."); return; }
  const list = DATA.shortcuts[curSection];
  const name = list[curIndex].label || list[curIndex].id;
  if (!confirm("Delete '" + name + "'?")) return;
  list.splice(curIndex, 1);
  curIndex = Math.min(curIndex, list.length - 1);
  renderList();
  if (curIndex >= 0) selectItem(curIndex); else { showEditor(false); }
  setDirty(true);
  setStatus("Deleted '" + name + "'.");
};

function move(delta) {
  const list = DATA.shortcuts[curSection];
  const j = curIndex + delta;
  if (curIndex < 0 || j < 0 || j >= list.length) return;
  [list[curIndex], list[j]] = [list[j], list[curIndex]];
  curIndex = j;
  renderList();
  setDirty(true);
}
$("up").onclick = () => move(-1);
$("down").onclick = () => move(1);

$("apply").onclick = applyChanges;
document.querySelectorAll('input[name="icontype"]').forEach((r) => (r.onchange = syncIconType));
$("f-icon").oninput = renderPreview;
$("f-iconsrc").oninput = renderPreview;

// Enter in a text field applies changes
for (const id of ["f-id", "f-label", "f-href", "f-bg", "f-icon", "f-iconsrc"]) {
  $(id).addEventListener("keydown", (e) => { if (e.key === "Enter") { e.preventDefault(); applyChanges(); } });
}

$("save").onclick = async () => {
  try {
    const res = await fetch("/api/save", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(DATA.shortcuts),
    });
    const out = await res.json();
    if (out.ok) { setDirty(false); setStatus("Saved successfully at " + new Date().toLocaleTimeString() + "."); }
    else { alert("Error saving: " + out.error); }
  } catch (err) { alert("Error saving: " + err); }
};

window.addEventListener("beforeunload", (e) => {
  if (dirty) { e.preventDefault(); e.returnValue = ""; }
});

fetch("/api/data").then((r) => r.json()).then(init).catch((err) => setStatus("Failed to load data: " + err));
</script>
</body>
</html>`;
