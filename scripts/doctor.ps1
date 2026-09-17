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

# Pick up anything winget just installed. A process inherits the PATH it was
# started with, so running this straight after an install would otherwise
# report half the toolchain as missing - which is a false alarm, and the kind
# that teaches people to ignore the checker.
$env:PATH = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
            [Environment]::GetEnvironmentVariable("Path", "User")

$script:Pass = 0; $script:Warn = 0; $script:Fail = 0

function Ok   { param($m) $script:Pass++; Write-Host "  PASS  $m" -ForegroundColor Green }
function Warn { param($m) $script:Warn++; Write-Host "  WARN  $m" -ForegroundColor Yellow }
function Bad  { param($m) $script:Fail++; Write-Host "  FAIL  $m" -ForegroundColor Red }
function Section { param($m) Write-Host "`n$m" -ForegroundColor Magenta }

# --- talking to WSL safely ---------------------------------------------------
# wsl.exe ships with Windows whether or not the feature was ever enabled, so
# `Get-Command wsl` proves nothing, and on a machine without WSL the calls below
# can sit there for a long time before admitting it. doctor runs as the last
# step of every install, so that time is spent on exactly the clean machines
# this repo is for. Ask the service registry first - instant - and put a
# deadline on anything that does run.
#
# These are duplicated from scripts/lib/detect.ps1 on purpose: doctor.ps1 is
# documented as runnable on its own, straight off a URL, with no lib/ beside it.
function Test-WslPresent {
    if (-not (Get-Command wsl -ErrorAction SilentlyContinue)) { return $false }
    return (@(Get-Service -Name "LxssManager", "WSLService" -ErrorAction SilentlyContinue).Count -gt 0)
}

