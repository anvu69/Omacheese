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

$WorkDir = Join-Path $env:TEMP "omacheese-install"
if (Test-Path -LiteralPath $WorkDir) { Remove-Item -LiteralPath $WorkDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

$RepoRoot = $null

# --- archive -----------------------------------------------------------------
# One request for the whole repo rather than a list of files to fetch. A list
# goes stale silently: the version this replaced was missing 25 files, including
# the launcher behind SUPER+SPACE, and still reported success.
$zip = Join-Path $WorkDir "repo.zip"
try {
    $ProgressPreference = "SilentlyContinue"   # the progress bar makes this ~10x slower
    Write-Host "  fetching..." -ForegroundColor DarkGray
    Invoke-WebRequest -UseBasicParsing -OutFile $zip `
        -Uri "https://codeload.github.com/$owner/$name/zip/refs/heads/$Branch"
    Expand-Archive -LiteralPath $zip -DestinationPath $WorkDir -Force
    Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue

    # GitHub wraps everything in <repo>-<branch>/.
    $inner = Get-ChildItem -LiteralPath $WorkDir -Directory |
             Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName "scripts\setup.ps1") } |
             Select-Object -First 1
    if ($inner) { $RepoRoot = $inner.FullName }
} catch {
    Write-Host "  archive failed: $($_.Exception.Message)" -ForegroundColor Yellow
}

# --- git, if the archive did not work ----------------------------------------
if (-not $RepoRoot -and (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "  falling back to git clone" -ForegroundColor Yellow
    $clone = Join-Path $WorkDir "repo"
    git clone --depth 1 --branch $Branch "https://github.com/$owner/$name.git" $clone 2>&1 | Out-Null
    if (Test-Path -LiteralPath (Join-Path $clone "scripts\setup.ps1")) { $RepoRoot = $clone }
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

# Hand over to the interactive setup: it detects the machine and offers only the
# modules it can actually run. From here on this is the same code path as a
# cloned repo.
$setupArgs = @{}
if ($Preset)  { $setupArgs["Preset"]  = $Preset }
if ($Modules) { $setupArgs["Modules"] = $Modules }
if ($Yes)     { $setupArgs["Yes"]     = $true }
if ($DryRun)  { $setupArgs["DryRun"]  = $true }

& (Join-Path $RepoRoot "scripts\setup.ps1") @setupArgs
