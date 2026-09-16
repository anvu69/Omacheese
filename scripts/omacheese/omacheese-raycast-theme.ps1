# Apply the active palette to Raycast.
#
#   omacheese-raycast-theme.ps1              import it into Raycast
#   omacheese-raycast-theme.ps1 -ShowUrl     print the link instead
#
# Raycast has no "import theme from file" - a theme travels as a deep link, so
# this builds one from the theme omacheese-theme.ps1 rendered. Nothing here
# hardcodes a colour, so Raycast follows whatever the rest of the desktop is
# wearing rather than being a second place to change.
#
# The format is the one themes.ray.so itself uses (lib/url.ts in
# raycast/theme-explorer): every field except `colors` becomes a query
# parameter, then the twelve colours follow in a fixed order as one
# comma-separated `colors` value. Order matters - they are positional.
#
# Themes are part of Raycast's paid tier. At the time of writing they are free
# during the Windows beta, but that is a beta courtesy, not a promise.

[CmdletBinding()]
param(
    [switch]$ShowUrl
)

$ErrorActionPreference = "Stop"

# omacheese-theme.ps1 writes this whenever a theme is set.
$themeFile = Join-Path $env:USERPROFILE ".config\omacheese\raycast-theme.json"
if (-not (Test-Path -LiteralPath $themeFile)) {
    Write-Host "No rendered theme yet. Pick one first:" -ForegroundColor Red
    Write-Host "  ./scripts/omacheese/omacheese-theme.ps1 -List" -ForegroundColor Cyan
    Write-Host "  ./scripts/omacheese/omacheese-theme.ps1 -Set tokyo-night" -ForegroundColor Cyan
    exit 1
}

$theme = Get-Content -LiteralPath $themeFile -Raw | ConvertFrom-Json

# Positional, and in this exact order.
$order = @("background", "backgroundSecondary", "text", "selection", "loader",
           "red", "orange", "yellow", "green", "blue", "purple", "magenta")

$missing = $order | Where-Object { -not $theme.colors.PSObject.Properties.Name.Contains($_) }
if ($missing) {
    Write-Host "Theme is missing colours: $($missing -join ', ')" -ForegroundColor Red
    exit 1
}

$params = @()
foreach ($p in $theme.PSObject.Properties) {
    if ($p.Name -eq "colors") { continue }
    $params += ("{0}={1}" -f [uri]::EscapeDataString($p.Name), [uri]::EscapeDataString([string]$p.Value))
}
$colors = ($order | ForEach-Object { [uri]::EscapeDataString([string]$theme.colors.$_) }) -join ","
$params += "colors=$colors"

$url = "raycast://theme?" + ($params -join "&")

if ($ShowUrl) { $url; exit 0 }

# A deep link to an app that is not installed fails in a way that is easy to
# misread as "the theme is broken", so say which it is.
if (-not (Test-Path -LiteralPath "HKCU:\SOFTWARE\Classes\raycast")) {
    Write-Host "Raycast does not look installed - the raycast:// handler is not registered." -ForegroundColor Yellow
    Write-Host "  winget install --id 9PFXXSHC64H3 --source msstore" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "The link, if you want it anyway:" -ForegroundColor DarkGray
    Write-Host "  $url" -ForegroundColor DarkGray
    exit 1
}

Start-Process $url
Write-Host "Sent '$($theme.name)' to Raycast." -ForegroundColor Green
Write-Host "Raycast asks before adding it; themes are a paid feature there." -ForegroundColor DarkGray
