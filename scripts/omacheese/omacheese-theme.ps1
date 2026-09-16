# One palette, applied everywhere.
#
#   omacheese-theme.ps1 -List
#   omacheese-theme.ps1 -Current
#   omacheese-theme.ps1 -Set catppuccin
#
# The colours used to live as hex literals in four different files, which meant
# "change the theme" was a find-and-replace across komorebi, yasb, Alacritty and
# the menu, and they drifted. Now there is one palette and the configs are
# rendered from templates.
#
# The palettes are Omarchy's own, copied verbatim from omacom/omarchy
# themes/<name>/colors.toml, so any of its 22 themes can be dropped into
# configs/theme/ and used without translation. Every one declares the same 26
# keys, which is what makes them interchangeable:
#
#   accent selection muted
#   background dark_background darker_background lighter_background
#   foreground dark_foreground light_foreground bright_foreground
#   red yellow orange green cyan blue magenta brown
#   bright_red bright_yellow bright_green bright_cyan bright_blue bright_magenta
#
# Templates are the real configs with the hex literals replaced by {{token}}.
# Everything else in them - yasb's min-widths, Alacritty's font stack, komorebi's
# rules - is untouched, so theming cannot break layout.

[CmdletBinding()]
param(
    [string]$Set,
    [switch]$List,
    [switch]$Current,
    [switch]$NoRestart
)

$ErrorActionPreference = "Stop"

$cfg       = Join-Path $env:USERPROFILE ".config"
$themeHome = Join-Path $cfg "omacheese\theme"
$palDir    = Join-Path $themeHome "palettes"
$tmplDir   = Join-Path $themeHome "templates"
$activeFile = Join-Path $themeHome "active"

# Run from a clone too, so the repo copies win when they exist.
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if (Test-Path -LiteralPath (Join-Path $repoRoot "configs\theme")) {
    $palDir = Join-Path $repoRoot "configs\theme"
}

function Get-PaletteFile {
    if (-not (Test-Path -LiteralPath $palDir)) { return @() }
    return @(Get-ChildItem $palDir -Filter *.toml | Sort-Object Name)
}

# These files are `key = "value"` and nothing else, so a regex is the whole
# parser. Bringing in a TOML library to read 26 lines would be worse.
function Read-Palette {
    param([string]$Path)
    $map = @{}
    foreach ($line in Get-Content -LiteralPath $Path) {
        $m = [regex]::Match($line, '^\s*(\w+)\s*=\s*"([^"]*)"')
        if ($m.Success) { $map[$m.Groups[1].Value] = $m.Groups[2].Value }
    }
    return $map
}

function Get-ActiveTheme {
    if (Test-Path -LiteralPath $activeFile) {
        $n = (Get-Content -LiteralPath $activeFile -Raw).Trim()
        if ($n) { return $n }
    }
    return "tokyo-night"
}

function Expand-Template {
    param([string]$Text, [hashtable]$Palette, [string]$Label)
    $out = $Text
    foreach ($m in [regex]::Matches($Text, '\{\{(\w+)\}\}')) {
        $key = $m.Groups[1].Value
        if ($Palette.ContainsKey($key)) {
            $out = $out.Replace($m.Value, $Palette[$key])
        } else {
            # Leave the token visible rather than emitting an empty colour: empty
            # renders as black and reads as a styling bug, while {{accent}} sitting
            # in a config says exactly what is wrong.
            Write-Warning "${Label}: palette has no '$key'"
        }
    }
    return $out
}

# Raycast has its own schema and wants exactly twelve colours, so it is built
# rather than templated. See omacheese-raycast-theme.ps1 for how it gets imported.
function Write-RaycastTheme {
    param([hashtable]$P, [string]$Name, [string]$Destination)
    $appearance = "dark"
    if ($P.ContainsKey("mode") -and $P["mode"]) { $appearance = $P["mode"] }
    $theme = [ordered]@{
        author         = "windows11-dev-poweruser"
        authorUsername = "anvu69"
        version        = "1"
        name           = "Omacheese $Name"
        appearance     = $appearance
        colors         = [ordered]@{
            background          = $P["background"]
            backgroundSecondary = $P["lighter_background"]
            text                = $P["bright_foreground"]
            selection           = $P["selection"]
            loader              = $P["accent"]
            red                 = $P["red"]
            orange              = $P["orange"]
            yellow              = $P["yellow"]
            green               = $P["green"]
            blue                = $P["blue"]
            purple              = $P["magenta"]
            magenta             = $P["bright_magenta"]
        }
    }
    $json = $theme | ConvertTo-Json -Depth 4
    Set-Content -LiteralPath $Destination -Value $json -Encoding UTF8
}

# ---------------------------------------------------------------------------

