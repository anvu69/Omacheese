# Omarchy SUPER+CTRL+B: show/hide the status bar.
# yasb has no toggle command, so this stops or starts the process.

$ErrorActionPreference = "SilentlyContinue"

$running = Get-Process yasb -ErrorAction SilentlyContinue

if ($running) {
    $running | Stop-Process -Force
    exit 0
}

$yasb = Get-Command yasb.exe -ErrorAction SilentlyContinue
if (-not $yasb) {
    $fallback = "$env:ProgramFiles\YASB\yasb.exe"
    if (Test-Path -LiteralPath $fallback) { $yasb = $fallback } else { exit 1 }
} else {
    $yasb = $yasb.Source
}

Start-Process -FilePath $yasb -WindowStyle Hidden
