#!/usr/bin/env pwsh
param([switch]$Relative)
$ErrorActionPreference = 'Stop'
$root = if ($Relative) { '../' } else { '/' }

# ── Load data ──────────────────────────────────────────────────────────────
$units    = Get-Content '_data/units.json'    -Raw | ConvertFrom-Json
$sections = Get-Content '_data/sections.json' -Raw | ConvertFrom-Json

# shortcuts.json is an object keyed by grid id; sort sections and entries, write back, then flatten
$shortcutsRaw = Get-Content '_data/shortcuts.json' -Raw | ConvertFrom-Json
$sortedData   = [ordered]@{}
foreach ($grid in ($shortcutsRaw.PSObject.Properties.Name | Sort-Object)) {
    $sortedData[$grid] = @($shortcutsRaw.$grid | Sort-Object id)
}
($sortedData | ConvertTo-Json -Depth 10) + "`n" | Set-Content '_data/shortcuts.json' -Encoding utf8NoBOM
$shortcuts = foreach ($grid in $sortedData.Keys) {
    foreach ($item in $sortedData[$grid]) {
        $item | Add-Member -NotePropertyName 'grid' -NotePropertyValue $grid -PassThru
    }
}

# ── Helpers ────────────────────────────────────────────────────────────────
function EscHtml([string]$str) {
    return $str -replace '&', '&amp;' `
                -replace '"', '&quot;' `
                -replace '<', '&lt;'  `
                -replace '>', '&gt;'
}

function Test-VisibleOn($sc, [string]$code) {
    if ($null -ne $sc.only    -and $sc.only.Count    -gt 0) { return [bool](@($sc.only)    -contains $code) }
    if ($null -ne $sc.exclude -and $sc.exclude.Count -gt 0) { return [bool](@($sc.exclude) -notcontains $code) }
    return $true
}

function Test-SectionVisibleFor($section, $unit) {
    $tags = @($unit.code) + @($unit.tags)
    if ($null -ne $section.only    -and $section.only.Count    -gt 0) { return [bool](@($section.only)    | Where-Object { $tags -contains $_ }) }
    if ($null -ne $section.exclude -and $section.exclude.Count -gt 0) { return -not [bool](@($section.exclude) | Where-Object { $tags -contains $_ }) }
    return $true
}

# Detect whether a WebP file has an alpha channel by reading its header.
# (RIFF container: "VP8X" extended sets an alpha flag; "VP8L" lossless has an
# alpha_is_used bit; "VP8 " simple-lossy never has alpha.)
function Test-WebpHasAlpha([string]$file) {
    if (-not (Test-Path -LiteralPath $file)) { return $false }
    try {
        $b = [System.IO.File]::ReadAllBytes($file)
        if ($b.Length -lt 16) { return $false }
        if ([System.Text.Encoding]::ASCII.GetString($b, 0, 4) -ne 'RIFF' -or
            [System.Text.Encoding]::ASCII.GetString($b, 8, 4) -ne 'WEBP') { return $false }
        $fourcc = [System.Text.Encoding]::ASCII.GetString($b, 12, 4)
        if ($fourcc -eq 'VP8X') { return ($b.Length -ge 21 -and ($b[20] -band 0x10) -ne 0) }   # alpha flag
        if ($fourcc -eq 'VP8L') {                                                               # alpha_is_used bit
            if ($b.Length -lt 25 -or $b[20] -ne 0x2f) { return $false }
            $bits = [uint32]$b[21] -bor ([uint32]$b[22] -shl 8) -bor ([uint32]$b[23] -shl 16) -bor ([uint32]$b[24] -shl 24)
            return ((($bits -shr 28) -band 1) -eq 1)
        }
        return $false
    } catch { return $false }
}

# Transparent raster icons need the same inset as SVGs. Memoised per file.
$script:InsetCache = @{}
function Test-NeedsInset([string]$iconSrc) {
    if ($iconSrc -notmatch '\.webp$') { return $false }
    $abs = Join-Path 'icons' $iconSrc
    if (-not $script:InsetCache.ContainsKey($abs)) {
        $script:InsetCache[$abs] = Test-WebpHasAlpha $abs
    }
    return $script:InsetCache[$abs]
}

function Render-Icon($sc, [string]$accent) {
    if ($sc.icon_src) {
        $src   = EscHtml $sc.icon_src
        $alt   = EscHtml $sc.label
        $style = " style=`"background-color:$(EscHtml $(if ($sc.bg) { $sc.bg } else { $accent }))`""
        $cls   = if (Test-NeedsInset $sc.icon_src) { ' class="inset"' } else { '' }
        return "<div class=`"g-icon`"$style><img src=`"$($root)icons/$src`" alt=`"$alt`"$cls></div>"
    }
    $color     = if ($sc.color) { $sc.color } else { $accent }
    $dataIcon  = "$(EscHtml $color):$(EscHtml $sc.icon)"
    $alt       = EscHtml $sc.label
    return "<div class=`"g-icon`"><img data-icon=`"$dataIcon`" alt=`"$alt`"></div>"
}

