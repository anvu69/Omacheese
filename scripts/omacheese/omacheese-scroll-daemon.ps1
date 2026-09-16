# Keeps the Scrolling layout looking like the Omarchy horizontal strip.
#
#   omacheese-scroll-daemon.ps1                 watch komorebi and keep it right
#   omacheese-scroll-daemon.ps1 -Once           apply once and exit
#   omacheese-scroll-daemon.ps1 -Stop           stop a running daemon
#   omacheese-scroll-daemon.ps1 -WindowPercent 88
#
# WHY THIS IS A DAEMON AND NOT PART OF THE TOGGLE
#
# Two things could not be done from a one-shot script:
#
#   1. The geometry was lost whenever Scrolling was entered by any route other
#      than SUPER+CTRL+S. `komorebic cycle-layout next` (SUPER+SHIFT+L) walks
#      onto Scrolling without touching padding, so the strip came up with the
#      stock 8/6 padding and the neighbour showed a 1px sliver - which is what
#      "the peek is still only a few px" actually was.
#   2. The window at each end of the strip has nothing to reveal on its outer
#      side, so half the slack was being spent on empty screen. Fixing that
#      means reacting to focus, which means listening to komorebi.
#
# THE GEOMETRY
#
# komorebi's Scrolling layout centres the focused window inside the work area
# and parks the neighbours immediately outside it, so whatever the work area
# leaves over on each side is exactly what you see of them. The window keeps one
# width - only its position moves:
#
# workspace-work-area-offset takes LEFT and RIGHT where RIGHT is the TOTAL
# horizontal reduction, not the right inset - `komorebic workspace-work-area-offset
# --help` hints at this with "set right to left * 2 to maintain right padding".
# So RIGHT is fixed and only LEFT moves. Writing ws for workspace padding and
# cont for container padding, all of it measured rather than assumed:
#
#   window  = (monitor_width - R) - 2 * (ws + cont)
#   gap     = 2 * cont                      between adjacent windows
#   margin  = ws + cont                     top, bottom, and outer edge
#   peekL   = L + ws - cont
#   peekR   = R + ws - cont - L
#
# R follows from the width you want, and L from where the focus is:
#
#   R = monitor_width * (100 - WindowPercent) / 100 - 2 * (ws + cont)
#
#   focused is FIRST    L = cont - ws       peekL 0, everything on the right
#   focused is MIDDLE   L = R / 2           centred
#   focused is LAST     L = R + ws - cont   peekR 0, everything on the left
#
# Padding is deliberately NOT zeroed. An earlier version set both to 0 to buy a
# few more pixels of peek, and the strip came out with the windows touching each
# other and the screen edge - no gap anywhere, unlike every other layout. The
# padding komorebi.json already defines is used instead, so scrolling mode is
# spaced like BSP and only the horizontal offset is special. Measured on
# 2560x1440 at 90% with the stock 8/6 padding, window 2302px throughout:
#
#   L=0    R=228   gap 14  margin 15   peek    1px left, 229px right
#   L=114  R=228   gap 14  margin 15   peek  115px each side
#   L=230  R=228   gap 14  margin 15   peek  231px left,   0px right
#
# A workspace holding one window gets no offset at all - there is no neighbour
# to reveal, so spending 10% of the screen on it would be pure waste.
#
# WHY THE WATCHER NEVER CALLS komorebic
#
# This is the part that is easy to get wrong, and it cost a long debugging
# session. A komorebi event pipe accepts exactly ONE server and komorebi BLOCKS
# writing to it. So if the process draining the pipe stops to run `komorebic
# state`, the two deadlock: komorebic is waiting for komorebi to answer, and
# komorebi is waiting to finish an event write that nobody is reading. It
# resolves on a timeout, but in the meantime the whole window manager is frozen
# and `komorebic state` stops answering for anyone.
#
# So the watcher only ever reads. It parses the state out of the event payload
# itself - every event carries a full copy - and when something needs changing
# it hands the work to a detached `-Once` process, which is free to talk to
# komorebi because it is not holding the pipe.

[CmdletBinding()]
param(
    [ValidateRange(0, 100)]
    [int]$WindowPercent = 0,
    [switch]$Once,
    [switch]$Stop
)

$ErrorActionPreference = "SilentlyContinue"