if ($List) {
    $active = Get-ActiveTheme
    $pals = Get-PaletteFile
    if (-not $pals) { Write-Host "No palettes in $palDir" -ForegroundColor Yellow; exit 1 }
    foreach ($p in $pals) {
        $name = [IO.Path]::GetFileNameWithoutExtension($p.Name)
        $c = Read-Palette $p.FullName
        $mark = "  "
        if ($name -eq $active) { $mark = "* " }
        Write-Host ("{0}{1,-18} {2}  bg {3}  accent {4}" -f $mark, $name, $c["mode"], $c["background"], $c["accent"])
    }
    exit 0
}

if ($Current) { Get-ActiveTheme; exit 0 }

if (-not $Set) {
    Write-Host "Usage: omacheese-theme.ps1 -Set <name> | -List | -Current" -ForegroundColor Yellow
    exit 1
}

$palFile = Join-Path $palDir "$Set.toml"
if (-not (Test-Path -LiteralPath $palFile)) {
    Write-Host "No palette '$Set' in $palDir" -ForegroundColor Red
    Write-Host "Available:" -ForegroundColor Yellow
    foreach ($p in Get-PaletteFile) { Write-Host "  $([IO.Path]::GetFileNameWithoutExtension($p.Name))" }
    exit 1
}

$palette = Read-Palette $palFile
if ($palette.Count -lt 10) { Write-Host "Palette '$Set' looks empty." -ForegroundColor Red; exit 1 }

# Templates come from the repo when running in a clone, otherwise from the
# installed copy.
$tmplSource = $tmplDir
$repoTmpl = Join-Path $repoRoot "configs"
if (Test-Path -LiteralPath (Join-Path $repoTmpl "komorebi\komorebi.json.tmpl")) { $tmplSource = "repo" }

$targets = @(
    @{ Tmpl = "komorebi\komorebi.json.tmpl";   Repo = "configs\komorebi\komorebi.json.tmpl";   Dest = (Join-Path $cfg "komorebi\komorebi.json") }
    @{ Tmpl = "yasb\styles.css.tmpl";          Repo = "configs\yasb\styles.css.tmpl";          Dest = (Join-Path $cfg "yasb\styles.css") }
    @{ Tmpl = "alacritty\alacritty.toml.tmpl"; Repo = "configs\alacritty\alacritty.toml.tmpl"; Dest = (Join-Path $env:APPDATA "alacritty\alacritty.toml") }
)

$written = 0
foreach ($t in $targets) {
    if ($tmplSource -eq "repo") { $src = Join-Path $repoRoot $t.Repo }
    else { $src = Join-Path $tmplDir (Split-Path $t.Tmpl -Leaf) }

    if (-not (Test-Path -LiteralPath $src)) {
        Write-Warning "missing template: $src"
        continue
    }
    $destDir = Split-Path $t.Dest -Parent
    if (-not (Test-Path -LiteralPath $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }

    $text = Get-Content -LiteralPath $src -Raw
    $out  = Expand-Template -Text $text -Palette $palette -Label (Split-Path $src -Leaf)

    # Write without a BOM: komorebi and Alacritty both parse these, and a BOM in
    # front of a JSON or TOML document is not something either promises to skip.
    [IO.File]::WriteAllText($t.Dest, $out, (New-Object Text.UTF8Encoding($false)))
    Write-Host ("  + {0}" -f $t.Dest) -ForegroundColor Green
    $written++
}

$rcTheme = Join-Path $cfg "omacheese\raycast-theme.json"
$rcDir = Split-Path $rcTheme -Parent
if (-not (Test-Path -LiteralPath $rcDir)) { New-Item -ItemType Directory -Path $rcDir -Force | Out-Null }
Write-RaycastTheme -P $palette -Name $Set -Destination $rcTheme
Write-Host ("  + {0}" -f $rcTheme) -ForegroundColor Green

if (-not (Test-Path -LiteralPath $themeHome)) { New-Item -ItemType Directory -Path $themeHome -Force | Out-Null }
Set-Content -LiteralPath $activeFile -Value $Set -Encoding ASCII

Write-Host ""
Write-Host "Theme: $Set ($written configs rendered)" -ForegroundColor Cyan

if ($NoRestart) { exit 0 }

# yasb re-reads its stylesheet only on start; komorebi can be told.
if (Get-Process yasb -ErrorAction SilentlyContinue) {
    Get-Process yasb -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Milliseconds 600
    Start-Process yasb.exe -WindowStyle Hidden -ErrorAction SilentlyContinue
    Write-Host "  yasb restarted" -ForegroundColor DarkGray
}
if (Get-Command komorebic -ErrorAction SilentlyContinue) {
    komorebic reload-configuration 2>$null | Out-Null
    Write-Host "  komorebi reloaded" -ForegroundColor DarkGray
}
Write-Host "  Alacritty picks it up on the next window" -ForegroundColor DarkGray
Write-Host "  Raycast: ./scripts/omacheese/omacheese-raycast-theme.ps1" -ForegroundColor DarkGray
