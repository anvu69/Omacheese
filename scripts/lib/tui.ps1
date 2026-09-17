# Zero-dependency TUI primitives.
#
# Deliberately written against Windows PowerShell 5.1, because the whole point
# is to run on a machine where nothing is installed yet: no pwsh 7, no fzf, no
# node, no modules. That rules out ternaries, ??, and anything else from 7.x.
#
# Rendering is plain ANSI. conhost does not enable virtual terminal processing
# by default, so Initialize-Tui turns it on rather than assuming a terminal
# that already does (Windows Terminal does; the classic console host does not).

Set-StrictMode -Version 2.0

# --- Tokyo Night, matching yasb/alacritty/komorebi ---------------------------
# Built from [char]27 rather than the `e escape: `e only exists in PowerShell 6
# and later. On 5.1 the backtick is silently dropped and you get a literal "e",
# which prints garbage instead of colour.
$script:E = [string][char]27

$script:Tui = @{
    Esc     = $script:E
    Fg      = "$script:E[38;2;169;177;214m"
    Dim     = "$script:E[38;2;86;95;137m"
    Bright  = "$script:E[38;2;192;202;245m"
    Accent  = "$script:E[38;2;122;162;247m"
    Magenta = "$script:E[38;2;187;154;247m"
    Green   = "$script:E[38;2;158;206;106m"
    Yellow  = "$script:E[38;2;224;175;104m"
    Red     = "$script:E[38;2;247;118;142m"
    Cyan    = "$script:E[38;2;125;207;255m"
    Reset   = "$script:E[0m"
    Bold    = "$script:E[1m"
    SelBg   = "$script:E[48;2;41;46;66m"
}

$script:TuiVtEnabled = $false

function Initialize-Tui {
    [CmdletBinding()]
    param()

    try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new() } catch { }

    if ($script:TuiVtEnabled) { return }

    # ENABLE_VIRTUAL_TERMINAL_PROCESSING = 0x0004 on the output handle.
    #
    # DisableQuickEdit is the other half, and it fixes a bug that looks nothing
    # like a console setting. With QuickEdit on - the Windows default - a single
    # click anywhere in the window puts the console into selection mode, and
    # every write from the process blocks until someone presses Enter or Esc.
    # During a 10-minute winget or WSL step that reads as a hang: the work
    # underneath has finished, the installer looks frozen, and pressing Enter
    # "resumes" it. ENABLE_EXTENDED_FLAGS (0x0080) has to be set in the same
    # call or clearing ENABLE_QUICK_EDIT_MODE (0x0040) is ignored.
    $sig = @'
using System;
using System.Runtime.InteropServices;
public static class TuiNative {
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern IntPtr GetStdHandle(int nStdHandle);
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);
    public static bool EnableVt() {
        IntPtr h = GetStdHandle(-11);
        uint mode;
        if (!GetConsoleMode(h, out mode)) return false;
        return SetConsoleMode(h, mode | 0x0004);
    }
    public static bool DisableQuickEdit() {
        IntPtr h = GetStdHandle(-10);
        uint mode;
        if (!GetConsoleMode(h, out mode)) return false;
        mode = (mode & ~0x0040u) | 0x0080u;
        return SetConsoleMode(h, mode);
    }
}
'@
    try {
        if (-not ([System.Management.Automation.PSTypeName]'TuiNative').Type) {
            Add-Type -TypeDefinition $sig -ErrorAction Stop
        }
        [void][TuiNative]::EnableVt()
        [void][TuiNative]::DisableQuickEdit()
        $script:TuiVtEnabled = $true
    } catch {
        # Fall back to no colour rather than failing the installer.
        foreach ($k in @($script:Tui.Keys)) {
            if ($k -ne 'Esc') { $script:Tui[$k] = "" }
        }
    }
}

function Get-TuiPalette { return $script:Tui }

