# Verify the setup actually works.
#
#   ./scripts/doctor.ps1            check the installed configs
#   ./scripts/doctor.ps1 -Repo      check the repo's files instead
#   ./scripts/doctor.ps1 -Quick     skip the slow winget lookups
#
# This exists because two classes of bug in this repo were invisible until
# something failed at login:
#   * a winget id that does not resolve (yasb was installed as "amnweb.yasb")
#   * a whkd key name that VKey::from_keyname rejects, e.g. "enter" instead of
#     "return" - one bad name aborts the daemon, so EVERY hotkey dies silently
# Both are checked below.

[CmdletBinding()]
param(
    [switch]$Repo,
    [switch]$Quick
)

$RepoRoot = Split-Path -Parent $PSScriptRoot
$cfg      = Join-Path $env:USERPROFILE ".config"

$script:Pass = 0; $script:Warn = 0; $script:Fail = 0

function Ok   { param($m) $script:Pass++; Write-Host "  PASS  $m" -ForegroundColor Green }
function Warn { param($m) $script:Warn++; Write-Host "  WARN  $m" -ForegroundColor Yellow }
function Bad  { param($m) $script:Fail++; Write-Host "  FAIL  $m" -ForegroundColor Red }
function Section { param($m) Write-Host "`n$m" -ForegroundColor Magenta }

# --- whkd key names ----------------------------------------------------------
# Mirrors win_hotkeys VKey::from_keyname. Anything outside this set aborts whkd
# on startup, taking every binding with it.
$ValidKeys = @(
    'back','tab','clear','return','shift','ctrl','control','alt','menu','pause',
    'capital','escape','space','prior','next','end','home','left','up','right',
    'down','select','print','execute','snapshot','insert','delete','help',
    'win','lwin','rwin','apps','sleep','numlock','scroll',
    'lshift','rshift','lctrl','lcontrol','rctrl','rcontrol','lalt','lmenu','ralt','rmenu',
    'multiply','add','separator','subtract','decimal','divide',
    'oem_1','oem_plus','oem_comma','oem_minus','oem_period','oem_2','oem_3',
    'oem_4','oem_5','oem_6','oem_7','oem_8','oem_102','oem_clear',
    'attn','crsel','exsel','play','zoom','pa1',
    'browser_back','browser_forward','browser_refresh','browser_stop',
    'browser_search','browser_favorites','browser_home',
    'volume_mute','volume_down','volume_up',
    'media_next_track','media_prev_track','media_stop','media_play_pause',
    'launch_mail','launch_media_select','launch_app1','launch_app2'
)
$ValidKeys += 0..9 | ForEach-Object { "$_" }
$ValidKeys += 'a'..'z'
$ValidKeys += 1..24 | ForEach-Object { "f$_" }
$ValidKeys += 0..9 | ForEach-Object { "numpad$_" }

function Test-Whkdrc {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { Bad "whkdrc missing: $Path"; return }

    $chords = @{}
    $lineNo = 0
    $bad    = @()
    $dupes  = @()

    foreach ($line in Get-Content -LiteralPath $Path) {
        $lineNo++
        $chordText = $null

        if ($line -match '^\.pause\s+(.+)$') {
            $chordText = $Matches[1]
        } elseif ($line -notmatch '^\s*#' -and $line -notmatch '^\s*\.' -and
                  $line -match '^\s*([^:#]+?)\s*:\s*\S') {
            # Capture whatever sits left of the first colon, punctuation
            # included. Restricting this to [a-z0-9_+] would skip lines like
            # "alt + , : ..." instead of reporting them - which is exactly the
            # kind of miss this script exists to prevent.
            $chordText = $Matches[1]
        }
        if (-not $chordText) { continue }

        $keys = $chordText -split '\s*\+\s*' | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ }
        foreach ($k in $keys) {
            if ($ValidKeys -notcontains $k) { $bad += "line ${lineNo}: '$k' in '$($chordText.Trim())'" }
        }

        $norm = ($keys | Sort-Object) -join '+'
        if ($chords.ContainsKey($norm)) {
            $dupes += "line ${lineNo}: '$($chordText.Trim())' already bound at line $($chords[$norm])"
        } else {
            $chords[$norm] = $lineNo
        }
    }

    if ($bad.Count) {
        Bad "whkdrc has $($bad.Count) invalid key name(s) - whkd will refuse to start:"
        $bad | Select-Object -First 8 | ForEach-Object { Write-Host "          $_" -ForegroundColor Red }
    } else {
        Ok "whkdrc: all key names valid ($($chords.Count) chords)"
    }

    if ($dupes.Count) {
        Warn "whkdrc has $($dupes.Count) duplicate chord(s):"
        $dupes | Select-Object -First 5 | ForEach-Object { Write-Host "          $_" -ForegroundColor Yellow }
    } else {
        Ok "whkdrc: no duplicate chords"
    }
}

