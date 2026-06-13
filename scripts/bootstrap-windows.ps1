param(
  [string]$RepoRawBase = "",
  [switch]$SkipInstall,
  [switch]$SkipConfigs
)

$ErrorActionPreference = "Stop"

function Ensure-Dir {
  param([string]$Path)

  if (!(Test-Path $Path)) {
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
  }
}

function Download-File {
  param(
    [string]$RemotePath,
    [string]$LocalPath
  )

  $uri = "$RepoRawBase/$RemotePath"
  Write-Host "Downloading $RemotePath" -ForegroundColor Cyan

  Ensure-Dir (Split-Path -Parent $LocalPath)
  Invoke-WebRequest -UseBasicParsing -Uri $uri -OutFile $LocalPath
}

if ([string]::IsNullOrWhiteSpace($RepoRawBase)) {
  if ($script:repo) {
    $RepoRawBase = $script:repo
  } elseif ($global:repo) {
    $RepoRawBase = $global:repo
  } elseif ($env:DEV_REPO_RAW) {
    $RepoRawBase = $env:DEV_REPO_RAW
  } elseif ($env:WINDOWS11_DEV_POWERUSER_REPO_RAW) {
    $RepoRawBase = $env:WINDOWS11_DEV_POWERUSER_REPO_RAW
  }
}

if ([string]::IsNullOrWhiteSpace($RepoRawBase) -or $RepoRawBase -like "*<YOUR_USERNAME>*") {
  throw "Set -RepoRawBase to your GitHub raw URL, for example: https://raw.githubusercontent.com/anvu69/windows11-dev-poweruser/main"
}

$RepoRawBase = $RepoRawBase.TrimEnd("/")

Write-Host "Using repo raw base: $RepoRawBase" -ForegroundColor Green

if (!$SkipInstall) {
  $apps = @(
    "Alacritty.Alacritty",
    "LGUG2Z.komorebi",
    "LGUG2Z.whkd",
    "amnweb.yasb",
    "Microsoft.PowerShell",
    "JanDeDobbeleer.OhMyPosh",
    "DEVCOM.JetBrainsMonoNerdFont",
    "voidtools.Everything",
    "Brave.Brave",
    "dbeaver.dbeaver",
    "electerm.electerm",
    "Bitwarden.Bitwarden"
  )

  foreach ($app in $apps) {
    Write-Host "Installing $app" -ForegroundColor Cyan
    winget install --id $app -e --accept-source-agreements --accept-package-agreements
  }
}

if (!$SkipConfigs) {
  $WorkDir = Join-Path $env:TEMP "windows11-dev-poweruser-bootstrap"

  if (Test-Path $WorkDir) {
    Remove-Item $WorkDir -Recurse -Force
  }

  Ensure-Dir $WorkDir

  $files = @(
    "configs/alacritty/alacritty.toml",
    "configs/ssh/config.example",
    "configs/oh-my-posh/poweruser.omp.json",
    "configs/powershell/Microsoft.PowerShell_profile.ps1",
    "configs/komorebi/komorebi.json",
    "configs/whkd/whkdrc",
    "configs/yasb/config.yaml",
    "scripts/start-desktop.ps1"
  )

  foreach ($file in $files) {
    Download-File $file (Join-Path $WorkDir $file)
  }

  Ensure-Dir "$env:APPDATA\alacritty"
  Ensure-Dir "$env:USERPROFILE\.ssh"
  Ensure-Dir "$env:USERPROFILE\.config"
  Ensure-Dir "$env:USERPROFILE\.config\komorebi"
  Ensure-Dir "$env:USERPROFILE\.config\yasb"
  Ensure-Dir "$env:USERPROFILE\.config\oh-my-posh"
  Ensure-Dir "$env:USERPROFILE\.config\windows11-dev-poweruser"

  # Environment variables
  $KomorebiConfigHome = "$env:USERPROFILE\.config\komorebi"

  [Environment]::SetEnvironmentVariable(
    "KOMOREBI_CONFIG_HOME",
    $KomorebiConfigHome,
    [EnvironmentVariableTarget]::User
  )

  $env:KOMOREBI_CONFIG_HOME = $KomorebiConfigHome

  # Alacritty
  Copy-Item `
    (Join-Path $WorkDir "configs/alacritty/alacritty.toml") `
    "$env:APPDATA\alacritty\alacritty.toml" `
    -Force

  # SSH example only
  Copy-Item `
    (Join-Path $WorkDir "configs/ssh/config.example") `
    "$env:USERPROFILE\.ssh\config.example" `
    -Force

  # Oh My Posh
  Copy-Item `
    (Join-Path $WorkDir "configs/oh-my-posh/poweruser.omp.json") `
    "$env:USERPROFILE\.config\oh-my-posh\poweruser.omp.json" `
    -Force

  # komorebi
  Copy-Item `
    (Join-Path $WorkDir "configs/komorebi/komorebi.json") `
    "$env:USERPROFILE\.config\komorebi\komorebi.json" `
    -Force

  # whkd default path:
  # whkd reads C:\Users\<USER>\.config\whkdrc by default.
  Copy-Item `
    (Join-Path $WorkDir "configs/whkd/whkdrc") `
    "$env:USERPROFILE\.config\whkdrc" `
    -Force

  # YASB
  Copy-Item `
    (Join-Path $WorkDir "configs/yasb/config.yaml") `
    "$env:USERPROFILE\.config\yasb\config.yaml" `
    -Force

  # Start helper
  Copy-Item `
    (Join-Path $WorkDir "scripts/start-desktop.ps1") `
    "$env:USERPROFILE\.config\windows11-dev-poweruser\start-desktop.ps1" `
    -Force

  # PowerShell 7 profile only.
  # Do NOT copy into Documents\WindowsPowerShell because that is Windows PowerShell 5.1.
  $PwshProfile = "$env:USERPROFILE\Documents\PowerShell\Microsoft.PowerShell_profile.ps1"
  $PwshProfileDir = Split-Path -Parent $PwshProfile
  Ensure-Dir $PwshProfileDir

  Copy-Item `
    (Join-Path $WorkDir "configs/powershell/Microsoft.PowerShell_profile.ps1") `
    $PwshProfile `
    -Force

  Write-Host ""
  Write-Host "Configs installed." -ForegroundColor Green
  Write-Host "PowerShell profile installed only for PowerShell 7: $PwshProfile" -ForegroundColor Yellow
  Write-Host "whkd config installed at: $env:USERPROFILE\.config\whkdrc" -ForegroundColor Yellow
  Write-Host "KOMOREBI_CONFIG_HOME=$env:KOMOREBI_CONFIG_HOME" -ForegroundColor Yellow
}