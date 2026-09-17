# Strip Windows 11 back to something a tiling desktop can live in.
#
#   ./scripts/debloat-windows.ps1                        # pick groups, then apply
#   ./scripts/debloat-windows.ps1 -DryRun                # show the plan, change nothing
#   ./scripts/debloat-windows.ps1 -Groups tiling,privacy # no prompt
#   ./scripts/debloat-windows.ps1 -All                   # every group, plus the apps
#
# Wraps Win11Debloat (github.com/Raphire/Raphire/Win11Debloat) rather than
# reimplementing it: it is maintained, widely used, and already knows the
# registry paths. What this script adds is
#   * a pinned version, so a run today matches a run next month
#   * a version-controlled, reviewable profile (configs/windows/debloat.json)
#   * the handful of tiling tweaks Win11Debloat does not cover
#   * a choice. The profile is grouped - tiling, taskbar, explorer, privacy, ai,
#     system - and only tiling is load-bearing here: komorebi cannot place a
#     window Windows keeps snapping. Everything else is taste, so it is offered
#     rather than assumed, and a run with no arguments asks.
#
# Defaults with no console to ask in: tiling and the app removal. Settings are
# reversible (Win11Debloat writes a restore point first, and most flags have an
# inverse). Removing an app is not, which is why it is its own checklist line.

