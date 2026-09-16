# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Terminal
# @raycast.mode silent
# @raycast.packageName Omarchy
#
# Optional parameters:
# @raycast.icon 🖥️
# @raycast.argument1 { "type": "dropdown", "placeholder": "what", "data": [{"title": "PowerShell", "value": "pwsh"}, {"title": "WSL + tmux", "value": "wsl"}, {"title": "Neovim (WSL)", "value": "nvim"}, {"title": "btop", "value": "btop"}, {"title": "lazygit", "value": "lazygit"}] }
#
# Documentation:
# @raycast.description Open Alacritty running a shell or a TUI
# @raycast.author anvu69
# @raycast.authorURL https://github.com/anvu69/windows11-dev-poweruser

param([string]$Choice)

. (Join-Path $PSScriptRoot "_omarchy-lib.ps1")

switch ($Choice) {
    "pwsh" {
        # No -e: let Alacritty start its configured shell.
        $term = Get-Terminal
        if (-not $term) { throw "Alacritty is not installed." }
        Start-Process -FilePath $term
        "Terminal"
    }
    "wsl" {
        Start-InTerminal @("wsl.exe", "-d", "AlmaLinux-9", "--", "tmux", "new-session", "-A", "-s", "main")
        "WSL + tmux"
    }
    "nvim"    { Start-InTerminal @("wsl.exe", "-d", "AlmaLinux-9", "--", "nvim"); "Neovim" }
    "btop"    { Start-InTerminal @("btop");    "btop" }
    "lazygit" { Start-InTerminal @("lazygit"); "lazygit" }
}
