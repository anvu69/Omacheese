# Get or set the default coding agent.
#
#   omarchy-default-agent.ps1              print the current default
#   omarchy-default-agent.ps1 claude       set it
#   omarchy-default-agent.ps1 -List        show every agent and whether it is installed
#
# Ported from Omarchy's bin/omarchy-default-agent. Like the original, there is
# no built-in default: nothing is chosen until you choose it, so the menu shows
# every entry unchecked rather than pretending.

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Agent,
    [switch]$List
)

$ErrorActionPreference = "Stop"

$StateFile = Join-Path $env:USERPROFILE ".config\omarchy\defaults\agent"

# The registry of agents this setup knows how to launch.
#
# `Yolo` is the flag that makes the agent stop asking for permission. It is
# only used when you pass -Yolo to omarchy-agent.ps1 - unlike Omarchy, which
# applies it on every launch from the keybinding. That default is reasonable on
# a single-purpose Arch box; on a machine that also holds your SSH agent and
# your work tree, opting in each time is the better trade.
#
# Flags marked "verified" were checked against the installed CLI's --help.
$script:Agents = [ordered]@{
    claude = @{
        Name    = "Claude Code"
        Command = "claude"
        Yolo    = @("--dangerously-skip-permissions")   # verified
        Winget  = "Anthropic.ClaudeCode"
        Install = "winget install --id Anthropic.ClaudeCode -e"
    }
    codex = @{
        Name    = "Codex"
        Command = "codex"
        Yolo    = @("--dangerously-bypass-approvals-and-sandbox")  # verified
        Winget  = "OpenAI.Codex"
        Install = "winget install --id OpenAI.Codex -e"
    }
    gemini = @{
        Name    = "Gemini CLI"
        Command = "gemini"
        Yolo    = @("--yolo")                            # verified
        Install = "npm install -g @google/gemini-cli"
    }
    opencode = @{
        Name    = "OpenCode"
        Command = "opencode"
        Yolo    = @()   # no documented non-interactive approval flag on the TUI
        Install = "npm install -g opencode-ai"
    }
    copilot = @{
        Name    = "GitHub Copilot CLI"
        Command = "copilot"
        Yolo    = @("--allow-all")                       # unverified - not installed here
        Install = "npm install -g @github/copilot"
    }
    cursor = @{
        Name    = "Cursor CLI"
        Command = "cursor-agent"
        Yolo    = @("--force")                           # unverified - not installed here
        Install = "See https://cursor.com/cli"
    }
    crush = @{
        Name    = "Crush"
        Command = "crush"
        Yolo    = @("--yolo")                            # unverified - not installed here
        Install = "npm install -g @charmland/crush"
    }
}

function Test-AgentInstalled {
    param([string]$Key)
    [bool](Get-Command $script:Agents[$Key].Command -ErrorAction SilentlyContinue)
}

function Get-DefaultAgent {
    if (Test-Path -LiteralPath $StateFile) {
        $v = (Get-Content -LiteralPath $StateFile -Raw).Trim()
        if ($v -and $script:Agents.Contains($v)) { return $v }
    }
    return $null
}

function Set-DefaultAgent {
    param([Parameter(Mandatory)][string]$Key)

    if (-not $script:Agents.Contains($Key)) {
        Write-Host "Unknown agent '$Key'. Known: $($script:Agents.Keys -join ', ')" -ForegroundColor Red
        exit 1
    }

    $dir = Split-Path -Parent $StateFile
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    Set-Content -LiteralPath $StateFile -Value $Key -NoNewline -Encoding utf8

    $a = $script:Agents[$Key]
    Write-Host "Default agent: $($a.Name)" -ForegroundColor Green
    if (-not (Test-AgentInstalled $Key)) {
        Write-Host "  not installed yet - $($a.Install)" -ForegroundColor Yellow
    }
}

# --- entry -------------------------------------------------------------------

if ($List) {
    $current = Get-DefaultAgent
    foreach ($k in $script:Agents.Keys) {
        $a       = $script:Agents[$k]
        $mark    = if ($k -eq $current) { "*" } else { " " }
        $state   = if (Test-AgentInstalled $k) { "installed" } else { "-" }
        Write-Host ("{0} {1,-10} {2,-22} {3}" -f $mark, $k, $a.Name, $state)
    }
    return
}

if ($Agent) { Set-DefaultAgent $Agent; return }

$current = Get-DefaultAgent
if ($current) { Write-Output $current }
