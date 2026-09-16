# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Agent Panes
# @raycast.mode silent
# @raycast.packageName Omacheese
#
# Optional parameters:
# @raycast.icon 🦾
# @raycast.argument1 { "type": "dropdown", "placeholder": "what", "data": [{"title": "Open herdr", "value": "open"}, {"title": "Agent status", "value": "status"}, {"title": "Install herdr", "value": "install"}] }
#
# Documentation:
# @raycast.description Open herdr, or show which agents are working, blocked or idle
# @raycast.author anvu69
# @raycast.authorURL https://github.com/anvu69/Omacheese
#
# herdr is optional in this repo, so every branch has to cope with it being
# absent - the helpers say so rather than opening a terminal that shuts again.

param([string]$Choice)

. (Join-Path $PSScriptRoot "_omacheese-lib.ps1")

switch ($Choice) {
    "status"  { Start-HelperInTerminal "omacheese-herdr-status.ps1"; "Agent status" }
    "install" { Start-HelperInTerminal "install-herdr.ps1";          "Installing herdr" }
    default   { Start-InTerminal @((Join-Path $OmacheeseBin "omacheese-herdr.cmd")); "herdr" }
}
