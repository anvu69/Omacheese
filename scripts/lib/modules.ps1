# Setup modules: what the TUI can install, and when each one is possible.
#
# Every module declares its own requirements against the detected machine, so
# the same repo works on a 32 GB workstation with a 4080 and on a 8 GB laptop
# with no discrete GPU - the laptop simply never sees the vLLM option.
#
# PowerShell 5.1 compatible.

Set-StrictMode -Version 2.0

function Get-SetupModules {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Machine
    )

    $mods = New-Object System.Collections.Generic.List[object]

    function New-Mod {
        param(
            [string]$Key, [string]$Description,
            [bool]$Default = $true,
            [bool]$Available = $true,
            [string]$Note = "",
            [bool]$NeedsElevation = $false,
            [string]$Est = "",
            [scriptblock]$Action
        )
        return [pscustomobject]@{
            Key            = $Key
            Description    = $Description
            Selected       = ($Default -and $Available)
            Available      = $Available
            Note           = $Note
            NeedsElevation = $NeedsElevation
            Est            = $Est
            Action         = $Action
            Status         = "Pending"
            Detail         = ""
        }
    }

    $wingetOk = $Machine.HasWinget

    # --- packages ------------------------------------------------------------
    $mods.Add((New-Mod -Key "core" -Description "PowerShell 7, Alacritty, git, Nerd Font" `
        -Available $wingetOk -Note "winget not found - install 'App Installer' from the Store" `
        -Est "3-6 min" `
        -Action { param($ctx) & $ctx.InstallWindows -Groups @("core") }))

    # Separate from `core` on purpose: these go into PowerShell 7's module
    # directory, so pwsh has to exist and be on PATH first. Running it as its
    # own step means PATH has been refreshed since core installed pwsh.
    $mods.Add((New-Mod -Key "psmodules" -Description "PSReadLine, PSFzf, posh-git, Terminal-Icons (into pwsh 7)" `
        -Available $wingetOk -Note "needs winget (installs after 'core')" `
        -Est "1-3 min" `
        -Action { param($ctx) & $ctx.InstallModules }))

    $mods.Add((New-Mod -Key "cli" -Description "fzf, ripgrep, fd, bat, eza, zoxide, lazygit, gh, jq" `
        -Available $wingetOk -Note "needs winget" -Est "3-5 min" `
        -Action { param($ctx) & $ctx.InstallWindows -Groups @("cli") }))

    # One binary that manages every language version, so a project can pin its
    # own without five separate managers fighting over PATH. The languages come
    # with it: installing a version manager and no version is how a finished
    # setup ended up with no node on it. The list is every language whose mise
    # backend is `core:` - a prebuilt toolchain, nothing compiled - which is
    # what makes it safe on Windows; dart, php and lua are not, and
    # docs/runtimes-and-languages.md says what to do instead.
    $mods.Add((New-Mod -Key "langs" -Description "mise + node, python, go, rust, java, ruby" `
        -Available $wingetOk -Note "needs winget; ~1 GB of toolchains" -Est "2-4 min" `
        -Action { param($ctx) & $ctx.InstallWindows -Groups @("langs") }))

    # Separate from the runtime in core because the SDK is four times the size
    # and only useful if you actually build .NET.
    $mods.Add((New-Mod -Key "dotnet" -Description ".NET 10 SDK (the runtime itself is in core)" `
        -Available $wingetOk -Note "needs winget; 205 MB" -Est "1-3 min" `
        -Action { param($ctx) & $ctx.InstallWindows -Groups @("dotnet") }))

    $mods.Add((New-Mod -Key "wm" -Description "komorebi + whkd + yasb (Omarchy keymap)" `
        -Available $wingetOk -Note "needs winget" -Est "2-3 min" `
        -Action { param($ctx) & $ctx.InstallWindows -Groups @("wm") }))

    $mods.Add((New-Mod -Key "desktop" -Description "Brave, Everything, Bitwarden, electerm, DBeaver, PowerToys" `
        -Available $wingetOk -Note "needs winget" -Est "5-10 min" `
        -Action { param($ctx) & $ctx.InstallWindows -Groups @("desktop") }))

    $mods.Add((New-Mod -Key "agents" -Description "Claude Code, Codex, uv + the agent launcher" `
        -Available $wingetOk -Note "needs winget" -Est "2-4 min" `
        -Action { param($ctx) & $ctx.InstallWindows -Groups @("agents") }))

    # Off by default like raycast, and for a related reason: herdr is excellent
    # but it is a second multiplexer on a machine that already has tmux, and it
    # is the one thing here that does not come from winget - the `herdr` moniker
    # on winget belongs to an unofficial fork, so install-herdr.ps1 goes to
    # herdr.dev instead. Opt in when you want it.
    $mods.Add((New-Mod -Key "herdr" -Description "herdr agent multiplexer + the hdl/hds/hdlm/hsl layouts" `
        -Default $false `
        -Note "installs from herdr.dev, not winget" -Est "1-2 min" `
        -Action { param($ctx) & $ctx.InstallHerdr }))

    # Off by default, and deliberately so. Raycast is a Microsoft Store package
    # that wants an account, which is a poor fit for provisioning a machine
    # unattended - but it is an excellent launcher, and the repo ships script
    # commands for it, so it is one checkbox away.
    $mods.Add((New-Mod -Key "raycast" -Description "Raycast launcher + the Omacheese script commands" `
        -Default $false `
        -Available $wingetOk -Note "Microsoft Store package; sign-in may be required" `
        -Est "2-4 min" `
        -Action { param($ctx) & $ctx.InstallWindows -Groups @("raycast") }))

    # --- configuration -------------------------------------------------------
    $mods.Add((New-Mod -Key "configs" -Description "Install dotfiles, keymap, theme, autostart" `
        -Est "10 s" `
        -Action { param($ctx) & $ctx.LinkConfigs }))

    $mods.Add((New-Mod -Key "debloat" -Description "Win11Debloat + the tweaks a tiling WM needs" `
        -Default $false `
        -Est "2-4 min" `
        -Action { param($ctx) & $ctx.Debloat }))

    # --- WSL -----------------------------------------------------------------
    # wsl --install needs admin and, on a clean machine, a reboot.
    $wslAvailable = $Machine.IsWin11 -or $Machine.Build -ge 19041
    $wslNote = ""
    if (-not $wslAvailable) { $wslNote = "needs Windows 10 2004+ / Windows 11" }
    elseif (-not $Machine.VirtEnabled) { $wslNote = "enable virtualisation (VT-x/AMD-V) in the BIOS first" }

    $mods.Add((New-Mod -Key "wsl" -Description "WSL2 + AlmaLinux 9 (dev/runtime OS)" `
        -Available ($wslAvailable -and $Machine.VirtEnabled) -Note $wslNote `
        -NeedsElevation $true -Est "5-15 min" `
        -Action { param($ctx) & $ctx.InstallWsl }))

    # --- local LLM -----------------------------------------------------------
    # This is the part that must never be assumed. It is offered only when the
    # detected hardware can actually run it, and the backend follows the tier.
    $llmAvailable = ($Machine.LlmTier -ne "none")
    $llmDesc = "Local LLM"
    $llmNote = $Machine.LlmNote

    switch ($Machine.LlmTier) {
        "vllm" {
            $llmDesc = "OPTIONAL - local LLM: vLLM on the GPU (~10 GB download)"
            if (-not $Machine.HasAlmaLinux) {
                $llmNote = "$($Machine.LlmNote) - select 'wsl' too, or run it after the reboot"
            }
        }
        "ollama" {
            $llmDesc = "OPTIONAL - local LLM: Ollama (no GPU needed)"
            # Ollama is installed through winget; vLLM is not (it lives in WSL).
            if (-not $wingetOk) {
                $llmAvailable = $false
                $llmNote = "needs winget to install Ollama"
            }
        }
        default { $llmDesc = "OPTIONAL - local LLM" }
    }

    $mods.Add((New-Mod -Key "localllm" -Description $llmDesc `
        -Default $false -Available $llmAvailable -Note $llmNote `
        -Est "10-30 min" `
        -Action { param($ctx) & $ctx.InstallLocalLlm }))

    # --- verify --------------------------------------------------------------
    $mods.Add((New-Mod -Key "verify" -Description "Run doctor.ps1 and report what is left" `
        -Est "1-2 min" `
        -Action { param($ctx) & $ctx.Doctor }))

    return $mods.ToArray()
}

