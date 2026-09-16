# Kept so the older documented URL still works.
#
# The install entry point is now install.ps1 at the repo root, because that is
# the shortest URL the repo can offer and it needs no $repo variable set first:
#
#   irm https://raw.githubusercontent.com/anvu69/windows11-dev-poweruser/main/install.ps1 | iex
#
# This forwards to it. If you are reading this because you saved the old
# one-liner, switch to the one above.

[CmdletBinding()]
param(
    # The old parameter: a raw base URL like
    # https://raw.githubusercontent.com/<owner>/<name>/<branch>
    [string]$RepoRawBase = "",
    [string]$Repo = "anvu69/windows11-dev-poweruser",
    [string]$Branch = "main",

    [ValidateSet("minimal", "desktop", "full", "everything", "custom")]
    [string]$Preset,
    [string[]]$Modules,
    [switch]$Yes,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

try {
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch { }

# `irm ... | iex` runs in the caller's scope, so a $repo set at the prompt is
# visible here - that is how the old one-liner passed the URL.
if ([string]::IsNullOrWhiteSpace($RepoRawBase)) {
    foreach ($candidate in @($repo, $script:repo, $global:repo,
                             $env:DEV_REPO_RAW, $env:WINDOWS11_DEV_POWERUSER_REPO_RAW)) {
        if (-not [string]::IsNullOrWhiteSpace($candidate)) { $RepoRawBase = $candidate; break }
    }
}

# Translate the old raw-base form into owner/name + branch.
if (-not [string]::IsNullOrWhiteSpace($RepoRawBase)) {
    $m = [regex]::Match($RepoRawBase.TrimEnd("/"),
        '^https?://raw\.githubusercontent\.com/([^/]+)/([^/]+)/([^/]+)')
    if (-not $m.Success) {
        $m = [regex]::Match($RepoRawBase.TrimEnd("/"), '^https?://github\.com/([^/]+)/([^/.]+)')
    }
    if ($m.Success) {
        $Repo = "$($m.Groups[1].Value)/$($m.Groups[2].Value)"
        if ($m.Groups.Count -gt 3 -and $m.Groups[3].Success) { $Branch = $m.Groups[3].Value }
    }
}

$owner, $name = $Repo.Split("/")
$installUrl = "https://raw.githubusercontent.com/$owner/$name/$Branch/install.ps1"

Write-Host "This script moved to install.ps1 at the repo root:" -ForegroundColor Yellow
Write-Host "  irm $installUrl | iex" -ForegroundColor Cyan
Write-Host ""

# Prefer the copy next to us when running from a clone, otherwise fetch it.
$local = Join-Path (Split-Path (Split-Path $PSCommandPath -Parent) -Parent) "install.ps1"
$forward = @{ Repo = $Repo; Branch = $Branch }
if ($Preset)  { $forward["Preset"]  = $Preset }
if ($Modules) { $forward["Modules"] = $Modules }
if ($Yes)     { $forward["Yes"]     = $true }
if ($DryRun)  { $forward["DryRun"]  = $true }

if ($PSCommandPath -and (Test-Path -LiteralPath $local)) {
    & $local @forward
} else {
    $tmp = Join-Path $env:TEMP "windows11-dev-poweruser-install.ps1"
    Invoke-WebRequest -UseBasicParsing -Uri $installUrl -OutFile $tmp
    & $tmp @forward
}
