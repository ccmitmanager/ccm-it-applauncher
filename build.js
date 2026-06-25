#!/usr/bin/env node
'use strict';

const fs   = require('fs');
const path = require('path');

const root = process.argv.includes('--relative') ? '../' : '/';

// ── Load data ──────────────────────────────────────────────────────────────
const DATA     = '_data';
const units    = JSON.parse(fs.readFileSync(path.join(DATA, 'units.json'),    'utf8'));
const sections = JSON.parse(fs.readFileSync(path.join(DATA, 'sections.json'), 'utf8'));

// shortcuts.json is an object keyed by grid id; sort sections and entries, write back, then flatten
const shortcutsRaw = JSON.parse(fs.readFileSync(path.join(DATA, 'shortcuts.json'), 'utf8'));
const shortcutsSorted = Object.fromEntries(
  Object.keys(shortcutsRaw).sort().map(grid => [
    grid,
    shortcutsRaw[grid].slice().sort((a, b) => a.id.localeCompare(b.id))
  ])
);
fs.writeFileSync(path.join(DATA, 'shortcuts.json'), JSON.stringify(shortcutsSorted, null, 2) + '\n', 'utf8');
const shortcuts = Object.entries(shortcutsSorted).flatMap(([grid, items]) =>
  items.map(item => ({ ...item, grid }))
);

