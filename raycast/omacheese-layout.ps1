# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Layout
# @raycast.mode silent
# @raycast.packageName Omarchy
#
# Optional parameters:
# @raycast.icon 🪟
# @raycast.argument1 { "type": "dropdown", "placeholder": "layout", "data": [{"title": "BSP", "value": "bsp"}, {"title": "Columns", "value": "columns"}, {"title": "Rows", "value": "rows"}, {"title": "Grid", "value": "grid"}, {"title": "Ultrawide vertical stack", "value": "ultrawide-vertical-stack"}, {"title": "Scrolling", "value": "scrolling"}, {"title": "Next layout", "value": "next"}, {"title": "Previous layout", "value": "previous"}, {"title": "Flip horizontal", "value": "flip-h"}, {"title": "Flip vertical", "value": "flip-v"}, {"title": "Promote window", "value": "promote"}, {"title": "Retile", "value": "retile"}, {"title": "Reload configuration", "value": "reload"}] }
#
# Documentation:
# @raycast.description Change the komorebi layout on the focused workspace
# @raycast.author anvu69
# @raycast.authorURL https://github.com/anvu69/windows11-dev-poweruser

param([string]$Choice)

. (Join-Path $PSScriptRoot "_omacheese-lib.ps1")

switch ($Choice) {
    "next"     { Invoke-Komorebic cycle-layout next;     "Next layout" }
    "previous" { Invoke-Komorebic cycle-layout previous; "Previous layout" }
    "flip-h"   { Invoke-Komorebic flip-layout horizontal; "Flipped horizontally" }
    "flip-v"   { Invoke-Komorebic flip-layout vertical;   "Flipped vertically" }
    "promote"  { Invoke-Komorebic promote;               "Promoted" }
    "retile"   { Invoke-Komorebic retile;                "Retiled" }
    "reload"   { Invoke-Komorebic reload-configuration;  "Reloaded komorebi.json" }
    "scrolling" {
        # Just set the layout. omacheese-scroll-daemon watches for Scrolling on
        # any workspace and applies the offsets itself, so this route gets the
        # peek without going through the toggle - which would turn the strip
        # OFF if it happened to be on already.
        Invoke-Komorebic change-layout scrolling
        Invoke-Komorebic scrolling-layout-columns 1
        "Scrolling"
    }
    default {
        Invoke-Komorebic change-layout $Choice
        "Layout: $Choice"
    }
}
