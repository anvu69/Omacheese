# Omacheese - interactive setup.
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

# powershell.exe -File binds "a,b,c" to a [string[]] parameter as ONE element,
# unlike -Command. Split here so both invocation styles behave the same.
if ($Modules) { $Modules = @($Modules -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }

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
        $Preset = Show-TuiMenu -Items $menuItems -Title "Omacheese" `
            -HeaderLines ($header + $warnings)
        if (-not $Preset) { Clear-Tui; Write-Host "Cancelled."; return }
    }

    $chosen = (Get-SetupProfiles) | Where-Object { $_.Key -eq $Preset }
    foreach ($m in $allModules) { $m.Selected = ($chosen.Modules -contains $m.Key) -and $m.Available }

    # Custom, or a profile the user wants to adjust: show the checklist.
    #
    # -DryRun never shows it. It is documented for CI and remote sessions,
    # where there is no console: the checklist ends at
    # $Host.UI.RawUI.ReadKey, which blocks forever rather than failing.
    if ($Preset -eq "custom" -and $DryRun) {
        # Nothing to pick from in a non-interactive run, and "custom" has no
        # default set, so say that rather than printing an empty plan.
        Clear-Tui
        Write-Host ""
        Write-Host ("  {0}-Preset custom needs the checklist, which -DryRun cannot show.{1}" -f $T.Yellow, $T.Reset)
        Write-Host ("  {0}Use -Modules a,b,c to spell out a custom set non-interactively.{1}" -f $T.Dim, $T.Reset)
        return
    }
    if ($Preset -eq "custom" -or (-not $Yes -and -not $DryRun)) {
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

# The local-LLM module is the one step that downloads many GB, can take half
# an hour, and is useless on the wrong hardware. It is never selected by
# default, and selecting it asks again here with the actual cost spelled out.
$llmStep = $steps | Where-Object { $_.Key -eq "localllm" } | Select-Object -First 1
if ($llmStep -and -not $Yes) {
    Write-Host ""
    Write-Host ("  {0}OPTIONAL: local LLM{1}" -f ($T.Yellow + $T.Bold), $T.Reset)
    Write-Host ("  {0}Nothing else in this setup depends on it. Skip it and everything" -f $T.Dim)
    Write-Host ("  else still works - the coding agents talk to hosted APIs.{0}" -f $T.Reset)
    Write-Host ""
    if ($Machine.LlmTier -eq "vllm") {
        Write-Host ("  backend   {0}vLLM in a GPU container{1}" -f $T.Fg, $T.Reset)
        Write-Host ("  needs     {0}WSL2 + Docker + NVIDIA Container Toolkit{1}" -f $T.Fg, $T.Reset)
        Write-Host ("  download  {0}~10 GB image, plus several GB of model weights{1}" -f $T.Yellow, $T.Reset)
        Write-Host ("  time      {0}10-30 min on a fast connection{1}" -f $T.Yellow, $T.Reset)
        if ($Machine.ModelHint) {
            Write-Host ("  model     {0}{1} @ {2}, sized for {3} GB VRAM{4}" -f `
                $T.Fg, $Machine.ModelHint.Model, $Machine.ModelHint.Quant, $Machine.Gpu.VramGb, $T.Reset)
        }
    } else {
        Write-Host ("  backend   {0}Ollama{1}" -f $T.Fg, $T.Reset)
        Write-Host ("  needs     {0}nothing extra - no WSL, no Docker, no CUDA{1}" -f $T.Fg, $T.Reset)
        Write-Host ("  download  {0}a few GB per model you pull{1}" -f $T.Yellow, $T.Reset)
        Write-Host ("  note      {0}{1}{2}" -f $T.Dim, $Machine.LlmNote, $T.Reset)
    }

    if (-not (Confirm-Tui "Include the local LLM step?" -DefaultNo)) {
        $steps = @($steps | Where-Object { $_.Key -ne "localllm" })
        Write-Host ("  {0}skipped - run ./scripts/install-localllm.ps1 later if you change your mind{1}" -f $T.Dim, $T.Reset)
    }
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

# Handed to every child as stdin. Without it a child that decides to ask a
# question reads THIS console instead, and since its output goes to a log the
# question is invisible: the installer simply stops, and carries on only when
# someone guesses to press Enter. Win11Debloat's "Restart as Administrator?
# (y/n)" is the one that actually did this. An empty file means any such prompt
# gets EOF and the child moves on or fails honestly.
$NullIn = Join-Path $RunDir "stdin.empty"
Set-Content -LiteralPath $NullIn -Value ([string]::Empty) -NoNewline