function Get-TuiWidth {
    $w = 100
    try { $w = [Console]::WindowWidth - 1 } catch { }
    if ($w -lt 60)  { $w = 60 }
    if ($w -gt 110) { $w = 110 }
    return $w
}

# --- frames ------------------------------------------------------------------
# Every line used to be its own Write-Host, on top of a full ESC[2J clear. So
# one keypress in the checklist blanked the screen and then repainted 24 lines,
# one console write at a time, and what that looks like is the whole list
# flashing every time you move the cursor.
#
# A frame is built in memory and written once instead. The screen is never
# blanked: the cursor goes home, each line clears itself to the right with
# ESC[K as it is drawn, and one ESC[0J at the end removes anything the previous
# frame left below. An identical frame is not written at all, which covers the
# keys the loops do not handle and the board refreshing with nothing new.
$script:TuiBuf       = $null
$script:TuiLastFrame = ""
$script:TuiLastWidth = 0

function Reset-TuiFrame { $script:TuiLastFrame = "" }

function Start-TuiFrame {
    param([int]$Width = 0)
    # A resized window leaves the old borders standing, and a frame that only
    # clears the columns it draws cannot remove them - so that one case still
    # wants a full clear.
    if ($Width -gt 0 -and $Width -ne $script:TuiLastWidth) {
        $script:TuiLastWidth = $Width
        Clear-Tui
    }
    $script:TuiBuf = New-Object System.Text.StringBuilder
}

function Stop-TuiFrame {
    if ($null -eq $script:TuiBuf) { return }
    $frame = $script:TuiBuf.ToString()
    $script:TuiBuf = $null
    if ($frame -eq $script:TuiLastFrame) { return }
    $script:TuiLastFrame = $frame
    # Formatted first, on its own line: inside a method call's parentheses the
    # comma separates ARGUMENTS, so [Console]::Out.Write("..." -f $a, $b) binds
    # to Write(string format, object arg0) and dies with "Index (zero based)
    # must be greater than or equal to zero and less than the size of the
    # argument list".
    $out = "{0}[H{1}{0}[0J" -f $script:E, $frame
    [Console]::Out.Write($out)
}

# Inside a frame, buffer the line; outside one, behave exactly as before, so
# the scripts that print plain lines between frames keep working.
function Write-TuiOut {
    param([string]$Text = "")
    if ($null -ne $script:TuiBuf) {
        [void]$script:TuiBuf.Append($Text).Append($script:E).Append("[K").Append("`n")
    } else {
        Reset-TuiFrame
        Write-Host $Text
    }
}

function Clear-Tui {
    $e = [char]27
    Reset-TuiFrame
    Write-Host ("{0}[2J{0}[H" -f $e) -NoNewline
}

function Hide-TuiCursor { Write-Host ("{0}[?25l" -f [char]27) -NoNewline }
function Show-TuiCursor { Write-Host ("{0}[?25h" -f [char]27) -NoNewline }

# Visible length: strip ANSI so padding maths stays correct.
function Get-TuiLen {
    param([string]$Text)
    if (-not $Text) { return 0 }
    return ($Text -replace ("{0}\[[0-9;]*m" -f [char]27), "").Length
}

function Write-TuiLine {
    param([string]$Text = "", [int]$Width = 0)
    if ($Width -le 0) { $Width = Get-TuiWidth }
    $pad = $Width - 4 - (Get-TuiLen $Text)
    if ($pad -lt 0) { $pad = 0 }
    Write-TuiOut ("{0}|{1} {2}{3} {0}|{1}" -f $script:Tui.Dim, $script:Tui.Reset, $Text, (" " * $pad))
}

