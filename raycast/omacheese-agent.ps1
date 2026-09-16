# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Agent
# @raycast.mode silent
# @raycast.packageName Omarchy
#
# Optional parameters:
# @raycast.icon 🤖
# @raycast.argument1 { "type": "dropdown", "placeholder": "where", "data": [{"title": "Default agent", "value": "default"}, {"title": "Default agent (WSL)", "value": "wsl"}, {"title": "Pick / change default", "value": "pick"}, {"title": "List agents", "value": "list"}] }
# @raycast.argument2 { "type": "text", "placeholder": "prompt (optional)", "optional": true }
#
# Documentation:
# @raycast.description Launch a coding agent, optionally with a prompt
# @raycast.author anvu69
# @raycast.authorURL https://github.com/anvu69/windows11-dev-poweruser
#
# -Yolo is deliberately not offered here. It skips every permission prompt, and
# a dropdown entry one keystroke away from "Default agent" is the wrong place
# for something that can run any command against your SSH agent and work trees.
# It stays in the SUPER+SPACE menu, behind a confirmation page.

param([string]$Choice, [string]$Prompt = "")

. (Join-Path $PSScriptRoot "_omacheese-lib.ps1")

switch ($Choice) {
    "list" { Start-HelperInTerminal "omacheese-default-agent.ps1" @("-List"); "Listing agents" }
    "pick" { Start-HelperInTerminal "omacheese-agent.ps1" @("-Pick");         "Pick an agent" }
    "wsl"  {
        if ($Prompt) { Start-HelperInTerminal "omacheese-agent.ps1" @("-Wsl", "-Prompt", $Prompt) }
        else         { Start-HelperInTerminal "omacheese-agent.ps1" @("-Wsl") }
        "Agent (WSL)"
    }
    default {
        if ($Prompt) { Start-HelperInTerminal "omacheese-agent.ps1" @("-Prompt", $Prompt) }
        else         { Start-HelperInTerminal "omacheese-agent.ps1" }
        "Agent"
    }
}
