# Omarchy SUPER+G (toggle window grouping), on komorebi stacks.
#
# Hyprland groups windows in place; komorebi calls the same idea a stack and
# splits it across `stack <direction>` and `unstack`. This script picks the
# right half so one key behaves like a toggle:
#
#   focused window is in a stack   -> unstack it
#   focused window is alone        -> stack it with a neighbour
#
# The neighbour search tries right, then down, then left, then up, which is
# the order that feels natural in a BSP tree.

$ErrorActionPreference = "SilentlyContinue"

if (-not (Get-Command komorebic.exe -ErrorAction SilentlyContinue)) { exit 1 }

try {
    $state = komorebic state 2>$null | ConvertFrom-Json
} catch {
    exit 1
}
if (-not $state) { exit 1 }

$monitor   = $state.monitors.elements[$state.monitors.focused]
$workspace = $monitor.workspaces.elements[$monitor.workspaces.focused]

# A container holding more than one window IS the stack.
$containers = $workspace.containers.elements
$focusedIdx = $workspace.containers.focused

if ($null -ne $containers -and $containers.Count -gt 0) {
    $focused = $containers[$focusedIdx]
    if ($focused.windows.elements.Count -gt 1) {
        komorebic unstack
        exit 0
    }
}

foreach ($direction in @("right", "down", "left", "up")) {
    komorebic stack $direction 2>$null
    if ($LASTEXITCODE -eq 0) { exit 0 }
}

exit 0
