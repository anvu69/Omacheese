# Omarchy scratchpad, approximated on komorebi.
#
# Hyprland has a real special workspace; komorebi does not. Workspace 10
# (index 9) is reserved as the scratchpad instead, and this script gives it
# the behaviour that matters: press once to jump there, press again to land
# back exactly where you were.
#
# Bound to SUPER+S and SUPER+` .

$ErrorActionPreference = "Stop"

$ScratchIndex = 9

if (-not (Get-Command komorebic.exe -ErrorAction SilentlyContinue)) { exit 1 }

try {
    $state = komorebic state 2>$null | ConvertFrom-Json
} catch {
    # komorebi is not running; nothing sensible to toggle.
    exit 1
}

if (-not $state) { exit 1 }

$monitor = $state.monitors.elements[$state.monitors.focused]
$current = $monitor.workspaces.focused

if ($current -eq $ScratchIndex) {
    # Already on the scratchpad -> go back to whatever we came from.
    komorebic focus-last-workspace
} else {
    komorebic focus-workspace $ScratchIndex
}
