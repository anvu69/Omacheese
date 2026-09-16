# One command to set up a fresh Windows 11 machine.
#
#   irm https://raw.githubusercontent.com/anvu69/Omacheese/main/install.ps1 | iex
#
# No git, no clone, nothing installed first. It fetches the repo as an archive
# and runs scripts/setup.ps1 - the same TUI a cloned repo gets.
#
# To pass options through `iex`, wrap it in a script block:
#
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/anvu69/Omacheese/main/install.ps1))) -Preset desktop -Yes
#
# Or fetch it to a file first, which is the better habit for anything that runs
# code off the internet:
#
#   irm https://raw.githubusercontent.com/anvu69/Omacheese/main/install.ps1 -OutFile install.ps1
#   ./install.ps1 -DryRun
#
# This file lives at the repo root on purpose: it is the shortest URL the repo
# can offer, and it is the first thing anyone sees.

[CmdletBinding()]
param(
    # owner/name. Override to install a fork.
    [string]$Repo = "anvu69/Omacheese",
    [string]$Branch = "main",

    # No [ValidateSet] here, deliberately. `irm | iex` - the command at the top
    # of this file - runs the text in the CALLER's scope, so param() declares
    # $Preset there. [string] turns $null into "", ValidateSet then rejects "",
    # and the whole script dies before running a line of itself:
    #
    #   Invoke-Expression: The attribute cannot be added because variable
    #   Preset with value  would no longer be valid.
    #
    # A default value would also fix it, but then this picks a preset nobody
    # asked for. The set is checked in the body instead.
    [string]$Preset,
    [string[]]$Modules,
    [switch]$Yes,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

# Windows PowerShell 5.1 on an untouched machine can still default to TLS 1.0,
# which GitHub refuses. This runs before anything is fetched.
try {
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch { }

# A clean Windows 11 leaves Windows PowerShell's execution policy at Restricted.
# `irm | iex` itself is unaffected - that text never touches disk - so the
# one-liner starts, prints the banner, and then dies on the very first thing it
# does: `& <repo>\scripts\setup.ps1`. PowerShell reports that against the line
# the user typed, so the message points at `iex` and reads as though the
# one-liner were wrong. Process scope only: nothing outside this run changes,
# and it needs no elevation.
try { Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction Stop } catch { }

# Validated here rather than with [ValidateSet] on the parameter: see the note
# in the param block. The error is better anyway - it names the valid presets.
$knownPresets = @("minimal", "desktop", "full", "everything", "custom")
if ($Preset -and $knownPresets -notcontains $Preset) {
    throw "-Preset must be one of: $($knownPresets -join ', ')"
}

if ($Repo -notmatch '^[^/\s]+/[^/\s]+$') {
    throw "-Repo must be owner/name, for example anvu69/Omacheese"
}
$owner, $name = $Repo.Split("/")

Write-Host ""
Write-Host "  Omacheese" -ForegroundColor Cyan
Write-Host "  $owner/$name@$Branch" -ForegroundColor DarkGray
Write-Host ""

# --- where the repo lands ----------------------------------------------------
# NOT %TEMP%, and this is not a detail.
#
# link-configs.ps1 SYMLINKS the PowerShell profile, ~/.config, whkdrc,
# komorebi.json and %APPDATA%\alacritty at whatever directory this script
# unpacked into. That makes the unpacked copy the installed repo, not scratch
# space, and it has to outlive the run. Out of %TEMP% it did not:
#
#   * this script cleared its own work directory at the START of every run, so
#     the second install broke every config the first one had linked
#   * Storage Sense and Disk Cleanup empty %TEMP% on their own schedule
#
# Either way every link dangles, and the symptoms are exactly what a broken
# install looks like: the shell prompt reverts to bare PowerShell, Alacritty
# loses its theme, SUPER+SPACE does nothing.
$InstallHome = Join-Path $env:LOCALAPPDATA "Omacheese"
$Stage       = Join-Path $InstallHome "download"
$Target      = Join-Path $InstallHome "repo"

$RepoRoot = $null

# Running from a clone (or from an already-unpacked copy)? Use it as-is rather
# than downloading over the top of the directory the configs point at.
if ($PSCommandPath) {
    $hereRoot = Split-Path -Parent $PSCommandPath
    if (Test-Path -LiteralPath (Join-Path $hereRoot "scripts\setup.ps1")) {
        $RepoRoot = $hereRoot
        Write-Host "  using the copy next to this script" -ForegroundColor DarkGray
        Write-Host "  $RepoRoot" -ForegroundColor DarkGray
    }
}

# --- archive -----------------------------------------------------------------
# One request for the whole repo rather than a list of files to fetch. A list
# goes stale silently: the version this replaced was missing 25 files, including
# the launcher behind SUPER+SPACE, and still reported success.
if (-not $RepoRoot) {
    if (Test-Path -LiteralPath $Stage) { Remove-Item -LiteralPath $Stage -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $Stage | Out-Null

    $zip = Join-Path $Stage "repo.zip"
    try {
        $ProgressPreference = "SilentlyContinue"   # the progress bar makes this ~10x slower
        Write-Host "  fetching..." -ForegroundColor DarkGray
        Invoke-WebRequest -UseBasicParsing -OutFile $zip `
            -Uri "https://codeload.github.com/$owner/$name/zip/refs/heads/$Branch"
        Expand-Archive -LiteralPath $zip -DestinationPath $Stage -Force
        Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue

        # GitHub wraps everything in <repo>-<branch>/. Move it into place under
        # the stable path, so links made on an earlier run still resolve.
        $inner = Get-ChildItem -LiteralPath $Stage -Directory |
                 Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName "scripts\setup.ps1") } |
                 Select-Object -First 1
        if ($inner) {
            if (Test-Path -LiteralPath $Target) { Remove-Item -LiteralPath $Target -Recurse -Force }
            Move-Item -LiteralPath $inner.FullName -Destination $Target -Force
            $RepoRoot = $Target
        }
    } catch {
        Write-Host "  archive failed: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# --- git, if the archive did not work ----------------------------------------
if (-not $RepoRoot -and (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "  falling back to git clone" -ForegroundColor Yellow
    if (Test-Path -LiteralPath $Target) { Remove-Item -LiteralPath $Target -Recurse -Force }
    git clone --depth 1 --branch $Branch "https://github.com/$owner/$name.git" $Target 2>&1 | Out-Null
    if (Test-Path -LiteralPath (Join-Path $Target "scripts\setup.ps1")) { $RepoRoot = $Target }
}

if (-not $RepoRoot) {
    throw @"
Could not fetch $owner/$name@$Branch.

Check your connection, or clone it and run the setup directly:

  git clone https://github.com/$owner/$name.git
  cd $name
  ./scripts/setup.ps1
"@
}

# Files that came out of a downloaded zip carry the mark of the web on some
# machines, and then every .ps1 in the repo trips the execution policy no
# matter what scope this process set. Clearing it once here is cheaper than
# explaining the error.
try {
    Get-ChildItem -LiteralPath $RepoRoot -Recurse -File -Include *.ps1, *.psm1, *.cmd -ErrorAction SilentlyContinue |
        Unblock-File -ErrorAction SilentlyContinue
} catch { }

# The old %TEMP% copy is deliberately NOT deleted here. Configs from an earlier
# install may still be symlinked into it, and this run might not include the
# `configs` module - removing it would break a working machine. link-configs.ps1
# clears it once it has repointed everything at $RepoRoot.

Write-Host "  installed to $RepoRoot" -ForegroundColor DarkGray
Write-Host ""

# Hand over to the interactive setup: it detects the machine and offers only the
# modules it can actually run. From here on this is the same code path as a
# cloned repo.
$setupArgs = @{}
if ($Preset)  { $setupArgs["Preset"]  = $Preset }
if ($Modules) { $setupArgs["Modules"] = $Modules }
if ($Yes)     { $setupArgs["Yes"]     = $true }
if ($DryRun)  { $setupArgs["DryRun"]  = $true }

& (Join-Path $RepoRoot "scripts\setup.ps1") @setupArgs
