# Start (or restart) the desktop: komorebi + whkd + yasb.
#
#   ./scripts/start-desktop.ps1
#   ./scripts/start-desktop.ps1 -Restart
#   ./scripts/start-desktop.ps1 -Stop
#
# link-configs.ps1 installs a copy of this at
# ~/.config/omarchy/bin/start-desktop.ps1 and points a Startup shortcut at it,
# so the desktop comes back on its own after a reboot.

[CmdletBinding()]
param(
    [switch]$Restart,
    [switch]$Stop
)

$ErrorActionPreference = "Continue"

$cfg                = Join-Path $env:USERPROFILE ".config"
$KomorebiConfigHome = Join-Path $cfg "komorebi"
$KomorebiConfig     = Join-Path $KomorebiConfigHome "komorebi.json"
$WhkdRc             = Join-Path $cfg "whkdrc"
$YasbConfig         = Join-Path $cfg "yasb\config.yaml"

function Have { param([string]$n) [bool](Get-Command $n -ErrorAction SilentlyContinue) }
function Stop-Proc { param([string]$n) Get-Process $n -ErrorAction SilentlyContinue | Stop-Process -Force }

[Environment]::SetEnvironmentVariable("KOMOREBI_CONFIG_HOME", $KomorebiConfigHome, "User")
$env:KOMOREBI_CONFIG_HOME = $KomorebiConfigHome

if ($Stop -or $Restart) {
    Write-Host "Stopping komorebi / whkd / yasb..." -ForegroundColor Yellow
    if (Have "komorebic") { komorebic stop --whkd 2>$null | Out-Null }
    Stop-Proc "komorebi"; Stop-Proc "whkd"; Stop-Proc "yasb"
    if ($Stop) { Write-Host "Stopped." -ForegroundColor Green; return }
    Start-Sleep -Milliseconds 500
}

if (-not (Have "komorebic")) {
    Write-Host "komorebic not found. Install komorebi first:" -ForegroundColor Red
    Write-Host "  winget install --id LGUG2Z.komorebi -e" -ForegroundColor Cyan
    exit 1
}
if (-not (Test-Path -LiteralPath $KomorebiConfig)) {
    Write-Host "Missing $KomorebiConfig - run ./scripts/link-configs.ps1" -ForegroundColor Red
    exit 1
}
if (-not (Test-Path -LiteralPath $WhkdRc)) {
    Write-Host "Missing $WhkdRc - hotkeys will not work." -ForegroundColor Yellow
}

# Already up? Do not stack a second komorebi on top of the first.
if (Get-Process komorebi -ErrorAction SilentlyContinue) {
    Write-Host "komorebi is already running (use -Restart)." -ForegroundColor DarkYellow
} else {
    Write-Host "Starting komorebi + whkd..." -ForegroundColor Cyan
    komorebic start --whkd | Out-Null

    # Wait for the named pipe to answer instead of sleeping a fixed amount.
    $ready = $false
    foreach ($i in 1..20) {
        Start-Sleep -Milliseconds 250
        komorebic state 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { $ready = $true; break }
    }
    if ($ready) {
        Write-Host "komorebi is up." -ForegroundColor Green
    } else {
        Write-Host "komorebi did not answer in 5s. Try: komorebic start --whkd" -ForegroundColor Red
    }
}

# whkd dies silently on a bad key name, so say so rather than leaving the user
# to discover that no hotkey works.
Start-Sleep -Milliseconds 300
if (-not (Get-Process whkd -ErrorAction SilentlyContinue)) {
    Write-Host "whkd is NOT running - every hotkey is dead." -ForegroundColor Red
    Write-Host "Usually a bad key name in whkdrc. Check with:" -ForegroundColor Yellow
    Write-Host "  ./scripts/doctor.ps1" -ForegroundColor Cyan
} else {
    Write-Host "whkd is up." -ForegroundColor Green
}

if (Have "yasb") {
    if (-not (Test-Path -LiteralPath $YasbConfig)) {
        Write-Host "Missing $YasbConfig - the bar will use its defaults." -ForegroundColor Yellow
    }
    if (Get-Process yasb -ErrorAction SilentlyContinue) {
        Write-Host "yasb is already running." -ForegroundColor DarkYellow
    } else {
        Write-Host "Starting yasb..." -ForegroundColor Cyan
        Start-Process yasb.exe -WindowStyle Hidden
    }
} else {
    Write-Host "yasb.exe not found: winget install --id AmN.yasb -e" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "SUPER+/      keybindings" -ForegroundColor DarkGray
Write-Host "SUPER+SPACE  menu" -ForegroundColor DarkGray