$ConfigHome     = Join-Path $env:USERPROFILE ".config\omacheese"
$SettingsFile   = Join-Path $ConfigHome "scrolling.json"
$PidFile        = Join-Path $ConfigHome "scroll-daemon.pid"
$PipeName       = "omacheese-scroll"
$DefaultPercent = 90

$env:KOMOREBI_CONFIG_HOME = Join-Path $env:USERPROFILE ".config\komorebi"

function Get-WindowPercent {
    if ($script:PercentOverride) { return $script:PercentOverride }
    try {
        if (Test-Path -LiteralPath $SettingsFile) {
            $v = (Get-Content -LiteralPath $SettingsFile -Raw | ConvertFrom-Json).window_percent
            if ($v -ge 60 -and $v -le 100) { return [int]$v }
        }
    } catch { }
    return $DefaultPercent
}

function Save-WindowPercent {
    param([int]$Value)
    try {
        if (-not (Test-Path -LiteralPath $ConfigHome)) {
            New-Item -ItemType Directory -Path $ConfigHome -Force | Out-Null
        }
        @{ window_percent = $Value } | ConvertTo-Json |
            Set-Content -LiteralPath $SettingsFile -Encoding ASCII
    } catch { }
}

# komorebi.json is where the non-scrolling padding lives, so that is what the
# strip hands back when you leave it.
function Get-DefaultPadding {
    $pad = @{ Workspace = 8; Container = 6 }
    try {
        $k = Join-Path $env:USERPROFILE ".config\komorebi\komorebi.json"
        if (Test-Path -LiteralPath $k) {
            $cfg = Get-Content -LiteralPath $k -Raw | ConvertFrom-Json
            if ($null -ne $cfg.default_workspace_padding) { $pad.Workspace = [int]$cfg.default_workspace_padding }
            if ($null -ne $cfg.default_container_padding) { $pad.Container = [int]$cfg.default_container_padding }
        }
    } catch { }
    return $pad
}

function Get-LayoutName {
    param($Workspace)
    if (-not $Workspace.layout) { return "" }
    if ($Workspace.layout.PSObject.Properties.Name -contains "Default") {
        return [string]$Workspace.layout.Default
    }
    return [string]$Workspace.layout
}

# Pure: works out what every workspace should look like and returns only the
# ones that are wrong. Takes a state object so it can be fed either from
# `komorebic state` or straight out of an event payload.
function Get-StripPlan {
    param($State, [int]$Percent, $Padding)

    $plan = @()
    if (-not $State -or -not $State.monitors) { return $plan }
    if (-not $Padding) { $Padding = Get-DefaultPadding }
    $wsPad   = [int]$Padding.Workspace
    $contPad = [int]$Padding.Container

    for ($mi = 0; $mi -lt $State.monitors.elements.Count; $mi++) {
        $mon = $State.monitors.elements[$mi]

        $width = 1920
        if ($mon.work_area_size -and $mon.work_area_size.right) { $width = [int]$mon.work_area_size.right }
        elseif ($mon.size -and $mon.size.right)                 { $width = [int]$mon.size.right }

        for ($wi = 0; $wi -lt $mon.workspaces.elements.Count; $wi++) {
            $ws   = $mon.workspaces.elements[$wi]
            $off  = $ws.work_area_offset
            $curL = if ($off) { [int]$off.left }  else { 0 }
            $curR = if ($off) { [int]$off.right } else { 0 }

            if ((Get-LayoutName $ws) -match "Scrolling") {
                $n     = $ws.containers.elements.Count
                $slack = 0
                $left  = 0
                if ($n -gt 1) {
                    # The padding sits inside the offset, so it has to come out
                    # of the slack or the window ends up narrower than asked.
                    $slack = [int][math]::Round($width * (100 - $Percent) / 100.0) - 2 * ($wsPad + $contPad)
                    if ($slack -lt 0) { $slack = 0 }
                    $bias = $wsPad - $contPad
                    $f = [int]$ws.containers.focused
                    if     ($f -le 0)      { $left = [math]::Max(0, -$bias) }
                    elseif ($f -ge $n - 1) { $left = $slack + $bias }
                    else                   { $left = [int][math]::Round($slack / 2.0) }
                    if ($left -lt 0) { $left = 0 }
                }

                $wrong = ($curL -ne $left) -or ($curR -ne $slack) -or
                         ([int]$ws.workspace_padding -ne $wsPad) -or
                         ([int]$ws.container_padding -ne $contPad)

                # Settings agreeing is not the same as the windows being right.
                # A layout pass that lands after we set the offset re-tiles to
                # the old geometry and leaves the settings looking correct, so
                # check the focused window against the width the offset implies.
                # Without this the strip could come up full width with a 1px
                # sliver and nothing would ever correct it.
                if (-not $wrong -and $n -gt 0) {
                    $fi = [int]$ws.containers.focused
                    if ($fi -ge 0 -and $fi -lt $n) {
                        $fwin = $ws.containers.elements[$fi].windows.elements[0]
                        if ($fwin -and $fwin.rect) {
                            $expected = $width - $slack - 2 * ($wsPad + $contPad)
                            if ([math]::Abs([int]$fwin.rect.right - $expected) -gt 8) { $wrong = $true }
                        }
                    }
                }

                if ($wrong) {
                    $plan += @{ Monitor = $mi; Workspace = $wi; Scrolling = $true
                                Left = $left; Slack = $slack
                                WsPad = $wsPad; ContPad = $contPad }
                }
            }
            elseif ($curL -ne 0 -or $curR -ne 0) {
                # Only touch workspaces carrying an offset - that offset is ours,
                # so this cleans up after the strip without trampling padding the
                # user set by hand on some other layout.
                $plan += @{ Monitor = $mi; Workspace = $wi; Scrolling = $false }
            }
        }
    }
    return ,$plan
}

