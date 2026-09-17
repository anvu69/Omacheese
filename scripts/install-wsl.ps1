# Install WSL2 and the AlmaLinux 9 distro.
#
#   ./scripts/install-wsl.ps1
#   ./scripts/install-wsl.ps1 -Distro Ubuntu-24.04
#
# Needs admin. On a clean machine `wsl --install` enables two Windows features
# and usually wants a reboot before any distro will start; this script says so
# rather than leaving you to work it out from a silent failure.

[CmdletBinding()]
param(
    [string]$Distro = "AlmaLinux-9",
    [switch]$SkipDistro
)

$ErrorActionPreference = "Continue"

# For Invoke-BoundedCommand: every call into wsl.exe gets a deadline, because a
# wedged WSL service answers nothing and this script would wait for it forever.
# detect.ps1 turns StrictMode on for whatever dot-sources it; this script is not
# written to it, so turn it back off rather than fail in an elevated window that
# has nowhere to print.
$RepoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $RepoRoot "scripts\lib\detect.ps1")
Set-StrictMode -Off

function Info { param($m) Write-Host "  $m" -ForegroundColor Cyan }
function Good { param($m) Write-Host "  $m" -ForegroundColor Green }
function Warn { param($m) Write-Host "  $m" -ForegroundColor Yellow }
function Bad  { param($m) Write-Host "  $m" -ForegroundColor Red }

$elevated = (New-Object Security.Principal.WindowsPrincipal(
    [Security.Principal.WindowsIdentity]::GetCurrent())
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $elevated) {
    Bad "This needs to run as administrator."
    exit 1
}

Write-Host "WSL2 setup" -ForegroundColor Green

# --- virtualisation ----------------------------------------------------------
$cpu = @(Get-CimInstance Win32_Processor)[0]
if ($cpu.PSObject.Properties.Name -contains "VirtualizationFirmwareEnabled" -and
    -not $cpu.VirtualizationFirmwareEnabled) {
    $cs = Get-CimInstance Win32_ComputerSystem
    if (-not $cs.HypervisorPresent) {
        Bad "Virtualisation is disabled in firmware. Enable VT-x / AMD-V in the BIOS, then re-run."
        exit 1
    }
}
Good "virtualisation available"

# --- features ----------------------------------------------------------------
# Ask WSL whether it runs, instead of asking DISM whether two feature names are
# on. The Store build of WSL (2.4 and later, which is what Windows installs now)
# needs VirtualMachinePlatform and nothing else: the legacy
# Microsoft-Windows-Subsystem-Linux feature can sit Disabled on a machine where
# `wsl --version` answers and distros run.
#
# Enabling it there was not free. Measured on this machine, with WSL 2.7.14
# working and no distro installed: 628s of DISM, then exit 3010 - and setup.ps1
# reads 3010 as "reboot first", so it skipped the local-LLM step and the distro
# install below never ran either. The machine needed neither.
$needReboot = $false

$probe = Invoke-BoundedCommand -FilePath "wsl.exe" -ArgumentList @("--version") `
         -TimeoutMs 8000 -StdoutEncoding ([System.Text.Encoding]::Unicode)

if ($probe.ExitCode -eq 0) {
    Good "WSL already runs - leaving the Windows features alone"
} else {
    foreach ($feature in @("Microsoft-Windows-Subsystem-Linux", "VirtualMachinePlatform")) {
        $state = (Get-WindowsOptionalFeature -Online -FeatureName $feature -ErrorAction SilentlyContinue).State
        if ($state -eq "Enabled") {
            Good "$feature already enabled"
        } else {
            Info "enabling $feature..."
            $r = Enable-WindowsOptionalFeature -Online -FeatureName $feature -All -NoRestart -ErrorAction SilentlyContinue
            # Do not wait to be told. VirtualMachinePlatform needs a reboot whether
            # or not DISM sets RestartNeeded, and treating "just enabled" as "ready"
            # is what made the distro install, and then everything downstream of it,
            # fail on a machine that was only a restart away from working.
            $needReboot = $true
            if ($r -and $r.RestartNeeded) { Info "  restart flagged by DISM" }
            Good "$feature enabled"
        }
    }
}

# --- kernel ------------------------------------------------------------------
Info "updating the WSL kernel..."
wsl.exe --update 2>&1 | Out-String | Write-Host
wsl.exe --set-default-version 2 2>&1 | Out-String | Write-Host

if ($needReboot) {
    Warn ""
    Warn "Windows features were just enabled - a RESTART is required before any"
    Warn "distro can start."
    if ($env:OMACHEESE_SETUP_RUN) {
        Warn "Setup registers itself to carry on after the restart - nothing to type."
    } else {
        Warn "After restarting: ./scripts/install-distro.ps1 (setup.ps1 does this by itself)"
    }
    # 3010 is the Windows installer convention for "succeeded, reboot required".
    # setup.ps1 reads it and skips the steps that would only fail until then -
    # the local-LLM module in particular, which needs a running distro and used
    # to report a failure that was really just "not yet".
    exit 3010
}

# --- distro ------------------------------------------------------------------
if ($SkipDistro) { Good "skipping distro install"; exit 0 }

$installed = @()
try {
    $raw = (& wsl.exe -l -q 2>$null) -join "`n"
    $installed = @(($raw -replace "`0", "") -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
} catch { }

if ($installed -contains $Distro) {
    Good "$Distro already installed"
} else {
    Info "installing $Distro (this downloads a few hundred MB)..."
    # --no-launch so the install does not block on the interactive first-run
    # user creation; the setup TUI is not a place to sit at a username prompt.
    wsl.exe --install -d $Distro --no-launch 2>&1 | Out-String | Write-Host
    if ($LASTEXITCODE -ne 0) {
        Warn "wsl --install returned $LASTEXITCODE."
        Warn "Available distros:"
        wsl.exe --list --online 2>&1 | Out-String | Write-Host
        exit 1
    }
    Good "$Distro installed"
}

Write-Host ""
Good "WSL is ready."
Write-Host ""
# The distro itself - a user, zsh, the tools, /etc/wsl.conf - is
# install-distro.ps1. setup.ps1 runs it as its next step; run on its own, this
# script runs it too, rather than printing the commands it would take.
if (-not $env:OMACHEESE_SETUP_RUN) {
    & (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File (Join-Path $RepoRoot "scripts\install-distro.ps1") -Distro $Distro
    exit $LASTEXITCODE
}
exit 0
