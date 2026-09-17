# What a TUI frame is allowed to put on the wire.
#
#   pwsh -NoProfile -File ./scripts/lib/tui.tests.ps1
#
# The rendering is the whole point of the change these check: a frame is built
# in memory and written once, without ever blanking the screen, and an
# unchanged frame is not written at all. None of that is visible from the
# outside except in the bytes, and the first version of it threw on every
# frame - [Console]::Out.Write("..." -f $a, $b) binds the comma as a second
# ARGUMENT, so it picked Write(string format, object arg0) - while still
# looking fine in a benchmark that only timed the loop.

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "tui.ps1")

$e = [char]27

function Invoke-Frame {
    param([string]$Text)
    Start-TuiFrame -Width 60
    Write-TuiTop "T" 60
    Write-TuiLine $Text 60
    Write-TuiBottom 60
    Stop-TuiFrame
}

# Capture what reaches the console, without a console.
$sw  = New-Object System.IO.StringWriter
$old = [Console]::Out
[Console]::SetOut($sw)
try {
    # The first frame at a new width clears the screen once, on purpose: a
    # resized window leaves old borders standing. Spend that here so the frames
    # under test are the steady-state ones.
    Invoke-Frame "warm-up"
    [void]$sw.GetStringBuilder().Clear()

    Invoke-Frame "one"
    $first = $sw.ToString(); [void]$sw.GetStringBuilder().Clear()

    Invoke-Frame "one"
    $repeat = $sw.ToString(); [void]$sw.GetStringBuilder().Clear()

    Invoke-Frame "two"
    $changed = $sw.ToString(); [void]$sw.GetStringBuilder().Clear()
} finally {
    [Console]::SetOut($old)
}

$checks = @(
    @{ Name = "starts at home, never blanks the screen"
       Ok   = ($first.StartsWith("$e[H") -and $first -notmatch "\[2J") }
    @{ Name = "every line clears to end of line"
       Ok   = (([regex]::Matches($first, [regex]::Escape("$e[K"))).Count -eq 3) }
    @{ Name = "frame erases what fell below it"
       Ok   = $first.EndsWith("$e[0J") }
    @{ Name = "one write per frame, not one per line"
       Ok   = ($first -notmatch "`n$e\[H") }
    @{ Name = "an identical frame writes nothing"
       Ok   = ($repeat.Length -eq 0) }
    @{ Name = "a changed frame is written"
       Ok   = ($changed.Length -gt 0 -and $changed -match "two") }
)

# Reported through the writer we captured, not Write-Host: once a script has
# swapped [Console]::Out and put it back, pwsh's Write-Host stops reaching
# stdout for the rest of the process - which is why the first version of this
# file exited 1 with not one line of output to say why.
$failed = 0
foreach ($c in $checks) {
    if ($c.Ok) { $old.WriteLine("  ok    {0}", $c.Name) }
    else       { $old.WriteLine("  FAIL  {0}", $c.Name); $failed++ }
}

if ($failed) {
    $old.WriteLine("{0} check(s) failed", $failed)
    $old.Flush()
    exit 1
}
$old.WriteLine("tui frames ok")
$old.Flush()
