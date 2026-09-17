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
        # Every language whose mise backend is `core:` - mise downloads a
        # prebuilt toolchain and nothing is compiled, which is what makes them
        # safe on Windows. Measured here, mise 2026.9.5, cold cache:
        #
        #   node@lts     24.21.0    8s     python@3      3.14.7   13s
        #   go@latest     1.27.1   12s     rust@latest   1.98.1   34s
        #   java@lts     25.0.2    11s     ruby@latest    4.0.7   32s
        #
        # dart, php and lua are deliberately absent: their backends are `http:`
        # and `vfox:`, and a vfox plugin builds from source, which fails on
        # Windows. docs/runtimes-and-languages.md has the measurements and the
        # winget alternatives.
        $langs = @("node@lts", "python@3", "go@latest", "rust@latest", "java@lts", "ruby@latest")

        # Never overwrite a pin that is already there: a machine pinned to
        # node@latest, or to whatever version a project needs, did not ask for
        # this list.
        #
        # Read the global config rather than asking `mise ls -g`: run from a
        # directory that has its own mise.toml, that command prints NOTHING for
        # a tool the local file overrides, so the check said "no node pinned"
        # on a machine that had one and overwrote the pin.
        $globalCfg = Join-Path $env:USERPROFILE ".config\mise\config.toml"
        $cfgText = ""
        if (Test-Path -LiteralPath $globalCfg) { $cfgText = Get-Content -LiteralPath $globalCfg -Raw }

        Write-Host ""
        foreach ($spec in $langs) {
            $tool = $spec.Split("@")[0]
            $m = [regex]::Match($cfgText, ('(?m)^\s*{0}\s*=\s*"?([^"\r\n]+)"?' -f [regex]::Escape($tool)))
            if ($m.Success) {
                Write-Host ("  = {0,-7} already pinned: {0}@{1}" -f $tool, $m.Groups[1].Value) -ForegroundColor DarkGray
                continue
            }
            Write-Host ("  + {0,-7} mise use -g {1}" -f $tool, $spec) -ForegroundColor Cyan
            & $mise.Source use -g $spec
            if ($LASTEXITCODE -ne 0) {
                Write-Host ("    mise could not install {0} - run 'mise use -g {1}' by hand." -f $tool, $spec) -ForegroundColor Yellow
            }
        }
        Write-Host "  open a new terminal for these to be on PATH" -ForegroundColor DarkGray
    } else {
        Write-Host "  mise not on PATH yet - open a new terminal, then: mise use -g node@lts python@3" -ForegroundColor Yellow
    }
}

if (-not $SkipModules) {
    Install-PowerShellModule -Manifest $manifest
}

Write-Host ""
Write-Host "Next steps:" -ForegroundColor Green
Write-Host "  1. ./scripts/link-configs.ps1        install configs + Omacheese helpers"
Write-Host "  2. ./scripts/start-desktop.ps1       start komorebi + whkd + yasb"
Write-Host ""
Write-Host "  WSL:      wsl --install -d AlmaLinux-9"
Write-Host "            wsl -d AlmaLinux-9 --cd `"$Repo`" -- bash scripts/install-almalinux.sh"
Write-Host "  Bitwarden: enable the SSH agent, and set the Windows service"
Write-Host "             'OpenSSH Authentication Agent' to Disabled."

# What landed, checked now rather than left as a step to remember. Left to
# setup.ps1 when this is one of its steps - it runs doctor once, last. Its own
# process, so doctor's exit code and preferences stay out of this script's.
if (-not $env:OMACHEESE_SETUP_RUN) {
    Write-Host ""
    & (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Repo "scripts\doctor.ps1")
}

if ($result.Failed.Count) { exit 1 }
exit 0