function Invoke-Wsl {
    param([string[]]$WslArgs, [int]$TimeoutMs = 20000)

    $out = ""
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName               = "wsl.exe"
        $psi.Arguments              = ($WslArgs -join ' ')
        $psi.UseShellExecute        = $false
        $psi.CreateNoWindow         = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError  = $true
        $psi.RedirectStandardInput  = $true

        $p = [System.Diagnostics.Process]::Start($psi)
        $p.StandardInput.Close()
        $stdout = $p.StandardOutput.ReadToEndAsync()
        [void]$p.StandardError.ReadToEndAsync()
        if (-not $p.WaitForExit($TimeoutMs)) {
            try { $p.Kill() } catch { }
            return ""
        }
        $out = $stdout.Result
    } catch { return "" }
    return ($out -replace "`0", "")
}

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
$ValidKeys += 0..9  | ForEach-Object { "$_" }
# NOT 'a'..'z': the string range operator is PowerShell 7+. On Windows
# PowerShell 5.1 it throws and yields nothing, so every single-letter key
# looked invalid and doctor reported a false failure on exactly the clean
# machines this repo is for. Build the letters from character codes instead.
$ValidKeys += 97..122 | ForEach-Object { [string][char]$_ }
$ValidKeys += 1..24 | ForEach-Object { "f$_" }
$ValidKeys += 0..9  | ForEach-Object { "numpad$_" }

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
# -Repo checks the repo's files, so what this particular box has installed is
# a different question - and on a CI runner the answer is always "nothing".
# Failing here made every CI run red for reasons no commit could fix, which
# is how a checker gets ignored.
if ($Repo) {
    Warn "skipped (-Repo mode checks files, not this machine)"
} else {
foreach ($c in @("winget","komorebic","whkd","yasb","alacritty","pwsh","git","fzf","wsl")) {
    if (Get-Command $c -ErrorAction SilentlyContinue) { Ok $c }
    elseif ($c -in @("fzf","alacritty")) { Warn "$c not on PATH (menus/pickers need it)" }
    else { Bad "$c not on PATH" }
}
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

Section "powershell 5.1 compatibility"
# A clean Windows 11 install has Windows PowerShell 5.1 and nothing else until
# winget installs pwsh 7. Anything the bootstrap path touches must therefore
# parse under 5.1 - PS7-only syntax (?., ??, ternaries) is a parse error there,
# so the script dies before printing anything.
$ps51 = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
if (Test-Path -LiteralPath $ps51) {
    $mustParse = @(
        "scripts\setup.ps1", "scripts\install-windows.ps1", "scripts\link-configs.ps1",
        "scripts\install-wsl.ps1", "scripts\install-localllm.ps1", "scripts\debloat-windows.ps1",
        "scripts\bootstrap-windows.ps1", "scripts\doctor.ps1",
        "scripts\lib\tui.ps1", "scripts\lib\detect.ps1", "scripts\lib\modules.ps1",
        "scripts\lib\common.ps1"
    )
    $bad51 = @()
    foreach ($rel in $mustParse) {
        $full = Join-Path $RepoRoot $rel
        if (-not (Test-Path -LiteralPath $full)) { continue }
        $out = & $ps51 -NoProfile -Command "
            `$e = `$null
            [System.Management.Automation.Language.Parser]::ParseFile('$full', [ref]`$null, [ref]`$e) | Out-Null
            if (`$e) { `$e[0].Message }" 2>&1
        if ($out) { $bad51 += "$rel : $out" }
    }
    if ($bad51.Count) {
        Bad "$($bad51.Count) script(s) do not parse under PowerShell 5.1:"
        $bad51 | ForEach-Object { Write-Host "          $_" -ForegroundColor Red }
    } else {
        Ok "all bootstrap scripts parse under PowerShell 5.1"
    }
} else {
    Warn "Windows PowerShell 5.1 not found - skipped the clean-machine parse check"
}

Section "fonts"
if ($Repo) { Warn "skipped (-Repo mode)" } else {
# Third instance of the same bug class in this repo: referring to something by
# a name that does not exist. A missing winget id prints an error; a bad whkd
# key name kills the daemon; a bad FONT family is the quietest of the three -
# Windows silently substitutes a font with no icon glyphs, so every icon turns
# into tofu or a random letter and icons overlap their labels.
#
# winget's DEVCOM.JetBrainsMonoNerdFont installs files named
# JetBrainsMonoNerdFont-*.ttf but registers the family as "JetBrainsMono NF".
Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
$families = @()
try {
    $families = (New-Object System.Drawing.Text.InstalledFontCollection).Families | ForEach-Object { $_.Name }
} catch { }

if (-not $families.Count) {
    Warn "could not enumerate installed fonts"
} else {
    $refs = @{}
    $alac = if ($Repo) { Join-Path $RepoRoot "configs\alacritty\alacritty.toml" } else { Join-Path $env:APPDATA "alacritty\alacritty.toml" }
    if (Test-Path -LiteralPath $alac) {
        Get-Content -LiteralPath $alac | Select-String -Pattern '^\s*family\s*=\s*"([^"]+)"' | ForEach-Object {
            $refs[$_.Matches[0].Groups[1].Value] = "alacritty"
        }
    }
    $kj = if ($Repo) { Join-Path $RepoRoot "configs\komorebi\komorebi.json" } else { Join-Path $cfg "komorebi\komorebi.json" }
    if (Test-Path -LiteralPath $kj) {
        Get-Content -LiteralPath $kj | Select-String -Pattern '"font_family"\s*:\s*"([^"]+)"' | ForEach-Object {
            $refs[$_.Matches[0].Groups[1].Value] = "komorebi stackbar"
        }
    }

    $missingFonts = @()
    foreach ($name in $refs.Keys) {
        if ($families -notcontains $name) { $missingFonts += "$name (in $($refs[$name]))" }
    }
    if ($missingFonts.Count) {
        Bad "font family not installed: $($missingFonts -join '; ')"
        Write-Host "          installed Nerd Font families:" -ForegroundColor Red
        $families | Where-Object { $_ -match 'NF$|NFM$|Nerd Font$' } | Select-Object -First 5 |
            ForEach-Object { Write-Host "            $_" -ForegroundColor Red }
    } elseif ($refs.Count) {
        Ok "all $($refs.Count) referenced font famil$(if ($refs.Count -eq 1) { 'y is' } else { 'ies are' }) installed"
    }

    # yasb CSS carries a fallback list, so only warn when none of them exist.
    $css = if ($Repo) { Join-Path $RepoRoot "configs\yasb\styles.css" } else { Join-Path $cfg "yasb\styles.css" }
    if (Test-Path -LiteralPath $css) {
        $line = (Get-Content -LiteralPath $css -Raw) -replace "`r?`n", " "
        if ($line -match 'font-family:\s*([^;]+);') {
            $list = @($Matches[1] -split ',' | ForEach-Object { $_.Trim().Trim('"') })
            $hit = @($list | Where-Object { $families -contains $_ })
            if ($hit.Count) { Ok "yasb font falls back to '$($hit[0])'" }
            else { Bad "yasb font-family lists nothing installed: $($list -join ', ')" }
        }
    }
}

# end of the fonts section
}

Section "runtimes and toolchains"
# The C++ and .NET runtimes are dependencies other software assumes is there,
# so their absence shows up as some unrelated app failing to start rather than
# as a missing runtime. Checked by registry, not by running anything.
if ($Repo) {
    Warn "skipped (-Repo mode)"
} else {
$uninstallKeys = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
)
$installedNames = @()
foreach ($k in $uninstallKeys) {
    if (Test-Path -LiteralPath $k) {
        $installedNames += @(Get-ChildItem -LiteralPath $k -ErrorAction SilentlyContinue |
            ForEach-Object { (Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue).DisplayName } |
            Where-Object { $_ })
    }
}

$vc = @($installedNames | Where-Object { $_ -match "Visual C\+\+ (2015|2017|2019|2022|v14)" })
if ($vc.Count) { Ok "Visual C++ runtime present ($($vc.Count) entries)" }
else { Warn "no Visual C++ 2015+ runtime (./scripts/install-windows.ps1 -Groups core)" }

# dotnet --list-runtimes is the answer from the tool itself rather than from
# the registry, and it distinguishes runtime from SDK, which matters here:
# core installs the runtime and the SDK is its own module.
$dotnet = Get-Command dotnet.exe -ErrorAction SilentlyContinue
if (-not $dotnet) {
    Warn "dotnet not on PATH - no .NET runtime (./scripts/install-windows.ps1 -Groups core)"
} else {
    $runtimes = @(& $dotnet.Source --list-runtimes 2>$null)
    $sdks     = @(& $dotnet.Source --list-sdks 2>$null)
    if ($runtimes.Count) { Ok ".NET runtimes: $($runtimes.Count) installed" }
    else { Warn "dotnet present but no runtimes listed" }
    if ($sdks.Count) { Ok ".NET SDK: $($sdks.Count) installed" }
    else { Warn "no .NET SDK - dotnet build will not work (./scripts/install-windows.ps1 -Groups dotnet)" }
}

$mise = Get-Command mise -ErrorAction SilentlyContinue
if (-not $mise) {
    Warn "mise not installed (./scripts/install-windows.ps1 -Groups langs)"
} else {
    $miseVer = ((& $mise.Source --version 2>$null) -join " ").Trim()
    Ok "mise $miseVer"
    # What it is actually managing on this machine, if anything.
    $tools = @(& $mise.Source ls --installed 2>$null | Where-Object { $_ -match "\S" })
    if ($tools.Count) { Ok "mise manages $($tools.Count) tool version(s) here" }
    else { Ok "mise installed, no toolchains pinned yet (mise use python@3.13)" }
}
}

