# windows11-dev-poweruser - interactive setup.
#
#   ./scripts/setup.ps1                 pick a profile, then run
#   ./scripts/setup.ps1 -Preset full    skip the menus
#   ./scripts/setup.ps1 -DryRun         show the plan, change nothing
#   ./scripts/setup.ps1 -Modules core,cli,configs
#
# Runs on Windows PowerShell 5.1 with no modules installed, because on a clean
# Windows 11 box that is all there is. Everything it needs to draw is in
# scripts/lib/tui.ps1.
#
# Each module logs to its own file under the run directory, so a failure
# leaves something to read rather than a wall of scrollback.

[CmdletBinding()]
param(
    [ValidateSet("minimal", "desktop", "full", "everything", "custom")]
    [string]$Preset,
    [string[]]$Modules,
    [switch]$DryRun,
    [switch]$Yes
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $RepoRoot "scripts\lib\tui.ps1")
. (Join-Path $RepoRoot "scripts\lib\detect.ps1")
. (Join-Path $RepoRoot "scripts\lib\modules.ps1")

Initialize-Tui
$T = Get-TuiPalette

# --- run directory -----------------------------------------------------------
$stamp  = Get-Date -Format "yyyyMMdd-HHmmss"
$RunDir = Join-Path $env:TEMP "w11-setup-$stamp"
New-Item -ItemType Directory -Force -Path $RunDir | Out-Null
$MainLog = Join-Path $RunDir "setup.log"

function Write-SetupLog {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $Message
    Add-Content -LiteralPath $MainLog -Value $line
}

Write-SetupLog "repo: $RepoRoot"

# --- detect ------------------------------------------------------------------
Write-TuiBanner
Write-Host ("  {0}detecting hardware...{1}" -f $T.Dim, $T.Reset)
$Machine = Get-MachineProfile
Write-SetupLog ("machine: build={0} ram={1} gpu={2} vram={3} tier={4}" -f `
    $Machine.Build, $Machine.RamGb, $Machine.Gpu.Name, $Machine.Gpu.VramGb, $Machine.LlmTier)

$header = Format-MachineSummary -Machine $Machine -Palette $T

# Blockers worth saying out loud before anything is selected.
$warnings = @()
if (-not $Machine.HasWinget) {
    $warnings += "{0}winget is missing - install 'App Installer' from the Microsoft Store first{1}" -f $T.Red, $T.Reset
}
if (-not $Machine.IsWin11) {
    $warnings += "{0}this is not Windows 11 - the tiling WM and taskbar tweaks assume it{1}" -f $T.Yellow, $T.Reset
}
if (-not $Machine.IsElevated) {
    $warnings += "{0}not running as admin - WSL install will ask for elevation{1}" -f $T.Dim, $T.Reset
}
if ($Machine.FreeGb -lt 25) {
    $warnings += "{0}only {1} GB free on {2}{3}" -f $T.Yellow, $Machine.FreeGb, $env:SystemDrive, $T.Reset
}

# --- module registry ---------------------------------------------------------
$allModules = Get-SetupModules -Machine $Machine

# --- choose ------------------------------------------------------------------
$selectedKeys = $null

if ($Modules) {
    $selectedKeys = $Modules
} else {
    if (-not $Preset) {
        $profiles = Get-SetupProfiles
        $menuItems = foreach ($p in $profiles) {
            [pscustomobject]@{ Key = $p.Key; Title = $p.Title; Description = $p.Description }
        }
        $Preset = Show-TuiMenu -Items $menuItems -Title "windows11-dev-poweruser" `
            -HeaderLines ($header + $warnings)
        if (-not $Preset) { Clear-Tui; Write-Host "Cancelled."; return }
    }

    $chosen = (Get-SetupProfiles) | Where-Object { $_.Key -eq $Preset }
    foreach ($m in $allModules) { $m.Selected = ($chosen.Modules -contains $m.Key) -and $m.Available }

    # Custom, or a profile the user wants to adjust: show the checklist.
    if ($Preset -eq "custom" -or -not $Yes) {
        $checkHeader = $header + $warnings + @(
            "",
            ("{0}[-]{1} means the machine cannot run it; the reason is shown underneath." -f $T.Dim, $T.Reset)
        )
        $selectedKeys = Show-TuiChecklist -Items $allModules -Title "Modules" -HeaderLines $checkHeader
        if ($null -eq $selectedKeys) { Clear-Tui; Write-Host "Cancelled."; return }
    } else {
        $selectedKeys = @($allModules | Where-Object { $_.Selected } | ForEach-Object { $_.Key })
    }
}

$steps = @($allModules | Where-Object { $selectedKeys -contains $_.Key })
if (-not $steps.Count) { Clear-Tui; Write-Host "Nothing selected."; return }

