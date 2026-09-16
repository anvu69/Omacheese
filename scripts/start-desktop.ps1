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

$ScrollDaemon = Join-Path $cfg "omarchy\bin\omarchy-scroll-daemon.ps1"
$MenuScript   = Join-Path $cfg "omarchy\bin\omarchy-menu.ps1"

if ($Stop -or $Restart) {
    Write-Host "Stopping komorebi / whkd / yasb..." -ForegroundColor Yellow
    if (Test-Path -LiteralPath $ScrollDaemon) {
        & $ScrollDaemon -Stop 2>$null | Out-Null
    }
    if (Test-Path -LiteralPath $MenuScript) {
        & $MenuScript -Stop 2>$null | Out-Null
    }
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

    # Fire and forget, in its own window, and do NOT wait.
    #
    # komorebic spawns komorebi.exe and whkd.exe as long-lived background
    # processes. Anything that makes this shell hold on to their output
    # handles never returns, because a window manager does not exit:
    #   komorebic start --whkd | Out-Null        hangs (pipeline stays open)
    #   Start-Process -NoNewWindow -Wait         hangs (children inherit the
    #                                            redirected stdout handle)
    # Readiness is established by polling the named pipe below instead.
    Start-Process -FilePath "komorebic.exe" -ArgumentList "start", "--whkd" `
        -WindowStyle Hidden -ErrorAction SilentlyContinue

    # Poll the named pipe rather than sleeping a fixed amount. 30s, because a
    # cold start here measured around 10s - the previous 5s budget declared
    # failure on a komorebi that was simply still starting.
    $ready = $false
    foreach ($i in 1..60) {
        Start-Sleep -Milliseconds 500
        komorebic state 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { $ready = $true; break }
    }
    if ($ready) {
        Write-Host "komorebi is up." -ForegroundColor Green
    } else {
        Write-Host "komorebi did not answer in 30s. Try: komorebic start --whkd" -ForegroundColor Red
    }
}

# whkd dies silently on a bad key name, so say so rather than leaving the user
# to discover that no hotkey works. komorebic starts it a moment after
# komorebi itself, so give it a beat before declaring it dead.
foreach ($i in 1..20) {
    if (Get-Process whkd -ErrorAction SilentlyContinue) { break }
    Start-Sleep -Milliseconds 250
}
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

# The scrolling strip needs someone watching focus - see the daemon's header.
# It is cheap (it sleeps on a named pipe) and it is what keeps SUPER+CTRL+S and
# SUPER+SHIFT+L agreeing about what the layout should look like.
if (Test-Path -LiteralPath $ScrollDaemon) {
    $pwshExe = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
    if (-not $pwshExe) { $pwshExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" }
    & $ScrollDaemon -Stop 2>$null | Out-Null
    Start-Process -FilePath $pwshExe `
        -ArgumentList "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$ScrollDaemon`"" `
        -WindowStyle Hidden -ErrorAction SilentlyContinue
    Write-Host "scroll daemon is up." -ForegroundColor Green
} else {
    Write-Host "omarchy-scroll-daemon.ps1 missing - run ./scripts/link-configs.ps1" -ForegroundColor Yellow
}

# The menu costs ~770ms to build, almost all of it XAML parsing and PowerShell
# startup, and it sits on SUPER+SPACE. Kept warm it opens in ~170ms. Everything
# still works without it - omarchy-menu.cmd falls back to building one.
if (Test-Path -LiteralPath $MenuScript) {
    $menuPwsh = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
    if (-not $menuPwsh) { $menuPwsh = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" }
    & $MenuScript -Stop 2>$null | Out-Null
    Start-Process -FilePath $menuPwsh `
        -ArgumentList "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$MenuScript`"", "-Serve" `
        -WindowStyle Hidden -ErrorAction SilentlyContinue
    Write-Host "menu server is up." -ForegroundColor Green
}

Write-Host ""
Write-Host "SUPER+/      keybindings" -ForegroundColor DarkGray
Write-Host "SUPER+SPACE  menu" -ForegroundColor DarkGray
