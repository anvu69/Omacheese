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

function Ensure-Dir {
  param([string]$Path)

  if (!(Test-Path $Path)) {
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
  }
}

$KomorebiConfigHome = Join-Path $env:USERPROFILE ".config\komorebi"
$KomorebiConfig = Join-Path $KomorebiConfigHome "komorebi.json"
$YasbConfig = Join-Path $env:USERPROFILE ".config\yasb\config.yaml"
$WhkdRc = Join-Path $env:USERPROFILE ".config\whkdrc"

Ensure-Dir $KomorebiConfigHome
Ensure-Dir "$env:USERPROFILE\.config"

[Environment]::SetEnvironmentVariable(
  "KOMOREBI_CONFIG_HOME",
  $KomorebiConfigHome,
  [EnvironmentVariableTarget]::User
)

$env:KOMOREBI_CONFIG_HOME = $KomorebiConfigHome

if (!(Has-Command "komorebic.exe")) {
  Write-Host "komorebic.exe not found. Install komorebi first." -ForegroundColor Red
  exit 1
}

if (!(Test-Path $KomorebiConfig)) {
  Write-Host "Missing komorebi config: $KomorebiConfig" -ForegroundColor Red
  exit 1
}

if (!(Test-Path $WhkdRc)) {
  Write-Host "Missing whkd config: $WhkdRc" -ForegroundColor Yellow
  Write-Host "Hotkeys will not work until whkdrc exists." -ForegroundColor Yellow
}

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
Write-Host "Starting komorebi with whkd..." -ForegroundColor Cyan

komorebic start --whkd

Start-Sleep -Seconds 2

Write-Host ""
Write-Host "komorebi state:" -ForegroundColor Cyan

try {
  komorebic state
} catch {
  Write-Host "komorebi state failed." -ForegroundColor Red
  Write-Host "Try manually:" -ForegroundColor Yellow
  Write-Host '$env:KOMOREBI_CONFIG_HOME="$env:USERPROFILE\.config\komorebi"'
  Write-Host "komorebic start --whkd"
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