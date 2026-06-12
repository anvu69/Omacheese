param(
  [switch]$Restart
)

$ErrorActionPreference = "Continue"

function Has-Command {
  param([string]$Name)
  return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

if (!(Has-Command "komorebic.exe")) {
  Write-Host "komorebic.exe not found. Install komorebi first." -ForegroundColor Red
  exit 1
}

if ($Restart) {
  Write-Host "Stopping komorebi/whkd/yasb..." -ForegroundColor Yellow
  komorebic stop --whkd 2>$null
  Get-Process yasb -ErrorAction SilentlyContinue | Stop-Process -Force
}

$KomorebiConfig = "$env:USERPROFILE\.config\komorebi\komorebi.json"

if (!(Test-Path $KomorebiConfig)) {
  Write-Host "Missing komorebi config: $KomorebiConfig" -ForegroundColor Red
  exit 1
}

Write-Host "Starting komorebi..." -ForegroundColor Cyan
komorebic start --config $KomorebiConfig --whkd

Start-Sleep -Seconds 1

Write-Host "komorebi state:" -ForegroundColor Cyan
komorebic state

if (Has-Command "yasb.exe") {
  Write-Host "Starting YASB..." -ForegroundColor Cyan
  Start-Process yasb.exe
} else {
  Write-Host "yasb.exe not found. Start YASB manually or check installation." -ForegroundColor Yellow
}