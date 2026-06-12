# Symlink/copy config files into Windows locations.
# Run from repo root in PowerShell.

$Repo = Split-Path -Parent $PSScriptRoot

function Ensure-Dir($Path) {
  if (!(Test-Path $Path)) { New-Item -ItemType Directory -Force -Path $Path | Out-Null }
}

Ensure-Dir "$env:APPDATA\alacritty"
Ensure-Dir "$env:USERPROFILE\.config"
Ensure-Dir "$env:USERPROFILE\.ssh"

Copy-Item "$Repo\configs\alacritty\alacritty.toml" "$env:APPDATA\alacritty\alacritty.toml" -Force
Copy-Item "$Repo\configs\ssh\config.example" "$env:USERPROFILE\.ssh\config.example" -Force

Write-Host "Copied Alacritty config and SSH config example." -ForegroundColor Green
Write-Host "Review SSH config.example before renaming to config." -ForegroundColor Yellow
