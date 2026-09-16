# Omarchy menu, ported to Windows.
#
# Omarchy funnels almost everything through one nested menu on SUPER+SPACE so
# you never have to remember where a setting lives. This is the same idea
# driven by fzf: pick a section, pick an action, it runs.
#
#   SUPER+SPACE   -> root menu
#   SUPER+ESC     -> straight to the system section
#
# Add your own entries by editing $Menus below.

[CmdletBinding()]
param(
    [string]$Menu = "root"
)

$ErrorActionPreference = "Stop"

$cfg  = Join-Path $env:USERPROFILE ".config"
$bin  = Join-Path $cfg "omarchy\bin"

# Resolve binaries instead of trusting PATH. This menu is launched from the
# bar, and a GUI process inherits the PATH of whatever started it - so bare
# "alacritty" or "nvim" silently did nothing, which is why picking an action
# just closed the window.
function Resolve-Bin {
    param([string]$Name, [string[]]$Fallbacks = @())
    $c = Get-Command $Name -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    foreach ($f in $Fallbacks) {
        $expanded = [Environment]::ExpandEnvironmentVariables($f)
        if (Test-Path -LiteralPath $expanded) { return $expanded }
    }
    return $null
}

$term = Resolve-Bin "alacritty" @(
    "%ProgramFiles%\Alacritty\alacritty.exe",
    "%LOCALAPPDATA%\Programs\Alacritty\alacritty.exe"
)

function Start-InTerminal {
    param([Parameter(Mandatory)][string[]]$Command)
    if ($term) {
        Start-Process -FilePath $term -ArgumentList (@("-e") + $Command)
    } else {
        # No Alacritty: fall back to a console window rather than doing nothing.
        Start-Process -FilePath $Command[0] -ArgumentList ($Command[1..($Command.Count - 1)])
    }
}

function Show-Problem {
    param([string]$Message)
    Write-Host ""
    Write-Host "  $Message" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Press Enter to close" -ForegroundColor DarkGray
    [void](Read-Host)
}

