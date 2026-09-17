# Install every config from the repo into the places the tools read.
#
#   ./scripts/link-configs.ps1            symlink (edits in the repo go live)
#   ./scripts/link-configs.ps1 -Copy      plain copies instead
#   ./scripts/link-configs.ps1 -NoAutostart
#
# Anything already present is backed up first, into ONE folder per run:
#   %USERPROFILE%\.config\omacheese\backups\<timestamp>\
# mirroring the original paths, with a manifest.tsv. The path is printed at
# the end; restore-backup.ps1 puts it all back.
#
# Symlinks need Developer Mode or an elevated shell; without either the script
# falls back to copying and says so.

[CmdletBinding()]
param(
    [switch]$Copy,
    [switch]$NoAutostart
)

$ErrorActionPreference = "Stop"

$Repo = Split-Path -Parent $PSScriptRoot
. (Join-Path $Repo "scripts\lib\common.ps1")

# A symlink is only worth making when its target is going to be there tomorrow.
# Run from a copy of the repo that lives under %TEMP% - which is where the
# one-liner installer used to unpack it - every link here points at a directory
# Windows deletes on its own schedule, and the whole setup silently reverts:
# the prompt goes back to bare PowerShell, Alacritty loses its theme, and
# SUPER+SPACE stops answering. Copy instead, so the files stand on their own.
$tempRoot = ""
if ($env:TEMP) { $tempRoot = [IO.Path]::GetFullPath($env:TEMP).TrimEnd('\') }
if (-not $Copy -and $tempRoot -and
    [IO.Path]::GetFullPath($Repo).StartsWith($tempRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
    Write-Host "  this repo is under %TEMP% - copying configs instead of linking them" -ForegroundColor Yellow
    Write-Host "  (a link into %TEMP% breaks the next time Windows clears it)" -ForegroundColor DarkGray
    $Copy = $true
}

$Install = if ($Copy) { "Install-ConfigFile" } else { "Install-ConfigLink" }

function Put {
    param([string]$Source, [string]$Destination)
    # The installers return a bool for callers that care; swallow it here so
    # the transcript stays readable.
    & $Install -Source (Join-Path $Repo $Source) -Destination $Destination | Out-Null
}

$cfg       = Join-Path $env:USERPROFILE ".config"
$omacheese   = Join-Path $cfg "omacheese\bin"

Write-Host "Installing configs ($(if ($Copy) { 'copy' } else { 'symlink' }) mode)" -ForegroundColor Green

foreach ($d in @(
    (Join-Path $env:APPDATA "alacritty"),
    (Join-Path $env:USERPROFILE ".ssh"),
    $cfg,
    (Join-Path $cfg "komorebi"),
    (Join-Path $cfg "yasb"),
    (Join-Path $cfg "oh-my-posh"),
    (Join-Path $cfg "wsl"),
    $omacheese
)) { Ensure-Dir $d }

Write-Host "`n[env]" -ForegroundColor Magenta
Set-UserEnvVar -Name "KOMOREBI_CONFIG_HOME" -Value (Join-Path $cfg "komorebi")

Write-Host "`n[terminal]" -ForegroundColor Magenta
Put "configs\alacritty\alacritty.toml"     (Join-Path $env:APPDATA "alacritty\alacritty.toml")
Put "configs\alacritty\alacritty.wsl.toml" (Join-Path $env:APPDATA "alacritty\alacritty.wsl.toml")

Write-Host "`n[window manager]" -ForegroundColor Magenta
Put "configs\komorebi\komorebi.json" (Join-Path $cfg "komorebi\komorebi.json")
# whkd reads ~/.config/whkdrc by default.
Put "configs\whkd\whkdrc"            (Join-Path $cfg "whkdrc")
Put "configs\yasb\config.yaml"       (Join-Path $cfg "yasb\config.yaml")
Put "configs\yasb\styles.css"        (Join-Path $cfg "yasb\styles.css")

Write-Host "`n[shell]" -ForegroundColor Magenta
Put "configs\oh-my-posh\poweruser.omp.json" (Join-Path $cfg "oh-my-posh\poweruser.omp.json")
# PowerShell 7 only. Documents\WindowsPowerShell is 5.1 and must not get this.
Put "configs\powershell\Microsoft.PowerShell_profile.ps1" `
    (Join-Path $env:USERPROFILE "Documents\PowerShell\Microsoft.PowerShell_profile.ps1")

Write-Host "`n[git]" -ForegroundColor Magenta
# Carry the existing identity across before replacing ~/.gitconfig. Without
# this, installing on a machine that already had git configured silently
# removes user.name/user.email, and the next commit either fails or is
# attributed to nobody. The repo's gitconfig includes ~/.gitconfig.local.
$gitLocal = Join-Path $env:USERPROFILE ".gitconfig.local"
$existingName  = ""
$existingEmail = ""
if (Get-Command git -ErrorAction SilentlyContinue) {
    $existingName  = (git config --global --get user.name)  2>$null
    $existingEmail = (git config --global --get user.email) 2>$null
}
if (($existingName -or $existingEmail) -and -not (Test-Path -LiteralPath $gitLocal)) {
    $body = @("# Preserved from your previous ~/.gitconfig by link-configs.ps1.", "[user]")
    if ($existingName)  { $body += "`tname = $existingName" }
    if ($existingEmail) { $body += "`temail = $existingEmail" }

    # Written BOM-less on purpose. git itself tolerates a BOM here, but
    # Set-Content -Encoding utf8 adds one on Windows PowerShell 5.1, and the
    # same habit already broke the WSL probe in doctor.ps1 (bash reported
    # "<BOM>printf: command not found"). Config files this repo generates are
    # consistently BOM-less so that stops being a class of bug.
    [System.IO.File]::WriteAllText($gitLocal, (($body -join "`n") + "`n"),
        (New-Object System.Text.UTF8Encoding($false)))
    Write-Host ("  + kept git identity in {0}" -f $gitLocal) -ForegroundColor Green
    Write-Host ("    {0} <{1}>" -f $existingName, $existingEmail) -ForegroundColor DarkGray
} elseif (Test-Path -LiteralPath $gitLocal) {
    Write-Host "  = .gitconfig.local already present (identity kept)" -ForegroundColor DarkGray
}

Put "configs\git\gitconfig" (Join-Path $env:USERPROFILE ".gitconfig")

Write-Host "`n[wsl]" -ForegroundColor Magenta
Put "configs\wsl\.wslconfig"           (Join-Path $env:USERPROFILE ".wslconfig")
Put "configs\wsl\wsl.conf"             (Join-Path $cfg "wsl\wsl.conf")
Put "configs\wsl\ssh-agent-bridge.sh"  (Join-Path $cfg "wsl\ssh-agent-bridge.sh")

# Lands next to the other omacheese helpers because that is the path
# omacheese-agent.ps1 -Wsl prints when it finds no agent inside the distro.
# ~/.config is readable from AlmaLinux as-is, so there is nothing to copy in.
& $Install -Source (Join-Path $Repo "scripts\install-agents-wsl.sh") `
           -Destination (Join-Path $cfg "omacheese\install-agents.sh") | Out-Null

# Dot-sourced by the PowerShell profile when present.
& $Install -Source (Join-Path $Repo "configs\powershell\agent-layouts.ps1") `
           -Destination (Join-Path $cfg "omacheese\agent-layouts.ps1") | Out-Null

# omacheese-herdr.cmd names this path when herdr is missing, so it has to be
# there for the message to be worth printing.
& $Install -Source (Join-Path $Repo "scripts\install-herdr.ps1") `
           -Destination (Join-Path $omacheese "install-herdr.ps1") | Out-Null

Write-Host "`n[ssh]" -ForegroundColor Magenta
# Example only - never overwrite a real ~/.ssh/config.
Install-ConfigFile -Source (Join-Path $Repo "configs\ssh\config.example") `
                   -Destination (Join-Path $env:USERPROFILE ".ssh\config.example") | Out-Null

Write-Host "`n[omacheese helpers]" -ForegroundColor Magenta
foreach ($s in Get-ChildItem (Join-Path $Repo "scripts\omacheese") | Where-Object { $_.Extension -in @(".ps1", ".cmd") }) {
    & $Install -Source $s.FullName -Destination (Join-Path $omacheese $s.Name) | Out-Null
}
& $Install -Source (Join-Path $Repo "scripts\start-desktop.ps1") `
           -Destination (Join-Path $omacheese "start-desktop.ps1") | Out-Null

# --- Raycast script commands -------------------------------------------------
# Installed whether or not Raycast is present: they are inert .ps1 files, and
# having them in place means enabling Raycast later is one setting rather than
# another install step. Raycast has to be pointed at the folder by hand -
# Settings -> Extensions -> Script Commands -> Add Script Directory - because
# that lives in its own store, not on disk where we could write it.
Write-Host "`n[raycast script commands]" -ForegroundColor Magenta
$raycastDir = Join-Path $cfg "omacheese\raycast"
Ensure-Dir $raycastDir
$raycastSrc = Join-Path $Repo "raycast"
if (Test-Path -LiteralPath $raycastSrc) {
    foreach ($s in Get-ChildItem $raycastSrc -Filter *.ps1) {
        & $Install -Source $s.FullName -Destination (Join-Path $raycastDir $s.Name) | Out-Null
    }
    Write-Host "  point Raycast at: $raycastDir" -ForegroundColor DarkGray
}

# --- theme -------------------------------------------------------------------
# Palettes and templates go in first, then the colours get rendered from them.
# komorebi.json, styles.css and alacritty.toml were copied above; this rewrites
# their colours for whichever theme is active, so the copies act as defaults and
# the palette has the last word.
Write-Host "`n[theme]" -ForegroundColor Magenta
$themeHome = Join-Path $cfg "omacheese\theme"
$palDest   = Join-Path $themeHome "palettes"
$tmplDest  = Join-Path $themeHome "templates"
Ensure-Dir $palDest
Ensure-Dir $tmplDest

foreach ($p in Get-ChildItem (Join-Path $Repo "configs\theme") -Filter *.toml -ErrorAction SilentlyContinue) {
    & $Install -Source $p.FullName -Destination (Join-Path $palDest $p.Name) | Out-Null
}
# Discovered, not listed. The previous hardcoded list had already gone stale:
# it never copied configs/herdr/config.toml.tmpl, so a machine installing from
# the archive rather than a clone silently had no herdr theming.
foreach ($src in Get-ChildItem (Join-Path $Repo "configs") -Recurse -Filter *.tmpl) {
    & $Install -Source $src.FullName -Destination (Join-Path $tmplDest $src.Name) | Out-Null
}

# Keep whatever theme was already chosen; only fall back on a fresh machine.
$activeFile = Join-Path $themeHome "active"
$activeTheme = "tokyo-night"
if (Test-Path -LiteralPath $activeFile) {
    $n = (Get-Content -LiteralPath $activeFile -Raw).Trim()
    if ($n) { $activeTheme = $n }
}

$themeScript = Join-Path $Repo "scripts\omacheese\omacheese-theme.ps1"
if (Test-Path -LiteralPath $themeScript) {
    & $themeScript -Set $activeTheme -NoRestart
} else {
    Write-Host "  omacheese-theme.ps1 missing - colours left as shipped" -ForegroundColor Yellow
}

# --- komorebi application-specific config ------------------------------------
# This is the community-maintained ruleset that teaches komorebi how Electron
# apps, installers and dialogs behave. komorebic check nags without it, and
# window management is visibly worse.
Write-Host "`n[komorebi applications.json]" -ForegroundColor Magenta
$asc = Join-Path $cfg "komorebi\applications.json"
if (Test-Path -LiteralPath $asc) {
    Write-Host "  = already present" -ForegroundColor DarkGray
} elseif (Get-Command komorebic -ErrorAction SilentlyContinue) {
    try {
        komorebic fetch-asc | Out-Null
        if (Test-Path -LiteralPath $asc) {
            Write-Host "  + fetched" -ForegroundColor Green
        } else {
            Write-Host "  ! fetch-asc ran but produced nothing; run it by hand" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "  ! komorebic fetch-asc failed: $($_.Exception.Message)" -ForegroundColor Yellow
    }
} else {
    Write-Host "  - komorebic not installed yet; run 'komorebic fetch-asc' later" -ForegroundColor DarkGray
}

# --- Autostart ---------------------------------------------------------------
# Without this the whole desktop has to be started by hand after every login,
# which is the difference between a demo and a setup you actually use.
if (-not $NoAutostart) {
    Write-Host "`n[autostart]" -ForegroundColor Magenta
    $startup  = [Environment]::GetFolderPath("Startup")
    $lnk      = Join-Path $startup "komorebi-desktop.lnk"
    # The target has to be a path that still exists after PowerShell updates
    # itself, because this shortcut outlives every one of them.
    #
    # Get-Command pwsh.exe resolves the Store package to its VERSIONED install
    # directory - measured here:
    #   C:\Program Files\WindowsApps\Microsoft.PowerShell_7.6.6.0_x64__...\pwsh.exe
    # That directory is replaced wholesale on the next update, and a Startup
    # shortcut pointing into it fails silently at login: no komorebi, no whkd,
    # no bar, and nothing to say why. Prefer the two stable spellings first -
    # the MSI location, then the Store execution alias - and only fall back to
    # whatever PATH resolves.
    #
    # No ?. here: this script has to parse under Windows PowerShell 5.1, which
    # is all a freshly installed Windows 11 has until winget brings pwsh 7.
    $target = $null
    foreach ($candidate in @(
        (Join-Path $env:ProgramFiles "PowerShell\7\pwsh.exe"),
        (Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps\pwsh.exe")
    )) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) { $target = $candidate; break }
    }
    if (-not $target) {
        $pwshCmd = Get-Command pwsh.exe -ErrorAction SilentlyContinue
        if ($pwshCmd) { $target = $pwshCmd.Source } else { $target = (Get-Command powershell.exe).Source }
    }

    try {
        $shell = New-Object -ComObject WScript.Shell
        $sc = $shell.CreateShortcut($lnk)
        $sc.TargetPath   = $target
        $sc.Arguments    = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$(Join-Path $omacheese 'start-desktop.ps1')`""
        $sc.WorkingDirectory = $omacheese
        $sc.Description  = "Start komorebi, whkd and yasb"
        $sc.Save()
        Write-Host "  + $lnk" -ForegroundColor Green
    } catch {
        Write-Host "  ! could not create the startup shortcut: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "Done." -ForegroundColor Green
Write-Host "  whkd config       : $(Join-Path $cfg 'whkdrc')"
Write-Host "  KOMOREBI_CONFIG_HOME = $env:KOMOREBI_CONFIG_HOME"

# Tell the user exactly where their old files went. On a machine that already
# had configs this is the most important line of the whole run.
Write-BackupSummary
$backupRoot = Get-BackupRoot
if ($backupRoot) {
    # Leave a breadcrumb so setup.ps1 can surface it in the final summary.
    $marker = Join-Path $env:USERPROFILE ".config\omacheese\last-backup.txt"
    Ensure-Dir (Split-Path -Parent $marker)
    Set-Content -LiteralPath $marker -Value $backupRoot -Encoding utf8
}

# --- retire the old %TEMP% install ------------------------------------------
# Installs made before the one-liner moved to %LOCALAPPDATA% unpacked the repo
# into %TEMP%\omacheese-install and linked everything at it. Everything above
# has just been repointed at $Repo, so that copy is now only a trap: it is what
# Windows clears when it sweeps %TEMP%, and finding it later makes it look like
# there are two installs. Safe to remove only now, and only from elsewhere.
$legacyRoot = ""
if ($tempRoot) { $legacyRoot = Join-Path $tempRoot "omacheese-install" }
if ($legacyRoot -and (Test-Path -LiteralPath $legacyRoot) -and
    -not [IO.Path]::GetFullPath($Repo).StartsWith([IO.Path]::GetFullPath($legacyRoot), [StringComparison]::OrdinalIgnoreCase)) {
    try {
        Remove-Item -LiteralPath $legacyRoot -Recurse -Force -ErrorAction Stop
        Write-Host ""
        Write-Host "  removed the old %TEMP% install ($legacyRoot)" -ForegroundColor DarkGray
    } catch { }
}

Write-Host ""
Write-Host "  Review ~/.ssh/config.example before renaming it to config." -ForegroundColor Yellow
Write-Host "  Inside WSL: sudo cp ~/.config/wsl/wsl.conf /etc/wsl.conf && wsl --shutdown" -ForegroundColor Yellow

# Run the check instead of printing "Then: ./scripts/doctor.ps1". Left to
# setup.ps1 when this is one of its steps - it runs doctor once, last. Its own
# process, so doctor gets its own ErrorActionPreference rather than this one's.
if (-not $env:OMACHEESE_SETUP_RUN) {
    Write-Host ""
    & (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Repo "scripts\doctor.ps1")
}
