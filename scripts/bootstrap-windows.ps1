<#
Bootstrap Windows-side setup without cloning the full repo.

Recommended one-liner:
  $repo="https://raw.githubusercontent.com/<USER>/windows11-dev-poweruser/main"; irm "$repo/scripts/bootstrap-windows.ps1" | iex

Alternative one-liner using env var:
  $env:DEV_REPO_RAW="https://raw.githubusercontent.com/<USER>/windows11-dev-poweruser/main"; irm "$env:DEV_REPO_RAW/scripts/bootstrap-windows.ps1" | iex

Safer usage:
  $repo = "https://raw.githubusercontent.com/<USER>/windows11-dev-poweruser/main"
  irm "$repo/scripts/bootstrap-windows.ps1" -OutFile "$env:TEMP\bootstrap-windows.ps1"
  notepad "$env:TEMP\bootstrap-windows.ps1"
  powershell -ExecutionPolicy Bypass -File "$env:TEMP\bootstrap-windows.ps1" -RepoRawBase $repo
#>

param(
  [string]$RepoRawBase = "",
  [switch]$SkipInstall,
  [switch]$SkipConfigs
)

$ErrorActionPreference = "Stop"

function Resolve-RepoRawBase {
  param([string]$InputValue)

  if ($InputValue -and $InputValue -notlike "*<YOUR_USERNAME>*") {
    return $InputValue.TrimEnd("/")
  }

  # Supports: $repo="https://raw.githubusercontent.com/.../main"; irm "$repo/scripts/bootstrap-windows.ps1" | iex
  $repoVar = Get-Variable -Name repo -ErrorAction SilentlyContinue
  if ($repoVar -and $repoVar.Value -and $repoVar.Value -notlike "*<YOUR_USERNAME>*") {
    return ([string]$repoVar.Value).TrimEnd("/")
  }

  # Supports: $env:DEV_REPO_RAW="https://raw.githubusercontent.com/.../main"; irm "$env:DEV_REPO_RAW/scripts/bootstrap-windows.ps1" | iex
  if ($env:DEV_REPO_RAW -and $env:DEV_REPO_RAW -notlike "*<YOUR_USERNAME>*") {
    return $env:DEV_REPO_RAW.TrimEnd("/")
  }

  # More explicit env var name for this repo.
  if ($env:WINDOWS11_DEV_POWERUSER_REPO_RAW -and $env:WINDOWS11_DEV_POWERUSER_REPO_RAW -notlike "*<YOUR_USERNAME>*") {
    return $env:WINDOWS11_DEV_POWERUSER_REPO_RAW.TrimEnd("/")
  }

  throw @"
RepoRawBase is missing.

Use one of these:

  `$repo="https://raw.githubusercontent.com/anvu69/windows11-dev-poweruser/main"; irm "`$repo/scripts/bootstrap-windows.ps1" | iex

or:

  irm "https://raw.githubusercontent.com/anvu69/windows11-dev-poweruser/main/scripts/bootstrap-windows.ps1" -OutFile "`$env:TEMP\bootstrap-windows.ps1"
  powershell -ExecutionPolicy Bypass -File "`$env:TEMP\bootstrap-windows.ps1" -RepoRawBase "https://raw.githubusercontent.com/anvu69/windows11-dev-poweruser/main"
"@
}

function Ensure-Dir([string]$Path) {
  if (!(Test-Path $Path)) {
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
  }
}

function Fetch([string]$RemotePath, [string]$LocalPath) {
  $uri = "$RepoRawBase/$RemotePath"
  Ensure-Dir (Split-Path -Parent $LocalPath)
  Write-Host "Downloading $RemotePath" -ForegroundColor Cyan
  Invoke-WebRequest -UseBasicParsing -Uri $uri -OutFile $LocalPath
}

$RepoRawBase = Resolve-RepoRawBase -InputValue $RepoRawBase
Write-Host "Using repo raw base: $RepoRawBase" -ForegroundColor DarkGray

$WorkDir = Join-Path $env:TEMP "windows11-dev-poweruser-bootstrap"
if (Test-Path $WorkDir) { Remove-Item $WorkDir -Recurse -Force }
Ensure-Dir $WorkDir

if (!$SkipInstall) {
  $InstallScript = Join-Path $WorkDir "install-windows.ps1"
  Fetch "scripts/install-windows.ps1" $InstallScript
  powershell -ExecutionPolicy Bypass -File $InstallScript
}

if (!$SkipConfigs) {
  $files = @(
    "configs/alacritty/alacritty.toml",
    "configs/ssh/config.example",
    "configs/oh-my-posh/poweruser.omp.json",
    "configs/powershell/Microsoft.PowerShell_profile.ps1"
  )

  foreach ($file in $files) {
    Fetch $file (Join-Path $WorkDir $file)
  }

  Ensure-Dir "$env:APPDATA\alacritty"
  Ensure-Dir "$env:USERPROFILE\.ssh"
  Ensure-Dir "$env:USERPROFILE\.config\oh-my-posh"

  Copy-Item (Join-Path $WorkDir "configs/alacritty/alacritty.toml") "$env:APPDATA\alacritty\alacritty.toml" -Force
  Copy-Item (Join-Path $WorkDir "configs/ssh/config.example") "$env:USERPROFILE\.ssh\config.example" -Force
  Copy-Item (Join-Path $WorkDir "configs/oh-my-posh/poweruser.omp.json") "$env:USERPROFILE\.config\oh-my-posh\poweruser.omp.json" -Force

  $ProfileDir = Split-Path -Parent $PROFILE
  Ensure-Dir $ProfileDir
  Copy-Item (Join-Path $WorkDir "configs/powershell/Microsoft.PowerShell_profile.ps1") $PROFILE -Force
}

Write-Host "Windows bootstrap complete." -ForegroundColor Green
Write-Host "Review ~/.ssh/config.example before renaming it to config." -ForegroundColor Yellow
Write-Host "Restart PowerShell/Alacritty after install." -ForegroundColor Yellow
