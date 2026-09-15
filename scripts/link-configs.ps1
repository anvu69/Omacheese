# Install every config from the repo into the places the tools read.
#
#   ./scripts/link-configs.ps1            symlink (edits in the repo go live)
#   ./scripts/link-configs.ps1 -Copy      plain copies instead
#   ./scripts/link-configs.ps1 -NoAutostart
#
# Anything already present is backed up first, into ONE folder per run:
#   %USERPROFILE%\.config\windows11-dev-poweruser\backups\<timestamp>\
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

$Install = if ($Copy) { "Install-ConfigFile" } else { "Install-ConfigLink" }

function Put {
    param([string]$Source, [string]$Destination)
    # The installers return a bool for callers that care; swallow it here so
    # the transcript stays readable.
    & $Install -Source (Join-Path $Repo $Source) -Destination $Destination | Out-Null
}

$cfg       = Join-Path $env:USERPROFILE ".config"
$omarchy   = Join-Path $cfg "omarchy\bin"

Write-Host "Installing configs ($(if ($Copy) { 'copy' } else { 'symlink' }) mode)" -ForegroundColor Green

foreach ($d in @(
    (Join-Path $env:APPDATA "alacritty"),
    (Join-Path $env:USERPROFILE ".ssh"),
    $cfg,
    (Join-Path $cfg "komorebi"),
    (Join-Path $cfg "yasb"),
    (Join-Path $cfg "oh-my-posh"),
    (Join-Path $cfg "wsl"),
    $omarchy
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

Write-Host "`n[ssh]" -ForegroundColor Magenta
# Example only - never overwrite a real ~/.ssh/config.
Install-ConfigFile -Source (Join-Path $Repo "configs\ssh\config.example") `
                   -Destination (Join-Path $env:USERPROFILE ".ssh\config.example") | Out-Null

Write-Host "`n[omarchy helpers]" -ForegroundColor Magenta
foreach ($s in Get-ChildItem (Join-Path $Repo "scripts\omarchy") | Where-Object { $_.Extension -in @(".ps1", ".cmd") }) {
    & $Install -Source $s.FullName -Destination (Join-Path $omarchy $s.Name) | Out-Null
}
& $Install -Source (Join-Path $Repo "scripts\start-desktop.ps1") `
           -Destination (Join-Path $omarchy "start-desktop.ps1") | Out-Null

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
    # No ?. here: this script has to parse under Windows PowerShell 5.1, which
    # is all a freshly installed Windows 11 has until winget brings pwsh 7.
    $pwshCmd = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    if ($pwshCmd) { $target = $pwshCmd.Source } else { $target = (Get-Command powershell.exe).Source }

    try {
        $shell = New-Object -ComObject WScript.Shell
        $sc = $shell.CreateShortcut($lnk)
        $sc.TargetPath   = $target
        $sc.Arguments    = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$(Join-Path $omarchy 'start-desktop.ps1')`""
        $sc.WorkingDirectory = $omarchy
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
    $marker = Join-Path $env:USERPROFILE ".config\windows11-dev-poweruser\last-backup.txt"
    Ensure-Dir (Split-Path -Parent $marker)
    Set-Content -LiteralPath $marker -Value $backupRoot -Encoding utf8
}

Write-Host ""
Write-Host "  Review ~/.ssh/config.example before renaming it to config." -ForegroundColor Yellow
Write-Host "  Inside WSL: sudo cp ~/.config/wsl/wsl.conf /etc/wsl.conf && wsl --shutdown" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Then: ./scripts/doctor.ps1" -ForegroundColor Cyan
