# PowerShell 7 profile - Windows 11 developer power-user setup.
#
# Installs to:
#   %USERPROFILE%\Documents\PowerShell\Microsoft.PowerShell_profile.ps1
#
# NOT to Documents\WindowsPowerShell\ - that path belongs to Windows
# PowerShell 5.1, which does not support most of what is below.

# --- PSReadLine -------------------------------------------------------------
# PSReadLine needs a real console. Guarding on one keeps non-interactive
# invocations (pwsh -Command from a script, CI, a hotkey handler) from
# printing "The handle is invalid" before they do their job.
$IsInteractiveHost = $Host.Name -eq 'ConsoleHost' -and -not [Console]::IsInputRedirected

if ($IsInteractiveHost -and (Get-Module -ListAvailable -Name PSReadLine)) {
    Import-Module PSReadLine

    Set-PSReadLineOption -EditMode Vi
    Set-PSReadLineOption -HistorySearchCursorMovesToEnd
    Set-PSReadLineOption -BellStyle None
    Set-PSReadLineOption -HistoryNoDuplicates

    # Without a cursor indicator, Vi mode is a guessing game about which mode
    # you are in.
    Set-PSReadLineOption -ViModeIndicator Cursor

    Set-PSReadLineKeyHandler -Key Tab        -Function MenuComplete
    Set-PSReadLineKeyHandler -Chord Ctrl+r   -Function ReverseSearchHistory
    Set-PSReadLineKeyHandler -Key UpArrow    -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key DownArrow  -Function HistorySearchForward
    # Accept the greyed-out suggestion a word at a time, fish-style.
    Set-PSReadLineKeyHandler -Chord Ctrl+f   -Function ForwardWord

    if ($PSVersionTable.PSVersion -ge [version]"7.2") {
        Set-PSReadLineOption -PredictionSource HistoryAndPlugin
        Set-PSReadLineOption -PredictionViewStyle ListView
        Set-PSReadLineOption -Colors @{
            Command   = "#7aa2f7"
            Parameter = "#bb9af7"
            String    = "#9ece6a"
            Number    = "#ff9e64"
            Operator  = "#7dcfff"
            Comment   = "#565f89"
            Error     = "#f7768e"
        }
    } else {
        Set-PSReadLineOption -PredictionSource History
    }
}

foreach ($m in @("Terminal-Icons", "posh-git")) {
    if (Get-Module -ListAvailable -Name $m) { Import-Module $m }
}

# CompletionPredictor feeds PSReadLine's prediction list and does nothing
# without an interactive line editor - and imported from a profile in a session
# whose stdio is redirected, it keeps the process alive after the work is done.
# Measured: `pwsh -Command 'Write-Host HI'` with stdin and stdout redirected
# printed HI and then never exited (killed at 200s); Terminal-Icons, posh-git,
# PSFzf and PSReadLine all exit in under 0.6s. Behind this guard the same
# command takes 0.3s, and an interactive console still gets the predictor.
if ($IsInteractiveHost -and (Get-Module -ListAvailable -Name CompletionPredictor)) {
    Import-Module CompletionPredictor
}

# --- PSFzf ------------------------------------------------------------------
# Ctrl+T files, Alt+C directories. Ctrl+R stays on PSReadLine's own search,
# which handles multi-line history better than the fzf version.
if ($IsInteractiveHost -and (Get-Module -ListAvailable -Name PSFzf) -and (Get-Command fzf -ErrorAction SilentlyContinue)) {
    Import-Module PSFzf
    Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -PSReadlineChordReverseHistory $null
    $env:FZF_DEFAULT_OPTS = '--height 40% --layout=reverse --border=rounded ' +
        '--color=bg+:#292e42,bg:#1a1b26,spinner:#bb9af7,hl:#7aa2f7 ' +
        '--color=fg:#a9b1d6,header:#7aa2f7,info:#e0af68,pointer:#bb9af7 ' +
        '--color=marker:#9ece6a,fg+:#c0caf5,prompt:#7aa2f7,hl+:#7dcfff'
}

# --- Prompt -----------------------------------------------------------------
$OmpTheme = Join-Path $env:USERPROFILE ".config\oh-my-posh\poweruser.omp.json"
if ((Get-Command oh-my-posh -ErrorAction SilentlyContinue) -and (Test-Path -LiteralPath $OmpTheme)) {
    oh-my-posh init pwsh --config $OmpTheme | Invoke-Expression
}

# --- mise -------------------------------------------------------------------
# Without this line mise is only an installer: `mise use -g node@22` writes the
# pin and a new shell still resolves `node` to whatever is on the machine PATH.
# Activating puts mise's shims first, which is what makes the pin - and the
# per-directory .mise.toml - actually take effect. Measured: 21 ms.
#
# Safe next to oh-my-posh: the pwsh activation adds shims to PATH and defines a
# `mise` wrapper, and does not define prompt().
if (Get-Command mise -ErrorAction SilentlyContinue) {
    (& mise activate pwsh) -join "`n" | Invoke-Expression
}

# --- zoxide -----------------------------------------------------------------
if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    Invoke-Expression (& { (zoxide init powershell | Out-String) })
}