# Each entry is: Label = command to run (string = shell, scriptblock = inline).
$Menus = [ordered]@{

    root = [ordered]@{
        "Apps            launch an application"      = { Show-Menu "apps" }
        "Agents          coding agents"              = { Show-Menu "agents" }
        "Windows         layout and tiling"          = { Show-Menu "windows" }
        "Workspaces      jump to a workspace"        = { Show-Menu "workspaces" }
        "Capture         screenshot and recording"   = { Show-Menu "capture" }
        "Toggle          flip a desktop setting"     = { Show-Menu "toggle" }
        "Setup           edit a config file"         = { Show-Menu "setup" }
        "Learn           keybindings and docs"       = { Show-Menu "learn" }
        "System          lock, sleep, restart"       = { Show-Menu "system" }
    }

    apps = [ordered]@{
        # No -e: let Alacritty start its configured shell (pwsh).
        "Terminal"                = {
            if ($term) { Start-Process -FilePath $term }
            else { Show-Problem "Alacritty is not installed." }
        }
        "Terminal (WSL + tmux)"   = { Start-InTerminal @("wsl.exe","-d","AlmaLinux-9","--","tmux","new-session","-A","-s","main") }
        "Neovim (WSL)"            = { Start-InTerminal @("wsl.exe","-d","AlmaLinux-9","--","nvim") }
        "Browser"                 = { $p = Resolve-Bin "brave"; if ($p) { Start-Process $p } else { Show-Problem "brave is not installed." } }
        "Browser (private)"       = { $p = Resolve-Bin "brave"; if ($p) { Start-Process $p -ArgumentList "--incognito" } else { Show-Problem "brave is not installed." } }
        "File manager"            = { $p = Resolve-Bin "explorer"; if ($p) { Start-Process $p } else { Show-Problem "explorer is not installed." } }
        "Everything (search)"     = { $p = Resolve-Bin "everything"; if ($p) { Start-Process $p } else { Show-Problem "everything is not installed." } }
        "electerm (SSH)"          = { $p = Resolve-Bin "electerm"; if ($p) { Start-Process $p } else { Show-Problem "electerm is not installed." } }
        "DBeaver"                 = { $p = Resolve-Bin "dbeaver"; if ($p) { Start-Process $p } else { Show-Problem "dbeaver is not installed." } }
        "Bitwarden"               = { $p = Resolve-Bin "bitwarden"; if ($p) { Start-Process $p } else { Show-Problem "bitwarden is not installed." } }
        "btop"                    = { Start-InTerminal @("btop") }
        "lazygit"                 = { Start-InTerminal @("lazygit") }
    }

    agents = [ordered]@{
        "Launch default agent"       = { & (Join-Path $bin "omarchy-agent.ps1") }
        "Launch default agent (WSL)" = { & (Join-Path $bin "omarchy-agent.ps1") -Wsl }
        "Launch with a prompt"       = {
            $p = Read-Host "Prompt"
            if ($p) { & (Join-Path $bin "omarchy-agent.ps1") -Prompt $p }
        }
        "Launch unattended (-Yolo)"  = {
            Write-Host "This skips every permission prompt. The agent can run any" -ForegroundColor Yellow
            Write-Host "command, including against your SSH agent and work trees." -ForegroundColor Yellow
            if ((Read-Host "Type yes to continue") -eq "yes") {
                & (Join-Path $bin "omarchy-agent.ps1") -Yolo
            }
        }
        "Pick / change default"      = { & (Join-Path $bin "omarchy-agent.ps1") -Pick }
        "List agents"                = {
            & (Join-Path $bin "omarchy-default-agent.ps1") -List
            Read-Host "`nEnter to close"
        }
    }

    windows = [ordered]@{
        "Scrolling mode (toggle)" = { & (Join-Path $bin "omarchy-scrolling.ps1") }
        "Scrolling: 2 columns"    = {
            komorebic change-layout scrolling
            komorebic scrolling-layout-columns 2
        }
        "Next layout"             = { komorebic cycle-layout next }
        "Previous layout"         = { komorebic cycle-layout previous }
        "BSP"                     = { komorebic change-layout bsp }
        "Columns"                 = { komorebic change-layout columns }
        "Rows"                    = { komorebic change-layout rows }
        "Grid"                    = { komorebic change-layout grid }
        "Ultrawide vertical stack"= { komorebic change-layout ultrawide-vertical-stack }
        "Scrolling"               = { komorebic change-layout scrolling }
        "Flip horizontal"         = { komorebic flip-layout horizontal }
        "Flip vertical"           = { komorebic flip-layout vertical }
        "Promote window"          = { komorebic promote }
        "Retile"                  = { komorebic retile }
        "Reload configuration"    = { komorebic reload-configuration }
    }

    capture = [ordered]@{
        "Region to clipboard"     = { Start-Process "ms-screenclip:" }
        "Snipping Tool"           = { Start-Process "snippingtool:" }
        "Screen recording (Xbox)" = { Start-Process "ms-gamebar:" }
        "Open Screenshots folder" = { Start-Process "explorer" -ArgumentList (Join-Path $env:USERPROFILE "Pictures\Screenshots") }
    }

    toggle = [ordered]@{
        "Status bar"              = { & (Join-Path $bin "omarchy-toggle-bar.ps1") }
        "Pause tiling"            = { komorebic toggle-pause }
        "Tiling on this workspace"= { komorebic toggle-tiling }
        "Float this window"       = { komorebic toggle-float }
        "Float override"          = { komorebic toggle-float-override }
        "Monocle"                 = { komorebic toggle-monocle }
        "Transparency"            = { komorebic toggle-transparency }
        "Title bars"              = { komorebic toggle-title-bars }
        "Mouse follows focus"     = { komorebic toggle-mouse-follows-focus }
        "Workspace layer"         = { komorebic toggle-workspace-layer }
    }

    setup = [ordered]@{
        "whkd keybindings"        = { Edit-Config (Join-Path $cfg "whkdrc") }
        "komorebi"                = { Edit-Config (Join-Path $cfg "komorebi\komorebi.json") }
        "yasb config"             = { Edit-Config (Join-Path $cfg "yasb\config.yaml") }
        "yasb styles"             = { Edit-Config (Join-Path $cfg "yasb\styles.css") }
        "Alacritty"               = { Edit-Config (Join-Path $env:APPDATA "alacritty\alacritty.toml") }
        "PowerShell profile"      = { Edit-Config $PROFILE.CurrentUserCurrentHost }
        "SSH config"              = { Edit-Config (Join-Path $env:USERPROFILE ".ssh\config") }
        "Git config"              = { Edit-Config (Join-Path $env:USERPROFILE ".gitconfig") }
        "WSL config"              = { Edit-Config (Join-Path $env:USERPROFILE ".wslconfig") }
        "Restart desktop"         = { & (Join-Path $bin "omarchy-restart-desktop.ps1") }
    }

    learn = [ordered]@{
        "Keybindings"             = { & (Join-Path $bin "omarchy-keybindings.ps1") }
        "komorebi docs"           = { Start-Process "https://lgug2z.github.io/komorebi/" }
        "yasb docs"               = { Start-Process "https://github.com/amnweb/yasb/wiki" }
        "Omarchy (the original)"  = { Start-Process "https://omarchy.org" }
    }

    system = [ordered]@{
        "Lock"                    = { rundll32.exe user32.dll,LockWorkStation }
        "Sleep"                   = { rundll32.exe powrprof.dll,SetSuspendState 0,1,0 }
        "Sign out"                = { shutdown.exe /l }
        "Restart"                 = { shutdown.exe /r /t 0 }
        "Shut down"               = { shutdown.exe /s /t 0 }
        "Restart desktop stack"   = { & (Join-Path $bin "omarchy-restart-desktop.ps1") }
        "Stop komorebi"           = { komorebic stop --whkd }
        "WSL shutdown"            = { wsl.exe --shutdown }
    }
}

