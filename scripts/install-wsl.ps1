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
$needReboot = $false
foreach ($feature in @("Microsoft-Windows-Subsystem-Linux", "VirtualMachinePlatform")) {
    $state = (Get-WindowsOptionalFeature -Online -FeatureName $feature -ErrorAction SilentlyContinue).State
    if ($state -eq "Enabled") {
        Good "$feature already enabled"
    } else {
        Info "enabling $feature..."
        $r = Enable-WindowsOptionalFeature -Online -FeatureName $feature -All -NoRestart -ErrorAction SilentlyContinue
        if ($r -and $r.RestartNeeded) { $needReboot = $true }
        Good "$feature enabled"
    }
}

# --- kernel ------------------------------------------------------------------
Info "updating the WSL kernel..."
wsl.exe --update 2>&1 | Out-String | Write-Host
wsl.exe --set-default-version 2 2>&1 | Out-String | Write-Host

if ($needReboot) {
    Warn ""
    Warn "Windows features were just enabled - a REBOOT is required before any"
    Warn "distro can start. After rebooting, run:"
    Warn "    wsl --install -d $Distro"
    Warn "    bash scripts/install-almalinux.sh   (inside the distro)"
    exit 0
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
Write-Host "  Next, inside the distro (it will ask you to create a user):" -ForegroundColor Cyan
Write-Host "    wsl -d $Distro"
Write-Host "    bash scripts/install-almalinux.sh"
Write-Host ""
Write-Host "  Then install the per-distro config:" -ForegroundColor Cyan
Write-Host "    sudo cp ~/.config/wsl/wsl.conf /etc/wsl.conf && exit"
Write-Host "    wsl --shutdown"
