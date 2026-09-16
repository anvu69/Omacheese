# Windows 11 developer power-user - package install.
#
#   ./scripts/install-windows.ps1                 # everything
#   ./scripts/install-windows.ps1 -Groups core,wm # a subset
#   ./scripts/install-windows.ps1 -SkipModules
#
# Packages come from configs/winget/packages.json so this script and
# bootstrap-windows.ps1 can never drift apart again. Every id in that file is
# checked by scripts/doctor.ps1 and by CI.

[CmdletBinding()]
param(
    # No ValidateSet here on purpose: powershell.exe -File binds "core,cli"
    # as ONE array element, and a ValidateSet would reject it before the
    # script can split it. Validated against the manifest below instead.
    [string[]]$Groups,
    [switch]$SkipModules,
    [switch]$ModulesOnly,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

if ($Groups) { $Groups = @($Groups -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }

$Repo = Split-Path -Parent $PSScriptRoot
. (Join-Path $Repo "scripts\lib\common.ps1")

$manifestPath = Join-Path $Repo "configs\winget\packages.json"
if (-not (Test-Path -LiteralPath $manifestPath)) {
    throw "Missing package manifest: $manifestPath"
}
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json

$known = @($manifest.groups.PSObject.Properties.Name)
if ($Groups) {
    $unknown = @($Groups | Where-Object { $known -notcontains $_ })
    if ($unknown.Count) {
        throw "Unknown group(s): $($unknown -join ', '). Known: $($known -join ', ')"
    }
}

Write-Host "Windows 11 power-user setup" -ForegroundColor Green
if (Test-IsElevated) {
    Write-Host "Running elevated." -ForegroundColor DarkGray
} else {
    Write-Host "Running unelevated; winget may prompt for machine-scope installs." -ForegroundColor DarkGray
}

if ($ModulesOnly) {
    Install-PowerShellModule -Manifest $manifest
    return
}

$result = Install-WingetManifest -Manifest $manifest -Groups $Groups -Force:$Force

if (-not $SkipModules) {
    Install-PowerShellModule -Manifest $manifest
}

Write-Host ""
Write-Host "Next steps:" -ForegroundColor Green
Write-Host "  1. ./scripts/link-configs.ps1        install configs + Omacheese helpers"
Write-Host "  2. ./scripts/doctor.ps1              verify everything landed"
Write-Host "  3. ./scripts/start-desktop.ps1       start komorebi + whkd + yasb"
Write-Host ""
Write-Host "  WSL:      wsl --install -d AlmaLinux-9   then  bash scripts/install-almalinux.sh"
Write-Host "  Bitwarden: enable the SSH agent, and set the Windows service"
Write-Host "             'OpenSSH Authentication Agent' to Disabled."

if ($result.Failed.Count) { exit 1 }
