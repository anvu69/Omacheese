# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Desktop
# @raycast.mode silent
# @raycast.packageName Omarchy
#
# Optional parameters:
# @raycast.icon ⚙️
# @raycast.needsConfirmation true
# @raycast.argument1 { "type": "dropdown", "placeholder": "action", "data": [{"title": "Restart desktop stack", "value": "restart"}, {"title": "Keybindings cheatsheet", "value": "keys"}, {"title": "Omacheese menu", "value": "menu"}, {"title": "Stop komorebi", "value": "stop"}, {"title": "WSL shutdown", "value": "wsl"}] }
#
# Documentation:
# @raycast.description Restart, inspect or stop the komorebi / whkd / yasb stack
# @raycast.author anvu69
# @raycast.authorURL https://github.com/anvu69/windows11-dev-poweruser
#
# needsConfirmation is on because two of these entries tear the desktop down.
# Lock, sleep, restart and shut down are deliberately absent - Raycast ships
# those as built-in system commands, and a second copy would just be noise.

param([string]$Choice)

. (Join-Path $PSScriptRoot "_omacheese-lib.ps1")

switch ($Choice) {
    "restart" { Start-Helper "omacheese-restart-desktop.ps1"; "Restarting the desktop" }
    "keys"    { Start-HelperInTerminal "omacheese-keybindings.ps1"; "Keybindings" }
    "menu"    { Start-Helper "omacheese-menu.ps1"; "Menu" }
    "stop"    { Invoke-Komorebic stop --whkd; "komorebi stopped" }
    "wsl"     {
        $wsl = Resolve-Bin "wsl" @("%SystemRoot%\System32\wsl.exe")
        if (-not $wsl) { throw "wsl.exe not found." }
        & $wsl --shutdown | Out-Null
        "WSL shut down"
    }
}
