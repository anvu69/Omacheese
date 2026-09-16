# Omarchy-style keybinding cheatsheet.
# Parses the live whkdrc and pipes it into fzf so the bindings are searchable
# rather than something you have to remember. Bound to SUPER+/.

$ErrorActionPreference = "Stop"

$whkdrc = Join-Path $env:USERPROFILE ".config\whkdrc"
if (-not (Test-Path -LiteralPath $whkdrc)) {
    Write-Host "No whkdrc at $whkdrc" -ForegroundColor Red
    Read-Host "Enter to close"
    exit 1
}

# Pretty names for the key tokens whkd requires but nobody wants to read.
$prettyKey = @{
    'oem_comma' = ','; 'oem_period' = '.'; 'oem_minus' = '-'; 'oem_plus' = '='
    'oem_1'     = ';'; 'oem_2'      = '/'; 'oem_3'     = '`'; 'oem_4'    = '['
    'oem_5'     = '\'; 'oem_6'      = ']'; 'oem_7'     = "'"
    'return'    = 'Enter'; 'back' = 'Backspace'; 'snapshot' = 'PrtSc'
    'escape'    = 'Esc'; 'prior' = 'PgUp'; 'next' = 'PgDn'
    'win'       = 'SUPER'; 'control' = 'CTRL'; 'alt' = 'ALT'; 'shift' = 'SHIFT'
}

function Format-Chord {
    param([string]$Chord)
    $parts = $Chord -split '\s*\+\s*' | ForEach-Object {
        $t = $_.Trim().ToLower()
        if ($prettyKey.ContainsKey($t)) { $prettyKey[$t] } else { $t.ToUpper() }
    }
    return ($parts -join ' + ')
}

$section = "General"
$rows    = New-Object System.Collections.Generic.List[string]

$lines  = @(Get-Content -LiteralPath $whkdrc)
$isRule = { param($s) $s -match '^#\s*-{10,}\s*$' }

for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = $lines[$i]

    # A section banner is a comment sandwiched between two `# -----` rulers.
    # Requiring both sides keeps ordinary prose comments (and the closing
    # ruler of the previous banner) from being promoted to headings.
    if ($line -match '^\s*#') {
        if ($i -gt 0 -and $i -lt $lines.Count - 1 -and
            (& $isRule $lines[$i - 1]) -and (& $isRule $lines[$i + 1]) -and
            $line -match '^#\s{1,4}(\S.*?)\s*$') {
            # Drop the right-aligned hint that follows two or more spaces.
            $section = ($Matches[1] -split '\s{2,}')[0].Trim()
        }
        continue
    }

    if ($line -match '^\.pause\s+(.+)$') {
        $rows.Add(("{0}`t{1}`t{2}" -f "Meta", (Format-Chord $Matches[1].Trim()), "Pause/resume ALL hotkeys"))
        continue
    }

    if ($line -match '^\s*([a-z0-9_+\s]+?)\s*:\s*(.+?)\s*$') {
        $chord   = Format-Chord $Matches[1]
        $command = $Matches[2]

        # Make the command column readable instead of literal.
        # Order matters: unwrap the launcher shells before shortening what they
        # were launching, or the outer pattern stops matching. The launchers
        # are matched by basename so the list keeps reading as actions rather
        # than as %USERPROFILE% paths.
        $desc = $command `
            -replace '^start "" alacritty --class [a-z-]+,[a-z-]+ -e\s*', '' `
            -replace '"[^"]*\\omarchy-(run|term)\.cmd"\s*', '' `
            -replace '"[^"]*\\([a-z-]+)\.ps1"',   '$1' `
            -replace 'pwsh -NoProfile -ExecutionPolicy Bypass -File\s*', '' `
            -replace '^start ""\s*',            'launch ' `
            -replace '^komorebic\s+',           '' `
            -replace '\s+&&\s+komorebic\s+',    ' + ' `
            -replace 'rundll32\.exe user32\.dll,LockWorkStation', 'lock session'

        $rows.Add(("{0}`t{1}`t{2}" -f $section, $chord, $desc))
    }
}

# Resolve rather than trust PATH: this is launched from the bar, which may
# have been restarted from an environment that has no fzf on PATH.
$fzf = Get-Command fzf -ErrorAction SilentlyContinue
if (-not $fzf) {
    foreach ($cand in @(
        "%LOCALAPPDATA%\Microsoft\WinGet\Links\fzf.exe",
        "%ProgramFiles%\fzf\fzf.exe",
        "%USERPROFILE%\scoop\shims\fzf.exe",
        "%ChocolateyInstall%\bin\fzf.exe",
        "%ProgramFiles%\fzf\fzf.exe",
        "%USERPROFILE%\scoop\shims\fzf.exe",
        "%ChocolateyInstall%\bin\fzf.exe"
    ))  {
        $expanded = [Environment]::ExpandEnvironmentVariables($cand)
        if (Test-Path -LiteralPath $expanded) {
            $fzf = [pscustomobject]@{ Source = $expanded }
            break
        }
    }
}

$header = "  SUPER = Windows key      {0} bindings      ESC to close" -f $rows.Count

if ($fzf) {
    $rows |
        ForEach-Object {
            $p = $_ -split "`t"
            "{0,-22} {1,-30} {2}" -f $p[0], $p[1], $p[2]
        } |
        & $fzf.Source `
            --prompt "keys > " `
            --header $header `
            --header-first `
            --layout reverse `
            --info inline `
            --no-mouse `
            --border rounded |
        Out-Null
} else {
    Write-Host $header -ForegroundColor Cyan
    Write-Host ""
    $last = ""
    foreach ($r in $rows) {
        $p = $r -split "`t"
        if ($p[0] -ne $last) {
            Write-Host ""
            Write-Host ("  " + $p[0]) -ForegroundColor Magenta
            $last = $p[0]
        }
        Write-Host ("    {0,-30} {1}" -f $p[1], $p[2])
    }
    Write-Host ""
    Write-Host "  (install fzf for a searchable view)" -ForegroundColor DarkGray
    Read-Host "`nEnter to close"
}
