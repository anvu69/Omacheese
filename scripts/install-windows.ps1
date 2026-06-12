# Windows 11 developer power-user install script
# Run in PowerShell 7 or Windows PowerShell.

$ErrorActionPreference = "Stop"

$apps = @(
  # Terminal / shell / git
  "Alacritty.Alacritty",
  "Git.Git",
  "Microsoft.PowerShell",
  "JanDeDobbeleer.OhMyPosh",
  "DEVCOM.JetBrainsMonoNerdFont",

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
  "7zip.7zip",
  "junegunn.fzf",
  "ajeetdsouza.zoxide",
  "eza-community.eza",
  "sharkdp.bat"
)

foreach ($app in $apps) {
  Write-Host "Installing $app..." -ForegroundColor Cyan
  winget install --id $app -e --accept-source-agreements --accept-package-agreements
}


Write-Host "Installing PowerShell modules..." -ForegroundColor Cyan
try {
  Install-Module PSReadLine -Scope CurrentUser -Force -AllowClobber
  Install-Module Terminal-Icons -Scope CurrentUser -Force -AllowClobber
} catch {
  Write-Warning "PowerShell module install failed. You can rerun: Install-Module PSReadLine, Terminal-Icons"
}

Write-Host "\nDone. Next steps:" -ForegroundColor Green
Write-Host "1. Install WSL2 AlmaLinux."
Write-Host "2. Enable Bitwarden Desktop SSH Agent."
Write-Host "3. Copy/link configs using scripts/link-configs.ps1."
Write-Host "4. Restart PowerShell to load Oh My Posh profile."