// ── Helpers ────────────────────────────────────────────────────────────────
function esc(str) {
  return String(str)
    .replace(/&/g,  '&amp;')
    .replace(/"/g,  '&quot;')
    .replace(/</g,  '&lt;')
    .replace(/>/g,  '&gt;');
}

function visibleOn(shortcut, unitCode) {
  if (shortcut.only)    return shortcut.only.includes(unitCode);
  if (shortcut.exclude) return !shortcut.exclude.includes(unitCode);
  return true;
}

function sectionVisibleFor(section, unit) {
  const tags = [unit.code, ...(unit.tags || [])];
  if (section.only)    return section.only.some(t => tags.includes(t));
  if (section.exclude) return !section.exclude.some(t => tags.includes(t));
  return true;
}

// Detect alpha channel by reading VP8X/VP8L header flags in the RIFF container.
function webpHasAlpha(absPath) {
  let fd;
  try {
    fd = fs.openSync(absPath, 'r');
    const buf = Buffer.alloc(25);
    const n = fs.readSync(fd, buf, 0, 25, 0);
    if (n < 16 || buf.toString('ascii', 0, 4) !== 'RIFF' || buf.toString('ascii', 8, 12) !== 'WEBP') {
      return false;
    }
    const fourcc = buf.toString('ascii', 12, 16);
    if (fourcc === 'VP8X') return n >= 21 && (buf[20] & 0x10) !== 0;      // alpha flag
    if (fourcc === 'VP8L') {                                              // alpha_is_used bit
      if (n < 25 || buf[20] !== 0x2f) return false;
      const bits = (buf[21] | (buf[22] << 8) | (buf[23] << 16) | (buf[24] << 24)) >>> 0;
      return ((bits >> 28) & 1) === 1;
    }
    return false;
  } catch {
    return false;
  } finally {
    if (fd !== undefined) fs.closeSync(fd);
  }
}

// Transparent raster icons need the same inset as SVGs. Memoised per file.
const insetCache = new Map();
function needsInset(iconSrc) {
  if (!/\.webp$/i.test(iconSrc)) return false;
  const abs = path.join('icons', iconSrc);
  if (!insetCache.has(abs)) insetCache.set(abs, webpHasAlpha(abs));
  return insetCache.get(abs);
}

function renderIcon(sc, accent) {
  if (sc.icon_src) {
    const style = ` style="background-color:${esc(sc.bg || accent)}"`;
    const cls = needsInset(sc.icon_src) ? ' class="inset"' : '';
    return `<div class="g-icon"${style}><img src="${root}icons/${esc(sc.icon_src)}" alt="${esc(sc.label)}"${cls}></div>`;
  }
  const color = sc.color || accent;
  return `<div class="g-icon"><img data-icon="${esc(color)}:${esc(sc.icon)}" alt="${esc(sc.label)}"></div>`;
}

function renderItem(sc, accent) {
  return `
      <a href="${esc(sc.href)}" class="g-item">
        ${renderIcon(sc, accent)}
        <div class="g-label">${esc(sc.label)}</div>
      </a>`;
}

// ── Shared nav dropdowns (edit here to update all pages) ──────────────────
const SHARED_NAV = `
      <div class="dd">
        <button class="dd-btn" aria-haspopup="true" aria-expanded="false">
          System Administration <span class="dd-caret"></span>
        </button>
        <div class="dd-menu">
          <a href="https://ccmschools.app/go/testenv/">Test Environments</a>
          <a href="https://admin.parentidpassport.com/PIPSPlus-Admin/">PIPSPlus Admin</a>
          <a href="https://ccm.busminder.com.au/admin/">BusMinder Administration</a>
          <a href="https://cmd.ms">Microsoft Admin Portals</a>
        </div>
      </div>

      <div class="dd">
        <button class="dd-btn" aria-haspopup="true" aria-expanded="false">
          The Source <span class="dd-caret"></span>
        </button>
        <div class="dd-menu">
          <a href="https://ccmschools.sharepoint.com/sites/ccm-policy">Policy &amp; Procedure Portal</a>
          <a href="https://ccmschools.sharepoint.com/sites/TeachingLearning">Teaching &amp; Learning Portal</a>
          <a href="https://ccmschools.sharepoint.com/sites/ccm-hrp">HR &amp; Payroll Portal</a>
          <a href="https://ccmschools.sharepoint.com/sites/ccm-policy/leaders/">School Leaders Guide</a>
        </div>
      </div>`;

// ── Inline JS (identical on every page) ───────────────────────────────────
const PAGE_SCRIPT = `  <script>
    (function () {
      'use strict';

      const dds          = document.querySelectorAll('.dd');
      const topbar       = document.querySelector('.topbar');
      const hamburgerBtn = document.querySelector('.hamburger-btn');
      const topbarNav    = document.getElementById('topbar-nav');

      function closeAllNav() {
        dds.forEach(d => {
          d.classList.remove('open');
          d.querySelector('.dd-btn').setAttribute('aria-expanded', 'false');
        });
        topbar.classList.remove('nav-open');
        hamburgerBtn.setAttribute('aria-expanded', 'false');
      }

      dds.forEach(dd => {
        const btn = dd.querySelector('.dd-btn');
        btn.addEventListener('click', e => {
          e.stopPropagation();
          const opening = !dd.classList.contains('open');
          dds.forEach(d => {
            d.classList.remove('open');
            d.querySelector('.dd-btn').setAttribute('aria-expanded', 'false');
          });
          if (opening) {
            dd.classList.add('open');
            btn.setAttribute('aria-expanded', 'true');
          }
        });
      });

      document.addEventListener('click', closeAllNav);
      document.addEventListener('keydown', e => { if (e.key === 'Escape') closeAllNav(); });

      hamburgerBtn.addEventListener('click', e => {
        e.stopPropagation();
        const opening = !topbar.classList.contains('nav-open');
        topbar.classList.toggle('nav-open', opening);
        hamburgerBtn.setAttribute('aria-expanded', opening ? 'true' : 'false');
        if (!opening) {
          dds.forEach(d => {
            d.classList.remove('open');
            d.querySelector('.dd-btn').setAttribute('aria-expanded', 'false');
          });
        }
      });

      topbarNav.addEventListener('click', e => e.stopPropagation());

      const fBtns = document.querySelectorAll('.f-btn');
      const grids = document.querySelectorAll('.grid');

      fBtns.forEach(btn => {
        btn.addEventListener('click', () => {
          fBtns.forEach(b => {
            b.classList.remove('active');
            b.setAttribute('aria-selected', 'false');
          });
          grids.forEach(g => g.classList.remove('active'));
          btn.classList.add('active');
          btn.setAttribute('aria-selected', 'true');
          const target = document.getElementById(btn.dataset.target);
          if (target) target.classList.add('active');
        });
      });

      document.querySelectorAll('img[data-icon]').forEach(img => {
        const raw   = img.getAttribute('data-icon');
        const colon = raw.indexOf(':');
        const color = raw.slice(0, colon);
        const label = raw.slice(colon + 1);
        const fs    = label.length > 3 ? 16 : label.length > 2 ? 20 : 26;
        const svg =
          "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 80 80'>" +
          "<rect width='80' height='80' fill='" + color + "'/>" +
          "<text x='40' y='40' font-size='" + fs + "'" +
          " text-anchor='middle' dominant-baseline='middle'" +
          " fill='white' font-family='sans-serif' font-weight='400'>" +
          label +
          "</text></svg>";
        img.src = 'data:image/svg+xml,' + encodeURIComponent(svg);
      });

    })();
  </script>`;

// ── Page builder ───────────────────────────────────────────────────────────
function buildPage(unit) {
  const unitShortcuts = shortcuts.filter(sc => visibleOn(sc, unit.code));
  const activeSections = sections.filter(s =>
    sectionVisibleFor(s, unit) && unitShortcuts.some(sc => sc.grid === s.id)
  );

  if (activeSections.length === 0) {
    console.warn(`  [WARN] ${unit.code}: no shortcuts found — skipping`);
    return null;
  }

  const filterButtons = activeSections.map((s, i) =>
    `    <button class="f-btn${i === 0 ? ' active' : ''}" role="tab" ` +
    `aria-selected="${i === 0 ? 'true' : 'false'}" ` +
    `data-target="grid-${s.id}">${esc(s.label)}</button>`
  ).join('\n');

  const grids = activeSections.map((s, i) => {
    const items = unitShortcuts
      .filter(sc => sc.grid === s.id)
      .sort((a, b) => a.label.localeCompare(b.label))
      .map(sc => renderItem(sc, unit.accent))
      .join('');
    return (
      `    <div class="grid${i === 0 ? ' active' : ''}" ` +
      `id="grid-${s.id}" role="tabpanel">${items}\n    </div>`
    );
  }).join('\n\n');

  return `<!DOCTYPE html>
<html lang="en">

<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${esc(unit.name)} – Staff Apps</title>
  <link rel="apple-touch-icon" sizes="180x180" href="../style/apple-touch-icon.png">
  <link rel="icon" type="image/png" sizes="32x32" href="../style/favicon-32x32.png">
  <link rel="icon" type="image/png" sizes="16x16" href="../style/favicon-16x16.png">
  <link rel="manifest" href="../style/site.webmanifest">
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Pliant:ital,wght@0,100..900;1,100..900&display=swap" rel="stylesheet">
  <link rel="stylesheet" href="../style/styles.css">
  <style>:root { --accent: ${esc('#22325d')}; }</style>
</head>

<body>

  <nav class="topbar" aria-label="Main navigation">

    <button class="hamburger-btn" aria-label="Open navigation menu" aria-expanded="false"
      aria-controls="topbar-nav">&#9776; Menu</button>

    <div class="topbar-nav" id="topbar-nav">

      <a href="${esc(unit.collegeAppsUrl)}" class="tb-link">College Apps</a>

      <a href="/${unit.code}/" class="tb-link active">${esc(unit.shortName)} Staff Apps</a>
      ${SHARED_NAV}
    </div>

  </nav>

  <div class="logo-wrap">
    <img src="${esc(root + unit.logo.replace(/^\//, ''))}" alt="${esc(unit.name)}">
  </div>

  <div class="filter-row" role="tablist" aria-label="Content category">
${filterButtons}
  </div>

  <main class="grid-wrap">
${grids}
  </main>

  <footer>
    <p>A ministry of <a href="https://www.ccmschools.edu.au">Christian Community Ministries</a></p>
  </footer>

${PAGE_SCRIPT}

</body>

</html>
`;
}

// ── Main ───────────────────────────────────────────────────────────────────
let built   = 0;
let skipped = 0;

for (const unit of units) {
  if (!unit.name || unit.accent === '#') {
    console.warn(`  [SKIP] ${unit.code}: incomplete (fill in name/accent in units.json)`);
    skipped++;
    continue;
  }

  const html = buildPage(unit);
  if (!html) { skipped++; continue; }

  fs.mkdirSync(unit.code, { recursive: true });
  fs.writeFileSync(path.join(unit.code, 'index.html'), html, 'utf8');
  console.log(`  + ${unit.code}/index.html`);
  built++;
}

console.log(`\nDone. Built ${built} of ${units.length} pages (${skipped} skipped).`);
