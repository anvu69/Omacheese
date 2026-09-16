# Launch the default coding agent in a terminal.
#
#   omacheese-agent.ps1                 launch the default agent
#   omacheese-agent.ps1 -Pick           choose one first
#   omacheese-agent.ps1 -Prompt "..."   launch with an opening prompt
#   omacheese-agent.ps1 -Yolo           skip permission prompts (see below)
#   omacheese-agent.ps1 -Wsl            run it inside AlmaLinux instead
#
# Ported from Omarchy's bin/omarchy-agent, bound to SUPER+SHIFT+CTRL+A.
#
# ON -Yolo
# Omarchy passes each agent's skip-permissions flag on every launch, because a
# keybinding that stops to ask is not much of a keybinding. That is a fair call
# on a dedicated machine. Here it is opt-in: this box holds the Bitwarden SSH
# agent and your work trees, and an agent running unattended with full approval
# can reach both. Pass -Yolo when you mean it.

[CmdletBinding()]
param(
    [switch]$Pick,
    [string]$Prompt,
    [switch]$Yolo,
    [switch]$Wsl,
    [string]$Directory
)

$ErrorActionPreference = "Stop"

$here      = Split-Path -Parent $MyInvocation.MyCommand.Path
$defaults  = Join-Path $here "omacheese-default-agent.ps1"
if (-not (Test-Path -LiteralPath $defaults)) { throw "Missing $defaults" }

# Dot-source to reuse the registry rather than duplicating it.
. $defaults

$agentKey = Get-DefaultAgent

if ($Pick -or -not $agentKey) {
    $fzf = Get-Command fzf -ErrorAction SilentlyContinue
    if (-not $fzf) {
        Write-Host "No default agent set and fzf is not installed." -ForegroundColor Yellow
        Write-Host "Set one with: omacheese-default-agent.ps1 claude" -ForegroundColor Cyan
        Read-Host "`nEnter to close"
        return
    }

    $rows = foreach ($k in $script:Agents.Keys) {
        $a     = $script:Agents[$k]
        $state = if (Test-AgentInstalled $k) { "installed" } else { "not installed" }
        "{0,-10} {1,-22} {2}" -f $k, $a.Name, $state
    }

    $choice = $rows | & $fzf.Source `
        --prompt "agent > " `
        --header "  ENTER to set as default and launch      ESC to cancel" `
        --header-first --layout reverse --info inline --no-mouse --border rounded

    if (-not $choice) { return }
    $agentKey = ($choice -split '\s+')[0]
    Set-DefaultAgent $agentKey | Out-Null
}

# NOT $agent. omacheese-default-agent.ps1 declares param([string]$Agent), and
# dot-sourcing it puts that variable - complete with its [string] type
# constraint - into this scope. Assigning the hashtable to it silently
# coerced it to the string "System.Collections.Hashtable", so every launch
# printed an empty agent name and then died on `& $agent.Command`.
$agentDef = $script:Agents[$agentKey]

if (-not $Wsl -and -not (Test-AgentInstalled $agentKey)) {
    Write-Host "$($agentDef.Name) is not installed." -ForegroundColor Red
    Write-Host "  $($agentDef.Install)" -ForegroundColor Cyan
    Read-Host "`nEnter to close"
    return
}

# Agents ask about trusting a directory on first run. Starting in $HOME means
# answering that for your entire profile, so prefer a work root when we are
# sitting in $HOME - the same reasoning as Omarchy's $HOME/Work check.
if (-not $Directory) {
    $Directory = $PWD.Path
    if ($Directory -eq $env:USERPROFILE) {
        foreach ($candidate in @("D:\Projects", (Join-Path $env:USERPROFILE "Projects"), (Join-Path $env:USERPROFILE "Work"))) {
            if (Test-Path -LiteralPath $candidate) { $Directory = $candidate; break }
        }
    }
}

$argv = @()
if ($Yolo) { $argv += $agentDef.Yolo }
if ($Prompt) { $argv += $Prompt }

if ($Wsl) {
    $distro = "AlmaLinux-9"

    # Everything below is checked inside the distro, because that is the machine
    # the agent actually runs on. Test-AgentInstalled above asks the Windows
    # PATH, which answers a different question: claude can be installed on
    # Windows and absent in AlmaLinux, and on a fresh install it always is. The
    # WSL module installs zsh, tmux and the CLI tools - no agent, and no Node.
    $distros = @(& wsl.exe -l -q 2>$null) | ForEach-Object { ($_ -replace "`0", "").Trim() }
    if ($distros -notcontains $distro) {
        Write-Host "$distro is not installed." -ForegroundColor Red
        Write-Host "  ./scripts/setup.ps1 -Modules wsl" -ForegroundColor Cyan
        Read-Host "`nEnter to close"
        return
    }

    $probe = ((& wsl.exe -d $distro -- bash -lc "command -v $($agentDef.Command) 2>/dev/null" 2>$null) -join "").Trim()

    # A hit under /mnt/c is the Windows copy leaking in over the interop PATH.
    # It is a shim around a Windows .exe, so running it from a Linux shell
    # either fails or quietly runs the Windows agent against Windows paths,
    # which is the opposite of what -Wsl is for.
    if (-not $probe -or $probe -like "/mnt/*") {
        $why = if ($probe) { "only the Windows copy is visible, over the interop PATH" }
               else        { "not installed in $distro" }
        Write-Host "$($agentDef.Name): $why." -ForegroundColor Red
        Write-Host ""
        Write-Host "Install it inside the distro:" -ForegroundColor Cyan
        Write-Host "  wsl -d $distro -- bash -lc '$($agentDef.LinuxInstall)'" -ForegroundColor White
        Write-Host ""
        Write-Host "Or install every agent at once:" -ForegroundColor Cyan
        Write-Host "  wsl -d $distro -- bash ~/.config/omacheese/install-agents.sh" -ForegroundColor White
        if ($probe -like "/mnt/*") {
            Write-Host ""
            Write-Host "Windows binaries shadow Linux ones until wsl.conf is applied:" -ForegroundColor DarkGray
            Write-Host "  wsl -d $distro -- sudo cp ~/.config/wsl/wsl.conf /etc/wsl.conf" -ForegroundColor DarkGray
            Write-Host "  wsl --shutdown" -ForegroundColor DarkGray
        }
        Read-Host "`nEnter to close"
        return
    }

    # Run the Linux copy of the agent inside the distro, in the mapped path.
    $wslPath = ((& wsl.exe -d $distro -- wslpath -a "$($Directory -replace '\\','/')" 2>$null) -join "").Trim()
    if (-not $wslPath) { $wslPath = "." }
    $inner = "cd '$wslPath' && $($agentDef.Command) $($argv -join ' ')"
    Write-Host "Launching $($agentDef.Name) in $distro..." -ForegroundColor Cyan
    & wsl.exe -d $distro -- bash -lc $inner
    if ($LASTEXITCODE -ne 0) { Read-Host "`nExited with $LASTEXITCODE. Enter to close" }
    return
}

Write-Host "Launching $($agentDef.Name)$(if ($Yolo) { ' (yolo)' })" -ForegroundColor Cyan
Write-Host "  in $Directory" -ForegroundColor DarkGray

Push-Location $Directory
try {
    & $agentDef.Command @argv
} finally {
    Pop-Location
}