# What the live board is currently showing, so a running step can refresh it.
$script:BoardSteps  = $null
$script:BoardTitle  = ""
$script:BoardFooter = @()
$script:BoardTail   = ""
$script:BoardDrawn  = [datetime]::MinValue

function Show-Board {
    if (-not $script:BoardSteps) { return }
    $footer = $script:BoardFooter
    if ($script:BoardTail) { $footer = $footer + ("{0}{1}{2}" -f $T.Dim, $script:BoardTail, $T.Reset) }
    Write-TuiBoard -Steps $script:BoardSteps -Title $script:BoardTitle -FooterLines $footer
    $script:BoardDrawn = Get-Date
}

# A step that prints nothing for ten minutes is indistinguishable from one that
# has hung, and that is how every long winget run read. Show its last line of
# output instead. Throttled, and only redrawn when the line actually changes,
# so the board does not strobe.
function Update-StepTail {
    param([string]$Log)
    if (-not $script:BoardSteps) { return }
    if (((Get-Date) - $script:BoardDrawn).TotalMilliseconds -lt 1200) { return }

    $line = ""
    try {
        if (Test-Path -LiteralPath $Log) {
            $line = @(Get-Content -LiteralPath $Log -Tail 8 -ErrorAction SilentlyContinue |
                      Where-Object { $_ -and $_.Trim() }) | Select-Object -Last 1
        }
    } catch { }
    if (-not $line) { return }

    $line = ([string]$line).Trim()
    if ($line.Length -gt 78) { $line = $line.Substring(0, 78) + "..." }
    if ($line -eq $script:BoardTail) { return }

    $script:BoardTail = $line
    Show-Board
}

