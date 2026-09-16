# Get or set the default coding agent.
#
#   omacheese-default-agent.ps1              print the current default
#   omacheese-default-agent.ps1 claude       set it
#   omacheese-default-agent.ps1 -List        show every agent and whether it is installed
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

$StateFile = Join-Path $env:USERPROFILE ".config\omacheese\defaults\agent"

# The registry of agents this setup knows how to launch.
#
# `Yolo` is the flag that makes the agent stop asking for permission. It is
# only used when you pass -Yolo to omacheese-agent.ps1 - unlike Omarchy, which
# applies it on every launch from the keybinding. That default is reasonable on
# a single-purpose Arch box; on a machine that also holds your SSH agent and
# your work tree, opting in each time is the better trade.
#
# Flags marked "verified" were checked against the installed CLI's --help.
#
# `Mise` names the tool in mise's registry, where mise can install the agent
# directly. That is the preferred route now that mise is the only version
# manager here: it is one command on both operating systems and it keeps the
# agent upgradable with `mise up`. Verified on Windows, mise 2026.9.5 - the
# aqua-backed ones install in about 20 seconds each; the npm-backed ones do
# not work when the package compiles native code.
#
# `Install` is the Windows line, `LinuxInstall` the one for -Wsl. They are not
# the same command and could not be: winget does not exist inside AlmaLinux,
# and Claude Code ships a native Linux installer that needs no Node at all,
# which the WSL image otherwise does not have.
$script:Agents = [ordered]@{
    claude = @{
        Name    = "Claude Code"
        Command = "claude"
        Yolo    = @("--dangerously-skip-permissions")   # verified
        Winget  = "Anthropic.ClaudeCode"
        Mise    = "claude"                              # aqua:anthropics/claude-code
        Install = "winget install --id Anthropic.ClaudeCode -e"
        LinuxInstall = "curl -fsSL https://claude.ai/install.sh | bash"
    }
    codex = @{
        Name    = "Codex"
        Command = "codex"
        Yolo    = @("--dangerously-bypass-approvals-and-sandbox")  # verified
        Winget  = "OpenAI.Codex"
        Mise    = "codex"                               # aqua:openai/codex
        Install = "winget install --id OpenAI.Codex -e"
        LinuxInstall = "mise use -g codex"
    }
    gemini = @{
        Name    = "Gemini CLI"
        Command = "gemini"
        Yolo    = @("--yolo")                            # verified
        # The one agent mise cannot install on Windows: its only backend is
        # npm, and gemini-cli pulls node-pty, whose install script compiles
        # native code. Measured: mise install gemini fails with "lifecycle
        # script install failed for node-pty". So mise supplies node and npm
        # does the rest - which is exactly the job fnm used to have.
        Install = "mise use -g node@lts; npm install -g @google/gemini-cli"
        LinuxInstall = "mise use -g node@lts && npm install -g @google/gemini-cli"
    }
    opencode = @{
        Name    = "OpenCode"
        Command = "opencode"
        Yolo    = @()   # no documented non-interactive approval flag on the TUI
        Mise    = "opencode"                            # aqua:anomalyco/opencode
        Install = "mise use -g opencode"
        LinuxInstall = "mise use -g opencode"
    }
    copilot = @{
        Name    = "GitHub Copilot CLI"
        Command = "copilot"
        Yolo    = @("--allow-all")                       # unverified - not installed here
        Mise    = "copilot"                             # aqua:github/copilot-cli
        Install = "mise use -g copilot"
        LinuxInstall = "mise use -g copilot"
    }
    cursor = @{
        Name    = "Cursor CLI"
        Command = "cursor-agent"
        Yolo    = @("--force")                           # unverified - not installed here
        Install = "See https://cursor.com/cli"
        LinuxInstall = "curl https://cursor.com/install -fsS | bash"
    }
    crush = @{
        Name    = "Crush"
        Command = "crush"
        Yolo    = @("--yolo")                            # unverified - not installed here
        Mise    = "crush"                               # aqua:charmbracelet/crush
        Install = "mise use -g crush"
        LinuxInstall = "mise use -g crush"
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

# Dot-sourced, this file is just a registry - omacheese-agent.ps1 loads it to
# reuse the agent table. Without this guard the entry section ran too and
# printed the current default into the caller output.
#
# Note for anyone dot-sourcing this: the param block above comes with it, so
# a [string]-constrained $Agent lands in your scope. Assigning anything else
# to a variable of that name is silently coerced to a string - which is
# exactly how the agent launcher spent its life calling "& " on the text
# "System.Collections.Hashtable".
if ($MyInvocation.InvocationName -eq ".") { return }

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
