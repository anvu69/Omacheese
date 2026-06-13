$ErrorActionPreference = "Stop"

$Repo = Split-Path -Parent $PSScriptRoot

function Ensure-Dir {
  param([string]$Path)

  if (!(Test-Path $Path)) {
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
  }
}

function Copy-Config {
  param(
    [string]$Source,
    [string]$Destination
  )

  if (!(Test-Path $Source)) {
    Write-Host "Missing source: $Source" -ForegroundColor Yellow
    return
  }

  Ensure-Dir (Split-Path -Parent $Destination)
  Copy-Item $Source $Destination -Force
  Write-Host "Copied: $Destination" -ForegroundColor Green
}

Ensure-Dir "$env:APPDATA\alacritty"
Ensure-Dir "$env:USERPROFILE\.ssh"
Ensure-Dir "$env:USERPROFILE\.config"
Ensure-Dir "$env:USERPROFILE\.config\komorebi"
Ensure-Dir "$env:USERPROFILE\.config\yasb"
Ensure-Dir "$env:USERPROFILE\.config\oh-my-posh"
Ensure-Dir "$env:USERPROFILE\.config\windows11-dev-poweruser"

# Environment variables
$KomorebiConfigHome = "$env:USERPROFILE\.config\komorebi"

[Environment]::SetEnvironmentVariable(
  "KOMOREBI_CONFIG_HOME",
  $KomorebiConfigHome,
  [EnvironmentVariableTarget]::User
)

$env:KOMOREBI_CONFIG_HOME = $KomorebiConfigHome

# Alacritty
Copy-Config `
  "$Repo\configs\alacritty\alacritty.toml" `
  "$env:APPDATA\alacritty\alacritty.toml"

# komorebi
Copy-Config `
  "$Repo\configs\komorebi\komorebi.json" `
  "$env:USERPROFILE\.config\komorebi\komorebi.json"

# whkd default path
Copy-Config `
  "$Repo\configs\whkd\whkdrc" `
  "$env:USERPROFILE\.config\whkdrc"

# yasb
Copy-Config `
  "$Repo\configs\yasb\config.yaml" `
  "$env:USERPROFILE\.config\yasb\config.yaml"

# SSH example only
Copy-Config `
  "$Repo\configs\ssh\config.example" `
  "$env:USERPROFILE\.ssh\config.example"

# Oh My Posh
Copy-Config `
  "$Repo\configs\oh-my-posh\poweruser.omp.json" `
  "$env:USERPROFILE\.config\oh-my-posh\poweruser.omp.json"

# PowerShell 7 profile only
$PwshProfile = "$env:USERPROFILE\Documents\PowerShell\Microsoft.PowerShell_profile.ps1"

Copy-Config `
  "$Repo\configs\powershell\Microsoft.PowerShell_profile.ps1" `
  $PwshProfile

# Optional helper script
Copy-Config `
  "$Repo\scripts\start-desktop.ps1" `
  "$env:USERPROFILE\.config\windows11-dev-poweruser\start-desktop.ps1"

Write-Host ""
Write-Host "Windows configs copied." -ForegroundColor Green
Write-Host "PowerShell profile installed only for PowerShell 7." -ForegroundColor Yellow
Write-Host "whkd config path: $env:USERPROFILE\.config\whkdrc" -ForegroundColor Yellow
Write-Host "KOMOREBI_CONFIG_HOME=$env:KOMOREBI_CONFIG_HOME" -ForegroundColor Yellow
Write-Host "Review ~/.ssh/config.example before renaming it to config." -ForegroundColor Yellow