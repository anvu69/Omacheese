# Symlink/copy config files into Windows locations.
# Run from repo root in PowerShell.

$Repo = Split-Path -Parent $PSScriptRoot

function Ensure-Dir($Path) {
  if (!(Test-Path $Path)) { New-Item -ItemType Directory -Force -Path $Path | Out-Null }
}

Ensure-Dir "$env:APPDATA\alacritty"
Ensure-Dir "$env:USERPROFILE\.config"
Ensure-Dir "$env:USERPROFILE\.ssh"
Ensure-Dir "$env:USERPROFILE\.config\oh-my-posh"

Copy-Item "$Repo\configs\alacritty\alacritty.toml" "$env:APPDATA\alacritty\alacritty.toml" -Force
Copy-Item "$Repo\configs\ssh\config.example" "$env:USERPROFILE\.ssh\config.example" -Force
Copy-Item "$Repo\configs\oh-my-posh\poweruser.omp.json" "$env:USERPROFILE\.config\oh-my-posh\poweruser.omp.json" -Force

$ProfileDir = Split-Path -Parent $PROFILE
Ensure-Dir $ProfileDir
Copy-Item "$Repo\configs\powershell\Microsoft.PowerShell_profile.ps1" $PROFILE -Force

Write-Host "Copied Alacritty, Oh My Posh, PowerShell profile, and SSH config example." -ForegroundColor Green
Write-Host "Review SSH config.example before renaming to config." -ForegroundColor Yellow
Write-Host "Restart PowerShell to load Oh My Posh and aliases." -ForegroundColor Yellow
