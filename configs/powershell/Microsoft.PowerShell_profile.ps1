# PowerShell 7 profile for Windows 11 power-user workflow
# Target path: $PROFILE, usually Documents\PowerShell\Microsoft.PowerShell_profile.ps1

$env:EDITOR = "nvim"
$env:VISUAL = "nvim"

# PSReadLine: better editing, history search, Vi mode.
if (Get-Module -ListAvailable -Name PSReadLine) {
  Import-Module PSReadLine
  Set-PSReadLineOption -EditMode Vi
  Set-PSReadLineOption -PredictionSource HistoryAndPlugin
  Set-PSReadLineOption -PredictionViewStyle ListView
  Set-PSReadLineOption -HistorySearchCursorMovesToEnd
  Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
  Set-PSReadLineKeyHandler -Chord Ctrl+r -Function ReverseSearchHistory
}

if (Get-Module -ListAvailable -Name Terminal-Icons) {
  Import-Module Terminal-Icons
}

# zoxide: smarter cd
if (Get-Command zoxide -ErrorAction SilentlyContinue) {
  Invoke-Expression (& { (zoxide init powershell | Out-String) })
}

# Oh My Posh prompt
$ompTheme = "$HOME\.config\oh-my-posh\poweruser.omp.json"
if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
  if (Test-Path $ompTheme) {
    oh-my-posh init pwsh --config $ompTheme | Invoke-Expression
  } else {
    oh-my-posh init pwsh | Invoke-Expression
  }
}

# Navigation aliases
Set-Alias -Name v -Value nvim -ErrorAction SilentlyContinue
Set-Alias -Name g -Value git -ErrorAction SilentlyContinue
Set-Alias -Name k -Value kubectl -ErrorAction SilentlyContinue
Set-Alias -Name tf -Value terraform -ErrorAction SilentlyContinue

function .. { Set-Location .. }
function ... { Set-Location ../.. }
function .... { Set-Location ../../.. }
function home { Set-Location $HOME }
function dev { Set-Location "$HOME\Dev" }

# Listing helpers. Prefer eza when available, fallback to Get-ChildItem.
function l {
  if (Get-Command eza -ErrorAction SilentlyContinue) { eza --icons --group-directories-first @args }
  else { Get-ChildItem @args }
}
function ll {
  if (Get-Command eza -ErrorAction SilentlyContinue) { eza -lah --icons --group-directories-first @args }
  else { Get-ChildItem -Force @args }
}
function la { ll @args }

# Git aliases/functions
function gs { git status --short --branch }
function ga { git add @args }
function gaa { git add --all }
function gcmsg { git commit -m "$args" }
function gco { git checkout @args }
function gcb { git checkout -b @args }
function gp { git push @args }
function gl { git pull @args }
function gd { git diff @args }
function gds { git diff --staged @args }
function glog { git log --oneline --graph --decorate --all -n 30 }
function lg { lazygit @args }

# Process / port helpers
function ports { Get-NetTCPConnection -State Listen | Sort-Object LocalPort | Format-Table LocalAddress,LocalPort,OwningProcess -AutoSize }
function pgrepw($name) { Get-Process | Where-Object { $_.ProcessName -like "*$name*" } }
function killp($name) { Get-Process | Where-Object { $_.ProcessName -like "*$name*" } | Stop-Process -Force }

# SSH host picker using fzf and Windows OpenSSH config.
function ss {
  $config = "$HOME\.ssh\config"
  if (!(Test-Path $config)) { Write-Warning "No SSH config found at $config"; return }
  $host = Select-String -Path $config -Pattern '^Host\s+' |
    ForEach-Object { ($_ -replace '^Host\s+', '').Trim() } |
    Where-Object { $_ -notmatch '[*?]' } |
    fzf --prompt='SSH > '
  if ($host) { ssh $host }
}

function sst {
  $config = "$HOME\.ssh\config"
  if (!(Test-Path $config)) { Write-Warning "No SSH config found at $config"; return }
  $host = Select-String -Path $config -Pattern '^Host\s+' |
    ForEach-Object { ($_ -replace '^Host\s+', '').Trim() } |
    Where-Object { $_ -notmatch '[*?]' } |
    fzf --prompt='SSH tmux > '
  if ($host) { wsl.exe tmux new-session -A -s $host "ssh $host" }
}

# Quick edit config files
function ep { nvim $PROFILE }
function ea { nvim "$env:APPDATA\alacritty\alacritty.toml" }
function es { nvim "$HOME\.ssh\config" }

# WSL shortcuts
function alma { wsl.exe -d AlmaLinux-9 }
function wu { wsl.exe -d AlmaLinux-9 -- sudo dnf update -y }
