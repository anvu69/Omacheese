# Toggle PaperWM-style horizontal scrolling on the focused workspace.
#
#   SUPER+CTRL+S
#   omarchy-scrolling.ps1 -WindowPercent 92     wider peek, narrower window
#
# Omarchy (via hyprscroller) has a mode where windows sit in one horizontal
# strip: the focused window takes almost the whole screen and the neighbours
# wait just off the edge, so you scroll sideways through them instead of
# splitting the screen smaller and smaller.
#
# komorebi has the strip natively as the `scrolling` layout. What this script
# adds is the padding that lets the neighbour peek in at the edge.
#
# THE GEOMETRY
#
#   inset  = workspace_padding + container_padding
#   window = monitor_width - 2 * inset
#   peek   = inset - 2 * container_padding      <- the sliver of the neighbour
#
# Two things follow, and both were wrong before:
#
#   1. container_padding is the gap BETWEEN windows, and it comes off the peek
#      twice. At the old default of 6 it ate 12px of an already thin sliver.
#      Scrolling mode sets it to 0, so peek == inset.
#
#   2. A fixed padding is a different fraction of every screen. 40px is 3% of a
#      1366px laptop but 1.6% of a 2560px monitor, which is why the sliver only
#      registered on the small one. The inset is computed from the monitor
#      width instead, so it looks the same everywhere.
#
# The two knobs pull against each other: a 95% window leaves 5% of the screen
# over, so the peek cannot exceed 2.5% per side. Measured on the 2560x1440
# monitor this was written on:
#
#   -WindowPercent 95   window 2444px (95.5%)   peek  70px   <- default
#   -WindowPercent 92   window 2368px (92.5%)   peek 108px
#   -WindowPercent 90   window 2316px (90.5%)   peek 134px
#
# For comparison the old fixed -Padding 40 with its 6px container padding gave
# a 2466px window and a 33px peek, and stock 8/6 padding gave 8px - a sliver
# you could not see at all.

[CmdletBinding()]
param(
    [ValidateRange(70, 100)]
    [int]$WindowPercent = 95,
    [ValidateSet("bsp", "columns", "rows", "vertical-stack", "horizontal-stack",
                 "ultrawide-vertical-stack", "grid", "right-main-vertical-stack")]
    [string]$RestoreLayout = "bsp",
    [int]$RestorePadding = 8,
    [int]$RestoreContainerPadding = 6
)

$ErrorActionPreference = "SilentlyContinue"
$configHome = Join-Path $env:USERPROFILE ".config\komorebi"
$env:KOMOREBI_CONFIG_HOME = $configHome

if (-not (Get-Command komorebic.exe -ErrorAction SilentlyContinue)) { exit 1 }

try {
    $state = komorebic state 2>$null | ConvertFrom-Json
} catch {
    exit 1
}
if (-not $state) { exit 1 }

$monitorIndex = $state.monitors.focused
$monitor      = $state.monitors.elements[$monitorIndex]
$wsIndex      = $monitor.workspaces.focused
$workspace    = $monitor.workspaces.elements[$wsIndex]

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

# How long to wait before the final retile, derived from the animation rather
# than guessed - see Set-Strip below for why the wait exists at all.
$settleMs = 250
try {
    $kjson = Join-Path $configHome "komorebi.json"
    if (Test-Path -LiteralPath $kjson) {
        $cfg = Get-Content -LiteralPath $kjson -Raw | ConvertFrom-Json
        if ($cfg.animation.enabled -and $cfg.animation.duration) {
            $settleMs = [int]$cfg.animation.duration + 90
        }
    }
} catch {
    # An unreadable or half-written komorebi.json is not worth failing over -
    # the wait only has to outlast the animation, and 250ms does.
    $settleMs = 250
}
if ($settleMs -lt 150) { $settleMs = 150 }
if ($settleMs -gt 600) { $settleMs = 600 }

function Set-Strip {
    param([string]$Layout, [int]$WsPad, [int]$ContPad, [switch]$OneColumn)

    # Order matters, and so does the trailing retile. Measured against
    # komorebi 0.1.39:
    #
    #   * `change-layout` updates the workspace record but does not always
    #     re-tile the windows already on it.
    #   * the padding commands DO re-tile - which is why padding has to be set
    #     after the layout, or the pass runs against the layout you just left.
    #   * that pass is animated, and a `retile` issued while the animation is
    #     still in flight is overwritten when the animation lands. With no
    #     wait the strip came up at the old geometry; from 150ms on it was
    #     correct every time.
    komorebic change-layout $Layout 2>$null | Out-Null
    if ($OneColumn) {
        # After change-layout, not before: the column count belongs to the
        # Scrolling layout, so setting it from another layout is dropped and
        # the strip comes up split into columns.
        komorebic scrolling-layout-columns 1 2>$null | Out-Null
    }
    komorebic container-padding $monitorIndex $wsIndex $ContPad 2>$null | Out-Null
    komorebic workspace-padding  $monitorIndex $wsIndex $WsPad   2>$null | Out-Null
    Start-Sleep -Milliseconds $settleMs
    komorebic retile 2>$null | Out-Null
}

if ($current -match "Scrolling") {
    Set-Strip -Layout $RestoreLayout -WsPad $RestorePadding -ContPad $RestoreContainerPadding
    exit 0
}

# Work area, not the raw monitor size: the bar reserves space, and padding is
# applied inside what is left.
$width = 1920
if ($monitor.work_area_size -and $monitor.work_area_size.right) {
    $width = [int]$monitor.work_area_size.right
} elseif ($monitor.size -and $monitor.size.right) {
    $width = [int]$monitor.size.right
}

# inset each side = half of the leftover percentage
$inset = [int][math]::Round($width * (100 - $WindowPercent) / 200.0)
if ($inset -lt 8) { $inset = 8 }

Set-Strip -Layout "scrolling" -WsPad $inset -ContPad 0 -OneColumn
