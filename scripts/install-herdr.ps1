# Install herdr, the agent multiplexer, plus this repo's config for it.
#
#   ./scripts/install-herdr.ps1
#   ./scripts/install-herdr.ps1 -Check      report what is there, change nothing
#
# WHY NOT WINGET
#
# Every other package in this repo installs through winget. herdr does not, and
# the reason is worth writing down, because `winget install herdr` is a trap.
# Searching winget for "herdr" returns four packages:
#
#   hdosys.herdr-win            "Herdr Extended" - an unofficial third-party
#                               fork, and it holds the `herdr` MONIKER, so a
#                               bare `winget install herdr` resolves to this
#   khanhtd36.herdr-khanhtd36   another unofficial fork, relicensed AGPL-3.0
#   hdosys.herdr-sandbox        a different tool entirely (Windows Sandbox)
#   Herdr.Herdr.Preview         the real one, published by Herdr, Inc. - but
#                               the PREVIEW channel only
#
# There is no official stable package on winget, and herdr's own docs say
# stable is the channel to use on Windows. So this installs from herdr.dev,
# which is what those docs tell you to run. That installer is per-user, needs
# no admin, verifies a SHA-256 from the release manifest, and puts the binary
# under %LOCALAPPDATA%\Programs\Herdr\bin.

[CmdletBinding()]
param(
    [switch]$Check,
    [ValidateSet("stable", "preview")]
    [string]$Channel = "stable"
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$ConfigHome = Join-Path $env:USERPROFILE ".config"

function Find-Herdr {
    # Freshly installed, herdr is on the user PATH but not in this process's
    # inherited copy - the same trap that had sixteen hotkeys launching nothing.
    $c = Get-Command herdr -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    $known = Join-Path $env:LOCALAPPDATA "Programs\Herdr\bin\herdr.exe"
    if (Test-Path -LiteralPath $known) { return $known }
    return $null
}

$existing = Find-Herdr

if ($Check) {
    if ($existing) {
        Write-Host "herdr: $existing" -ForegroundColor Green
        & $existing --version
    } else {
        Write-Host "herdr: not installed" -ForegroundColor Yellow
    }
    $cfg = Join-Path $env:APPDATA "herdr\config.toml"
    if (Test-Path -LiteralPath $cfg) { Write-Host "config: $cfg" -ForegroundColor Green }
    else { Write-Host "config: not installed (./scripts/link-configs.ps1)" -ForegroundColor Yellow }
    return
}

if ($existing) {
    Write-Host "herdr already installed: $existing" -ForegroundColor Green
    & $existing --version
} else {
    Write-Host "Installing herdr ($Channel) from herdr.dev" -ForegroundColor Cyan
    Write-Host "  not winget - see the comment at the top of this script" -ForegroundColor DarkGray

    $installer = Join-Path ([System.IO.Path]::GetTempPath()) "herdr-install.ps1"
    try {
        Invoke-WebRequest -Uri "https://herdr.dev/install.ps1" -OutFile $installer -UseBasicParsing
    } catch {
        Write-Host "Could not download the herdr installer: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }

    $installArgs = @()
    if ($Channel -eq "preview") { $installArgs += @("-Channel", "preview") }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer @installArgs
    Remove-Item -LiteralPath $installer -Force -ErrorAction SilentlyContinue

    $existing = Find-Herdr
    if (-not $existing) {
        Write-Host "herdr did not land on PATH. Open a new terminal and check ``herdr --version``." -ForegroundColor Yellow
        exit 1
    }
}

# The config is rendered from the palette, so let the theme script own it
# rather than copying a stale file over the top.
$theme = Join-Path $RepoRoot "scripts\omacheese\omacheese-theme.ps1"
if (Test-Path -LiteralPath $theme) {
    # There is no "re-render in place" switch: -Set <name> is the render, and
    # -Current is how you find out what name to pass.
    $active = (& $theme -Current 2>$null | Select-Object -First 1)
    if ($active) { $active = "$active".Trim() }
    if (-not $active) { $active = "tokyo-night" }
    Write-Host "`nRendering the herdr config from palette '$active'" -ForegroundColor Cyan
    & $theme -Set $active -NoRestart
}

Write-Host ""
Write-Host "Done." -ForegroundColor Green
Write-Host "  SUPER+CTRL+ENTER   launch or reattach to the herdr session" -ForegroundColor Gray
Write-Host "  hdl claude         editor + agent + terminal in one tab" -ForegroundColor Gray
Write-Host "  hstat              which agents are working, blocked or idle" -ForegroundColor Gray