function Invoke-Step {
    param(
        [string]$Key,
        [string[]]$Arguments,
        [string]$File,
        [switch]$Elevate,
        # Win11Debloat, and anything else that needs the Appx or DISM cmdlets,
        # cannot run under pwsh 7. Without this every step ran in whatever host
        # started the setup, so running it from PowerShell 7 - the natural thing
        # to do after installing pwsh by hand - broke the debloat step outright.
        [switch]$WindowsPowerShell
    )

    $log = Join-Path $RunDir "$Key.log"
    Write-SetupLog "run $File $($Arguments -join ' ')"

    if ($WindowsPowerShell) {
        $psExe = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
        if (-not (Test-Path -LiteralPath $psExe)) { $psExe = (Get-Process -Id $PID).Path }
    } else {
        $psExe = (Get-Process -Id $PID).Path
    }

    # One string, not an array: Start-Process joins an array with spaces and
    # does not quote, so a username with a space in it broke every step.
    $argLine = '-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $File
    if ($Arguments -and $Arguments.Count) { $argLine += " " + ($Arguments -join " ") }

    if ($Elevate -and -not $Machine.IsElevated) {
        # -Verb RunAs cannot redirect any stream, so this one gets its own
        # window and the user watches it there. -Wait is what actually waits:
        # a handle to an elevated child cannot always be reopened by PID from
        # an unelevated parent, so WaitForExit() alone is not dependable here.
        try {
            $p = Start-Process -FilePath $psExe -ArgumentList $argLine -Verb RunAs -PassThru -Wait
        } catch {
            # Declined, or nobody answered: Windows dismisses the UAC dialog on
            # its own after about two minutes. Neither is a crash in the step,
            # but the exception text names pwsh.exe and a working directory and
            # never says "administrator", and an elevated step writes no log of
            # its own - so the board pointed at a log file that did not exist.
            Set-Content -LiteralPath $log -Value @(
                "This step needs administrator rights, and the UAC prompt was not accepted.",
                "(Windows also dismisses that prompt by itself after about two minutes.)",
                "",
                "Re-run this from a terminal that is already elevated, or run the step alone:",
                "  $File"
            )
            return 1223  # ERROR_CANCELLED
        }
        try { $p.WaitForExit() } catch { }
        return $p.ExitCode
    }

    $p = Start-Process -FilePath $psExe -ArgumentList $argLine `
        -NoNewWindow -PassThru `
        -RedirectStandardInput $NullIn `
        -RedirectStandardOutput $log -RedirectStandardError "$log.err"

    # Touching .Handle is not decoration. On Windows PowerShell 5.1 - the host
    # this runs in on a fresh machine - Start-Process -PassThru WITHOUT -Wait
    # hands back a Process whose ExitCode reads back EMPTY once it has exited,
    # because nothing kept the process handle open. Every step then looked like
    # it succeeded, including the ones that failed. Reading .Handle caches the
    # SafeHandle on the object, and the exit code survives. Measured on 5.1:
    # without it, exit 3010 came back as nothing; with it, 3010. pwsh 7 happens
    # to be fine either way, which is exactly how this would have shipped.
    $null = $p.Handle

    # Poll instead of -Wait so the board can keep reporting.
    while (-not $p.HasExited) {
        Start-Sleep -Milliseconds 400
        Update-StepTail -Log $log
    }
    $p.WaitForExit()
    return $p.ExitCode
}

# Store apps have no path to launch: their Start-menu shortcut is the handle.
function Start-StartMenuApp {
    param([string]$Name)
    foreach ($r in @([Environment]::GetFolderPath("Programs"),
                     [Environment]::GetFolderPath("CommonPrograms"))) {
        if (-not $r -or -not (Test-Path -LiteralPath $r)) { continue }
        $hit = Get-ChildItem -LiteralPath $r -Filter "*.lnk" -Recurse -ErrorAction SilentlyContinue |
               Where-Object { $_.BaseName -like "*$Name*" } |
               Sort-Object { $_.BaseName.Length } | Select-Object -First 1
        if ($hit) {
            try { Start-Process -FilePath $hit.FullName; return $true } catch { }
        }
    }
    return $false
}

$ctx = @{
    InstallWindows = {
        param([string[]]$Groups)
        Invoke-Step -Key "pkg-$($Groups -join '-')" `
            -File (Join-Path $RepoRoot "scripts\install-windows.ps1") `
            -Arguments @("-Groups", ($Groups -join ","), "-SkipModules")
    }
    InstallModules = {
        Invoke-Step -Key "psmodules" `
            -File (Join-Path $RepoRoot "scripts\install-windows.ps1") `
            -Arguments @("-ModulesOnly")
    }
    LinkConfigs = {
        Invoke-Step -Key "configs" -File (Join-Path $RepoRoot "scripts\link-configs.ps1") -Arguments @()
    }
    InstallHerdr = {
        Invoke-Step -Key "herdr" -File (Join-Path $RepoRoot "scripts\install-herdr.ps1") -Arguments @()
    }
    Debloat = {
        # Windows PowerShell, and elevated: Win11Debloat needs the Appx module
        # (absent from pwsh 7) and admin, and asks for the latter with an
        # interactive prompt that this runner cannot answer.
        Invoke-Step -Key "debloat" -File (Join-Path $RepoRoot "scripts\debloat-windows.ps1") `
            -Arguments @() -WindowsPowerShell -Elevate
    }
    InstallWsl = {
        Invoke-Step -Key "wsl" -File (Join-Path $RepoRoot "scripts\install-wsl.ps1") -Arguments @() -Elevate
    }
    InstallLocalLlm = {
        Invoke-Step -Key "localllm" -File (Join-Path $RepoRoot "scripts\install-localllm.ps1") `
            -Arguments @("-Tier", $Machine.LlmTier)
    }
    Doctor = {
        # doctor exits 1 whenever anything failed, which for a partial install
        # (say, configs without the window manager) is expected rather than an
        # error in this run. Report its own tally instead of a bare exit code,
        # and only treat real failures as a failed step.
        $code = Invoke-Step -Key "verify" -File (Join-Path $RepoRoot "scripts\doctor.ps1") -Arguments @("-Quick")

        $log = Join-Path $RunDir "verify.log"
        if (Test-Path -LiteralPath $log) {
            $summary = Get-Content -LiteralPath $log |
                Where-Object { $_ -match '(\d+) passed\s+(\d+) warnings\s+(\d+) failures' } |
                Select-Object -Last 1
            if ($summary -and $summary -match '(\d+) passed\s+(\d+) warnings\s+(\d+) failures') {
                $script:DoctorSummary = "{0} passed, {1} warnings, {2} failures" -f $Matches[1], $Matches[2], $Matches[3]
                return [int]$Matches[3]
            }
        }
        return $code
    }
}

# --- run ---------------------------------------------------------------------
$startAll = Get-Date
$failed = @()

# Set when a step reports that Windows needs restarting before it can finish.
# Steps listed against it are skipped rather than run into a wall: the local-LLM
# module needs a distro that cannot boot until the reboot has happened, and
# failing there told the user nothing except that something was broken.
$script:RebootRequired = $false
$NeedsRunningWsl = @("localllm")

for ($i = 0; $i -lt $steps.Count; $i++) {
    $s = $steps[$i]

    if ($script:RebootRequired -and $NeedsRunningWsl -contains $s.Key) {
        $s.Status = "Skipped"
        $s.Detail = "needs the restart WSL asked for - run it after rebooting"
        Write-SetupLog "$($s.Key): Skipped (reboot pending)"
        continue
    }

    $s.Status = "Running"
    $s.Detail = "started $(Get-Date -Format 'HH:mm:ss')"

    $script:BoardSteps  = $steps
    $script:BoardTitle  = ("Installing  [{0}/{1}]" -f ($i + 1), $steps.Count)
    $script:BoardFooter = @(
        ("{0}{1}{2}  {3}" -f $T.Bright, $s.Key, $T.Reset, $s.Description),
        ("{0}logs: {1}{2}" -f $T.Dim, $RunDir, $T.Reset)
    )
    $script:BoardTail = ""
    Show-Board

    # Refresh PATH between steps so a module can use what the previous one
    # installed (configs looks for komorebic, verify looks for everything).
    $env:PATH = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [Environment]::GetEnvironmentVariable("Path", "User")

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

    # 3010 is the installer convention for "done, but Windows must restart".
    # install-wsl.ps1 returns it after enabling the Windows features, which is
    # a success - the machine is one reboot from a working WSL, not broken.
    $note = $null
    if ($code -eq 3010) {
        $script:RebootRequired = $true
        $code = 0
        $note = "RESTART REQUIRED to finish"
    }

    if ($code -eq 0) {
        $s.Status = "Done"
        if ($note) {
            $s.Detail = "{0}s - {1}" -f $elapsed, $note
        } elseif ($s.Key -eq "verify" -and $script:DoctorSummary) {
            $s.Detail = "{0}s - {1}" -f $elapsed, $script:DoctorSummary
        } else {
            $s.Detail = "{0}s" -f $elapsed
        }
    } else {
        $s.Status = "Failed"
        if ($s.Key -eq "verify" -and $script:DoctorSummary) {
            $s.Detail = "{0} - see verify.log" -f $script:DoctorSummary
        } else {
            $s.Detail = "exit $code after {0}s - see {1}.log" -f $elapsed, $s.Key
        }
        $failed += $s.Key
    }
    Write-SetupLog "$($s.Key): $($s.Status) in ${elapsed}s (exit $code)"
}

$script:BoardSteps = $null

$didWsl     = @($steps | Where-Object { $_.Key -eq "wsl"     -and $_.Status -eq "Done" }).Count -gt 0
$didWm      = @($steps | Where-Object { $_.Key -eq "wm"      -and $_.Status -eq "Done" }).Count -gt 0
$didConfigs = @($steps | Where-Object { $_.Key -eq "configs" -and $_.Status -eq "Done" }).Count -gt 0
$didRaycast = @($steps | Where-Object { $_.Key -eq "raycast" -and $_.Status -eq "Done" }).Count -gt 0

# --- start what was just installed -------------------------------------------
# Nothing used to start after a successful install. komorebi, whkd and yasb all
# waited for the next login, PowerToys was the only thing that came up on its
# own, and the honest impression of a fresh machine was that the setup had done
# nothing at all. The Startup shortcut handles every later login; this handles
# the session the user is sitting in.
$env:PATH = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
            [Environment]::GetEnvironmentVariable("Path", "User")

$desktopUp = $false
if ($didWm -and $didConfigs) {
    $startScript = Join-Path $RepoRoot "scripts\start-desktop.ps1"
    if (Test-Path -LiteralPath $startScript) {
        Write-Host ""
        Write-Host ("  {0}starting komorebi + whkd + yasb...{1}" -f $T.Dim, $T.Reset)
        $rc = Invoke-Step -Key "desktop-start" -File $startScript -Arguments @()
        # Ask the process list, not the exit code: start-desktop.ps1 reports a
        # komorebi that never answered on stdout and still exits 0, and claiming
        # "the desktop is running" when it is not is worse than saying nothing.
        $desktopUp = [bool](Get-Process komorebi -ErrorAction SilentlyContinue)
        Write-SetupLog "desktop-start: exit $rc, komorebi running: $desktopUp"
    }
}

# Raycast is a Store app that wants an account, so it is useless until someone
# has actually opened it once. Installing it and saying nothing left it sitting
# there configured by nobody.
$raycastUp = $false
if ($didRaycast) {
    $raycastUp = Start-StartMenuApp -Name "Raycast"
    Write-SetupLog "raycast launch: $raycastUp"
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

# Where the machine's previous configs went. The most important line for
# anyone who ran this on a box that already had a setup.
$marker = Join-Path $env:USERPROFILE ".config\omacheese\last-backup.txt"
if (Test-Path -LiteralPath $marker) {
    $backupDir = (Get-Content -LiteralPath $marker -Raw).Trim()
    if ($backupDir -and (Test-Path -LiteralPath $backupDir)) {
        $mf = Join-Path $backupDir "manifest.tsv"
        $n = 0
        if (Test-Path -LiteralPath $mf) {
            $n = @(Get-Content -LiteralPath $mf | Where-Object { $_ -notmatch '^#' }).Count
        }
        if ($n -gt 0) {
            $footer += ""
            $footer += "{0}Your previous config was backed up ({1} file(s)):{2}" -f ($T.Yellow + $T.Bold), $n, $T.Reset
            $footer += "  {0}{1}{2}" -f $T.Cyan, $backupDir, $T.Reset
            $footer += "  {0}restore: ./scripts/restore-backup.ps1{1}" -f $T.Dim, $T.Reset
        }
    }
}

$resume = Join-Path $RepoRoot "scripts\setup.ps1"
# Write-TuiLine pads but cannot truncate (it would cut ANSI codes mid-sequence),
# so a full path under the profile pushes the box border off screen.
if ($env:USERPROFILE -and $resume.StartsWith($env:USERPROFILE, [StringComparison]::OrdinalIgnoreCase)) {
    $resume = "~" + $resume.Substring($env:USERPROFILE.Length)
}

if ($script:RebootRequired) {
    $footer += ""
    $footer += "{0}RESTART WINDOWS to finish.{1}" -f ($T.Yellow + $T.Bold), $T.Reset
    $footer += "  {0}WSL's Windows features are enabled but inactive until then; anything" -f $T.Dim
    $footer += "  that needs a running distro was skipped rather than failed.{0}" -f $T.Reset
    $footer += "  after rebooting:"
    $footer += "    {0}wsl --install -d AlmaLinux-9{1}" -f $T.Cyan, $T.Reset
    $footer += "    {0}{1} -Modules localllm{2}" -f $T.Cyan, $resume, $T.Reset
}

$footer += ""
$footer += "{0}Next:{1}" -f $T.Bright, $T.Reset
if ($desktopUp) {
    $footer += "  {0}the desktop is running{1} - {2}SUPER + /{1} for the keymap, {2}SUPER + SPACE{1} for the menu" -f $T.Green, $T.Reset, $T.Cyan
} elseif ($didWm) {
    $footer += "  {0}./scripts/start-desktop.ps1{1}   then {0}SUPER + /{1} for the keymap" -f $T.Cyan, $T.Reset
}
if ($didRaycast) {
    if ($raycastUp) { $footer += "  {0}Raycast is open{1} - sign in, then add {2}~/.config/omacheese/raycast{1} as a script directory" -f $T.Green, $T.Reset, $T.Cyan }
    else            { $footer += "  {0}open Raycast once{1} to sign in and add {0}~/.config/omacheese/raycast{1}" -f $T.Cyan, $T.Reset }
}
if ($didWsl -and -not $script:RebootRequired) {
    # --cd takes a Windows path. Saying "wsl -d AlmaLinux-9, then bash
    # scripts/install-almalinux.sh" put you in your Linux home, where the repo
    # is not - it is on the Windows side, under /mnt.
    $footer += "  {0}set up the distro:{1}" -f $T.Cyan, $T.Reset
    $footer += "    {0}wsl -d AlmaLinux-9 --cd `"{1}`"{2}" -f $T.Cyan, $RepoRoot, $T.Reset
    $footer += "      {0}-- bash scripts/install-almalinux.sh{1}" -f $T.Cyan, $T.Reset
}
# PATH is read once per process. Everything winget just installed is missing
# from the shell this was launched from, which is why a fresh machine looked
# like it needed a full restart to run anything.
$footer += "  {0}open a NEW terminal{1}            this one still has the old PATH" -f $T.Cyan, $T.Reset
$footer += "  {0}./scripts/doctor.ps1{1}          full check including winget ids" -f $T.Cyan, $T.Reset

Write-TuiBoard -Steps $steps -Title "Done" -FooterLines $footer
Write-Host ""

if ($failed.Count) { exit 1 }
