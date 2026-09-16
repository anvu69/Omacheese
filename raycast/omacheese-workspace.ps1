# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Workspace
# @raycast.mode silent
# @raycast.packageName Omarchy
#
# Optional parameters:
# @raycast.icon 🗂️
# @raycast.argument1 { "type": "dropdown", "placeholder": "workspace", "data": [{"title": "1  term", "value": "0"}, {"title": "2  web", "value": "1"}, {"title": "3  code", "value": "2"}, {"title": "4  ssh", "value": "3"}, {"title": "5  db", "value": "4"}, {"title": "6  docs", "value": "5"}, {"title": "7  chat", "value": "6"}, {"title": "8  monitor", "value": "7"}, {"title": "9  media", "value": "8"}, {"title": "10  scratch", "value": "9"}] }
# @raycast.argument2 { "type": "dropdown", "placeholder": "action", "optional": true, "data": [{"title": "Focus", "value": "focus"}, {"title": "Move window here", "value": "move"}, {"title": "Send window here (stay)", "value": "send"}] }
#
# Documentation:
# @raycast.description Jump to a workspace, or move the focused window to one
# @raycast.author anvu69
# @raycast.authorURL https://github.com/anvu69/windows11-dev-poweruser
#
# The titles here mirror the workspace names in komorebi.json. If you rename a
# workspace there, rename it in the dropdown too - Raycast metadata is static,
# so it cannot read the live list the way the SUPER+SPACE menu does.

param([string]$Index, [string]$Action = "focus")

. (Join-Path $PSScriptRoot "_omacheese-lib.ps1")

if ([string]::IsNullOrWhiteSpace($Action)) { $Action = "focus" }

switch ($Action) {
    "move" { Invoke-Komorebic move-to-workspace $Index; "Moved to workspace $([int]$Index + 1)" }
    "send" { Invoke-Komorebic send-to-workspace $Index; "Sent to workspace $([int]$Index + 1)" }
    default { Invoke-Komorebic focus-workspace $Index; "Workspace $([int]$Index + 1)" }
}
