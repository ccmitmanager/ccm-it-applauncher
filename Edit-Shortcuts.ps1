#Requires -Version 5.1
<#
.SYNOPSIS
    Graphical editor for AppLauncher shortcuts.json
.DESCRIPTION
    Edit, add, delete, and reorder shortcuts across all sections.
    Reads sections.json for section labels and units.json for unit codes.
    Run from the repo root or any subdirectory.
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# --- Resolve data paths relative to this script ---
$scriptDir     = $PSScriptRoot
if (-not $scriptDir) { $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path }

$dataDir       = Join-Path $scriptDir "_data"
$iconsDir      = Join-Path $scriptDir "icons"
$shortcutsPath = Join-Path $dataDir "shortcuts.json"
$sectionsPath  = Join-Path $dataDir "sections.json"
$unitsPath     = Join-Path $dataDir "units.json"

foreach ($p in $shortcutsPath, $sectionsPath, $unitsPath) {
    if (-not (Test-Path $p)) {
        [System.Windows.Forms.MessageBox]::Show("Required file not found:`n$p", "Startup Error", "OK", "Error")
        exit 1
    }
}

# --- Load reference data ---
$sectionsData = Get-Content $sectionsPath -Raw | ConvertFrom-Json
$unitsData    = Get-Content $unitsPath    -Raw | ConvertFrom-Json
$unitCodes    = @($unitsData | ForEach-Object { $_.code } | Sort-Object)

