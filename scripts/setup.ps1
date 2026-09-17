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
    [switch]$Yes,

    # Set by the RunOnce entry written when a step needs Windows restarted.
    # Nothing else should pass it.
    [switch]$Resume
)

$ErrorActionPreference = "Stop"

# powershell.exe -File binds "a,b,c" to a [string[]] parameter as ONE element,
# unlike -Command. Split here so both invocation styles behave the same.
if ($Modules) { $Modules = @($Modules -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }

$RepoRoot = Split-Path -Parent $PSScriptRoot

# --- resume after a restart --------------------------------------------------
# See scripts\lib\resume.ps1. Every question was answered before the restart,
# so a resumed run asks none.
. (Join-Path $RepoRoot "scripts\lib\resume.ps1")
$script:LinuxPassword = $null
$script:DistroAgents  = ""
$saved = $null
if ($Resume) {
    $saved = Read-SetupResume
    if (-not $saved) {
        Write-Host "Nothing to resume." -ForegroundColor DarkGray
        return
    }
    $Modules = @($saved.Modules)
    $script:DistroAgents  = $saved.DistroAgents
    $script:LinuxPassword = $saved.LinuxPassword
    $Yes = $true
}

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

# Steps that run doctor.ps1 for you when started on their own (link-configs,
# debloat, install-windows, start-desktop) check this and leave it to the setup,
# which runs it once, last. Inherited by every step started from here; the
# elevated ones get it written into their command line, since a process started
# through UAC does not reliably inherit this one's environment.
$env:OMACHEESE_SETUP_RUN = $RunDir

function Write-SetupLog {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $Message
    # A log line must never be what ends an install. Under
    # ErrorActionPreference=Stop, Add-Content failing on a sharing violation -
    # anything holding setup.log open to read it: a `tail -f`, a
    # `Get-Content -Wait`, a virus scanner - threw straight out of the run loop.
    # Measured: the distro step finished its whole job and the setup died on
    # the next line of its own log. Retry briefly, then drop the line.
    for ($try = 0; $try -lt 5; $try++) {
        try {
            $fs = New-Object System.IO.FileStream($MainLog, [System.IO.FileMode]::Append,
                [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)
            try {
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($line + "`r`n")
                $fs.Write($bytes, 0, $bytes.Length)
            } finally { $fs.Dispose() }
            return
        } catch {
            Start-Sleep -Milliseconds 100
        }
    }
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
        # verify is not offered: it always runs, last. See below.
        $selectedKeys = Show-TuiChecklist -Items @($allModules | Where-Object { $_.Key -ne "verify" }) `
            -Title "Modules" -HeaderLines $checkHeader
        if ($null -eq $selectedKeys) { Clear-Tui; Write-Host "Cancelled."; return }
    } else {
        $selectedKeys = @($allModules | Where-Object { $_.Selected } | ForEach-Object { $_.Key })
    }
}

$steps = @($allModules | Where-Object { $selectedKeys -contains $_.Key })
if (-not $steps.Count) { Clear-Tui; Write-Host "Nothing selected."; return }

# --- debloat: which groups ---------------------------------------------------
# debloat-windows.ps1 asks this itself when it has a console. As a step it does
# not: every step runs with stdin redirected to an empty file, so the script
# saw no console, took its defaults - tiling AND removing 24 apps - and nobody
# was asked. Measured by running it exactly as the step does. So the question
# is put here, where the person is, and the step is handed the answer.
#
# Before the plan, so the plan shows what was picked. Not under -Yes, which
# means "defaults, no questions", and not under -DryRun, which is documented for
# consoles that cannot answer (see the checklist note above).
$script:DebloatArgs = @()
if (($steps | Where-Object { $_.Key -eq "debloat" }) -and -not $Yes -and -not $DryRun) {
    . (Join-Path $RepoRoot "scripts\lib\debloat.ps1")
    $dbCfg = Get-Content -LiteralPath (Join-Path $RepoRoot "configs\windows\debloat.json") -Raw | ConvertFrom-Json

    $dbPicked = Show-TuiChecklist -Items (Get-DebloatGroupItems -DebloatConfig $dbCfg) -Title "Debloat" -HeaderLines @(
        "Which parts of the debloat to apply. Only tiling is needed by komorebi.",
        ("{0}Settings are reversible; removing apps is not.{1}" -f $T.Dim, $T.Reset)
    )
    if ($null -eq $dbPicked) { Clear-Tui; Write-Host "Cancelled."; return }

    if (@($dbPicked).Count -eq 0) {
        # An empty answer is an answer: drop the step rather than run it to do
        # nothing, and say so on the plan's absence rather than silently.
        $steps = @($steps | Where-Object { $_.Key -ne "debloat" })
        if (-not $steps.Count) { Clear-Tui; Write-Host "Nothing selected."; return }
    } else {
        $script:DebloatArgs = @("-Groups", (@($dbPicked) -join ","))
        foreach ($s in $steps) {
            if ($s.Key -eq "debloat") { $s.Description = "Win11Debloat: " + (@($dbPicked) -join ", ") }
        }
    }
}

# --- distro: the Linux password ----------------------------------------------
# install-distro.ps1 creates a Linux user named after this Windows account. It
# needs a password for sudo, and once steps start there is no console to type
# one into - so it is asked here, with the other questions, and only when the
# account does not already have one. Under -Yes nothing is asked: the account
# is created without a password and the next interactive run asks.
if (($steps | Where-Object { $_.Key -eq "distro" }) -and -not $DryRun) {
    . (Join-Path $RepoRoot "scripts\lib\distro.ps1")

    # The agents installed on the Windows side, installed inside WSL as well,
    # when the agents module is part of this run.
    if ($steps | Where-Object { $_.Key -eq "agents" }) { $script:DistroAgents = "claude,codex" }

    if (-not $Yes -and -not $script:LinuxPassword) {
        $linuxUser = ConvertTo-LinuxUserName -Name $env:USERNAME
        if ((Get-DistroUserState -Distro "AlmaLinux-9" -User $linuxUser) -ne "ready") {
            Clear-Tui
            Write-Host ""
            Write-Host ("  {0}WSL: Linux user '{1}'{2}" -f ($T.Bright + $T.Bold), $linuxUser, $T.Reset)
            Write-Host ("  {0}The distro step creates this account. Its password is what sudo asks for{1}" -f $T.Dim, $T.Reset)
            Write-Host ("  {0}inside WSL - it is not your Windows password unless you make it so.{1}" -f $T.Dim, $T.Reset)
            Write-Host ""
            $script:LinuxPassword = Read-LinuxPassword -User $linuxUser
            if (-not $script:LinuxPassword) {
                Write-Host ("  {0}no password - the account is created without one, and the next run asks again{1}" -f $T.Yellow, $T.Reset)
            }
        }
    }
}

# --- verify: always, last ----------------------------------------------------
# It used to be a module like any other - untickable, left out of Custom, and
# run with -Quick when it did run - and the summary then told you to go and run
# ./scripts/doctor.ps1 yourself for the full check. Nobody should have to finish
# an installer by hand. The full check costs ~21s against ~8s for -Quick, on a
# run measured in minutes, and what it finds is printed in the summary.
$verifyStep = $allModules | Where-Object { $_.Key -eq "verify" } | Select-Object -First 1
$steps = @($steps | Where-Object { $_.Key -ne "verify" })
if ($verifyStep) { $steps += $verifyStep }

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

    # A Windows PowerShell child must not inherit pwsh 7's module directories.
    # Started from a pwsh 7 session it does - they come first in PSModulePath -
    # and it then loads the Core build of Microsoft.PowerShell.Security and
    # friends and fails on them: "command was found in the module ... but the
    # module could not be loaded". Measured with ConvertTo-SecureString: fails
    # on the inherited path, works on the filtered one. The debloat step runs in
    # Windows PowerShell on purpose, so a setup started from pwsh 7 handed it a
    # broken module path.
    $savedModulePath = $env:PSModulePath
    if ($psExe -like "*\WindowsPowerShell\v1.0\powershell.exe") {
        $env:PSModulePath = (@($env:PSModulePath -split ';' | Where-Object {
            $_ -and $_ -notlike '*\Documents\PowerShell\Modules*' -and
                    $_ -notlike '*\Program Files\PowerShell\*' -and
                    $_ -notlike '*\WindowsApps\Microsoft.PowerShell_*' }) -join ';')
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
        #
        # It transcribes itself instead. Without this an elevated step left NO
        # log: its window closes the moment it ends, and a step that failed in
        # it - debloat did - reported "see debloat.log" against a file that was
        # never written. Start-Transcript is the only redirection available to
        # a process this one cannot pipe.
        # PSModulePath is written into the command too: whether a UAC-started
        # process inherits this environment is not something to rely on.
        $inner = "`$env:PSModulePath = '{4}'; `$env:OMACHEESE_SETUP_RUN = '{3}'; Start-Transcript -LiteralPath '{0}' -Force | Out-Null; try {{ & '{1}'{2}; exit `$LASTEXITCODE }} finally {{ try {{ Stop-Transcript | Out-Null }} catch {{ }} }}" -f `
            $log.Replace("'", "''"), $File.Replace("'", "''"), $(if ($Arguments -and $Arguments.Count) { " " + ($Arguments -join " ") } else { "" }), $RunDir.Replace("'", "''"), $env:PSModulePath.Replace("'", "''")
        $elevArgs = '-NoProfile -ExecutionPolicy Bypass -Command "{0}"' -f $inner.Replace('"', '\"')

        try {
            $p = Start-Process -FilePath $psExe -ArgumentList $elevArgs -Verb RunAs -PassThru -Wait
        } catch {
            $env:PSModulePath = $savedModulePath
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
        $env:PSModulePath = $savedModulePath
        try { $p.WaitForExit() } catch { }
        return $p.ExitCode
    }

    try {
        $p = Start-Process -FilePath $psExe -ArgumentList $argLine `
            -NoNewWindow -PassThru `
            -RedirectStandardInput $NullIn `
            -RedirectStandardOutput $log -RedirectStandardError "$log.err"
    } finally {
        # The child has its copy; this process keeps the one it started with.
        $env:PSModulePath = $savedModulePath
    }

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
            -Arguments $script:DebloatArgs -WindowsPowerShell -Elevate
    }
    InstallDesktop = {
        $code = Invoke-Step -Key "pkg-desktop" -File (Join-Path $RepoRoot "scripts\install-windows.ps1") `
            -Arguments @("-Groups", "desktop", "-SkipModules")
        # Bitwarden's SSH agent needs the pipe Windows' own agent service holds.
        # Checked first: reading the start type needs no admin, so a machine
        # where it is already done gets no UAC prompt for it.
        $svc = Get-Service ssh-agent -ErrorAction SilentlyContinue
        if ($code -eq 0 -and $svc -and $svc.StartType -ne "Disabled") {
            $code = Invoke-Step -Key "ssh-agent" -File (Join-Path $RepoRoot "scripts\disable-openssh-agent.ps1") `
                -Arguments @() -Elevate
        }
        $code
    }
    InstallWsl = {
        Invoke-Step -Key "wsl" -File (Join-Path $RepoRoot "scripts\install-wsl.ps1") -Arguments @() -Elevate
    }
    InstallDistro = {
        $distroArgs = @()
        if ($script:DistroAgents) { $distroArgs = @("-Agents", $script:DistroAgents) }
        # The password travels in this process's environment for the length of
        # one Start-Process: inherited by the step, never on a command line, never
        # on disk. install-distro.ps1 removes it from its own copy on read.
        if ($script:LinuxPassword) { $env:OMACHEESE_LINUX_PASSWORD = $script:LinuxPassword }
        try {
            Invoke-Step -Key "distro" -File (Join-Path $RepoRoot "scripts\install-distro.ps1") -Arguments $distroArgs
        } finally {
            Remove-Item Env:OMACHEESE_LINUX_PASSWORD -ErrorAction SilentlyContinue
            $script:LinuxPassword = $null
        }
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
        $code = Invoke-Step -Key "verify" -File (Join-Path $RepoRoot "scripts\doctor.ps1") -Arguments @()

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
$NeedsRunningWsl = @("distro", "localllm")
$script:ResumeKeys = @()

for ($i = 0; $i -lt $steps.Count; $i++) {
    $s = $steps[$i]

    if ($script:RebootRequired -and $NeedsRunningWsl -contains $s.Key) {
        $s.Status = "Skipped"
        $s.Detail = "runs by itself after the restart"
        $script:ResumeKeys += $s.Key
        Write-SetupLog "$($s.Key): Skipped (reboot pending, resumes after restart)"
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
$didDesktop = @($steps | Where-Object { $_.Key -eq "desktop" -and $_.Status -eq "Done" }).Count -gt 0
$didDistro  = @($steps | Where-Object { $_.Key -eq "distro"  -and $_.Status -eq "Done" }).Count -gt 0

# Apps that do nothing useful until someone signs in or flips a setting. They
# are opened here, at the end, so the settings get done while the person is
# still at the machine - and what to do in each is on the summary below.
# Raycast wants an account; Bitwarden wants a sign-in and its SSH agent
# switched on (the Windows agent service was already handed over during the
# desktop step); Brave wants a profile and asks to be the default browser.
$appsToOpen = @()
if ($didRaycast) { $appsToOpen += "Raycast" }
if ($didDesktop) { $appsToOpen += @("Bitwarden", "Brave") }
if ($saved) { $appsToOpen += @($saved.OpenApps) }
$appsToOpen = @($appsToOpen | Select-Object -Unique)

# Not while a restart is pending: it would close them again. They are carried
# into the resume state instead and opened after the restart.
$openedApps = @()
if (-not $script:RebootRequired) {
    foreach ($app in $appsToOpen) {
        if (Start-StartMenuApp -Name $app) { $openedApps += $app }
        Write-SetupLog "open $app : $($openedApps -contains $app)"
    }
}
$raycastUp = $openedApps -contains "Raycast"

# Debloat settings that Windows only reads at sign-in. Win11Debloat says which:
# "Warning: 'Disable window snapping' requires a reboot to take full effect".
$script:RestartRecommended = @()
$debloatLog = Join-Path $RunDir "debloat.log"
if (Test-Path -LiteralPath $debloatLog) {
    $script:RestartRecommended = @(Get-Content -LiteralPath $debloatLog |
        Where-Object { $_ -match "'(.+)' requires a reboot to take full effect" } |
        ForEach-Object { $Matches[1] } | Select-Object -Unique)
}

# --- carry on after the restart ----------------------------------------------
if ($script:RebootRequired -and $script:ResumeKeys.Count) {
    $resumeCmd = Save-SetupResume -Modules $script:ResumeKeys -SetupScript (Join-Path $RepoRoot "scripts\setup.ps1") `
        -DistroAgents $script:DistroAgents -OpenApps $appsToOpen -LinuxPassword $script:LinuxPassword
    Write-SetupLog "resume registered: $($script:ResumeKeys -join ',') via RunOnce: $resumeCmd"
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

if ($script:RebootRequired) {
    # Said plainly and first: what needs the restart, why, and that nothing has
    # to be remembered across it.
    $footer += ""
    $footer += "{0}RESTART WINDOWS to finish.{1}" -f ($T.Yellow + $T.Bold), $T.Reset
    $footer += "  {0}WSL was just enabled. Its Windows features only start after a restart,{1}" -f $T.Fg, $T.Reset
    $footer += "  {0}so nothing that needs a running Linux could run yet.{1}" -f $T.Fg, $T.Reset
    if ($script:ResumeKeys.Count) {
        $footer += "  {0}After you sign in again, this setup carries on by itself:{1} {2}" -f $T.Green, $T.Reset, ($script:ResumeKeys -join ", ")
        $footer += "  {0}(a PowerShell window opens for it - nothing to type){1}" -f $T.Dim, $T.Reset
    }
} elseif ($script:RestartRecommended.Count) {
    $footer += ""
    $footer += "{0}Restart recommended{1} - nothing is waiting on it, but these only take" -f ($T.Yellow + $T.Bold), $T.Reset
    $footer += "  full effect after one:"
    foreach ($r in ($script:RestartRecommended | Select-Object -First 4)) {
        $footer += "    {0}{1}{2}" -f $T.Dim, $r, $T.Reset
    }
}

# A terminal started from this setup inherits the PATH this process refreshed
# after every step. The one the setup was launched from does not - PATH is read
# once per process - which is why everything winget installed looked missing
# there. So open a new one rather than telling people to.
$newTerminal = $false
$pathChanged = @($steps | Where-Object { $_.Key -in @("core", "cli", "langs", "dotnet", "agents") -and $_.Status -eq "Done" }).Count -gt 0
if ($pathChanged -and -not $script:RebootRequired) {
    $term = Get-Command alacritty -ErrorAction SilentlyContinue
    try {
        if ($term) { Start-Process -FilePath $term.Source -WorkingDirectory $env:USERPROFILE; $newTerminal = $true }
    } catch { }
    Write-SetupLog "new terminal: $newTerminal"
}

$footer += ""
$footer += "{0}Next:{1}" -f $T.Bright, $T.Reset
if ($desktopUp) {
    $footer += "  {0}the desktop is running{1} - {2}SUPER + /{1} for the keymap, {2}SUPER + SPACE{1} for the menu" -f $T.Green, $T.Reset, $T.Cyan
} elseif ($didWm) {
    $footer += "  {0}the desktop did not start{1} - what went wrong is in desktop-start.log" -f $T.Red, $T.Reset
}
foreach ($app in $openedApps) {
    switch ($app) {
        "Raycast"   { $footer += "  {0}Raycast is open{1}    sign in, then add {2}~/.config/omacheese/raycast{1} as a script directory" -f $T.Green, $T.Reset, $T.Cyan }
        "Bitwarden" { $footer += "  {0}Bitwarden is open{1}  sign in, then Settings > turn on the SSH agent" -f $T.Green, $T.Reset }
        "Brave"     { $footer += "  {0}Brave is open{1}      set up your profile; it will offer to be the default browser" -f $T.Green, $T.Reset }
    }
}
foreach ($app in @($appsToOpen | Where-Object { $openedApps -notcontains $_ })) {
    if (-not $script:RebootRequired) {
        $footer += "  {0}{1} did not open{2} - find it in the Start menu" -f $T.Yellow, $app, $T.Reset
    }
}
if ($didDistro) {
    $footer += "  {0}WSL is ready{1}       {2}wsl{1} opens AlmaLinux as {3} in zsh" -f $T.Green, $T.Reset, $T.Cyan, (ConvertTo-LinuxUserName -Name $env:USERNAME)
}
if ($newTerminal) {
    $footer += "  {0}a new terminal is open{1} with the updated PATH - this one still has the old one" -f $T.Green, $T.Reset
} elseif ($pathChanged -and -not $script:RebootRequired) {
    $footer += "  {0}open a NEW terminal{1} - this one still has the old PATH" -f $T.Cyan, $T.Reset
}

# What the verify step found, printed here instead of "run ./scripts/doctor.ps1"
# - it has just been run, in full, so the answer is already on disk.
$verifyLog = Join-Path $RunDir "verify.log"
if (Test-Path -LiteralPath $verifyLog) {
    $left = @(Get-Content -LiteralPath $verifyLog |
        ForEach-Object { $_ -replace ("{0}\[[0-9;]*m" -f [char]27), "" } |
        Where-Object { $_ -match '^\s*(WARN|FAIL)\s+(.+)$' } |
        ForEach-Object { [pscustomobject]@{ Level = $Matches[1]; Text = $Matches[2].Trim() } })

    $footer += ""
    if ($left.Count) {
        $footer += "{0}Still to look at{1} ({2}):" -f $T.Bright, $T.Reset, $script:DoctorSummary
        # Write-TuiLine pads but cannot truncate, so cut the plain text first;
        # doctor lines carry a remedy in brackets and can run long.
        $room = (Get-TuiWidth) - 14
        $shown = 0
        foreach ($l in ($left | Sort-Object { if ($_.Level -eq "FAIL") { 0 } else { 1 } })) {
            if ($shown -ge 10) { break }
            $txt = $l.Text
            if ($txt.Length -gt $room) { $txt = $txt.Substring(0, $room - 3) + "..." }
            $col = if ($l.Level -eq "FAIL") { $T.Red } else { $T.Yellow }
            $footer += "  {0}{1}{2}  {3}" -f $col, $l.Level, $T.Reset, $txt
            $shown++
        }
        if ($left.Count -gt $shown) {
            $footer += "  {0}...and {1} more in verify.log{2}" -f $T.Dim, ($left.Count - $shown), $T.Reset
        }
    } else {
        $footer += "{0}Verified: {1}.{2}" -f $T.Green, $script:DoctorSummary, $T.Reset
    }
}

Write-TuiBoard -Steps $steps -Title "Done" -FooterLines $footer
Write-Host ""

# Offer the restart instead of leaving it as homework. Default No: a stray Enter
# must not reboot a machine with unsaved work on it, and -Yes never restarts on
# its own for the same reason. The countdown is long enough to save a file.
if (($script:RebootRequired -or $script:RestartRecommended.Count) -and -not $Yes) {
    $question = "Restart Windows now?"
    if ($script:RebootRequired -and $script:ResumeKeys.Count) {
        $question = "Restart Windows now? Setup continues by itself after you sign in."
    }
    if (Confirm-Tui $question -DefaultNo) {
        & shutdown.exe /r /t 30 /c "Omacheese setup: restarting to finish. Save your work - cancel with: shutdown /a"
        Write-Host ("  {0}Restarting in 30 seconds. Save your work.{1}" -f ($T.Yellow + $T.Bold), $T.Reset)
    } elseif ($script:RebootRequired) {
        Write-Host ("  {0}Restart whenever you are ready - setup picks up on the next sign-in.{1}" -f $T.Dim, $T.Reset)
    }
}

if ($failed.Count) { exit 1 }
