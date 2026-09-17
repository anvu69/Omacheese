# Windows 11 developer power-user - package install.
#
#   ./scripts/install-windows.ps1                 # everything
#   ./scripts/install-windows.ps1 -Groups core,wm # a subset
#   ./scripts/install-windows.ps1 -SkipModules
#   ./scripts/install-windows.ps1 -Groups core -Force   # upgrade, not skip
#
# By default a package that is already installed is SKIPPED, not upgraded:
# provisioning a machine should not silently move versions under someone who
# is already using it. -Force re-runs winget install across the selection, so
# anything with a newer version gets it. That is how you reach the latest
# PowerShell on a machine that already shipped with an older pwsh 7.
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

# The langs group installs mise, and mise on its own installs no language: a
# fresh machine finished the whole setup with no node on it, while
# packages.json told the truth about the agents group needing one ("Node comes
# from mise"). Everything npm-shaped - a coding agent installed that way, any
# repo with a package.json - then failed until someone typed this line by hand.
if (-not $Groups -or $Groups -contains "langs") {
    # winget wrote mise onto the machine PATH, which this process read at start.
    $env:PATH = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [Environment]::GetEnvironmentVariable("Path", "User")
    $mise = Get-Command mise -ErrorAction SilentlyContinue
    if ($mise) {
        # Never overwrite a pin that is already there: a machine pinned to
        # node@latest, or to whatever a project needs, did not ask for lts.
        #
        # Read the global config rather than asking `mise ls -g`: run from a
        # directory that has its own mise.toml, that command prints NOTHING for
        # a tool the local file overrides, so the check said "no node pinned"
        # on a machine that had one and overwrote the pin.
        $globalCfg = Join-Path $env:USERPROFILE ".config\mise\config.toml"
        $pinnedNode = $null
        if (Test-Path -LiteralPath $globalCfg) {
            $m = [regex]::Match((Get-Content -LiteralPath $globalCfg -Raw), '(?m)^\s*node\s*=\s*"?([^"\r\n]+)"?')
            if ($m.Success) { $pinnedNode = $m.Groups[1].Value }
        }
        if ($pinnedNode) {
            Write-Host ""
            Write-Host "node already pinned in mise: node@$pinnedNode" -ForegroundColor DarkGray
        } else {
            Write-Host ""
            Write-Host "Installing node through mise (mise use -g node@lts)..." -ForegroundColor Cyan
            & $mise.Source use -g node@lts
            if ($LASTEXITCODE -ne 0) {
                Write-Host "  mise could not install node - run 'mise use -g node@lts' by hand." -ForegroundColor Yellow
            }
        }
        # Only node. python, go, rust and dart are one command each and most
        # machines want a different set; see docs/runtimes-and-languages.md.
    } else {
        Write-Host "  mise not on PATH yet - open a new terminal, then: mise use -g node@lts" -ForegroundColor Yellow
    }
}

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