# Icon files available for icon_src, relative to the icons directory
$iconFiles = @()
if (Test-Path $iconsDir) {
    $iconFiles = Get-ChildItem $iconsDir -Recurse -File |
        ForEach-Object { $_.FullName.Substring($iconsDir.Length).TrimStart('\', '/').Replace('\', '/') } |
        Sort-Object
}

# ============================================================
# DATA LOAD / SAVE
# ============================================================
function ConvertTo-EditableItem ([object]$psObj) {
    $ht = [ordered]@{}
    foreach ($p in $psObj.PSObject.Properties) {
        $v = $p.Value
        if ($null -eq $v) { continue }
        if ($v -is [System.Array] -or ($v -is [System.Collections.IList] -and $v -isnot [string])) {
            $ht[$p.Name] = [System.Collections.Generic.List[string]](@($v | ForEach-Object { "$_" }))
        } else {
            $ht[$p.Name] = "$v"
        }
    }
    return $ht
}

function Load-Shortcuts {
    $raw = Get-Content $shortcutsPath -Raw | ConvertFrom-Json
    $ht  = [ordered]@{}
    foreach ($prop in $raw.PSObject.Properties) {
        $list = [System.Collections.Generic.List[object]]::new()
        foreach ($item in $prop.Value) {
            $list.Add((ConvertTo-EditableItem $item))
        }
        $ht[$prop.Name] = $list
    }
    return $ht
}

function Save-Shortcuts ([object]$data) {
    $root = [ordered]@{}
    foreach ($key in $data.Keys) {
        $root[$key] = @($data[$key] | ForEach-Object {
            $entry = [ordered]@{}
            foreach ($k in $_.Keys) {
                $v = $_[$k]
                if ($null -eq $v) { continue }
                if ($v -is [System.Collections.IList] -and $v -isnot [string]) {
                    $arr = @($v | ForEach-Object { "$_" })
                    if ($arr.Count -gt 0) { $entry[$k] = $arr }
                } elseif ("$v" -ne "") {
                    $entry[$k] = "$v"
                }
            }
            [pscustomobject]$entry
        })
    }
    $json = $root | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($shortcutsPath, $json, [System.Text.UTF8Encoding]::new($false))
}

$shortcutsData = Load-Shortcuts

# ============================================================
# FORM
# ============================================================
$form = [System.Windows.Forms.Form]@{
    Text          = "AppLauncher Shortcuts Editor"
    Size          = [System.Drawing.Size]::new(980, 720)
    StartPosition = "CenterScreen"
    MinimumSize   = [System.Drawing.Size]::new(740, 540)
    Font          = [System.Drawing.Font]::new("Segoe UI", 9)
}

# ---- Status / Save bar (docked bottom) ----
$pnlBottom = [System.Windows.Forms.Panel]@{
    Dock      = "Bottom"
    Height    = 46
    BackColor = [System.Drawing.Color]::FromArgb(232, 232, 232)
}
$form.Controls.Add($pnlBottom)

$lblStatus = [System.Windows.Forms.Label]@{
    AutoSize  = $true
    Location  = [System.Drawing.Point]::new(12, 15)
    ForeColor = [System.Drawing.Color]::FromArgb(70, 70, 70)
}
$pnlBottom.Controls.Add($lblStatus)

$btnSaveAll = [System.Windows.Forms.Button]@{
    Text      = "Save All to shortcuts.json"
    Width     = 218
    Height    = 30
    Anchor    = "Top,Right"
    FlatStyle = "Flat"
    BackColor = [System.Drawing.Color]::FromArgb(40, 167, 69)
    ForeColor = [System.Drawing.Color]::White
}
$btnSaveAll.Location = [System.Drawing.Point]::new($pnlBottom.Width - $btnSaveAll.Width - 12, 8)
$pnlBottom.Controls.Add($btnSaveAll)

# ---- Main splitter ----
$split = New-Object System.Windows.Forms.SplitContainer
$split.Dock = "Fill"
$form.Controls.Add($split)

# ============================================================
# LEFT PANEL  — section picker + shortcut list
# ============================================================
# WinForms dock layout processes controls from highest index to lowest (back→front).
# The Fill control must be at index 0 (added first) so it is processed LAST and
# receives whatever space remains after Top and Bottom panels have been allocated.

$lstShortcuts = [System.Windows.Forms.ListBox]@{
    Dock           = "Fill"
    IntegralHeight = $false
}
$split.Panel1.Controls.Add($lstShortcuts)   # index 0 — processed last, fills remaining space

# Buttons docked to bottom of left panel
$pnlLeftBtns = [System.Windows.Forms.FlowLayoutPanel]@{
    Dock          = "Bottom"
    Height        = 36
    FlowDirection = "LeftToRight"
    WrapContents  = $false
    Padding       = [System.Windows.Forms.Padding]::new(6, 4, 0, 0)
}
$split.Panel1.Controls.Add($pnlLeftBtns)   # index 1 — processed second

foreach ($def in @(
    @{n="btnAdd";  t="+ Add";  w=60},
    @{n="btnDel";  t="Delete"; w=60},
    @{n="btnUp";   t="▲";      w=34},
    @{n="btnDown"; t="▼";      w=34}
)) {
    $b = [System.Windows.Forms.Button]@{ Text=$def.t; Width=$def.w; Height=28; FlatStyle="System" }
    $pnlLeftBtns.Controls.Add($b)
    Set-Variable -Name $def.n -Value $b
}

# Header panel docked to top (added last = highest index = processed first, carves top space)
$pnlLeftTop = [System.Windows.Forms.Panel]@{
    Dock   = "Top"
    Height = 82
}
$split.Panel1.Controls.Add($pnlLeftTop)    # highest index — processed first, takes top 82 px

$lblSec = [System.Windows.Forms.Label]@{
    Text     = "Section"
    Location = [System.Drawing.Point]::new(8, 6)
    AutoSize = $true
}
$pnlLeftTop.Controls.Add($lblSec)

$cboSection = [System.Windows.Forms.ComboBox]@{
    Location      = [System.Drawing.Point]::new(8, 24)
    Width         = 238
    DropDownStyle = "DropDownList"
}
$pnlLeftTop.Controls.Add($cboSection)

$lblShortcutsHead = [System.Windows.Forms.Label]@{
    Text     = "Shortcuts"
    Location = [System.Drawing.Point]::new(8, 58)
    AutoSize = $true
}
$pnlLeftTop.Controls.Add($lblShortcutsHead)

# ============================================================
# RIGHT PANEL  — edit form
# ============================================================
$pnlScroll = [System.Windows.Forms.Panel]@{
    Dock       = "Fill"
    AutoScroll = $true
}
$split.Panel2.Controls.Add($pnlScroll)

$canvas = [System.Windows.Forms.Panel]@{
    Width   = 520
    Height  = 800
    Padding = [System.Windows.Forms.Padding]::new(0)
}
$pnlScroll.Controls.Add($canvas)

# Helpers
$y  = 12
$lX = 8
$lW = 108
$iX = 122
$iW = 370

function Add-FieldRow ([string]$text, [int]$top) {
    $lbl = [System.Windows.Forms.Label]@{
        Text      = $text
        Location  = [System.Drawing.Point]::new($lX, ($top + 3))
        Width     = $lW
        TextAlign = "MiddleRight"
    }
    $canvas.Controls.Add($lbl)
}

function New-Input ([int]$top, [int]$width = $iW) {
    $tb = [System.Windows.Forms.TextBox]@{
        Location = [System.Drawing.Point]::new($iX, $top)
        Width    = $width
    }
    $canvas.Controls.Add($tb)
    return $tb
}

function Add-Separator ([int]$top) {
    $sep = [System.Windows.Forms.Label]@{
        Location    = [System.Drawing.Point]::new($lX, $top)
        Width       = 500
        Height      = 1
        BackColor   = [System.Drawing.Color]::Silver
        BorderStyle = "None"
    }
    $canvas.Controls.Add($sep)
}

Add-FieldRow "ID:"     $y; $txtId    = New-Input $y;   $y += 30
Add-FieldRow "Label:"  $y; $txtLabel = New-Input $y;   $y += 30
Add-FieldRow "URL:"    $y; $txtHref  = New-Input $y;   $y += 30
Add-Separator $y; $y += 10

# Icon type radio buttons
Add-FieldRow "Icon type:" $y
$rdoIconText = [System.Windows.Forms.RadioButton]@{
    Text     = "Text  (icon)"
    Location = [System.Drawing.Point]::new($iX, $y)
    Width    = 115
    Checked  = $true
}
$canvas.Controls.Add($rdoIconText)

$rdoIconFile = [System.Windows.Forms.RadioButton]@{
    Text     = "Image file  (icon_src)"
    Location = [System.Drawing.Point]::new($iX + 115, $y)
    Width    = 180
}
$canvas.Controls.Add($rdoIconFile)
$y += 30

# Icon value — text box or file combobox (toggled)
Add-FieldRow "Icon value:" $y

$txtIconText = [System.Windows.Forms.TextBox]@{
    Location = [System.Drawing.Point]::new($iX, $y)
    Width    = $iW
}
$canvas.Controls.Add($txtIconText)

$cboIconFile = [System.Windows.Forms.ComboBox]@{
    Location           = [System.Drawing.Point]::new($iX, $y)
    Width              = $iW
    DropDownStyle      = "DropDown"
    AutoCompleteMode   = "SuggestAppend"
    AutoCompleteSource = "ListItems"
    Visible            = $false
}
foreach ($f in $iconFiles) { [void]$cboIconFile.Items.Add($f) }
$canvas.Controls.Add($cboIconFile)
$y += 30

Add-FieldRow "Background:" $y
$txtBg = New-Input $y 160
$canvas.Controls.Add([System.Windows.Forms.Label]@{
    Text      = "(optional hex / CSS color)"
    Location  = [System.Drawing.Point]::new($iX + 168, $y + 3)
    AutoSize  = $true
    ForeColor = [System.Drawing.Color]::Gray
})
$y += 30

Add-Separator $y; $y += 10

# Only / Exclude side-by-side
$lblOnlyHead = [System.Windows.Forms.Label]@{
    Text     = "Show only for these units:"
    Location = [System.Drawing.Point]::new($lX, $y)
    AutoSize = $true
    Font     = [System.Drawing.Font]::new("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
}
$canvas.Controls.Add($lblOnlyHead)

$lblExclHead = [System.Windows.Forms.Label]@{
    Text     = "Exclude from these units:"
    Location = [System.Drawing.Point]::new(260, $y)
    AutoSize = $true
    Font     = [System.Drawing.Font]::new("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
}
$canvas.Controls.Add($lblExclHead)
$y += 22

$clbOnly = [System.Windows.Forms.CheckedListBox]@{
    Location     = [System.Drawing.Point]::new($lX, $y)
    Width        = 234
    Height       = 170
    CheckOnClick = $true
}
foreach ($c in $unitCodes) { [void]$clbOnly.Items.Add($c) }
$canvas.Controls.Add($clbOnly)

$clbExclude = [System.Windows.Forms.CheckedListBox]@{
    Location     = [System.Drawing.Point]::new(252, $y)
    Width        = 234
    Height       = 170
    CheckOnClick = $true
}
foreach ($c in $unitCodes) { [void]$clbExclude.Items.Add($c) }
$canvas.Controls.Add($clbExclude)
$y += 178

$canvas.Controls.Add([System.Windows.Forms.Label]@{
    Text      = "Tip: 'Only' and 'Exclude' are mutually exclusive — don't set both."
    Location  = [System.Drawing.Point]::new($lX, $y)
    AutoSize  = $true
    ForeColor = [System.Drawing.Color]::Gray
})
$y += 24

Add-Separator $y; $y += 12

# Apply button
$btnApply = [System.Windows.Forms.Button]@{
    Text      = "Apply Changes"
    Location  = [System.Drawing.Point]::new($iX, $y)
    Width     = 150
    Height    = 32
    FlatStyle = "Flat"
    BackColor = [System.Drawing.Color]::FromArgb(0, 120, 212)
    ForeColor = [System.Drawing.Color]::White
}
$canvas.Controls.Add($btnApply)
$y += 50

$canvas.Height = $y

# ============================================================
# LOGIC
# ============================================================
$script:dirty       = $false
$script:sectionKeys = [System.Collections.Generic.List[string]]::new()

function Set-Status ([string]$msg) { $lblStatus.Text = $msg }

function Set-Dirty ([bool]$val) {
    $script:dirty    = $val
    $btnSaveAll.Text = "Save All to shortcuts.json$(if ($val) { ' *' })"
}

function Get-SectionKey {
    $i = $cboSection.SelectedIndex
    if ($i -lt 0) { return $null }
    return $script:sectionKeys[$i]
}

function Update-UnitFilterState {
    $key = Get-SectionKey
    $sec = $sectionsData | Where-Object { $_.id -eq $key } | Select-Object -First 1
    $enabled = ($sec -and $sec.only -eq "school")
    $clbOnly.Enabled     = $enabled
    $clbExclude.Enabled  = $enabled
    $lblOnlyHead.Enabled = $enabled
    $lblExclHead.Enabled = $enabled
}

function Refresh-List {
    $lstShortcuts.BeginUpdate()
    $lstShortcuts.Items.Clear()
    $key = Get-SectionKey
    if ($key -and $shortcutsData.Contains($key)) {
        foreach ($item in $shortcutsData[$key]) {
            $disp = if ($item.Contains("label") -and $item["label"]) { $item["label"] } else { $item["id"] }
            [void]$lstShortcuts.Items.Add($disp)
        }
    }
    $lstShortcuts.EndUpdate()
}

function Load-ItemToForm ([object]$item) {
    $txtId.Text    = if ($item.Contains("id"))    { $item["id"] }    else { "" }
    $txtLabel.Text = if ($item.Contains("label")) { $item["label"] } else { "" }
    $txtHref.Text  = if ($item.Contains("href"))  { $item["href"] }  else { "" }
    $txtBg.Text    = if ($item.Contains("bg"))    { $item["bg"] }    else { "" }

    if ($item.Contains("icon_src")) {
        $rdoIconFile.Checked = $true
        $cboIconFile.Text    = $item["icon_src"]
        $txtIconText.Text    = ""
    } else {
        $rdoIconText.Checked = $true
        $txtIconText.Text    = if ($item.Contains("icon")) { $item["icon"] } else { "" }
        $cboIconFile.Text    = ""
    }

    for ($i = 0; $i -lt $clbOnly.Items.Count; $i++) {
        $clbOnly.SetItemChecked($i,
            ($item.Contains("only") -and $item["only"] -contains $clbOnly.Items[$i]))
    }
    for ($i = 0; $i -lt $clbExclude.Items.Count; $i++) {
        $clbExclude.SetItemChecked($i,
            ($item.Contains("exclude") -and $item["exclude"] -contains $clbExclude.Items[$i]))
    }
}

function Clear-Form {
    $txtId.Text = $txtLabel.Text = $txtHref.Text = $txtBg.Text = ""
    $txtIconText.Text = $cboIconFile.Text = ""
    $rdoIconText.Checked = $true
    for ($i = 0; $i -lt $clbOnly.Items.Count;    $i++) { $clbOnly.SetItemChecked($i, $false) }
    for ($i = 0; $i -lt $clbExclude.Items.Count; $i++) { $clbExclude.SetItemChecked($i, $false) }
}

function Apply-Changes {
    $key = Get-SectionKey
    if (-not $key) { Set-Status "Select a section first."; return }

    # Intent is derived from the list selection: no selection => append a new entry,
    # an existing selection => update that entry. (More robust than a persistent flag.)
    $idx = $lstShortcuts.SelectedIndex

    $item = [ordered]@{}
    $id   = $txtId.Text.Trim()
    if (-not $id) { [System.Windows.Forms.MessageBox]::Show("ID is required.", "Validation", "OK", "Warning"); return }
    $item["id"]   = $id
    $item["href"] = $txtHref.Text.Trim()

    if ($rdoIconFile.Checked) {
        $src = $cboIconFile.Text.Trim()
        if ($src) { $item["icon_src"] = $src }
    } else {
        $ico = $txtIconText.Text.Trim()
        if ($ico) { $item["icon"] = $ico }
    }

    $lbl = $txtLabel.Text.Trim()
    if ($lbl) { $item["label"] = $lbl }

    $bg = $txtBg.Text.Trim()
    if ($bg) { $item["bg"] = $bg }

    if ($clbOnly.Enabled) {
        $onlyArr = @($clbOnly.CheckedItems    | ForEach-Object { "$_" })
        $exclArr = @($clbExclude.CheckedItems | ForEach-Object { "$_" })
        if ($onlyArr.Count -gt 0) { $item["only"]    = $onlyArr }
        if ($exclArr.Count -gt 0) { $item["exclude"] = $exclArr }
    }

    if (-not $shortcutsData.Contains($key)) {
        $shortcutsData[$key] = [System.Collections.Generic.List[object]]::new()
    }
    $list = $shortcutsData[$key]
    $disp = if ($item["label"]) { $item["label"] } else { $item["id"] }

    if ($idx -lt 0) {
        # No selection -> append the freshly composed entry.
        $list.Add($item)
        [void]$lstShortcuts.Items.Add($disp)
        $lstShortcuts.SelectedIndex = $lstShortcuts.Items.Count - 1
        Set-Status "Added '$disp'. Click Save All to write to disk."
    } else {
        # Update the selected entry. Use RemoveAt/Insert rather than the index-setter,
        # which PowerShell does not reliably chain through two indexers.
        $list.RemoveAt($idx)
        $list.Insert($idx, $item)
        $lstShortcuts.BeginUpdate()
        $lstShortcuts.Items.RemoveAt($idx)
        $lstShortcuts.Items.Insert($idx, $disp)
        $lstShortcuts.EndUpdate()
        $lstShortcuts.SelectedIndex = $idx
        Set-Status "Changes applied to '$disp'. Click Save All to write to disk."
    }

    Set-Dirty $true
}

# ============================================================
# POPULATE SECTION DROPDOWN
# ============================================================
foreach ($sec in $sectionsData) {
    [void]$cboSection.Items.Add("$($sec.label)  [$($sec.id)]")
    [void]$script:sectionKeys.Add($sec.id)
}
# Any section keys in the data file not in sections.json
foreach ($key in $shortcutsData.Keys) {
    if ($script:sectionKeys -notcontains $key) {
        [void]$cboSection.Items.Add("$key  [$key]")
        [void]$script:sectionKeys.Add($key)
    }
}

# ============================================================
# EVENTS
# ============================================================
$rdoIconText.Add_CheckedChanged({
    $txtIconText.Visible = $rdoIconText.Checked
    $cboIconFile.Visible = -not $rdoIconText.Checked
})
$rdoIconFile.Add_CheckedChanged({
    $txtIconText.Visible = $rdoIconText.Checked
    $cboIconFile.Visible = -not $rdoIconText.Checked
})

$cboSection.Add_SelectedIndexChanged({
    Refresh-List
    Clear-Form
    Update-UnitFilterState
    Set-Status ""
})

$lstShortcuts.Add_SelectedIndexChanged({
    $idx = $lstShortcuts.SelectedIndex
    if ($idx -ge 0) {
        $key = Get-SectionKey
        Load-ItemToForm ($shortcutsData[$key][$idx])
    }
})

$btnApply.Add_Click({ Apply-Changes })

# Also apply on Enter key in the main text fields
foreach ($tb in $txtId, $txtLabel, $txtHref, $txtBg, $txtIconText) {
    $tb.Add_KeyDown({
        if ($_.KeyCode -eq "Return") { Apply-Changes; $_.SuppressKeyPress = $true }
    })
}

$btnAdd.Add_Click({
    $key = Get-SectionKey
    if (-not $key) { Set-Status "Select a section first."; return }
    $lstShortcuts.ClearSelected()   # SelectedIndex = -1 => Apply will append a new entry
    Clear-Form
    $txtId.Focus()
    Set-Status "New shortcut for '$key'. Fill in the fields, then click Apply Changes to add it."
})

$btnDel.Add_Click({
    $key = Get-SectionKey
    $idx = $lstShortcuts.SelectedIndex
    if ($idx -lt 0) { Set-Status "Select a shortcut to delete."; return }
    $name = $lstShortcuts.Items[$idx]
    $res  = [System.Windows.Forms.MessageBox]::Show(
        "Delete '$name'?", "Confirm Delete", "YesNo", "Warning")
    if ($res -eq "Yes") {
        $shortcutsData[$key].RemoveAt($idx)
        $lstShortcuts.Items.RemoveAt($idx)
        $newIdx = [Math]::Min($idx, $lstShortcuts.Items.Count - 1)
        if ($newIdx -ge 0) { $lstShortcuts.SelectedIndex = $newIdx } else { Clear-Form }
        Set-Dirty $true
        Set-Status "Deleted '$name'."
    }
})

$btnUp.Add_Click({
    $key = Get-SectionKey
    $idx = $lstShortcuts.SelectedIndex
    if ($idx -le 0) { return }
    $item = $shortcutsData[$key][$idx]
    $shortcutsData[$key].RemoveAt($idx)
    $shortcutsData[$key].Insert($idx - 1, $item)
    $disp = $lstShortcuts.Items[$idx]
    $lstShortcuts.Items.RemoveAt($idx)
    $lstShortcuts.Items.Insert($idx - 1, $disp)
    $lstShortcuts.SelectedIndex = $idx - 1
    Set-Dirty $true
})

$btnDown.Add_Click({
    $key = Get-SectionKey
    $idx = $lstShortcuts.SelectedIndex
    if ($idx -lt 0 -or $idx -ge ($lstShortcuts.Items.Count - 1)) { return }
    $item = $shortcutsData[$key][$idx]
    $shortcutsData[$key].RemoveAt($idx)
    $shortcutsData[$key].Insert($idx + 1, $item)
    $disp = $lstShortcuts.Items[$idx]
    $lstShortcuts.Items.RemoveAt($idx)
    $lstShortcuts.Items.Insert($idx + 1, $disp)
    $lstShortcuts.SelectedIndex = $idx + 1
    Set-Dirty $true
})

$btnSaveAll.Add_Click({
    try {
        Save-Shortcuts $shortcutsData
        Set-Dirty $false
        Set-Status "Saved successfully at $(Get-Date -Format 'HH:mm:ss')."
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Error saving file:`n$_", "Save Error", "OK", "Error")
    }
})

$form.Add_FormClosing({
    if ($script:dirty) {
        $res = [System.Windows.Forms.MessageBox]::Show(
            "You have unsaved changes. Close without saving?",
            "Unsaved Changes", "YesNo", "Warning")
        if ($res -ne "Yes") { $_.Cancel = $true }
    }
})

$form.Add_Shown({
    $split.Panel1MinSize    = 200
    $split.Panel2MinSize    = 440
    $split.SplitterDistance = 270
    if ($cboSection.Items.Count -gt 0) {
        $cboSection.SelectedIndex = 0   # triggers SelectedIndexChanged → Update-UnitFilterState
    }
})

[System.Windows.Forms.Application]::Run($form)