function Render-Item($sc, [string]$accent) {
    $icon  = Render-Icon $sc $accent
    $href  = EscHtml $sc.href
    $label = EscHtml $sc.label
    return @"

      <a href="$href" class="g-item">
        $icon
        <div class="g-label">$label</div>
      </a>
"@
}

# ── Shared nav dropdowns (edit here to update all pages) ──────────────────
$SHARED_NAV = @'

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
      </div>
'@

# ── Inline JS (identical on every page) ───────────────────────────────────
$PAGE_SCRIPT = @'
  <script>
    (function () {
      'use strict';

      var dds          = document.querySelectorAll('.dd');
      var topbar       = document.querySelector('.topbar');
      var hamburgerBtn = document.querySelector('.hamburger-btn');
      var topbarNav    = document.getElementById('topbar-nav');

      function closeAllNav() {
        dds.forEach(function (d) {
          d.classList.remove('open');
          d.querySelector('.dd-btn').setAttribute('aria-expanded', 'false');
        });
        topbar.classList.remove('nav-open');
        hamburgerBtn.setAttribute('aria-expanded', 'false');
      }

      dds.forEach(function (dd) {
        var btn = dd.querySelector('.dd-btn');
        btn.addEventListener('click', function (e) {
          e.stopPropagation();
          var opening = !dd.classList.contains('open');
          dds.forEach(function (d) {
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
      document.addEventListener('keydown', function (e) {
        if (e.key === 'Escape') { closeAllNav(); }
      });

      hamburgerBtn.addEventListener('click', function (e) {
        e.stopPropagation();
        var opening = !topbar.classList.contains('nav-open');
        topbar.classList.toggle('nav-open', opening);
        hamburgerBtn.setAttribute('aria-expanded', opening ? 'true' : 'false');
        if (!opening) {
          dds.forEach(function (d) {
            d.classList.remove('open');
            d.querySelector('.dd-btn').setAttribute('aria-expanded', 'false');
          });
        }
      });

      topbarNav.addEventListener('click', function (e) {
        e.stopPropagation();
      });

      var fBtns = document.querySelectorAll('.f-btn');
      var grids = document.querySelectorAll('.grid');

      fBtns.forEach(function (btn) {
        btn.addEventListener('click', function () {
          fBtns.forEach(function (b) {
            b.classList.remove('active');
            b.setAttribute('aria-selected', 'false');
          });
          grids.forEach(function (g) { g.classList.remove('active'); });
          btn.classList.add('active');
          btn.setAttribute('aria-selected', 'true');
          var target = document.getElementById(btn.dataset.target);
          if (target) { target.classList.add('active'); }
        });
      });

      document.querySelectorAll('img[data-icon]').forEach(function (img) {
        var raw   = img.getAttribute('data-icon');
        var colon = raw.indexOf(':');
        var color = raw.slice(0, colon);
        var label = raw.slice(colon + 1);
        var fs    = label.length > 3 ? 16 : label.length > 2 ? 20 : 26;
        var svg =
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
  </script>
'@

# ── Page builder ───────────────────────────────────────────────────────────
function Build-Page($unit) {
    $unitShortcuts  = $shortcuts | Where-Object { Test-VisibleOn $_ $unit.code }
    $activeSections = $sections  | Where-Object {
        $id = $_.id
        (Test-SectionVisibleFor $_ $unit) -and [bool]($unitShortcuts | Where-Object { $_.grid -eq $id })
    }

    if (-not $activeSections) {
        Write-Warning "  $($unit.code): no shortcuts found — skipping"
        return $null
    }

    # Filter buttons
    $i = 0
    $filterButtons = (@($activeSections) | ForEach-Object {
        $active   = if ($i -eq 0) { ' active' } else { '' }
        $selected = if ($i -eq 0) { 'true' }   else { 'false' }
        $label    = EscHtml $_.label
        $id       = $_.id
        $i++
        "    <button class=`"f-btn$active`" role=`"tab`" aria-selected=`"$selected`" data-target=`"grid-$id`">$label</button>"
    }) -join "`n"

    # Grids
    $i = 0
    $grids = (@($activeSections) | ForEach-Object {
        $section = $_
        $active  = if ($i -eq 0) { ' active' } else { '' }
        $id      = $section.id
        $i++
        $items = ($unitShortcuts | Where-Object { $_.grid -eq $section.id } | Sort-Object label | ForEach-Object {
            Render-Item $_ $unit.accent
        }) -join ''
        "    <div class=`"grid$active`" id=`"grid-$id`" role=`"tabpanel`">$items`n    </div>"
    }) -join "`n`n"

    # Escape per-unit values for embedding in HTML
    $title      = EscHtml $unit.name
    $accent     = EscHtml $unit.accent
    $logo       = EscHtml ($root + $unit.logo.TrimStart('/'))
    $altName    = EscHtml $unit.name
    $collegeUrl = EscHtml $unit.collegeAppsUrl
    $code       = $unit.code
    $shortName  = EscHtml $unit.shortName

    return @"
<!DOCTYPE html>
<html lang="en">

<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>$title – Staff Apps</title>
  <link rel="apple-touch-icon" sizes="180x180" href="../style/apple-touch-icon.png">
  <link rel="icon" type="image/png" sizes="32x32" href="../style/favicon-32x32.png">
  <link rel="icon" type="image/png" sizes="16x16" href="../style/favicon-16x16.png">
  <link rel="manifest" href="../style/site.webmanifest">
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Pliant:ital,wght@0,100..900;1,100..900&display=swap" rel="stylesheet">
  <link rel="stylesheet" href="../style/styles.css">
  <style>:root { --accent: $accent; }</style>
</head>

<body>

  <nav class="topbar" aria-label="Main navigation">

    <button class="hamburger-btn" aria-label="Open navigation menu" aria-expanded="false"
      aria-controls="topbar-nav">&#9776; Menu</button>

    <div class="topbar-nav" id="topbar-nav">

      <a href="$collegeUrl" class="tb-link">College Apps</a>

      <a href="/$code/" class="tb-link active">$shortName Staff Apps</a>
      $SHARED_NAV
    </div>

  </nav>

  <div class="logo-wrap">
    <img src="$logo" alt="$altName">
  </div>

  <div class="filter-row" role="tablist" aria-label="Content category">
$filterButtons
  </div>

  <main class="grid-wrap">
$grids
  </main>

  <footer>
    <p>A ministry of <a href="https://www.ccmschools.edu.au">Christian Community Ministries</a></p>
  </footer>

$PAGE_SCRIPT

</body>

</html>
"@
}

# ── Main ───────────────────────────────────────────────────────────────────
$built   = 0
$skipped = 0

foreach ($unit in $units) {
    if ([string]::IsNullOrWhiteSpace($unit.name) -or $unit.accent -eq '#') {
        Write-Warning "  $($unit.code): incomplete (fill in name/accent in units.json) — skipping"
        $skipped++
        continue
    }

    $html = Build-Page $unit
    if (-not $html) { $skipped++; continue }

    New-Item -ItemType Directory -Force -Path $unit.code | Out-Null
    $html | Set-Content -Path (Join-Path $unit.code 'index.html') -Encoding utf8NoBOM
    Write-Host "  + $($unit.code)/index.html"
    $built++
}

Write-Host "`nDone. Built $built of $($units.Count) pages ($skipped skipped)."
