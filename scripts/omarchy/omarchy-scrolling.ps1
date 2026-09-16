# Toggle PaperWM-style horizontal scrolling on the focused workspace.
#
#   SUPER+CTRL+S
#
# Omarchy (via hyprscroller) has a mode where windows sit in one horizontal
# strip: the focused window takes almost the whole screen and the neighbours
# wait just off the edge, so you scroll sideways through them instead of
# splitting the screen smaller and smaller.
#
# komorebi has this natively as the `scrolling` layout. Two settings turn it
# into the Omarchy shape:
#
#   scrolling-layout-columns 1   one window per screen
#   workspace-padding <n>        pulls the window in from the edges, which is
#                                what lets the neighbour peek in at the side
#
# Measured on a 2560px monitor:
#   padding  8  -> window 2530px (98.8%), neighbour ends at x=1    (no peek)
#   padding 40  -> window 2466px (96.3%), neighbour ends at x=33   (33px peek)
#   padding 70  -> window 2406px (94.0%), neighbour ends at x=63   (63px peek)
#
# 40 is the default here: ~96% with a visible sliver of what is behind you.

[CmdletBinding()]
param(
    [int]$Padding = 40,
    [int]$Columns = 1,
    [ValidateSet("bsp", "columns", "rows", "vertical-stack", "horizontal-stack",
                 "ultrawide-vertical-stack", "grid", "right-main-vertical-stack")]
    [string]$RestoreLayout = "bsp",
    [int]$RestorePadding = 8
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
$wsIndex   = $monitor.workspaces.focused
$workspace = $monitor.workspaces.elements[$wsIndex]

# layout is an object like @{ Default = "BSP" } for the built-ins, and the
# plain string "Scrolling" is what we are looking for either way.
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
    komorebic workspace-padding 0 $wsIndex $RestorePadding 2>$null | Out-Null
} else {
    komorebic change-layout scrolling 2>$null | Out-Null
    komorebic scrolling-layout-columns $Columns 2>$null | Out-Null
    komorebic workspace-padding 0 $wsIndex $Padding 2>$null | Out-Null
}