# =============================================================================

Write-Host "doctor - $(if ($Repo) { 'repo files' } else { 'installed config' })" -ForegroundColor Cyan

Section "commands"
foreach ($c in @("winget","komorebic","whkd","yasb","alacritty","pwsh","git","fzf","wsl")) {
    if (Get-Command $c -ErrorAction SilentlyContinue) { Ok $c }
    elseif ($c -in @("fzf","alacritty")) { Warn "$c not on PATH (menus/pickers need it)" }
    else { Bad "$c not on PATH" }
}

Section "package manifest"
$manifestPath = Join-Path $RepoRoot "configs\winget\packages.json"
if (Test-Path -LiteralPath $manifestPath) {
    try {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $ids = $manifest.groups.PSObject.Properties.Value.packages.id
        Ok "packages.json parses ($($ids.Count) packages)"

        if ($Quick) {
            Warn "skipped winget id resolution (-Quick)"
        } else {
            $badIds = @()
            foreach ($id in $ids) {
                $out = winget show --id $id -e --disable-interactivity 2>&1 | Out-String
                if ($out -match "No package found") { $badIds += $id }
            }
            if ($badIds.Count) {
                Bad "winget ids that do not resolve: $($badIds -join ', ')"
            } else {
                Ok "all $($ids.Count) winget ids resolve"
            }
        }
    } catch { Bad "packages.json is not valid JSON: $($_.Exception.Message)" }
} else { Bad "missing $manifestPath" }

Section "whkd"
$whkdrcPath = if ($Repo) { Join-Path $RepoRoot "configs\whkd\whkdrc" } else { Join-Path $cfg "whkdrc" }
Test-Whkdrc $whkdrcPath

Section "komorebi"
$kjson = if ($Repo) { Join-Path $RepoRoot "configs\komorebi\komorebi.json" } else { Join-Path $cfg "komorebi\komorebi.json" }
if (Test-Path -LiteralPath $kjson) {
    try {
        $k = Get-Content -LiteralPath $kjson -Raw | ConvertFrom-Json
        Ok "komorebi.json parses ($($k.monitors[0].workspaces.Count) workspaces)"
        if ($k.PSObject.Properties.Name -contains "float_rules") {
            Bad "komorebi.json still uses 'float_rules' (renamed to ignore_rules; use floating_applications to actually float)"
        } else { Ok "komorebi.json uses current rule keys" }
        if (-not $k.app_specific_configuration_path) {
            Warn "app_specific_configuration_path not set (run: komorebic fetch-asc)"
        } else { Ok "app_specific_configuration_path set" }
    } catch { Bad "komorebi.json is not valid JSON: $($_.Exception.Message)" }
} else { Bad "missing $kjson" }

if (-not $Repo) {
    $asc = Join-Path $cfg "komorebi\applications.json"
    if (Test-Path -LiteralPath $asc) { Ok "applications.json present" }
    else { Warn "applications.json missing - run: komorebic fetch-asc" }
}

