# PowerShell 7 profile for Windows 11 developer power-user setup.
# This file is intended for:
#   C:\Users\<USER>\Documents\PowerShell\Microsoft.PowerShell_profile.ps1
#
# Do not install this into:
#   C:\Users\<USER>\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1
#
# That path belongs to Windows PowerShell 5.1.

# PSReadLine
if (Get-Module -ListAvailable -Name PSReadLine) {
  Import-Module PSReadLine

  Set-PSReadLineOption -EditMode Vi
  Set-PSReadLineOption -HistorySearchCursorMovesToEnd
  Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
  Set-PSReadLineKeyHandler -Chord Ctrl+r -Function ReverseSearchHistory

  if ($PSVersionTable.PSVersion -ge [version]"7.2") {
    Set-PSReadLineOption -PredictionSource HistoryAndPlugin
    Set-PSReadLineOption -PredictionViewStyle ListView
  } else {
    Set-PSReadLineOption -PredictionSource History
  }
}

# Terminal Icons
if (Get-Module -ListAvailable -Name Terminal-Icons) {
  Import-Module Terminal-Icons
}

# Oh My Posh
$OmpTheme = "$env:USERPROFILE\.config\oh-my-posh\poweruser.omp.json"

if ((Get-Command oh-my-posh -ErrorAction SilentlyContinue) -and (Test-Path $OmpTheme)) {
  oh-my-posh init pwsh --config $OmpTheme | Invoke-Expression
}

# zoxide
if (Get-Command zoxide -ErrorAction SilentlyContinue) {
  Invoke-Expression (& { (zoxide init powershell | Out-String) })
}

# Common aliases
Set-Alias ll Get-ChildItem
Set-Alias grep Select-String
Set-Alias g git

function la {
  Get-ChildItem -Force
}

function reload-profile {
  . $PROFILE
}

function which {
  param([string]$Command)

  Get-Command $Command | Select-Object -ExpandProperty Source
}

# Git shortcuts
function gs {
  git status
}

function ga {
  git add @args
}

function gcmsg {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Message
  )

  git commit -m $Message
}

function gp {
  git push
}

function gl {
  git pull
}

function gco {
  git checkout @args
}

function gb {
  git branch @args
}

# SSH host picker using fzf
function sshp {
  $sshConfig = "$env:USERPROFILE\.ssh\config"

  if (!(Test-Path $sshConfig)) {
    Write-Host "Missing SSH config: $sshConfig" -ForegroundColor Yellow
    return
  }

  if (!(Get-Command fzf -ErrorAction SilentlyContinue)) {
    Write-Host "fzf not found" -ForegroundColor Yellow
    return
  }

  $hostName = Get-Content $sshConfig |
    Select-String -Pattern "^Host\s+" |
    ForEach-Object { ($_ -replace "^Host\s+", "").Trim() } |
    Where-Object { $_ -notmatch "[\*\?]" } |
    fzf --prompt "SSH > "

  if ($hostName) {
    ssh $hostName
  }
}

# Useful paths
$env:KOMOREBI_CONFIG_HOME = "$env:USERPROFILE\.config\komorebi"