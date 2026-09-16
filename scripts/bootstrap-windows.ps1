# Bootstrap the Windows side straight from GitHub, without cloning.
#
#   $repo="https://raw.githubusercontent.com/anvu69/windows11-dev-poweruser/main"
#   irm "$repo/scripts/bootstrap-windows.ps1" | iex
#
# It fetches the repo and then runs the SAME setup.ps1 the cloned repo uses, so
# there is one install path and one experience.
#
# WHY A ZIP AND NOT A FILE LIST
#
# This used to enumerate every file it needed. That list went stale the moment
# anything was added: by the time it was replaced it was missing 25 files,
# including omarchy-menu.cmd - which is what SUPER+SPACE and the bar's menu
# button actually run - the scroll daemon, the whole theme system and every
# Raycast command. A no-clone install produced a desktop that looked installed
# and was not.
#
# A list of files cannot be kept correct by discipline alone, so there is no
# list. The archive is whatever is in the repo, which is also one request
# instead of forty: measured at 1.6s for the lot.

[CmdletBinding()]
param(
    [string]$RepoRawBase = "",
    [string]$Branch = "",
    [ValidateSet("minimal", "desktop", "full", "everything", "custom")]
    [string]$Preset,
    [string[]]$Modules,
    [switch]$Yes,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

# Windows PowerShell 5.1 on an untouched machine can still default to TLS 1.0,
# which GitHub refuses.
try {
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch { }

# `irm ... | iex` runs in the caller's scope, so $repo set at the prompt is
# visible here. Fall back through the usual env vars too.
if ([string]::IsNullOrWhiteSpace($RepoRawBase)) {
    foreach ($candidate in @(
        $repo, $script:repo, $global:repo,
        $env:DEV_REPO_RAW, $env:WINDOWS11_DEV_POWERUSER_REPO_RAW
    )) {
        if (-not [string]::IsNullOrWhiteSpace($candidate)) { $RepoRawBase = $candidate; break }
    }
}

if ([string]::IsNullOrWhiteSpace($RepoRawBase) -or $RepoRawBase -like "*<YOUR_USERNAME>*") {
    throw @"
Set -RepoRawBase to your GitHub raw URL, for example:

  `$repo="https://raw.githubusercontent.com/anvu69/windows11-dev-poweruser/main"
  irm "`$repo/scripts/bootstrap-windows.ps1" | iex
"@
}

$RepoRawBase = $RepoRawBase.TrimEnd("/")

# Accept either the raw base the README documents or a plain repo URL, and work
# out owner/repo/branch from it.
$owner = $null; $name = $null; $ref = $Branch
$m = [regex]::Match($RepoRawBase, '^https?://raw\.githubusercontent\.com/([^/]+)/([^/]+)/([^/]+)')
if ($m.Success) {
    $owner = $m.Groups[1].Value; $name = $m.Groups[2].Value
    if (-not $ref) { $ref = $m.Groups[3].Value }
} else {
    $m2 = [regex]::Match($RepoRawBase, '^https?://github\.com/([^/]+)/([^/.]+)')
    if ($m2.Success) {
        $owner = $m2.Groups[1].Value; $name = $m2.Groups[2].Value
        if (-not $ref) { $ref = "main" }
    }
}
if (-not $owner) { throw "Could not work out the repository from '$RepoRawBase'." }

Write-Host "Repository: $owner/$name@$ref" -ForegroundColor Green

$WorkDir = Join-Path $env:TEMP "windows11-dev-poweruser-bootstrap"
if (Test-Path -LiteralPath $WorkDir) { Remove-Item -LiteralPath $WorkDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

$RepoRoot = $null

# --- 1. archive --------------------------------------------------------------
$zip = Join-Path $WorkDir "repo.zip"
$zipUrl = "https://codeload.github.com/$owner/$name/zip/refs/heads/$ref"
Write-Host "Downloading $zipUrl" -ForegroundColor Cyan
try {
    $ProgressPreference = "SilentlyContinue"   # the progress bar makes this ~10x slower
    Invoke-WebRequest -UseBasicParsing -Uri $zipUrl -OutFile $zip
    Expand-Archive -LiteralPath $zip -DestinationPath $WorkDir -Force
    Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue

    # GitHub wraps everything in <repo>-<ref>/.
    $inner = Get-ChildItem -LiteralPath $WorkDir -Directory | Select-Object -First 1
    if ($inner -and (Test-Path -LiteralPath (Join-Path $inner.FullName "scripts\setup.ps1"))) {
        $RepoRoot = $inner.FullName
    }
} catch {
    Write-Host "  archive download failed: $($_.Exception.Message)" -ForegroundColor Yellow
}

# --- 2. git, if the archive did not work -------------------------------------
if (-not $RepoRoot -and (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "Falling back to git clone" -ForegroundColor Cyan
    $clone = Join-Path $WorkDir "repo"
    git clone --depth 1 --branch $ref "https://github.com/$owner/$name.git" $clone 2>&1 | Out-Null
    if (Test-Path -LiteralPath (Join-Path $clone "scripts\setup.ps1")) { $RepoRoot = $clone }
}

if (-not $RepoRoot) {
    throw @"
Could not fetch the repository.

Check the URL and your connection, or clone it yourself and run scripts/setup.ps1:

  git clone https://github.com/$owner/$name.git
  cd $name
  ./scripts/setup.ps1
"@
}

Write-Host "Fetched to $RepoRoot" -ForegroundColor Green

# Hand over to the interactive setup, which detects the machine and offers only
# the modules it can actually run. Everything below here is one code path with
# the cloned-repo experience.
$setupArgs = @{}
if ($Preset)  { $setupArgs["Preset"]  = $Preset }
if ($Modules) { $setupArgs["Modules"] = $Modules }
if ($Yes)     { $setupArgs["Yes"]     = $true }
if ($DryRun)  { $setupArgs["DryRun"]  = $true }

& (Join-Path $RepoRoot "scripts\setup.ps1") @setupArgs
