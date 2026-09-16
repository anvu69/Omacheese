# Agent layouts for herdr - the Windows counterpart to the tmux tdl/tds/tdlm/tsl
# functions in configs/zsh/agent-layouts.zsh. Ported from Omarchy's
# default/bash/fns/herdr.
#
#   hdl <ai> [ai2]    editor + agent + terminal in one tab
#   hds [ai]          editor / diff / terminal / agent in a 2x2
#   hdlm <ai> [ai2]   one hdl tab per subdirectory of the current directory
#   hsl <n> <cmd>     n tiled panes all running the same command
#
# WHY THESE ARE POWERSHELL AND THE TMUX ONES ARE ZSH
#
# tmux only exists inside WSL here, but the coding agents are installed on
# Windows - claude and codex resolve on the Windows PATH, and SUPER+A launches
# the Windows copy. herdr ships a native Windows binary, so it can sit where the
# agents already are instead of dragging them into the distro. Same four
# layouts, same argument order, so the two halves stay interchangeable.
#
# herdr's own vocabulary maps onto tmux's:
#   tmux session -> herdr workspace,  window -> tab,  pane -> pane

function Test-InHerdr {
    if (-not $env:HERDR_PANE_ID) {
        Write-Host "This needs to run inside a herdr pane (start one with SUPER+CTRL+ENTER)." -ForegroundColor Yellow
        return $false
    }
    return $true
}

# Split a pane and return the new pane's id.
function Split-HerdrPane {
    param(
        [Parameter(Mandatory)][string]$Pane,
        [Parameter(Mandatory)][ValidateSet("right", "down")][string]$Direction,
        [Parameter(Mandatory)][double]$Ratio,
        [Parameter(Mandatory)][string]$Cwd
    )
    # --no-focus so the layout is built in one pass without the focus jumping
    # around while panes appear. InvariantCulture on the ratio: herdr parses a
    # float, and a machine set to a comma decimal separator would otherwise
    # send "0,7" and get rejected.
    $r = $Ratio.ToString([System.Globalization.CultureInfo]::InvariantCulture)
    $json = & herdr pane split $Pane --direction $Direction --ratio $r --cwd $Cwd --no-focus 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $json) { return $null }
    try { return ($json | ConvertFrom-Json).result.pane.pane_id } catch { return $null }
}

# Editor left, agent right, a short terminal underneath.
function hdl {
    param([Parameter(Mandatory, Position = 0)][string]$Ai, [Parameter(Position = 1)][string]$SecondAi)
    if (-not (Test-InHerdr)) { return }

    $cwd = $PWD.Path
    $editor = $env:HERDR_PANE_ID

    & herdr tab rename $env:HERDR_TAB_ID (Split-Path $cwd -Leaf) | Out-Null

    $null   = Split-HerdrPane -Pane $editor -Direction down  -Ratio 0.85 -Cwd $cwd
    $aiPane = Split-HerdrPane -Pane $editor -Direction right -Ratio 0.70 -Cwd $cwd
    if (-not $aiPane) { Write-Host "herdr would not split the pane." -ForegroundColor Red; return }

    if ($SecondAi) {
        $second = Split-HerdrPane -Pane $aiPane -Direction down -Ratio 0.5 -Cwd $cwd
        if ($second) { & herdr pane run $second $SecondAi | Out-Null }
    }

    & herdr pane run $aiPane $Ai | Out-Null
    $ed = if ($env:EDITOR) { $env:EDITOR } else { "nvim" }
    & herdr pane run $editor "$ed ." | Out-Null
}

# Editor, live diff, terminal and agent in four quarters.
function hds {
    param([Parameter(Position = 0)][string]$Ai = "opencode")
    if (-not (Test-InHerdr)) { return }

    $cwd = $PWD.Path
    $editor = $env:HERDR_PANE_ID

    & herdr tab rename $env:HERDR_TAB_ID (Split-Path $cwd -Leaf) | Out-Null

    $terminal = Split-HerdrPane -Pane $editor   -Direction down  -Ratio 0.5 -Cwd $cwd
    $diff     = Split-HerdrPane -Pane $editor   -Direction right -Ratio 0.5 -Cwd $cwd
    $aiPane   = Split-HerdrPane -Pane $terminal -Direction right -Ratio 0.5 -Cwd $cwd
    if (-not $aiPane) { Write-Host "herdr would not split the pane." -ForegroundColor Red; return }

    $ed = if ($env:EDITOR) { $env:EDITOR } else { "nvim" }
    & herdr pane run $editor "$ed ." | Out-Null
    # Omarchy runs `hunk diff --watch` here; hunk has no Windows build, so this
    # is git's own stat loop - same job, nothing extra to install.
    & herdr pane run $diff "while (1) { Clear-Host; git diff --stat HEAD; Start-Sleep 2 }" | Out-Null
    & herdr pane run $aiPane $Ai | Out-Null
}