# Talks to komorebi. Only ever called from -Once, never from the watcher.
function Invoke-StripPlan {
    param($Plan)
    if (-not $Plan -or $Plan.Count -eq 0) { return }
    $pad = Get-DefaultPadding
    foreach ($item in $Plan) {
        $mi = $item.Monitor; $wi = $item.Workspace
        if ($item.Scrolling) {
            # Each of these re-tiles on its own, so no explicit retile is needed.
            # The padding is the same as every other layout uses - only the
            # offset is particular to the strip.
            komorebic workspace-work-area-offset $mi $wi $item.Left 0 $item.Slack 0 2>$null | Out-Null
            komorebic workspace-padding $mi $wi $item.WsPad 2>$null | Out-Null
            komorebic container-padding $mi $wi $item.ContPad 2>$null | Out-Null
        } else {
            komorebic workspace-work-area-offset $mi $wi 0 0 0 0 2>$null | Out-Null
            komorebic workspace-padding $mi $wi $pad.Workspace 2>$null | Out-Null
            komorebic container-padding $mi $wi $pad.Container 2>$null | Out-Null
        }
    }
}

function Sync-Strip {
    try { $state = komorebic state 2>$null | ConvertFrom-Json } catch { return }
    if (-not $state) { return }
    Invoke-StripPlan (Get-StripPlan -State $state -Percent (Get-WindowPercent) -Padding (Get-DefaultPadding))
}

# ---------------------------------------------------------------------------

if ($WindowPercent -gt 0) {
    $script:PercentOverride = $WindowPercent
    Save-WindowPercent $WindowPercent
}

if ($Stop) {
    try {
        if (Test-Path -LiteralPath $PidFile) {
            $old = [int](Get-Content -LiteralPath $PidFile -Raw).Trim()
            Stop-Process -Id $old -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
        }
    } catch { }
    komorebic unsubscribe-pipe $PipeName 2>$null | Out-Null
    exit 0
}

if ($Once) { Sync-Strip; exit 0 }

# One daemon per session, and this guard is not optional: the event pipe accepts
# exactly ONE server, so a second copy subscribing under the same name leaves
# komorebi blocked trying to connect and it stops answering at all. Local\
# rather than Global\ - the global namespace can throw depending on how the
# process was launched, and a guard that throws is a guard that is not there.
$mutex = $null
try { $mutex = New-Object System.Threading.Mutex($false, "Local\omacheese-scroll-daemon") } catch { $mutex = $null }
if ($mutex) {
    if (-not $mutex.WaitOne(0)) { exit 0 }
} else {
    try {
        if (Test-Path -LiteralPath $PidFile) {
            $prev = [int](Get-Content -LiteralPath $PidFile -Raw).Trim()
            if (Get-Process -Id $prev -ErrorAction SilentlyContinue) { exit 0 }
        }
    } catch { }
}
try { $PID | Set-Content -LiteralPath $PidFile -Encoding ASCII } catch { }