# --- plan --------------------------------------------------------------------
Clear-Tui
$w = Get-TuiWidth
Write-TuiTop "Plan" $w
foreach ($h in $header) { Write-TuiLine $h $w }
Write-TuiSep $w
foreach ($s in $steps) {
    $elev = ""
    if ($s.NeedsElevation -and -not $Machine.IsElevated) { $elev = "{0}(will prompt for admin){1}" -f $T.Yellow, $T.Reset }
    Write-TuiLine ("{0}{1,-12}{2} {3}{4,-16}{2} {5} {6}" -f `
        $T.Bright, $s.Key, $T.Reset, $T.Dim, $s.Est, $s.Description, $elev) $w
}
Write-TuiSep $w
Write-TuiLine ("logs: {0}{1}{2}" -f $T.Dim, $RunDir, $T.Reset) $w
Write-TuiBottom $w

if ($DryRun) {
    Write-Host ""
    Write-Host ("  {0}Dry run - nothing was changed.{1}" -f $T.Yellow, $T.Reset)
    return
}

if (-not $Yes) {
    if (-not (Confirm-Tui "Run these $($steps.Count) steps?")) {
        Write-Host "Cancelled."
        return
    }
}

# --- actions -----------------------------------------------------------------
# Each action runs a repo script and streams to its own log. Keeping the
# invocation in one place means the TUI is the only thing that knows about
# progress, and the scripts stay usable on their own.

function Invoke-Step {
    param([string]$Key, [string[]]$Arguments, [string]$File, [switch]$Elevate)

    $log = Join-Path $RunDir "$Key.log"
    Write-SetupLog "run $File $($Arguments -join ' ')"

    $psExe = (Get-Process -Id $PID).Path
    $argList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $File) + $Arguments

    if ($Elevate -and -not $Machine.IsElevated) {
        $p = Start-Process -FilePath $psExe -ArgumentList $argList -Verb RunAs -PassThru -Wait
        return $p.ExitCode
    }

    $p = Start-Process -FilePath $psExe -ArgumentList $argList `
        -NoNewWindow -PassThru -Wait `
        -RedirectStandardOutput $log -RedirectStandardError "$log.err"
    return $p.ExitCode
}

$ctx = @{
    InstallWindows = {
        param([string[]]$Groups)
        Invoke-Step -Key "pkg-$($Groups -join '-')" `
            -File (Join-Path $RepoRoot "scripts\install-windows.ps1") `
            -Arguments @("-Groups", ($Groups -join ","), "-SkipModules")
    }
    LinkConfigs = {
        Invoke-Step -Key "configs" -File (Join-Path $RepoRoot "scripts\link-configs.ps1") -Arguments @()
    }
    Debloat = {
        Invoke-Step -Key "debloat" -File (Join-Path $RepoRoot "scripts\debloat-windows.ps1") -Arguments @()
    }
    InstallWsl = {
        Invoke-Step -Key "wsl" -File (Join-Path $RepoRoot "scripts\install-wsl.ps1") -Arguments @() -Elevate
    }
    InstallLocalLlm = {
        Invoke-Step -Key "localllm" -File (Join-Path $RepoRoot "scripts\install-localllm.ps1") `
            -Arguments @("-Tier", $Machine.LlmTier)
    }
    Doctor = {
        Invoke-Step -Key "verify" -File (Join-Path $RepoRoot "scripts\doctor.ps1") -Arguments @("-Quick")
    }
}

# --- run ---------------------------------------------------------------------
$startAll = Get-Date
$failed = @()

for ($i = 0; $i -lt $steps.Count; $i++) {
    $s = $steps[$i]
    $s.Status = "Running"
    $s.Detail = "started $(Get-Date -Format 'HH:mm:ss')"

    Write-TuiBoard -Steps $steps -Title ("Installing  [{0}/{1}]" -f ($i + 1), $steps.Count) `
        -FooterLines @(
            ("{0}{1}{2}  {3}" -f $T.Bright, $s.Key, $T.Reset, $s.Description),
            ("{0}logs: {1}{2}" -f $T.Dim, $RunDir, $T.Reset)
        )

    $t0 = Get-Date
    $code = 0
    try {
        $code = & $s.Action $ctx
        if ($null -eq $code) { $code = 0 }
    } catch {
        $code = 1
        Write-SetupLog "EXCEPTION in $($s.Key): $($_.Exception.Message)"
        Add-Content -LiteralPath (Join-Path $RunDir "$($s.Key).log") -Value $_.Exception.ToString()
    }
    $elapsed = [math]::Round(((Get-Date) - $t0).TotalSeconds)

    if ($code -eq 0) {
        $s.Status = "Done"
        $s.Detail = "{0}s" -f $elapsed
    } else {
        $s.Status = "Failed"
        $s.Detail = "exit $code after {0}s - see {1}.log" -f $elapsed, $s.Key
        $failed += $s.Key
    }
    Write-SetupLog "$($s.Key): $($s.Status) in ${elapsed}s (exit $code)"
}

# --- summary -----------------------------------------------------------------
$total = [math]::Round(((Get-Date) - $startAll).TotalMinutes, 1)

$footer = @()
if ($failed.Count) {
    $footer += "{0}{1} step(s) failed: {2}{3}" -f $T.Red, $failed.Count, ($failed -join ", "), $T.Reset
    $footer += "{0}logs: {1}{2}" -f $T.Dim, $RunDir, $T.Reset
} else {
    $footer += "{0}All {1} steps completed in {2} min.{3}" -f $T.Green, $steps.Count, $total, $T.Reset
}

$didWsl = @($steps | Where-Object { $_.Key -eq "wsl" -and $_.Status -eq "Done" }).Count -gt 0
$didWm  = @($steps | Where-Object { $_.Key -eq "wm"  -and $_.Status -eq "Done" }).Count -gt 0

$footer += ""
$footer += "{0}Next:{1}" -f $T.Bright, $T.Reset
if ($didWsl)  { $footer += "  {0}wsl --install -d AlmaLinux-9{1} may need a reboot first" -f $T.Cyan, $T.Reset }
if ($didWm)   { $footer += "  {0}./scripts/start-desktop.ps1{1}   then {0}SUPER + /{1} for the keymap" -f $T.Cyan, $T.Reset }
$footer += "  {0}./scripts/doctor.ps1{1}          full check including winget ids" -f $T.Cyan, $T.Reset

Write-TuiBoard -Steps $steps -Title "Done" -FooterLines $footer
Write-Host ""

if ($failed.Count) { exit 1 }