[CmdletBinding()]
param(
    # Pin. Bump deliberately after reading the upstream changelog.
    [string]$Ref = "2026.08.24",

    # Which groups of settings to apply, from configs/windows/debloat.json, plus
    # the pseudo-group "apps" for removing the bundled ones. Left empty, a
    # console gets a checklist and anything else gets the defaults below.
    [string[]]$Groups,
    [switch]$All,

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

# powershell.exe -File binds "a,b,c" to a [string[]] as ONE element, unlike
# -Command, and the elevated relaunch below goes through -File.
if ($Groups) { $Groups = @($Groups -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }

$Repo = Split-Path -Parent $PSScriptRoot

# Not $Profile: that is a PowerShell automatic variable holding the path to
# your shell profile, and shadowing it breaks anything that reads it later.
$ProfilePath = Join-Path $Repo "configs\windows\debloat.json"
if (-not (Test-Path -LiteralPath $ProfilePath)) { throw "Missing profile: $ProfilePath" }

# --- what to apply -----------------------------------------------------------
# The settings used to be all-or-nothing: 39 registry tweaks fixed in the
# profile, applied in full or not at all. Only the tiling group is actually
# required by anything in this repo - komorebi cannot place windows Windows
# keeps snapping - so the rest is now a choice, offered as groups rather than as
# 39 separate lines because the checklist does not scroll.
#
# Chosen HERE, before the elevation relaunch, so the picking happens in the
# terminal you already have rather than in a window that appears for it. The
# child is then told what was picked and never asks again.
. (Join-Path $Repo "scripts\lib\debloat.ps1")
$profileJson = Get-Content -LiteralPath $ProfilePath -Raw | ConvertFrom-Json
$knownGroups = @(Get-DebloatGroups -DebloatConfig $profileJson)

if ($All) {
    $Groups = @($knownGroups) + "apps"
} elseif ($Groups) {
    $unknown = @($Groups | Where-Object { $knownGroups -notcontains $_ -and $_ -ne "apps" })
    if ($unknown.Count) {
        throw "Unknown group(s): $($unknown -join ', '). Known: $(($knownGroups + 'apps') -join ', ')"
    }
} else {
    # tiling and apps are the defaults: the first is what this desktop needs to
    # work at all, the second is what most people came here for.
    $Groups = @("tiling", "apps")

    $interactive = ($Host.Name -eq "ConsoleHost")
    try { $interactive = $interactive -and -not [Console]::IsInputRedirected } catch { }

    if ($interactive) {
        . (Join-Path $Repo "scripts\lib\tui.ps1")
        Initialize-Tui

        $items  = Get-DebloatGroupItems -DebloatConfig $profileJson
        $picked = Show-TuiChecklist -Items $items -Title "Debloat" -HeaderLines @(
            "Everything here is optional except tiling, which komorebi needs.",
            "Settings are reversible; removing apps is not."
        )
        Clear-Tui
        if ($null -eq $picked) { Write-Host "Cancelled - nothing was changed."; exit 0 }
        $Groups = @($picked)
    }
}

if ($RemoveApps -and $Groups -notcontains "apps") { $Groups += "apps" }
$RemoveApps = [bool]($Groups -contains "apps")
$tweakGroups = @($Groups | Where-Object { $_ -ne "apps" })

if (-not $tweakGroups.Count -and -not $RemoveApps) {
    Write-Host "Nothing selected - nothing to do." -ForegroundColor Yellow
    exit 0
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

# Not for -DryRun: it prints a plan and changes nothing, so asking for
# administrator - and opening a second window to hold the answer - buys nothing
# and makes the one safe way to inspect this script the most annoying one.
if (($isCore -or -not $isElevated) -and $PSCommandPath -and -not $DryRun) {
    $winPs = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    if (-not (Test-Path -LiteralPath $winPs)) {
        throw "Windows PowerShell 5.1 not found at $winPs, and Win11Debloat cannot run under pwsh."
    }

    $relaunch = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$PSCommandPath`"")
    foreach ($k in $PSBoundParameters.Keys) {
        # Groups is passed explicitly below - by now it holds what was picked,
        # which is not what was bound. All and RemoveApps are already folded
        # into it, and re-sending them would only widen the selection again.
        if ($k -in @("Pause", "Groups", "All", "RemoveApps")) { continue }
        $v = $PSBoundParameters[$k]
        if ($v -is [switch]) {
            if ($v.IsPresent) { $relaunch += "-$k" }
        } else {
            $relaunch += @("-$k", "`"$v`"")
        }
    }
    # The elevated copy must not ask again: it gets the answer.
    $relaunch += @("-Groups", "`"$($Groups -join ',')`"")

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

# Apps removed only when the apps group is picked. The list lives in
# scripts\lib\debloat.ps1, next to the checklist line that describes it.
$AppsToRemove = (Get-DebloatAppsToRemove) -join ','

Write-Host "Win11Debloat wrapper" -ForegroundColor Green
Write-Host "  pinned ref : $Ref"
Write-Host "  profile    : $ProfilePath"
Write-Host "  groups     : $(if ($tweakGroups.Count) { $tweakGroups -join ', ' } else { 'none' })"
Write-Host "  app removal: $(if ($RemoveApps) { 'YES - not reversible' } else { 'no' })"

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

# The profile in the repo holds every group; Win11Debloat applies whatever is
# in the file it is handed. So hand it a copy holding only what was picked.
#
# CreateRestorePoint lives in the profile too, not on this command line, which
# is why the old `Where-Object { $_ -ne "-CreateRestorePoint" }` filtered a
# string that was never in the argument list: -NoRestorePoint did nothing at all.
$selected = @($profileJson.Tweaks | Where-Object { $tweakGroups -contains $_.Group })

if ($NoRestorePoint -or $selected.Count -ne @($profileJson.Tweaks).Count) {
    $cfg = Get-Content -LiteralPath $ProfilePath -Raw | ConvertFrom-Json
    $cfg.Tweaks = $selected
    if ($NoRestorePoint) {
        $cfg.Deployment = @($cfg.Deployment | Where-Object { $_.Name -ne "CreateRestorePoint" })
    }

    # An empty Tweaks list with nothing else left would be refused by the
    # importer ("no importable data"), and with only apps picked there is
    # nothing for it to read anyway.
    if ($selected.Count -or @($cfg.Deployment).Count) {
        $ProfilePath = Join-Path $env:TEMP "debloat-selected.json"
        $cfg | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $ProfilePath -Encoding UTF8
        $w11.Config = $ProfilePath
    } else {
        $w11.Remove("Config")
    }

    Write-Host "  applying   : $($selected.Count) of $(@($profileJson.Tweaks).Count) settings$(if ($NoRestorePoint) { ', no restore point' })" -ForegroundColor DarkGray
}

# Printed from the same hashtable the call uses, so the preview cannot drift
# from what runs.
$preview = ($w11.GetEnumerator() | Sort-Object Name | ForEach-Object {
    if ($_.Value -is [bool]) { "-$($_.Key)" } else { "-$($_.Key) $($_.Value)" }
}) -join " "
Write-Host "`nWould run:" -ForegroundColor Magenta
Write-Host "  $entry $preview" -ForegroundColor DarkGray

if ($DryRun) {
    if ($w11.ContainsKey("Config")) {
        $cfgShown = Get-Content -LiteralPath $w11.Config -Raw | ConvertFrom-Json
        Write-Host "`nSettings that would be applied:" -ForegroundColor Magenta
        @($cfgShown.Deployment) + @($cfgShown.Tweaks) |
            Where-Object { $_ } |
            ForEach-Object { Write-Host ("  -{0}" -f $_.Name) -ForegroundColor DarkGray }
    } else {
        Write-Host "`nNo settings selected - app removal only." -ForegroundColor Magenta
    }
    if ($RemoveApps) {
        Write-Host "`nApps that would be removed:" -ForegroundColor Magenta
        $AppsToRemove -split ',' | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
    }
    Write-Host "`nDry run - nothing was changed." -ForegroundColor Yellow
    if ($Pause) { Read-Host "`nEnter to close" | Out-Null }
    return
}

Write-Host ""

# Our strictness is not Win11Debloat's to obey. Set-StrictMode is inherited by
# every child scope, so dot-sourcing scripts\lib\tui.ps1 for the checklist put
# StrictMode 2.0 on this script AND on the upstream code called below, which is
# not written to it:
#
#   Resolve-UserProfilePath.ps1:29
#     if (-not $script:ResolvedUserSidCache) { $script:ResolvedUserSidCache = @{} }
#
# Reading a variable that has never been set is exactly what strict mode
# forbids, so a run that got as far as the first per-user registry write died
# with "The variable '$script:ResolvedUserSidCache' cannot be retrieved because
# it has not been set". Measured: a child script reading an unset variable
# throws under an inherited StrictMode 2.0 and is fine after Set-StrictMode -Off.
Set-StrictMode -Off
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

    # News and interests used to live in ...\CurrentVersion\Feeds. Windows 11
    # 24H2 removed the feature and left the key behind, locked: writing
    # ShellFeedsTaskbarViewMode there fails with "Attempted to perform an
    # unauthorized operation" even elevated, and under ErrorActionPreference=Stop
    # that ended the whole step - after every Win11Debloat setting had already
    # been applied, so the run reported FAIL having done its job. Widgets, which
    # replaced it, are handled by DisableWidgets in the profile.

    # The search highlight repaints the taskbar on a timer, which komorebi has
    # no say over. Guarded like the one above: a tweak that cannot be applied is
    # worth a line of output, not a failed install.
    try {
        $dsh = "HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings"
        if (-not (Test-Path $dsh)) { New-Item -Path $dsh -Force | Out-Null }
        Set-ItemProperty -Path $dsh -Name "IsDynamicSearchBoxEnabled" -Value 0 -Type DWord
        Write-Host "  + search highlights off" -ForegroundColor Green
    } catch {
        Write-Host "  ! could not turn off search highlights: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    Write-Host "`n  Restart Explorer for these to take effect:" -ForegroundColor Yellow
    Write-Host "    Stop-Process -Name explorer -Force" -ForegroundColor Cyan
}

Write-Host ""
Write-Host "Done." -ForegroundColor Green

# Run the check instead of printing "Verify with: ./scripts/doctor.ps1". Left to
# setup.ps1 when this is one of its steps - it runs doctor once, last. Its own
# process on purpose: this script runs under ErrorActionPreference=Stop, and the
# checklist may have dot-sourced StrictMode into it; doctor is written to
# neither, and in-process it would inherit both - the Win11Debloat failure
# again.
if (-not $env:OMACHEESE_SETUP_RUN) {
    Write-Host ""
    & (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Repo "scripts\doctor.ps1")
    # doctor exits 1 for anything it finds anywhere on the machine; that is
    # not this script failing.
    $global:LASTEXITCODE = 0
}

# Only set by the elevated relaunch: without it that window closes the instant
# it finishes and nobody ever sees what it did.
if ($Pause) { Read-Host "`nEnter to close" | Out-Null }