Section "installed configs"
if ($Repo) {
    Warn "skipped (-Repo mode)"
} else {
    $expected = @{
        "alacritty"          = Join-Path $env:APPDATA "alacritty\alacritty.toml"
        "alacritty (wsl)"    = Join-Path $env:APPDATA "alacritty\alacritty.wsl.toml"
        "whkdrc"             = Join-Path $cfg "whkdrc"
        "komorebi.json"      = Join-Path $cfg "komorebi\komorebi.json"
        "yasb config"        = Join-Path $cfg "yasb\config.yaml"
        "yasb styles"        = Join-Path $cfg "yasb\styles.css"
        "oh-my-posh theme"   = Join-Path $cfg "oh-my-posh\poweruser.omp.json"
        "pwsh profile"       = Join-Path $env:USERPROFILE "Documents\PowerShell\Microsoft.PowerShell_profile.ps1"
        ".gitconfig"         = Join-Path $env:USERPROFILE ".gitconfig"
        ".wslconfig"         = Join-Path $env:USERPROFILE ".wslconfig"
        "ssh-agent-bridge"   = Join-Path $cfg "wsl\ssh-agent-bridge.sh"
        "omarchy-menu"       = Join-Path $cfg "omarchy\bin\omarchy-menu.ps1"
        "omarchy-keybindings"= Join-Path $cfg "omarchy\bin\omarchy-keybindings.ps1"
        "start-desktop"      = Join-Path $cfg "omarchy\bin\start-desktop.ps1"
    }
    foreach ($name in $expected.Keys | Sort-Object) {
        if (Test-Path -LiteralPath $expected[$name]) { Ok $name } else { Bad "$name missing ($($expected[$name]))" }
    }

    $bad51 = Join-Path $env:USERPROFILE "Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1"
    if (Test-Path -LiteralPath $bad51) {
        Warn "a profile exists in Documents\WindowsPowerShell (that is PS 5.1, not PS 7)"
    }
}

Section "environment"
$kch = [Environment]::GetEnvironmentVariable("KOMOREBI_CONFIG_HOME", "User")
if ($kch) { Ok "KOMOREBI_CONFIG_HOME=$kch" } else { Bad "KOMOREBI_CONFIG_HOME not set for the user" }

$startupLnk = Join-Path ([Environment]::GetFolderPath("Startup")) "komorebi-desktop.lnk"
if (Test-Path -LiteralPath $startupLnk) { Ok "autostart shortcut present" }
else { Warn "no autostart shortcut - the desktop will not come back after a reboot" }

Section "ssh agent"
$agentSvc = Get-Service ssh-agent -ErrorAction SilentlyContinue
if ($agentSvc -and $agentSvc.StartType -ne "Disabled") {
    Warn "Windows 'OpenSSH Authentication Agent' is $($agentSvc.StartType); Bitwarden needs it Disabled to own the pipe"
} elseif ($agentSvc) {
    Ok "OpenSSH Authentication Agent disabled (Bitwarden can own the agent pipe)"
}
if (Get-Command npiperelay.exe -ErrorAction SilentlyContinue) {
    Ok "npiperelay present (WSL agent bridge can work)"
} else {
    Warn "npiperelay not found - WSL will have no SSH keys. winget install --id albertony.npiperelay -e"
}

Section "coding agents"
$agentState = Join-Path $cfg "omarchy\defaults\agent"
$knownAgents = @{ claude = "claude"; codex = "codex"; gemini = "gemini"; opencode = "opencode"
                  copilot = "copilot"; cursor = "cursor-agent"; crush = "crush" }
$installedAgents = @()
foreach ($k in $knownAgents.Keys) {
    if (Get-Command $knownAgents[$k] -ErrorAction SilentlyContinue) { $installedAgents += $k }
}
if ($installedAgents.Count) { Ok "agents installed: $($installedAgents -join ', ')" }
else { Warn "no coding agent installed (./scripts/install-windows.ps1 -Groups ai)" }

if (Test-Path -LiteralPath $agentState) {
    Ok "default agent: $((Get-Content -LiteralPath $agentState -Raw).Trim())"
} else {
    Warn "no default agent set (SUPER+SHIFT+CTRL+A, or omarchy-default-agent.ps1 claude)"
}

