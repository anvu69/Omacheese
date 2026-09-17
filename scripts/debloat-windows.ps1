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
    [switch]$SkipTweaks,

    # Set only by the elevated relaunch below, so the new window stays up long
    # enough to read. Nothing else should pass it.
    [switch]$Pause
)

$ErrorActionPreference = "Stop"

# The elevated relaunch gets its own window, and an error under
# ErrorActionPreference=Stop ends the script - so that window disappears with
# the message still on it. From the outside the whole step reads as "it opens a
# PowerShell window and fails", which is exactly how the argument-splatting bug
# below presented, and why it took a transcript to find.
trap {
    if ($Pause) {
        Write-Host ""
        Write-Host $_.Exception.Message -ForegroundColor Red
        Write-Host ""
        Read-Host "Enter to close" | Out-Null
    }
    break
}

# --- host and elevation ------------------------------------------------------
# Win11Debloat is a Windows PowerShell 5.1 script and says so: it calls
# Get-AppxPackage and Get-ComputerRestorePoint, and under pwsh 7 the Appx module
# fails with "Operation is not supported on this platform" (0x80131539). Recent
# versions refuse to start at all when $PSVersionTable.PSEdition is 'Core'.
#
# That is not hypothetical here. setup.ps1 runs every step in the host it was
# itself started from, so installing PowerShell 7 by hand and re-running the
# setup from pwsh - the obvious move when the one-liner fails - is exactly what
# turns this step into a hard failure.
#
# It also needs admin, and upstream asks for it with `Read-Host "Restart as
# Administrator? (y/n)"`. As a setup step with its output redirected to a log,
# that is an invisible question, and the installer stops dead until someone
# guesses to press Enter. Decide both here, before anything is downloaded.
$isCore = ($PSVersionTable.PSEdition -eq "Core")
$isElevated = (New-Object Security.Principal.WindowsPrincipal(
    [Security.Principal.WindowsIdentity]::GetCurrent())
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (($isCore -or -not $isElevated) -and $PSCommandPath) {
    $winPs = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    if (-not (Test-Path -LiteralPath $winPs)) {
        throw "Windows PowerShell 5.1 not found at $winPs, and Win11Debloat cannot run under pwsh."
    }

    $relaunch = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$PSCommandPath`"")
    foreach ($k in $PSBoundParameters.Keys) {
        if ($k -eq "Pause") { continue }
        $v = $PSBoundParameters[$k]
        if ($v -is [switch]) {
            if ($v.IsPresent) { $relaunch += "-$k" }
        } else {
            $relaunch += @("-$k", "`"$v`"")
        }
    }

    if ($isElevated) {
        Write-Host "Re-running under Windows PowerShell 5.1 (Win11Debloat needs the Appx module)." -ForegroundColor Yellow
        $p = Start-Process -FilePath $winPs -ArgumentList $relaunch -NoNewWindow -PassThru -Wait
    } else {
        Write-Host "Win11Debloat needs administrator. Accepting the UAC prompt opens a new window." -ForegroundColor Yellow
        try {
            $p = Start-Process -FilePath $winPs -ArgumentList ($relaunch + "-Pause") -Verb RunAs -PassThru -Wait
        } catch {
            # Declining UAC throws. Say what happened rather than letting a raw
            # "The operation was canceled by the user" be the whole story.
            Write-Host "Elevation was declined - nothing was changed." -ForegroundColor Yellow
            Write-Host "Run this from an elevated Windows PowerShell to apply it." -ForegroundColor DarkGray
            exit 1
        }
    }
    exit $p.ExitCode
}

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

# --- Build the arguments -----------------------------------------------------
# A HASHTABLE, splatted. An array splat passes its elements POSITIONALLY - it
# does not re-read the ones starting with a dash as parameter names - and
# Win11Debloat's first three string parameters are LogPath, User and Config, so
#   & $entry @("-Silent", "-Config", $path)
# bound LogPath="-Silent", User="-Config", Config=$path and died inside
# Win11Debloat with "User -Config was not found". -DryRun never showed it
# because it returns before the call.
$w11 = @{ Silent = $true; Config = $ProfilePath }
if ($RemoveApps) {
    $w11.RemoveApps = $true
    $w11.Apps       = $AppsToRemove
}

# CreateRestorePoint comes from the profile, not from this command line, so the
# old `Where-Object { $_ -ne "-CreateRestorePoint" }` filtered a string that was
# never in the list: -NoRestorePoint did nothing at all. Take the setting out of
# a copy of the profile instead, which is where it actually lives.
if ($NoRestorePoint) {
    $cfg = Get-Content -LiteralPath $ProfilePath -Raw | ConvertFrom-Json
    $cfg.Deployment = @($cfg.Deployment | Where-Object { $_.Name -ne "CreateRestorePoint" })
    $ProfilePath  = Join-Path $env:TEMP "debloat-norestore.json"
    $cfg | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $ProfilePath -Encoding UTF8
    $w11.Config   = $ProfilePath
    Write-Host "  restore point: skipped (profile copied to $ProfilePath)" -ForegroundColor Yellow
}

# Printed from the same hashtable the call uses, so the preview cannot drift
# from what runs.
$preview = ($w11.GetEnumerator() | Sort-Object Name | ForEach-Object {
    if ($_.Value -is [bool]) { "-$($_.Key)" } else { "-$($_.Key) $($_.Value)" }
}) -join " "
Write-Host "`nWould run:" -ForegroundColor Magenta
Write-Host "  $entry $preview" -ForegroundColor DarkGray

if ($DryRun) {
    $cfgShown = Get-Content -LiteralPath $ProfilePath -Raw | ConvertFrom-Json
    Write-Host "`nSettings in the profile:" -ForegroundColor Magenta
    @($cfgShown.Deployment) + @($cfgShown.Tweaks) |
        Where-Object { $_ } |
        ForEach-Object { Write-Host ("  -{0}" -f $_.Name) -ForegroundColor DarkGray }
    if ($RemoveApps) {
        Write-Host "`nApps that would be removed:" -ForegroundColor Magenta
        $AppsToRemove -split ',' | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
    }
    Write-Host "`nDry run - nothing was changed." -ForegroundColor Yellow
    if ($Pause) { Read-Host "`nEnter to close" | Out-Null }
    return
}

Write-Host ""
& $entry @w11

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

# Only set by the elevated relaunch: without it that window closes the instant
# it finishes and nobody ever sees what it did.
if ($Pause) { Read-Host "`nEnter to close" | Out-Null }
