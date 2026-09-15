# Strip Windows 11 back to something a tiling desktop can live in.
#
#   ./scripts/debloat-windows.ps1 -DryRun      # show what would run
#   ./scripts/debloat-windows.ps1              # apply settings
#   ./scripts/debloat-windows.ps1 -RemoveApps  # also uninstall bundled apps
#
# Wraps Win11Debloat (github.com/Raphire/Raphire/Win11Debloat) rather than
# reimplementing it: it is maintained, widely used, and already knows the
# registry paths. What this script adds is
#   * a pinned version, so a run today matches a run next month
#   * a version-controlled, reviewable profile (configs/windows/debloat.json)
#   * the handful of tiling tweaks Win11Debloat does not cover
#
# Settings changes are reversible (Win11Debloat writes a restore point first,
# and most flags have an inverse). App removal is not, so it is opt-in.

[CmdletBinding()]
param(
    # Pin. Bump deliberately after reading the upstream changelog.
    [string]$Ref = "2026.08.24",
    [switch]$RemoveApps,
    [switch]$DryRun,
    [switch]$NoRestorePoint,
    [switch]$SkipTweaks
)

$ErrorActionPreference = "Stop"

$Repo = Split-Path -Parent $PSScriptRoot

# Not $Profile: that is a PowerShell automatic variable holding the path to
# your shell profile, and shadowing it breaks anything that reads it later.
$ProfilePath = Join-Path $Repo "configs\windows\debloat.json"

if (-not (Test-Path -LiteralPath $ProfilePath)) { throw "Missing profile: $ProfilePath" }

# Apps removed only when -RemoveApps is given. Keep this list conservative:
# everything here is a bundled consumer app with no role in a dev setup.
$AppsToRemove = @(
    "Clipchamp.Clipchamp"
    "Microsoft.BingNews"
    "Microsoft.BingWeather"
    "Microsoft.BingSearch"
    "Microsoft.GamingApp"
    "Microsoft.GetHelp"
    "Microsoft.Getstarted"
    "Microsoft.MicrosoftOfficeHub"
    "Microsoft.MicrosoftSolitaireCollection"
    "Microsoft.People"
    "Microsoft.PowerAutomateDesktop"
    "Microsoft.Todos"
    "Microsoft.WindowsFeedbackHub"
    "Microsoft.WindowsMaps"
    "Microsoft.Xbox.TCUI"
    "Microsoft.XboxGameOverlay"
    "Microsoft.XboxGamingOverlay"
    "Microsoft.XboxIdentityProvider"
    "Microsoft.XboxSpeechToTextOverlay"
    "Microsoft.ZuneMusic"
    "Microsoft.ZuneVideo"
    "MicrosoftCorporationII.MicrosoftFamily"
    "MicrosoftTeams"
    "MSTeams"
) -join ','

Write-Host "Win11Debloat wrapper" -ForegroundColor Green
Write-Host "  pinned ref : $Ref"
Write-Host "  profile    : $ProfilePath"
Write-Host "  app removal: $(if ($RemoveApps) { 'YES' } else { 'no (pass -RemoveApps)' })"

# --- Fetch a pinned copy -----------------------------------------------------
$work = Join-Path $env:TEMP "win11debloat-$Ref"
$entry = Join-Path $work "Win11Debloat-$Ref\Win11Debloat.ps1"

if (-not (Test-Path -LiteralPath $entry)) {
    if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $work | Out-Null

    $zip = Join-Path $work "src.zip"
    $url = "https://github.com/Raphire/Win11Debloat/archive/refs/tags/$Ref.zip"
    Write-Host "`nDownloading $url" -ForegroundColor Cyan
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $zip
    Expand-Archive -LiteralPath $zip -DestinationPath $work -Force
}

if (-not (Test-Path -LiteralPath $entry)) {
    throw "Win11Debloat.ps1 not found after extracting $Ref. Check the tag name."
}

# --- Build the argument list -------------------------------------------------
$argList = @("-Silent", "-Config", $ProfilePath)
if ($RemoveApps)     { $argList += @("-RemoveApps", "-Apps", $AppsToRemove) }
if ($NoRestorePoint) { $argList = $argList | Where-Object { $_ -ne "-CreateRestorePoint" } }

Write-Host "`nWould run:" -ForegroundColor Magenta
Write-Host "  $entry $($argList -join ' ')" -ForegroundColor DarkGray

if ($DryRun) {
    Write-Host "`nSettings in the profile:" -ForegroundColor Magenta
    (Get-Content -LiteralPath $ProfilePath -Raw | ConvertFrom-Json).Settings |
        ForEach-Object { Write-Host ("  -{0}" -f $_.Name) -ForegroundColor DarkGray }
    if ($RemoveApps) {
        Write-Host "`nApps that would be removed:" -ForegroundColor Magenta
        $AppsToRemove -split ',' | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
    }
    Write-Host "`nDry run - nothing was changed." -ForegroundColor Yellow
    return
}

Write-Host ""
& $entry @argList

# --- Tweaks Win11Debloat does not cover --------------------------------------
if (-not $SkipTweaks) {
    Write-Host "`n[extra tweaks]" -ForegroundColor Magenta

    # Auto-hide the Windows taskbar. yasb already occupies the top edge and
    # reserves its own space via the AppBar API; a second permanent bar just
    # eats rows from every tiled window.
    $sr = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3"
    try {
        $settings = (Get-ItemProperty -Path $sr -Name Settings -ErrorAction Stop).Settings
        if (($settings[8] -band 0x08) -eq 0x08) {
            Write-Host "  = taskbar already auto-hides" -ForegroundColor DarkGray
        } else {
            $settings[8] = $settings[8] -bor 0x08
            Set-ItemProperty -Path $sr -Name Settings -Value $settings
            Write-Host "  + taskbar set to auto-hide" -ForegroundColor Green
        }
    } catch {
        Write-Host "  ! could not set taskbar auto-hide: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    # komorebi cannot manage what Explorer paints on the desktop, and the
    # search highlight repaints the taskbar on a timer.
    $sr2 = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds"
    if (-not (Test-Path $sr2)) { New-Item -Path $sr2 -Force | Out-Null }
    Set-ItemProperty -Path $sr2 -Name "ShellFeedsTaskbarViewMode" -Value 2 -Type DWord
    Write-Host "  + news and interests off" -ForegroundColor Green

    $dsh = "HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings"
    if (-not (Test-Path $dsh)) { New-Item -Path $dsh -Force | Out-Null }
    Set-ItemProperty -Path $dsh -Name "IsDynamicSearchBoxEnabled" -Value 0 -Type DWord
    Write-Host "  + search highlights off" -ForegroundColor Green

    Write-Host "`n  Restart Explorer for these to take effect:" -ForegroundColor Yellow
    Write-Host "    Stop-Process -Name explorer -Force" -ForegroundColor Cyan
}

Write-Host ""
Write-Host "Done. Verify with: ./scripts/doctor.ps1" -ForegroundColor Green