$Self = $PSCommandPath
$PwshExe = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
if (-not $PwshExe) { $PwshExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" }

# Hand the komorebic work to a separate process. See the header: doing it here
# would deadlock against the pipe we are draining.
function Request-Apply {
    Start-Process -FilePath $PwshExe `
        -ArgumentList "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$Self`"", "-Once" `
        -WindowStyle Hidden -ErrorAction SilentlyContinue
}

# Read once: the watcher must not touch the disk on every event either.
$padDefaults = Get-DefaultPadding

$server    = $null
$pending   = $null
$buffer    = New-Object byte[] 65536
$text      = New-Object System.Text.StringBuilder
$dirty     = $false
$lastData  = [datetime]::UtcNow
$lastSpawn = [datetime]::MinValue

function Connect-Pipe {
    if ($script:server) { try { $script:server.Dispose() } catch { } }
    $script:pending = $null
    $script:server = New-Object System.IO.Pipes.NamedPipeServerStream(
        $PipeName, [System.IO.Pipes.PipeDirection]::In, 1,
        [System.IO.Pipes.PipeTransmissionMode]::Byte,
        [System.IO.Pipes.PipeOptions]::Asynchronous)
    # Drop any subscription komorebi still thinks it has under this name first;
    # a second one under the same name wedges it.
    komorebic unsubscribe-pipe $PipeName 2>$null | Out-Null
    komorebic subscribe-pipe $PipeName 2>$null | Out-Null
    $t = $script:server.WaitForConnectionAsync()
    return $t.Wait(15000)
}

# Safe to call komorebi here - the pipe does not exist yet.
Sync-Strip
if (-not (Connect-Pipe)) { exit 1 }

while ($true) {
    if (-not $pending) { $pending = $server.ReadAsync($buffer, 0, $buffer.Length) }

    # Wait on the outstanding read rather than starting a second one - ReadAsync
    # throws "the stream is currently in use" if one is already in flight.
    if ($pending.Wait(250)) {
        $n = 0
        try { $n = $pending.Result } catch { $n = 0 }
        $pending = $null
        if ($n -le 0) {
            # komorebi went away or restarted; take the subscription again.
            if (-not (Connect-Pipe)) { Start-Sleep -Seconds 2 }
            continue
        }
        [void]$text.Append([System.Text.Encoding]::UTF8.GetString($buffer, 0, $n))
        $dirty = $true
        $lastData = [datetime]::UtcNow
    }

    # One user action emits several events, each carrying the whole state.
    # Coalesce the burst and look at the last complete one only.
    if ($dirty -and ([datetime]::UtcNow - $lastData).TotalMilliseconds -ge 140) {
        $dirty = $false
        $payload = $text.ToString()
        [void]$text.Clear()

        # Cheap reject before the expensive parse. komorebi emits events even
        # when nothing is happening, and parsing ~8KB of JSON each time costs
        # about 1% of a core all day. If the payload mentions neither the
        # Scrolling layout nor a work area offset of ours, there is nothing this
        # daemon could possibly want to do with it.
        if ($payload -notlike '*Scrolling*' -and $payload -notlike '*"work_area_offset":{*') {
            continue
        }

        # Events are newline delimited. Walk back to the last line that parses;
        # a trailing partial write is dropped, since the next event supersedes it
        # anyway.
        $state = $null
        $lines = $payload -split "`n"
        for ($i = $lines.Count - 1; $i -ge 0; $i--) {
            $line = $lines[$i].Trim()
            if ($line.Length -lt 2) { continue }
            try {
                $obj = $line | ConvertFrom-Json
                if ($obj.state) { $state = $obj.state; break }
            } catch { }
        }

        if ($state) {
            $plan = Get-StripPlan -State $state -Percent (Get-WindowPercent) -Padding $padDefaults
            # Throttle: an apply produces events of its own, and the state in
            # this payload is already a moment old.
            if ($plan.Count -gt 0 -and
                ([datetime]::UtcNow - $lastSpawn).TotalMilliseconds -ge 500) {
                $lastSpawn = [datetime]::UtcNow
                Request-Apply
            }
        }
    }
}