# Named presets, so a fresh machine does not have to reason about ten modules.
function Get-SetupProfiles {
    return @(
        [pscustomobject]@{
            Key = "minimal"; Title = "Minimal"
            Description = "Terminal, shell, CLI tools, dotfiles. No tiling WM."
            Modules = @("core", "langs", "psmodules", "cli", "configs", "verify")
        }
        [pscustomobject]@{
            Key = "desktop"; Title = "Desktop"
            Description = "Minimal + tiling WM with the Omarchy keymap, and debloat."
            Modules = @("core", "langs", "psmodules", "cli", "wm", "desktop", "configs", "debloat", "verify")
        }
        [pscustomobject]@{
            Key = "full"; Title = "Full"
            Description = "Desktop + coding agents + WSL2 AlmaLinux."
            Modules = @("core", "langs", "dotnet", "psmodules", "cli", "wm", "desktop", "agents", "configs", "debloat", "wsl", "verify")
        }
        [pscustomobject]@{
            Key = "everything"; Title = "Everything"
            Description = "Full + local LLM, where the hardware allows it."
            Modules = @("core", "langs", "dotnet", "psmodules", "cli", "wm", "desktop", "agents", "configs", "debloat", "wsl", "localllm", "verify")
        }
        [pscustomobject]@{
            Key = "custom"; Title = "Custom"
            Description = "Pick modules yourself."
            Modules = @()
        }
    )
}
