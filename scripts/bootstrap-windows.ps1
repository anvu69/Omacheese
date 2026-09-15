# Bootstrap the Windows side straight from GitHub Raw, without cloning.
#
#   $repo="https://raw.githubusercontent.com/anvu69/windows11-dev-poweruser/main"
#   irm "$repo/scripts/bootstrap-windows.ps1" | iex
#
# This downloads the repo's scripts and configs into a temp directory and then
# runs the SAME install-windows.ps1 / link-configs.ps1 the cloned repo uses.
# The previous version re-declared its own package list, which is how it ended
# up shipping a yasb id that does not exist ("amnweb.yasb") and silently
# skipping git, fzf, zoxide, eza and bat. There is now exactly one list:
# configs/winget/packages.json.

[CmdletBinding()]
param(
    [string]$RepoRawBase = "",
    [ValidateSet("core", "wm", "cli", "ai", "desktop")]
    [string[]]$Groups,
    [switch]$SkipInstall,
    [switch]$SkipConfigs,
    [switch]$NoAutostart
)

$ErrorActionPreference = "Stop"

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
Write-Host "Repo raw base: $RepoRawBase" -ForegroundColor Green

$WorkDir = Join-Path $env:TEMP "windows11-dev-poweruser-bootstrap"
if (Test-Path -LiteralPath $WorkDir) { Remove-Item -LiteralPath $WorkDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

function Get-RepoFile {
    param([Parameter(Mandatory)][string]$Path)
    $dest = Join-Path $WorkDir $Path
    $dir  = Split-Path -Parent $dest
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    Write-Host "  . $Path" -ForegroundColor DarkGray
    Invoke-WebRequest -UseBasicParsing -Uri "$RepoRawBase/$Path" -OutFile $dest
}

# Everything install-windows.ps1 and link-configs.ps1 touch.
$files = @(
    "scripts/lib/common.ps1"
    "scripts/install-windows.ps1"
    "scripts/link-configs.ps1"
    "scripts/start-desktop.ps1"
    "scripts/doctor.ps1"
    "scripts/omarchy/omarchy-menu.ps1"
    "scripts/omarchy/omarchy-keybindings.ps1"
    "scripts/omarchy/omarchy-scratchpad.ps1"
    "scripts/omarchy/omarchy-stack-toggle.ps1"
    "scripts/omarchy/omarchy-toggle-bar.ps1"
    "scripts/omarchy/omarchy-restart-desktop.ps1"
    "scripts/omarchy/omarchy-agent.ps1"
    "scripts/omarchy/omarchy-default-agent.ps1"
    "configs/winget/packages.json"
    "configs/alacritty/alacritty.toml"
    "configs/alacritty/alacritty.wsl.toml"
    "configs/komorebi/komorebi.json"
    "configs/whkd/whkdrc"
    "configs/yasb/config.yaml"
    "configs/yasb/styles.css"
    "configs/oh-my-posh/poweruser.omp.json"
    "configs/powershell/Microsoft.PowerShell_profile.ps1"
    "configs/git/gitconfig"
    "configs/ssh/config.example"
    "configs/wsl/.wslconfig"
    "configs/wsl/wsl.conf"
    "configs/wsl/ssh-agent-bridge.sh"
)

Write-Host "`nDownloading repo files" -ForegroundColor Cyan
foreach ($f in $files) { Get-RepoFile $f }

if (-not $SkipInstall) {
    Write-Host "`nInstalling packages" -ForegroundColor Cyan
    & (Join-Path $WorkDir "scripts/install-windows.ps1") -Groups $Groups
}

if (-not $SkipConfigs) {
    Write-Host "`nInstalling configs" -ForegroundColor Cyan
    # Always copy here. Symlinking would point at $WorkDir under %TEMP%, which
    # the next bootstrap run deletes - the configs would quietly vanish.
    # Clone the repo and use link-configs.ps1 if you want live-editable links.
    & (Join-Path $WorkDir "scripts/link-configs.ps1") -Copy -NoAutostart:$NoAutostart
}

Write-Host ""
Write-Host "Bootstrap complete." -ForegroundColor Green
Write-Host "Configs were COPIED. Clone the repo and run link-configs.ps1 if you" -ForegroundColor DarkGray
Write-Host "want edits in the repo to take effect without reinstalling." -ForegroundColor DarkGray
Write-Host ""
Write-Host "Verify with: & `"$WorkDir/scripts/doctor.ps1`"" -ForegroundColor Cyan