function Write-TuiTop {
    param([string]$Title, [int]$Width = 0)
    if ($Width -le 0) { $Width = Get-TuiWidth }
    $t = " $Title "
    $rest = $Width - 3 - $t.Length
    if ($rest -lt 0) { $rest = 0 }
    Write-TuiOut ("{0}+-{1}{2}{3}{0}{4}+{5}" -f `
        $script:Tui.Dim, $script:Tui.Bright, $t, $script:Tui.Dim, ("-" * $rest), $script:Tui.Reset)
}

function Write-TuiSep {
    param([int]$Width = 0)
    if ($Width -le 0) { $Width = Get-TuiWidth }
    Write-TuiOut ("{0}+{1}+{2}" -f $script:Tui.Dim, ("-" * ($Width - 2)), $script:Tui.Reset)
}

function Write-TuiBottom {
    param([int]$Width = 0)
    if ($Width -le 0) { $Width = Get-TuiWidth }
    Write-TuiOut ("{0}+{1}+{2}" -f $script:Tui.Dim, ("-" * ($Width - 2)), $script:Tui.Reset)
}

# Shift, Ctrl, Alt, the Windows keys and the lock keys each report a key-down
# of their own, with no character on it. Handing one to a caller is how
# "press Shift" became an answer at the confirmation prompt - Confirm-Tui read
# it, saw no 'y' and no 'n', and took its default, which is yes.
$script:TuiModifierVKeys = @(
    16,   # Shift
    17,   # Ctrl
    18,   # Alt
    20,   # CapsLock
    91,   # Left Windows
    92,   # Right Windows
    93,   # Menu/Application
    144,  # NumLock
    145   # ScrollLock
)

function Read-TuiKey {
    # Read a key without echoing it. A modifier on its own is not a keypress
    # anyone meant, so keep waiting for one that is.
    do {
        $k = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    } while ($script:TuiModifierVKeys -contains [int]$k.VirtualKeyCode)

    # Arrow and function keys report Character as [char]0. Casting that to bool
    # is not reliable across hosts, so normalise to a plain string here and let
    # callers compare strings only.
    $ch = ""
    if ($k.Character -and [int][char]$k.Character -ge 32) { $ch = [string]$k.Character }

    $name = ""
    switch ($k.VirtualKeyCode) {
        38 { $name = "Up" }
        40 { $name = "Down" }
        37 { $name = "Left" }
        39 { $name = "Right" }
        13 { $name = "Enter" }
        27 { $name = "Escape" }
        32 { $name = "Space" }
        36 { $name = "Home" }
        35 { $name = "End" }
        default { $name = "" }
    }
    return [pscustomobject]@{ Name = $name; Char = $ch }
}

# -----------------------------------------------------------------------------
# Checklist: multi-select with per-item availability and notes.
#
# Items must have: Key, Title, Description, Selected (bool),
#                  Available (bool), Note (string, shown when unavailable)
# Returns the list of selected Keys, or $null when cancelled.
# -----------------------------------------------------------------------------
function Show-TuiChecklist {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object[]]$Items,
        [string]$Title = "Select",
        [string[]]$HeaderLines = @()
    )

    $T = $script:Tui
    $cursor = 0
    Hide-TuiCursor

    try {
        while ($true) {
            $w = Get-TuiWidth
            Start-TuiFrame -Width $w
            Write-TuiTop $Title $w

            foreach ($h in $HeaderLines) { Write-TuiLine $h $w }
            if ($HeaderLines.Count) { Write-TuiSep $w }

            for ($i = 0; $i -lt $Items.Count; $i++) {
                $it = $Items[$i]

                if ($it.Available) {
                    if ($it.Selected) { $box = "$($T.Green)[x]$($T.Reset)" }
                    else              { $box = "$($T.Dim)[ ]$($T.Reset)" }
                } else {
                    $box = "$($T.Dim)[-]$($T.Reset)"
                }

                if ($i -eq $cursor) { $arrow = "$($T.Accent)>$($T.Reset)" } else { $arrow = " " }

                if (-not $it.Available)   { $nameCol = $T.Dim }
                elseif ($i -eq $cursor)   { $nameCol = $T.Bright + $T.Bold }
                else                      { $nameCol = $T.Fg }

                $name = "{0}{1,-12}{2}" -f $nameCol, $it.Key, $T.Reset
                $desc = "{0}{1}{2}" -f $T.Dim, $it.Description, $T.Reset

                Write-TuiLine ("{0} {1} {2} {3}" -f $arrow, $box, $name, $desc) $w

                if ((-not $it.Available) -and $it.Note) {
                    Write-TuiLine ("        {0}{1}{2}" -f $T.Yellow, $it.Note, $T.Reset) $w
                }
            }

            Write-TuiSep $w
            $n = @($Items | Where-Object { $_.Selected -and $_.Available }).Count
            Write-TuiLine ("{0}{1} selected{2}   {3}space{2} toggle  {3}a{2} all  {3}n{2} none  {3}enter{2} start  {3}q{2} quit" -f `
                $T.Green, $n, $T.Reset, $T.Accent) $w
            Write-TuiBottom $w
            Stop-TuiFrame

            $key = Read-TuiKey
            $ch = $key.Char.ToLower()

            switch ($key.Name) {
                "Up"    { $cursor--; if ($cursor -lt 0) { $cursor = $Items.Count - 1 }; continue }
                "Down"  { $cursor++; if ($cursor -ge $Items.Count) { $cursor = 0 }; continue }
                "Home"  { $cursor = 0; continue }
                "End"   { $cursor = $Items.Count - 1; continue }
                "Space" {
                    if ($Items[$cursor].Available) { $Items[$cursor].Selected = -not $Items[$cursor].Selected }
                    continue
                }
                "Enter" {
                    return @($Items | Where-Object { $_.Selected -and $_.Available } | ForEach-Object { $_.Key })
                }
                "Escape" { return $null }
            }

            switch ($ch) {
                "a" { foreach ($it in $Items) { if ($it.Available) { $it.Selected = $true } } }
                "n" { foreach ($it in $Items) { $it.Selected = $false } }
                "j" { $cursor++; if ($cursor -ge $Items.Count) { $cursor = 0 } }
                "k" { $cursor--; if ($cursor -lt 0) { $cursor = $Items.Count - 1 } }
                "q" { return $null }
            }
        }
    } finally {
        Show-TuiCursor
    }
}

