param(
  [switch]$Restart
)

$ErrorActionPreference = "Continue"

function Has-Command {
  param([string]$Name)
  return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Stop-If-Running {
  param([string]$ProcessName)

  Get-Process $ProcessName -ErrorAction SilentlyContinue | Stop-Process -Force
}

$KomorebiConfigHome = Join-Path $env:USERPROFILE ".config\komorebi"
$KomorebiConfig = Join-Path $KomorebiConfigHome "komorebi.json"
$YasbConfig = Join-Path $env:USERPROFILE ".config\yasb\config.yaml"

if (!(Has-Command "komorebic.exe")) {
  Write-Host "komorebic.exe not found. Install komorebi first." -ForegroundColor Red
  exit 1
}

if (!(Test-Path $KomorebiConfig)) {
  Write-Host "Missing komorebi config: $KomorebiConfig" -ForegroundColor Red
  exit 1
}

# Prefer KOMOREBI_CONFIG_HOME over passing --config.
# This avoids Windows quoting issues around Start-Process and --config paths.
[Environment]::SetEnvironmentVariable("KOMOREBI_CONFIG_HOME", $KomorebiConfigHome, "User")
$env:KOMOREBI_CONFIG_HOME = $KomorebiConfigHome

if ($Restart) {
  Write-Host "Stopping komorebi/whkd/yasb..." -ForegroundColor Yellow

  try {
    komorebic stop --whkd
  } catch {
    Write-Host "komorebic stop returned an error; continuing..." -ForegroundColor DarkYellow
  }

  Stop-If-Running "komorebi"
  Stop-If-Running "whkd"
  Stop-If-Running "yasb"
}

Write-Host "KOMOREBI_CONFIG_HOME=$env:KOMOREBI_CONFIG_HOME" -ForegroundColor DarkGray
Write-Host "Starting komorebi..." -ForegroundColor Cyan

# Do not pass --config here. komorebi will use KOMOREBI_CONFIG_HOME.
komorebic start --whkd

Start-Sleep -Seconds 2

Write-Host ""
Write-Host "komorebi state:" -ForegroundColor Cyan
try {
  komorebic state
} catch {
  Write-Host "komorebi state failed. Try running: komorebic start --whkd" -ForegroundColor Red
}

if (Has-Command "yasb.exe") {
  if (!(Test-Path $YasbConfig)) {
    Write-Host "Missing YASB config: $YasbConfig" -ForegroundColor Yellow
  }

  Write-Host ""
  Write-Host "Starting YASB..." -ForegroundColor Cyan
  Start-Process yasb.exe
} else {
  Write-Host "yasb.exe not found. Start YASB manually or check installation." -ForegroundColor Yellow
}
