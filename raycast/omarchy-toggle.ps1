# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Toggle
# @raycast.mode silent
# @raycast.packageName Omarchy
#
# Optional parameters:
# @raycast.icon 🔀
# @raycast.argument1 { "type": "dropdown", "placeholder": "setting", "data": [{"title": "Scrolling mode", "value": "scrolling"}, {"title": "Status bar", "value": "bar"}, {"title": "Pause tiling", "value": "pause"}, {"title": "Tiling on this workspace", "value": "tiling"}, {"title": "Float this window", "value": "float"}, {"title": "Float override", "value": "float-override"}, {"title": "Monocle", "value": "monocle"}, {"title": "Transparency", "value": "transparency"}, {"title": "Title bars", "value": "title-bars"}, {"title": "Mouse follows focus", "value": "mouse-follows-focus"}, {"title": "Workspace layer", "value": "workspace-layer"}] }
#
# Documentation:
# @raycast.description Flip a komorebi or desktop setting
# @raycast.author anvu69
# @raycast.authorURL https://github.com/anvu69/windows11-dev-poweruser

param([string]$Choice)

. (Join-Path $PSScriptRoot "_omarchy-lib.ps1")

switch ($Choice) {
    "scrolling" { Start-Helper "omarchy-scrolling.ps1";  "Scrolling mode toggled" }
    "bar"       { Start-Helper "omarchy-toggle-bar.ps1"; "Status bar toggled" }
    default {
        Invoke-Komorebic "toggle-$Choice"
        "Toggled $($Choice -replace '-', ' ')"
    }
}