Section "powershell 7 modules"
if ($Repo) { Warn "skipped (-Repo mode)" } else {
# The shipped profile is PS7-only, and the two PowerShells do not share a
# module directory (5.1 -> Documents\WindowsPowerShell\Modules,
# 7 -> Documents\PowerShell\Modules). Modules installed from the wrong host
# land where the profile never looks, and it degrades silently.
$pwshCmd = Get-Command pwsh.exe -ErrorAction SilentlyContinue
if (-not $pwshCmd) {
    Warn "PowerShell 7 not installed - the shipped profile needs it (-Groups core)"
} else {
    # Version, not just presence. install-windows.ps1 SKIPS a package that is
    # already installed, so a machine that came with an older pwsh 7 keeps it
    # and nothing says so. -Force is what re-runs winget and upgrades.
    $pwshVer = (& $pwshCmd.Source -NoProfile -Command '$PSVersionTable.PSVersion.ToString()' 2>$null | Select-Object -First 1)
    if ($pwshVer) { $pwshVer = "$pwshVer".Trim() }
    if (-not $Quick -and $pwshVer -and (Get-Command winget -ErrorAction SilentlyContinue)) {
        # Version numbers are digits in every locale; the column headers are
        # not, so read the numbers and ignore the labels. Two of them means
        # winget is showing Version and Available side by side.
        $listed = (winget list --id Microsoft.PowerShell -e --disable-interactivity 2>$null | Out-String)
        $vers = [regex]::Matches($listed, '\b\d+\.\d+\.\d+(\.\d+)?\b') | ForEach-Object { $_.Value }
        if ($vers.Count -ge 2) {
            Warn "pwsh $pwshVer installed, winget offers $($vers[-1]) (./scripts/install-windows.ps1 -Groups core -Force)"
        } else {
            Ok "pwsh $pwshVer (winget has nothing newer)"
        }
    } elseif ($pwshVer) {
        Ok "pwsh $pwshVer"
    }

    $wanted = @("PSReadLine", "Terminal-Icons", "PSFzf", "posh-git", "CompletionPredictor")
    $found = & $pwshCmd.Source -NoProfile -Command "
        foreach (`$m in @('$($wanted -join "','")')) {
            if (Get-Module -ListAvailable -Name `$m) { `$m }
        }" 2>$null
    $found = @($found | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })
    $missing = @($wanted | Where-Object { $found -notcontains $_ })
    if ($missing.Count) {
        Warn "missing from pwsh 7: $($missing -join ', ')  (./scripts/install-windows.ps1 -ModulesOnly)"
    } else {
        Ok "all $($wanted.Count) profile modules present in pwsh 7"
    }

    # Modules in the 5.1 tree that pwsh 7 cannot see are the classic symptom
    # of installing them from the wrong host.
    $ps51Modules = Join-Path $env:USERPROFILE "Documents\WindowsPowerShell\Modules"
    if (Test-Path -LiteralPath $ps51Modules) {
        $stray = @(Get-ChildItem -LiteralPath $ps51Modules -Directory -ErrorAction SilentlyContinue |
            Where-Object { $wanted -contains $_.Name } | ForEach-Object { $_.Name })
        if ($stray.Count) {
            Warn "also in the 5.1 module tree (pwsh 7 ignores these): $($stray -join ', ')"
        }
    }
}

# end of the powershell 7 modules section
}

Section "whkd"
$whkdrcPath = if ($Repo) { Join-Path $RepoRoot "configs\whkd\whkdrc" } else { Join-Path $cfg "whkdrc" }
Test-Whkdrc $whkdrcPath

# whkd shells out to the helper launcher; if that is missing, 11 bindings do
# nothing and whkd has no way to say so.
$runner = Join-Path $cfg "omacheese\bin\omacheese-run.cmd"
if ((Get-Content -LiteralPath $whkdrcPath -ErrorAction SilentlyContinue | Select-String -Quiet "omacheese-run.cmd")) {
    if ($Repo) {
        Ok "whkdrc uses the shell-agnostic launcher"
    } elseif (Test-Path -LiteralPath $runner) {
        Ok "omacheese-run.cmd installed"
    } else {
        Bad "whkdrc calls omacheese-run.cmd but it is missing ($runner) - run link-configs.ps1"
    }
}

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
        "omacheese-menu"       = Join-Path $cfg "omacheese\bin\omacheese-menu.ps1"
        "omacheese-keybindings"= Join-Path $cfg "omacheese\bin\omacheese-keybindings.ps1"
        "start-desktop"      = Join-Path $cfg "omacheese\bin\start-desktop.ps1"
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
if ($Repo) {
    Warn "skipped (-Repo mode)"
} else {
$kch = [Environment]::GetEnvironmentVariable("KOMOREBI_CONFIG_HOME", "User")
if ($kch) { Ok "KOMOREBI_CONFIG_HOME=$kch" } else { Bad "KOMOREBI_CONFIG_HOME not set for the user" }

$startupLnk = Join-Path ([Environment]::GetFolderPath("Startup")) "komorebi-desktop.lnk"
if (Test-Path -LiteralPath $startupLnk) { Ok "autostart shortcut present" }
else { Warn "no autostart shortcut - the desktop will not come back after a reboot" }

}

Section "ssh agent"
if ($Repo) { Warn "skipped (-Repo mode)" } else {
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

# end of the ssh agent section
}

Section "coding agents"
if ($Repo) { Warn "skipped (-Repo mode)" } else {
$agentState = Join-Path $cfg "omacheese\defaults\agent"
$agentRegistry = Join-Path $cfg "omacheese\bin\omacheese-default-agent.ps1"
$knownAgents = @{}
if (Test-Path -LiteralPath $agentRegistry) {
    # Dot-source the installed registry rather than keeping a second copy here.
    # A duplicated table is how a wrong command name survives: it looks right in
    # one file and is never compared against the other.
    . $agentRegistry
    foreach ($k in $script:Agents.Keys) { $knownAgents[$k] = $script:Agents[$k].Command }
    Ok "agent registry readable ($($knownAgents.Count) agents)"
} else {
    Bad "agent registry missing: $agentRegistry"
}
$installedAgents = @()
foreach ($k in $knownAgents.Keys) {
    if (Get-Command $knownAgents[$k] -ErrorAction SilentlyContinue) { $installedAgents += $k }
}
if ($installedAgents.Count) { Ok "agents installed: $($installedAgents -join ', ')" }
else { Warn "no coding agent installed (./scripts/install-windows.ps1 -Groups agents)" }

if (Test-Path -LiteralPath $agentState) {
    Ok "default agent: $((Get-Content -LiteralPath $agentState -Raw).Trim())"
} else {
    Warn "no default agent set (SUPER+SHIFT+CTRL+A, or omacheese-default-agent.ps1 claude)"
}

# SUPER+ALT+A runs the agent inside AlmaLinux. Installing it on Windows tells
# you nothing about that: the WSL module ships zsh, tmux and the CLI tools, and
# no agent and no Node. Before this check the hotkey printed "command not found"
# into a terminal that closed before anyone could read it.
if (-not $Quick -and $knownAgents.Count) {
    $distro = "AlmaLinux-9"
    $haveDistro = $false
    if (Test-WslPresent) {
        $haveDistro = @((Invoke-Wsl @("-l", "-q") -TimeoutMs 8000) -split "`r?`n" |
            ForEach-Object { $_.Trim() } | Where-Object { $_ }) -contains $distro
    }
    if (-not $haveDistro) {
        Warn "$distro not installed; SUPER+ALT+A (agent in WSL) cannot work"
    } else {
        $inWsl = @()
        foreach ($k in $knownAgents.Keys) {
            $hit = (Invoke-Wsl @("-d", $distro, "--", "bash", "-lc",
                ('"command -v {0} 2>/dev/null"' -f $knownAgents[$k]))).Trim()
            # /mnt/* is the Windows copy reaching in over the interop PATH, not
            # a Linux install, and it cannot serve as one.
            if ($hit -and $hit -notlike "/mnt/*") { $inWsl += $k }
        }
        if ($inWsl.Count) { Ok "agents in ${distro}: $($inWsl -join ', ')" }
        else { Warn "no agent installed in $distro (wsl -d $distro -- bash ~/.config/omacheese/install-agents.sh)" }
    }
}

# end of the coding agents section
}

Section "herdr (optional)"
# herdr is opt-in, so "not installed" is a normal state, not a warning worth
# nagging about. What IS worth checking is a half-installed one: the binary
# without its config, or a config herdr will not read.
if ($Repo) {
    Warn "skipped (-Repo mode)"
} else {
$herdrExe = (Get-Command herdr -ErrorAction SilentlyContinue).Source
if (-not $herdrExe) {
    $f = Join-Path $env:LOCALAPPDATA "Programs\Herdr\bin\herdr.exe"
    if (Test-Path -LiteralPath $f) { $herdrExe = $f }
}
if (-not $herdrExe) {
    Ok "herdr not installed (optional - ./scripts/install-herdr.ps1)"
} else {
    Ok "herdr: $herdrExe"

    # %APPDATA%, not ~/.config. herdr --help prints the path, and
    # `herdr config check` says "config: ok" for a file it never opened, so
    # the wrong path here is invisible without testing the right one.
    $herdrCfg = Join-Path $env:APPDATA "herdr\config.toml"
    if (Test-Path -LiteralPath $herdrCfg) {
        $check = (& $herdrExe config check 2>&1) -join "`n"
        if ($check -match "config: ok") { Ok "herdr config valid" }
        elseif ($check -match "unknown config key|parse error") {
            Bad "herdr config rejected: $(($check -split "`n" | Select-Object -Skip 1 -First 2) -join "; ")"
        } else { Warn "herdr config check said: $check" }
    } else {
        Warn "herdr installed but no config at $herdrCfg (./scripts/omacheese/omacheese-theme.ps1 -Set tokyo-night)"
    }

    $layouts = Join-Path $cfg "omacheese\agent-layouts.ps1"
    if (Test-Path -LiteralPath $layouts) { Ok "hdl/hds/hdlm/hsl installed" }
    else { Warn "agent-layouts.ps1 missing (./scripts/link-configs.ps1)" }
}
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
if (-not (Test-WslPresent)) {
    Warn "WSL is not installed (./scripts/setup.ps1 -Modules wsl)"
} else {
    $wslConf = Join-Path $env:USERPROFILE ".wslconfig"
    if (Test-Path -LiteralPath $wslConf) { Ok ".wslconfig present" } else { Warn ".wslconfig missing" }

    # Getting a shell snippet into WSL from PowerShell is fiddlier than it
    # looks, and two things broke here before this shape:
    #   * `wsl -- bash -lc '<script>'` loses the inner quotes on the way
    #     through PowerShell's native-argument handling, so bash ended up
    #     trying to run "%s" as a command
    #   * piping the script in adds a UTF-8 BOM on 5.1, and bash reports
    #     "<BOM>printf: command not found"
    # Writing a BOM-less temp file and running that avoids both.
    #
    # WSL also prints noise on stderr ("your 131072x1 screen size is bogus"),
    # so the payload is tagged and pulled back out by marker.
    $probeBody = "printf 'W11PROBE|%s|%s|%s|%s\n' `"`$(ps -p 1 -o comm=)`" `"`$(command -v docker || echo -)`" `"`$(command -v nvidia-ctk || echo -)`" `"`$([ -e /dev/dxg ] && echo dxg || echo -)`"`n"
    $probeFile = Join-Path $env:TEMP "w11-doctor-probe.sh"
    [System.IO.File]::WriteAllText($probeFile, ($probeBody -replace "`r`n", "`n"),
        (New-Object System.Text.UTF8Encoding($false)))

    # Bounded, like every other call into WSL here: booting a distro that has
    # never been started is slow, and one that cannot boot at all used to hold
    # the last step of the install open with nothing on screen.
    $probeLinux = (Invoke-Wsl @("-d", $distro, "--", "wslpath", "-a",
        ('"{0}"' -f ($probeFile -replace '\\', '/'))) -TimeoutMs 60000).Trim()

    $probe = ""
    if ($probeLinux) {
        $raw = Invoke-Wsl @("-d", $distro, "--", "bash", ('"{0}"' -f $probeLinux)) -TimeoutMs 60000
        foreach ($ln in ($raw -split "`r?`n")) {
            $idx = $ln.IndexOf("W11PROBE|")
            if ($idx -ge 0) { $probe = $ln.Substring($idx + 9).Trim(); break }
        }
    }

    if ($probe) {
        $parts = $probe -split '\|'
        if ($parts[0] -eq "systemd") { Ok "$distro runs systemd" } else { Warn "$distro PID 1 is '$($parts[0])' - set [boot] systemd=true in /etc/wsl.conf" }
        if ($parts[1] -like "/mnt/*")     { Warn "docker in $distro is the Windows binary via PATH leak; appendWindowsPath=false will remove it (./scripts/install-docker-wsl.sh)" }
        elseif ($parts[1] -ne "-")        { Ok "docker installed in $distro" }
        else                              { Warn "no docker in $distro (bash ./scripts/install-docker-wsl.sh)" }
        if ($parts[2] -ne "-") { Ok "nvidia-container-toolkit installed" } else { Warn "nvidia-container-toolkit missing - GPU containers will not work" }
        if ($parts[3] -eq "dxg") { Ok "/dev/dxg present (GPU passthrough)" } else { Warn "/dev/dxg missing - no GPU in WSL" }

        # Only ask about the model server on a machine where the local-LLM
        # module actually ran - docker in the distro is that evidence. A
        # running container proves nothing on its own: vLLM binds port 8000
        # only once the weights are loaded onto the GPU.
        if ($parts[1] -ne "-" -and $parts[1] -notlike "/mnt/*") {
            $served = $false
            try {
                # 127.0.0.1, not localhost: localhost resolves to ::1 first and
                # WSL forwards the port on IPv4 only, so the v6 attempt is not
                # refused - it hangs until the timeout. Measured here: ::1 still
                # waiting at 20s, 127.0.0.1 answering in 85ms.
                $served = (Invoke-WebRequest -Uri "http://127.0.0.1:8000/v1/models" `
                           -UseBasicParsing -TimeoutSec 10).StatusCode -eq 200
            } catch { }
            if ($served) { Ok "vLLM answering at http://127.0.0.1:8000/v1" }
            else { Warn "nothing answers on :8000 (wsl -d $distro -- docker logs vllm)" }
        }
    } else {
        Warn "could not probe $distro (not installed, or a different name)"
    }
}

Section "theme"
# A leftover {{token}} in a rendered config means the palette is missing a key -
# komorebi refuses the file outright, yasb just draws the element black.
$themeHome = Join-Path $env:USERPROFILE ".config\omacheese\theme"
$activeName = "tokyo-night"
$activeFile = Join-Path $themeHome "active"
if (Test-Path -LiteralPath $activeFile) {
    $n = (Get-Content -LiteralPath $activeFile -Raw).Trim()
    if ($n) { $activeName = $n }
}
$palFile = Join-Path $themeHome "palettes\$activeName.toml"
if (-not (Test-Path -LiteralPath $palFile)) {
    Warn "palette '$activeName' not installed - run ./scripts/link-configs.ps1"
} else {
    Ok "theme '$activeName'"
    $rendered = @(
        (Join-Path $env:USERPROFILE ".config\komorebi\komorebi.json"),
        (Join-Path $env:USERPROFILE ".config\yasb\styles.css"),
        (Join-Path $env:APPDATA "alacritty\alacritty.toml")
    )
    $stray = 0
    foreach ($f in $rendered) {
        if (-not (Test-Path -LiteralPath $f)) { continue }
        $txt = Get-Content -LiteralPath $f -Raw
        $m = [regex]::Matches($txt, '\{\{(\w+)\}\}')
        if ($m.Count -gt 0) {
            $names = ($m | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique) -join ', '
            Bad "$(Split-Path $f -Leaf): unresolved $names"
            $stray++
        }
    }
    if ($stray -eq 0) { Ok "rendered configs have no unresolved tokens" }
}

Section "raycast script commands"
# These are inert without Raycast, but a malformed metadata header means the
# command silently never appears - so validate the header rather than the app.
$rcDir = Join-Path $env:USERPROFILE ".config\omacheese\raycast"
if (-not (Test-Path -LiteralPath $rcDir)) {
    Warn "not installed - run ./scripts/link-configs.ps1"
} else {
    $rcFiles = @(Get-ChildItem $rcDir -Filter *.ps1 | Where-Object { $_.Name -notlike "_*" })
    if ($rcFiles.Count -eq 0) {
        Warn "no script commands in $rcDir"
    } else {
        $validModes = @("fullOutput", "compact", "silent", "inline")
        $rcBad = 0
        foreach ($f in $rcFiles) {
            $text = Get-Content -LiteralPath $f.FullName -Raw
            $meta = @{}
            foreach ($m in [regex]::Matches($text, '(?m)^#\s*@raycast\.(\w+)\s+(.*?)\s*$')) {
                $meta[$m.Groups[1].Value] = $m.Groups[2].Value
            }
            $missing = @("schemaVersion", "title", "mode") | Where-Object { -not $meta.ContainsKey($_) }
            if ($missing) { Bad "$($f.Name): missing @raycast.$($missing -join ', ')"; $rcBad++; continue }
            if ($validModes -notcontains $meta["mode"]) { Bad "$($f.Name): bad mode '$($meta['mode'])'"; $rcBad++; continue }
            $argBad = $false
            foreach ($k in $meta.Keys) {
                if ($k -notlike "argument*") { continue }
                try { $null = $meta[$k] | ConvertFrom-Json } catch { Bad "$($f.Name): $k is not valid JSON"; $argBad = $true }
            }
            if ($argBad) { $rcBad++ }
        }
        if ($rcBad -eq 0) { Ok "$($rcFiles.Count) script commands valid" }
    }
}

Section "processes"
foreach ($p in @("komorebi","whkd","yasb")) {
    if (Get-Process $p -ErrorAction SilentlyContinue) { Ok "$p running" }
    else { Warn "$p not running (./scripts/start-desktop.ps1)" }
}

# The scroll daemon is a pwsh process, so it cannot be found by image name.
# Without it the Scrolling layout still works, it just loses the neighbour peek
# and the alignment at the ends of the strip - a silent degradation worth
# reporting rather than leaving to be noticed.
$scrollPid = Join-Path $env:USERPROFILE ".config\omacheese\scroll-daemon.pid"
$scrollUp = $false
if (Test-Path -LiteralPath $scrollPid) {
    try {
        $sp = [int](Get-Content -LiteralPath $scrollPid -Raw).Trim()
        if (Get-Process -Id $sp -ErrorAction SilentlyContinue) { $scrollUp = $true }
    } catch { }
}
if ($scrollUp) { Ok "scroll daemon running" }
else { Warn "scroll daemon not running - scrolling mode loses its peek (./scripts/start-desktop.ps1)" }

# Also a pwsh process, so also invisible to an image-name check. Without it the
# menu still opens, it just takes ~770ms instead of ~170ms.
$menuPid = Join-Path $env:USERPROFILE ".config\omacheese\menu-server.pid"
$menuUp = $false
if (Test-Path -LiteralPath $menuPid) {
    try {
        $mp = [int](Get-Content -LiteralPath $menuPid -Raw).Trim()
        if (Get-Process -Id $mp -ErrorAction SilentlyContinue) { $menuUp = $true }
    } catch { }
}
if ($menuUp) { Ok "menu server running" }
else { Warn "menu server not running - SUPER+SPACE will be slow (./scripts/start-desktop.ps1)" }

Write-Host ""
Write-Host ("=" * 52)
Write-Host ("  {0} passed   {1} warnings   {2} failures" -f $script:Pass, $script:Warn, $script:Fail) -ForegroundColor $(
    if ($script:Fail) { "Red" } elseif ($script:Warn) { "Yellow" } else { "Green" })
Write-Host ("=" * 52)

# Always exit explicitly. Without the `exit 0`, the process inherits
# $LASTEXITCODE from whatever native command ran last - and doctor calls
# wsl.exe, which returns -1 when the distro is missing. GitHub's pwsh shell
# appends `exit $LASTEXITCODE`, so CI failed a step that had just printed
# "0 failures". The exit code now says exactly one thing: did a check fail.
if ($script:Fail) { exit 1 }
exit 0
