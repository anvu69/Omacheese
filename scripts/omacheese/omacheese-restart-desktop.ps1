# Omarchy SUPER+CTRL+R: restart the whole desktop stack.
# Delegates to the repo's start-desktop.ps1 so there is one startup path.

$ErrorActionPreference = "SilentlyContinue"

$start = Join-Path $env:USERPROFILE ".config\omacheese\bin\start-desktop.ps1"

if (-not (Test-Path -LiteralPath $start)) {
    Write-Host "start-desktop.ps1 not installed at $start" -ForegroundColor Red
    exit 1
}

& $start -Restart
