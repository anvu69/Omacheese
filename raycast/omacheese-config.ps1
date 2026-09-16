# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Edit Config
# @raycast.mode silent
# @raycast.packageName Omacheese
#
# Optional parameters:
# @raycast.icon 📝
# @raycast.argument1 { "type": "dropdown", "placeholder": "file", "data": [{"title": "whkd keybindings", "value": "whkdrc"}, {"title": "komorebi", "value": "komorebi"}, {"title": "yasb config", "value": "yasb"}, {"title": "yasb styles", "value": "yasb-css"}, {"title": "Alacritty", "value": "alacritty"}, {"title": "PowerShell profile", "value": "profile"}, {"title": "SSH config", "value": "ssh"}, {"title": "Git config", "value": "git"}, {"title": "WSL config", "value": "wsl"}, {"title": "Scrolling settings", "value": "scrolling"}] }
#
# Documentation:
# @raycast.description Open one of the desktop config files in your editor
# @raycast.author anvu69
# @raycast.authorURL https://github.com/anvu69/windows11-dev-poweruser

param([string]$Choice)

. (Join-Path $PSScriptRoot "_omacheese-lib.ps1")

$paths = @{
    "whkdrc"    = Join-Path $OmarchyConfig "whkdrc"
    "komorebi"  = Join-Path $OmarchyConfig "komorebi\komorebi.json"
    "yasb"      = Join-Path $OmarchyConfig "yasb\config.yaml"
    "yasb-css"  = Join-Path $OmarchyConfig "yasb\styles.css"
    "alacritty" = Join-Path $env:APPDATA "alacritty\alacritty.toml"
    "profile"   = $PROFILE.CurrentUserCurrentHost
    "ssh"       = Join-Path $env:USERPROFILE ".ssh\config"
    "git"       = Join-Path $env:USERPROFILE ".gitconfig"
    "wsl"       = Join-Path $env:USERPROFILE ".wslconfig"
    "scrolling" = Join-Path $OmarchyConfig "omacheese\scrolling.json"
}

$path = $paths[$Choice]
if (-not $path -or -not (Test-Path -LiteralPath $path)) { throw "Not found: $path" }

$editor = Resolve-Bin "nvim"
if (-not $editor) { $editor = Resolve-Bin "code" }
if (-not $editor) { $editor = Resolve-Bin "notepad" @("%SystemRoot%\System32\notepad.exe") }
if (-not $editor) { throw "No editor found (looked for nvim, code, notepad)." }

# notepad and code are GUI apps - putting them inside a terminal gives you an
# empty terminal and a detached editor, so only terminal editors go via -e.
if ($editor -match 'nvim|vim') { Start-InTerminal @($editor, $path) }
else { Start-Process -FilePath $editor -ArgumentList $path }

"Editing $(Split-Path $path -Leaf)"