# One hdl tab per subdirectory: a tree of projects, an agent each.
function hdlm {
    param([Parameter(Mandatory, Position = 0)][string]$Ai, [Parameter(Position = 1)][string]$SecondAi)
    if (-not (Test-InHerdr)) { return }

    $base = $PWD.Path
    & herdr workspace rename $env:HERDR_WORKSPACE_ID (Split-Path $base -Leaf) | Out-Null

    $first = $true
    foreach ($dir in Get-ChildItem -LiteralPath $base -Directory) {
        $cmd = "hdl $Ai"
        if ($SecondAi) { $cmd = "$cmd $SecondAi" }

        if ($first) {
            & herdr pane run $env:HERDR_PANE_ID "Set-Location '$($dir.FullName)'; $cmd" | Out-Null
            $first = $false
        } else {
            $json = & herdr tab create --workspace $env:HERDR_WORKSPACE_ID --cwd $dir.FullName --no-focus 2>$null
            if ($LASTEXITCODE -ne 0 -or -not $json) { continue }
            try { $pane = ($json | ConvertFrom-Json).result.root_pane.pane_id } catch { continue }
            & herdr pane run $pane $cmd | Out-Null
        }
    }
}

# n tiled panes, the same command in each. For running one agent several times
# over the same tree and taking whichever answer lands first.
function hsl {
    param([Parameter(Mandatory, Position = 0)][int]$Count, [Parameter(Mandatory, Position = 1)][string]$Command)
    if (-not (Test-InHerdr)) { return }
    if ($Count -lt 1) { Write-Host "Count must be at least 1." -ForegroundColor Yellow; return }

    $cwd = $PWD.Path
    & herdr tab rename $env:HERDR_TAB_ID (Split-Path $cwd -Leaf) | Out-Null

    # ceil(sqrt(count)) columns, rows spread across them. Each new column is
    # split off the rightmost one at 1/(n-k+1), which keeps them even and in
    # left-to-right order - the same arithmetic Omarchy's hsl uses.
    $cols = 1
    while ($cols * $cols -lt $Count) { $cols++ }

    $columns = @($env:HERDR_PANE_ID)
    for ($k = 1; $k -lt $cols; $k++) {
        $next = Split-HerdrPane -Pane $columns[-1] -Direction right -Ratio (1 / ($cols - $k + 1)) -Cwd $cwd
        if (-not $next) { break }
        $columns += $next
    }

    $panes = @()
    for ($i = 0; $i -lt $columns.Count; $i++) {
        $rows = [math]::Floor($Count / $cols)
        if ($i -lt ($Count % $cols)) { $rows++ }
        $panes += $columns[$i]
        $last = $columns[$i]
        for ($j = 1; $j -lt $rows; $j++) {
            $last = Split-HerdrPane -Pane $last -Direction down -Ratio (1 / ($rows - $j + 1)) -Cwd $cwd
            if (-not $last) { break }
            $panes += $last
        }
    }

    foreach ($pane in $panes) { & herdr pane run $pane $Command | Out-Null }
}

# herdr knows whether each agent is working, blocked or idle - that is the thing
# tmux cannot tell you. This is the one-line version of "which one wants me?".
# `herdr agent list` answers in raw JSON, which is right for a script and wrong
# for a person, so this is the table.
function hstat {
    $json = & herdr agent list 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $json) {
        Write-Host "No herdr server running (SUPER+CTRL+ENTER starts one)." -ForegroundColor Yellow
        return
    }
    $agents = @(($json | ConvertFrom-Json).result.agents)
    if (-not $agents.Count) { Write-Host "No agents running." -ForegroundColor DarkGray; return }

    # blocked first: that is the one waiting on you.
    $order = @{ blocked = 0; working = 1; idle = 2; done = 3; unknown = 4 }
    $agents |
        Sort-Object { $o = $order[[string]$_.agent_status]; if ($null -eq $o) { 9 } else { $o } } |
        ForEach-Object {
            [pscustomobject]@{
                State     = $_.agent_status
                Agent     = $_.agent
                Pane      = $_.pane_id
                Directory = Split-Path $_.cwd -Leaf
                Title     = $_.terminal_title_stripped
            }
        } | Format-Table -AutoSize
}