# -----------------------------------------------------------------------------
# Single-choice menu. Items: Key, Title, Description. Returns Key or $null.
# -----------------------------------------------------------------------------
function Show-TuiMenu {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object[]]$Items,
        [string]$Title = "Choose",
        [string[]]$HeaderLines = @()
    )

    $T = $script:Tui
    $cursor = 0
    Hide-TuiCursor
    try {
        while ($true) {
            $w = Get-TuiWidth
            Start-TuiFrame -Width $w
            Write-TuiTop $Title $w
            foreach ($h in $HeaderLines) { Write-TuiLine $h $w }
            if ($HeaderLines.Count) { Write-TuiSep $w }

            for ($i = 0; $i -lt $Items.Count; $i++) {
                $it = $Items[$i]
                if ($i -eq $cursor) {
                    Write-TuiLine ("{0}> {1}{2,-14}{3} {4}{5}{3}" -f `
                        $T.Accent, ($T.Bright + $T.Bold), $it.Title, $T.Reset, $T.Fg, $it.Description) $w
                } else {
                    Write-TuiLine ("  {0}{1,-14}{2} {3}{4}{2}" -f `
                        $T.Fg, $it.Title, $T.Reset, $T.Dim, $it.Description) $w
                }
            }

            Write-TuiSep $w
            Write-TuiLine ("{0}enter{1} choose  {0}q{1} back" -f $T.Accent, $T.Reset) $w
            Write-TuiBottom $w
            Stop-TuiFrame

            $key = Read-TuiKey
            $ch = $key.Char.ToLower()
            switch ($key.Name) {
                "Up"     { $cursor--; if ($cursor -lt 0) { $cursor = $Items.Count - 1 } }
                "Down"   { $cursor++; if ($cursor -ge $Items.Count) { $cursor = 0 } }
                "Enter"  { return $Items[$cursor].Key }
                "Escape" { return $null }
            }
            switch ($ch) {
                "j" { $cursor++; if ($cursor -ge $Items.Count) { $cursor = 0 } }
                "k" { $cursor--; if ($cursor -lt 0) { $cursor = $Items.Count - 1 } }
                "q" { return $null }
            }
        }
    } finally {
        Show-TuiCursor
    }
}