Section "windows tuning"
# The settings that actually conflict with a tiling WM, plus the ones the
# debloat profile is responsible for. This is what answers "is the taskbar
# tuned yet" without clicking through Settings.
$adv = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
$tuning = @(
    @{ N = "window snapping off";  P = $adv; K = "WindowArrangementActive"; V = 0 }
    @{ N = "snap assist off";      P = $adv; K = "SnapAssist";              V = 0 }
    @{ N = "task view hidden";     P = $adv; K = "ShowTaskViewButton";      V = 0 }
    @{ N = "widgets hidden";       P = $adv; K = "TaskbarDa";               V = 0 }
    @{ N = "file extensions shown";P = $adv; K = "HideFileExt";             V = 0 }
    @{ N = "hidden files shown";   P = $adv; K = "Hidden";                  V = 1 }
    @{ N = "search box hidden";    P = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"; K = "SearchboxTaskbarMode"; V = 0 }
)
foreach ($t in $tuning) {
    $actual = (Get-ItemProperty -Path $t.P -Name $t.K -ErrorAction SilentlyContinue).($t.K)
    if ($actual -eq $t.V) { Ok $t.N }
    else { Warn "$($t.N) - not set (./scripts/debloat-windows.ps1)" }
}

$mouse = Get-ItemProperty "HKCU:\Control Panel\Mouse" -ErrorAction SilentlyContinue
if ($mouse -and $mouse.MouseSpeed -eq "0") { Ok "mouse acceleration off" }
else { Warn "mouse acceleration on (./scripts/debloat-windows.ps1)" }

Section "wsl / docker"
$distro = "AlmaLinux-9"
if (Get-Command wsl -ErrorAction SilentlyContinue) {
    $wslConf = Join-Path $env:USERPROFILE ".wslconfig"
    if (Test-Path -LiteralPath $wslConf) { Ok ".wslconfig present" } else { Warn ".wslconfig missing" }

    $probe = & wsl.exe -d $distro -- bash -lc 'printf "%s|%s|%s|%s" "$(ps -p 1 -o comm=)" "$(command -v docker || echo -)" "$(command -v nvidia-ctk || echo -)" "$([ -e /dev/dxg ] && echo dxg || echo -)"' 2>$null
    $probe = ($probe -replace "`0", "").Trim()
    if ($probe) {
        $parts = $probe -split '\|'
        if ($parts[0] -eq "systemd") { Ok "$distro runs systemd" } else { Warn "$distro PID 1 is '$($parts[0])' - set [boot] systemd=true in /etc/wsl.conf" }
        if ($parts[1] -like "/mnt/*")     { Warn "docker in $distro is the Windows binary via PATH leak; appendWindowsPath=false will remove it (./scripts/install-docker-wsl.sh)" }
        elseif ($parts[1] -ne "-")        { Ok "docker installed in $distro" }
        else                              { Warn "no docker in $distro (bash ./scripts/install-docker-wsl.sh)" }
        if ($parts[2] -ne "-") { Ok "nvidia-container-toolkit installed" } else { Warn "nvidia-container-toolkit missing - GPU containers will not work" }
        if ($parts[3] -eq "dxg") { Ok "/dev/dxg present (GPU passthrough)" } else { Warn "/dev/dxg missing - no GPU in WSL" }
    } else {
        Warn "could not probe $distro (not installed, or a different name)"
    }
}

Section "processes"
foreach ($p in @("komorebi","whkd","yasb")) {
    if (Get-Process $p -ErrorAction SilentlyContinue) { Ok "$p running" }
    else { Warn "$p not running (./scripts/start-desktop.ps1)" }
}

Write-Host ""
Write-Host ("=" * 52)
Write-Host ("  {0} passed   {1} warnings   {2} failures" -f $script:Pass, $script:Warn, $script:Fail) -ForegroundColor $(
    if ($script:Fail) { "Red" } elseif ($script:Warn) { "Yellow" } else { "Green" })
Write-Host ("=" * 52)

if ($script:Fail) { exit 1 }
