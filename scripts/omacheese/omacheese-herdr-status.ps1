# Show what every herdr agent is doing, then hold the window open.
#
# The menu and Raycast both want a human-readable answer to "which agent is
# waiting on me?". `herdr agent list` answers in JSON, which is the right shape
# for a script and the wrong one for a person.

$ErrorActionPreference = "Stop"

$herdr = (Get-Command herdr -ErrorAction SilentlyContinue).Source
if (-not $herdr) {
    $fallback = Join-Path $env:LOCALAPPDATA "Programs\Herdr\bin\herdr.exe"
    if (Test-Path -LiteralPath $fallback) { $herdr = $fallback }
}
if (-not $herdr) {
    Write-Host "herdr is not installed." -ForegroundColor Red
    Write-Host "  Menu > Agents > Agent panes (herdr) > Install herdr" -ForegroundColor Cyan
    Read-Host "`nEnter to close"
    return
}

$json = & $herdr agent list 2>$null
if ($LASTEXITCODE -ne 0 -or -not $json) {
    Write-Host "No herdr server running." -ForegroundColor Yellow
    Write-Host "  SUPER+CTRL+ENTER starts one." -ForegroundColor Cyan
    Read-Host "`nEnter to close"
    return
}

$agents = @(($json | ConvertFrom-Json).result.agents)
if (-not $agents.Count) {
    Write-Host "herdr is running, but no agent panes are open." -ForegroundColor DarkGray
    Write-Host "  Inside a pane: hdl claude" -ForegroundColor Cyan
    Read-Host "`nEnter to close"
    return
}

# blocked first - that is the one waiting on you.
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

Read-Host "`nEnter to close"