# --- Environment ------------------------------------------------------------
$env:KOMOREBI_CONFIG_HOME = Join-Path $env:USERPROFILE ".config\komorebi"
$env:EDITOR = if (Get-Command nvim -ErrorAction SilentlyContinue) { "nvim" } else { "notepad" }

# --- Listing ----------------------------------------------------------------
# eza when present, Get-ChildItem otherwise - the docs promised this, the old
# profile aliased straight to Get-ChildItem and ignored eza entirely.
if (Get-Command eza -ErrorAction SilentlyContinue) {
    function ll { eza -lah --icons --group-directories-first --git @args }
    function la { eza -la  --icons --group-directories-first @args }
    function l  { eza -lh  --icons --group-directories-first @args }
    function lt { eza --tree --level=2 --icons @args }
} else {
    function ll { Get-ChildItem -Force @args }
    function la { Get-ChildItem -Force @args }
    function l  { Get-ChildItem @args }
    function lt { Get-ChildItem -Recurse -Depth 1 @args }
}

if (Get-Command bat -ErrorAction SilentlyContinue) {
    function cat { bat --paging=never @args }
}

# --- Editors / shortcuts ----------------------------------------------------
function v    { nvim @args }
function ep   { nvim $PROFILE.CurrentUserCurrentHost }
function ea   { nvim (Join-Path $env:APPDATA "alacritty\alacritty.toml") }
function es   { nvim (Join-Path $env:USERPROFILE ".ssh\config") }
function ek   { nvim (Join-Path $env:USERPROFILE ".config\whkdrc") }
function alma { wsl.exe -d AlmaLinux-9 }
function reload-profile { . $PROFILE.CurrentUserCurrentHost }

function which {
    param([Parameter(Mandatory)][string]$Command)
    (Get-Command $Command -ErrorAction SilentlyContinue).Source
}

# --- Git --------------------------------------------------------------------
Set-Alias g git
function gs   { git status --short --branch }
function ga   { git add @args }
function gc   { git commit @args }
function gcm  { git commit -m @args }
function gp   { git push @args }
function gl   { git pull @args }
function gd   { git diff @args }
function gco  { git checkout @args }
function gb   { git branch @args }
function glog { git log --oneline --graph --decorate -20 @args }
function lg   { lazygit @args }

# --- SSH --------------------------------------------------------------------
# Pick a host out of ~/.ssh/config with fzf and connect.
function ss {
    $sshConfig = Join-Path $env:USERPROFILE ".ssh\config"

    if (-not (Test-Path -LiteralPath $sshConfig)) {
        Write-Host "No SSH config at $sshConfig" -ForegroundColor Yellow
        return
    }
    if (-not (Get-Command fzf -ErrorAction SilentlyContinue)) {
        Write-Host "fzf not found: winget install --id junegunn.fzf -e" -ForegroundColor Yellow
        return
    }

    $target = Get-Content -LiteralPath $sshConfig |
        Select-String -Pattern '^\s*Host\s+(.+)$' |
        ForEach-Object { $_.Matches[0].Groups[1].Value -split '\s+' } |
        Where-Object { $_ -and $_ -notmatch '[\*\?]' } |
        Sort-Object -Unique |
        fzf --prompt "ssh > "

    if ($target) { ssh $target }
}

# Same, but hands off to tmux inside WSL so a dropped link keeps the session.
function sst {
    $sshConfig = Join-Path $env:USERPROFILE ".ssh\config"
    if (-not (Test-Path -LiteralPath $sshConfig)) { return }
    if (-not (Get-Command fzf -ErrorAction SilentlyContinue)) { return }

    $target = Get-Content -LiteralPath $sshConfig |
        Select-String -Pattern '^\s*Host\s+(.+)$' |
        ForEach-Object { $_.Matches[0].Groups[1].Value -split '\s+' } |
        Where-Object { $_ -and $_ -notmatch '[\*\?]' } |
        Sort-Object -Unique |
        fzf --prompt "ssh+tmux > "

    if ($target) {
        wsl.exe -d AlmaLinux-9 -- tmux new-session -A -s $target "ssh $target"
    }
}

# --- Desktop ----------------------------------------------------------------
function desktop { & (Join-Path $env:USERPROFILE ".config\omacheese\bin\start-desktop.ps1") @args }
function keys    { & (Join-Path $env:USERPROFILE ".config\omacheese\bin\omacheese-keybindings.ps1") }
function omenu   { & (Join-Path $env:USERPROFILE ".config\omacheese\bin\omacheese-menu.ps1") @args }

# --- Agent layouts (herdr) --------------------------------------------------
# hdl / hds / hdlm / hsl, the Windows counterpart to the tmux tdl/tds/tdlm/tsl
# functions in the WSL zshrc. Separate file so a machine without herdr simply
# does not get them, rather than getting functions that fail on use.
$agentLayouts = Join-Path $env:USERPROFILE ".config\omacheese\agent-layouts.ps1"
if (Test-Path -LiteralPath $agentLayouts) { . $agentLayouts }

function h { & herdr @args }
