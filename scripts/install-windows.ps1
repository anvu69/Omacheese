# Windows 11 developer power-user install script
# Run in PowerShell 7 or Windows PowerShell.

$ErrorActionPreference = "Stop"

$apps = @(
  # Terminal / shell / git
  "Alacritty.Alacritty",
  "Git.Git",
  "Microsoft.PowerShell",

  # Window manager stack
  "LGUG2Z.komorebi",
  "LGUG2Z.whkd",
  "AmN.yasb",

  # Productivity
  "voidtools.Everything",
  "Brave.Brave",
  "Bitwarden.Bitwarden",
  "electerm.electerm",
  "dbeaver.dbeaver",
  "7zip.7zip"
)

foreach ($app in $apps) {
  Write-Host "Installing $app..." -ForegroundColor Cyan
  winget install --id $app -e --accept-source-agreements --accept-package-agreements
}

Write-Host "\nDone. Next steps:" -ForegroundColor Green
Write-Host "1. Install WSL2 AlmaLinux."
Write-Host "2. Enable Bitwarden Desktop SSH Agent."
Write-Host "3. Copy/link configs using scripts/link-configs.ps1."
