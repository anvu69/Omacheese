# Toggle PaperWM-style horizontal scrolling on the focused workspace.
#
#   SUPER+CTRL+S
#   omacheese-scrolling.ps1 -WindowPercent 88     wider peek, narrower window
#
# Omarchy (via hyprscroller) has a mode where windows sit in one horizontal
# strip: the focused window takes almost the whole screen and the neighbours
# wait just off the edge, so you scroll sideways through them instead of
# splitting the screen smaller and smaller.
#
# This script only flips the layout. The geometry - how wide the window is,
# where it sits, and how much of the neighbours shows - belongs to
# omacheese-scroll-daemon.ps1, because it has to follow focus and has to survive
# the layout being entered some other way (SUPER+SHIFT+L cycles onto Scrolling
# without coming through here). See that file for the arithmetic.
#
# The daemon is started by start-desktop.ps1. If it is not running, the -Once
# call below still applies the geometry for the current focus, so the toggle
# degrades to "centred, correct width" rather than to nothing.

[CmdletBinding()]
param(
    [ValidateRange(0, 100)]
    [int]$WindowPercent = 0,
    [ValidateSet("bsp", "columns", "rows", "vertical-stack", "horizontal-stack",
                 "ultrawide-vertical-stack", "grid", "right-main-vertical-stack")]
    [string]$RestoreLayout = "bsp"
)

$ErrorActionPreference = "SilentlyContinue"
$env:KOMOREBI_CONFIG_HOME = Join-Path $env:USERPROFILE ".config\komorebi"

if (-not (Get-Command komorebic.exe -ErrorAction SilentlyContinue)) { exit 1 }

try {
    $state = komorebic state 2>$null | ConvertFrom-Json
} catch {
    exit 1
}
if (-not $state) { exit 1 }

$monitor   = $state.monitors.elements[$state.monitors.focused]
$workspace = $monitor.workspaces.elements[$monitor.workspaces.focused]

# layout is an object like @{ Default = "BSP" } for the built-ins; the plain
# string "Scrolling" is what we are looking for either way.
$current = ""
if ($workspace.layout) {
    if ($workspace.layout.PSObject.Properties.Name -contains "Default") {
        $current = [string]$workspace.layout.Default
    } else {
        $current = [string]$workspace.layout
    }
}

if ($current -match "Scrolling") {
    komorebic change-layout $RestoreLayout 2>$null | Out-Null
} else {
    komorebic change-layout scrolling 2>$null | Out-Null
    # After change-layout, not before: the column count belongs to the Scrolling
    # layout, so setting it from another layout is dropped and the strip comes
    # up split into columns.
    komorebic scrolling-layout-columns 1 2>$null | Out-Null
}

# Apply the geometry for the state we just moved to. The daemon would do this
# on its own a moment later, but doing it here keeps the toggle instant, and
# keeps it working on a machine where the daemon is not up.
$daemon = Join-Path $PSScriptRoot "omacheese-scroll-daemon.ps1"
if (Test-Path -LiteralPath $daemon) {
    if ($WindowPercent -gt 0) {
        & $daemon -Once -WindowPercent $WindowPercent
    } else {
        & $daemon -Once
    }
}