# Pure, so the wiring above it can stay dumb and this can be tested: returns
# $true, $false, or $null for "that was not an answer, keep waiting".
#
# Only y, n, Enter and Escape answer. Everything else used to fall through to
# the default, so any stray key - including one from a modifier - started an
# install nobody had confirmed.
function Get-TuiConfirmAnswer {
    param([string]$Char, [string]$Name, [switch]$DefaultNo)

    if ($Char -eq "y") { return $true }
    if ($Char -eq "n") { return $false }
    if ($Name -eq "Enter")  { return (-not $DefaultNo.IsPresent) }
    if ($Name -eq "Escape") { return $false }
    return $null
}

function Confirm-Tui {
    param([string]$Question, [switch]$DefaultNo)

    $T = $script:Tui
    $hint = "[Y/n]"
    if ($DefaultNo) { $hint = "[y/N]" }
    Write-Host ""
    Write-Host ("  {0}{1}{2} {3}{4}{2} " -f $T.Bright, $Question, $T.Reset, $T.Dim, $hint) -NoNewline

    while ($true) {
        $key = Read-TuiKey
        $answer = Get-TuiConfirmAnswer -Char $key.Char.ToLower() -Name $key.Name -DefaultNo:$DefaultNo
        if ($null -ne $answer) {
            Write-Host ""
            return $answer
        }
    }
}

# -----------------------------------------------------------------------------
# Progress board. Steps must have Key, Title and a mutable Status/Detail.
# Status: Pending | Running | Done | Failed | Skipped
# -----------------------------------------------------------------------------
function Write-TuiBoard {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object[]]$Steps,
        [string]$Title = "Installing",
        [string[]]$FooterLines = @()
    )

    $T = $script:Tui
    $w = Get-TuiWidth
    Start-TuiFrame -Width $w
    Write-TuiTop $Title $w

    foreach ($s in $Steps) {
        switch ($s.Status) {
            "Done"    { $icon = "{0}  ok  {1}" -f $T.Green,  $T.Reset; $col = $T.Fg }
            "Failed"  { $icon = "{0} FAIL {1}" -f $T.Red,    $T.Reset; $col = $T.Red }
            "Running" { $icon = "{0}  >>  {1}" -f $T.Cyan,   $T.Reset; $col = $T.Bright + $T.Bold }
            "Skipped" { $icon = "{0} skip {1}" -f $T.Dim,    $T.Reset; $col = $T.Dim }
            default   { $icon = "{0}  ..  {1}" -f $T.Dim,    $T.Reset; $col = $T.Dim }
        }
        $detail = ""
        if ($s.Detail) { $detail = "{0}{1}{2}" -f $T.Dim, $s.Detail, $T.Reset }
        Write-TuiLine ("{0} {1}{2,-14}{3} {4}" -f $icon, $col, $s.Key, $T.Reset, $detail) $w
    }

    if ($FooterLines.Count) {
        Write-TuiSep $w
        foreach ($f in $FooterLines) { Write-TuiLine $f $w }
    }
    Write-TuiBottom $w
    Stop-TuiFrame
}

function Write-TuiBanner {
    $T = $script:Tui
    Clear-Tui
    Write-Host ""
    Write-Host ("  {0}{1}Omacheese{2}" -f $T.Accent, $T.Bold, $T.Reset)
    Write-Host ("  {0}keyboard-first Windows 11, Omarchy keymap{1}" -f $T.Dim, $T.Reset)
    Write-Host ""
}