function Edit-Config {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        Show-Problem "Not found: $Path"
        return
    }

    $editor = Resolve-Bin "nvim"
    if (-not $editor) { $editor = Resolve-Bin "code" }
    if (-not $editor) { $editor = Resolve-Bin "notepad" @("%SystemRoot%\System32\notepad.exe") }

    if (-not $editor) {
        Show-Problem "No editor found (looked for nvim, code, notepad)."
        return
    }

    # notepad is a GUI app - putting it inside a terminal gives you an empty
    # terminal and a detached notepad, so only terminal editors go via -e.
    if ($editor -match 'nvim|vim') {
        Start-InTerminal @($editor, $Path)
    } else {
        Start-Process -FilePath $editor -ArgumentList $Path
    }
}

function Show-Menu {
    param([string]$Name)

    $entries = $Menus[$Name]
    if (-not $entries) {
        Write-Host "No such menu: $Name" -ForegroundColor Red
        return
    }

    $fzf = Get-Command fzf -ErrorAction SilentlyContinue
    if (-not $fzf) {
        Write-Host "fzf is required for the menu. Install it with:" -ForegroundColor Yellow
        Write-Host "  winget install --id junegunn.fzf -e" -ForegroundColor Cyan
        Read-Host "`nEnter to close"
        return
    }

    $prompt = if ($Name -eq "root") { "omarchy > " } else { "$Name > " }

    $choice = $entries.Keys |
        & $fzf.Source `
            --prompt $prompt `
            --header "  ENTER to run      ESC to cancel" `
            --header-first `
            --layout reverse `
            --info inline `
            --no-mouse `
            --border rounded

    if (-not $choice) { return }

    # Entries are always scriptblocks. Keeping it that way (rather than
    # accepting command strings) avoids an Invoke-Expression on menu labels.
    $action = $entries[$choice]
    if ($action -is [scriptblock]) { & $action }
    else { Write-Host "Menu entry '$choice' is not runnable." -ForegroundColor Red }
}

Show-Menu $Menu
