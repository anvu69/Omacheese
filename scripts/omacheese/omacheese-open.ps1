# Launch a GUI app by name, resolving it the way Windows itself does.
#
#   omacheese-open.ps1 alacritty
#   omacheese-open.ps1 brave --incognito
#   omacheese-open.ps1 alacritty -e wsl.exe -d AlmaLinux-9 -- nvim
#
# WHY THIS EXISTS
#
# whkdrc used to launch apps with `start "" alacritty`, which is a ShellExecute
# lookup: PATH, then the App Paths registry. Measured on a working install, that
# finds almost nothing, because GUI installers register neither:
#
#   start "" brave          fails      start "" brave.exe       launches
#   start "" alacritty      fails      start "" alacritty.exe   fails
#
# brave happens to register in App Paths, so the .exe suffix rescues it.
# Alacritty registers nowhere, so nothing rescues it, and SUPER+Enter opened an
# empty console window titled "alacritty" instead of a terminal. Sixteen
# bindings were in that state.
#
# So resolve the way a person would, cheapest first: PATH, App Paths, the start
# menu shortcut, then a couple of known install directories.
#
# Resolved paths are cached in ~/.config/omacheese/app-paths.txt so the .cmd
# wrapper can launch straight from the cache without starting PowerShell at all.
# That matters: this sits on SUPER+Enter.

[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [string]$App,

    [Parameter(ValueFromRemainingArguments)]
    [string[]]$Arguments
)

$ErrorActionPreference = "Stop"

$ConfigHome = Join-Path $env:USERPROFILE ".config\omacheese"
$CacheFile  = Join-Path $ConfigHome "app-paths.txt"

function Get-StartMenuTarget {
    param([string]$Name)
    $needle = ($Name -replace "[^a-zA-Z0-9]", "")
    if (-not $needle) { return $null }
    $lnks = @()
    foreach ($r in @([Environment]::GetFolderPath("Programs"),
                     [Environment]::GetFolderPath("CommonPrograms"))) {
        if ($r -and (Test-Path -LiteralPath $r)) {
            $lnks += Get-ChildItem $r -Filter *.lnk -Recurse -ErrorAction SilentlyContinue
        }
    }
    # Shortest matching name wins: "Brave" beats "Brave (Safe Mode)", and it
    # picks dbeaver.exe over the dbeaver-cli.exe a directory scan turns up.
    $hit = $lnks |
        Where-Object { ($_.BaseName -replace "[^a-zA-Z0-9]", "") -like "*$needle*" } |
        Sort-Object { $_.BaseName.Length } |
        Select-Object -First 1
    if (-not $hit) { return $null }
    try {
        $sh = New-Object -ComObject WScript.Shell
        $t = $sh.CreateShortcut($hit.FullName).TargetPath
        if ($t -and (Test-Path -LiteralPath $t)) { return $t }
    } catch { }
    return $null
}

function Resolve-App {
    param([string]$Name)

    $c = Get-Command $Name -ErrorAction SilentlyContinue
    if ($c -and $c.Source -and (Test-Path -LiteralPath $c.Source)) { return $c.Source }

    foreach ($hive in @("HKLM:", "HKCU:")) {
        $k = "$hive\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\$Name.exe"
        if (Test-Path -LiteralPath $k) {
            $v = (Get-ItemProperty -LiteralPath $k -ErrorAction SilentlyContinue)."(default)"
            if ($v) {
                $v = $v.Trim('"')
                if (Test-Path -LiteralPath $v) { return $v }
            }
        }
    }

    $sm = Get-StartMenuTarget $Name
    if ($sm) { return $sm }

    foreach ($f in @(
        "%ProgramFiles%\$Name\$Name.exe",
        "%ProgramFiles(x86)%\$Name\$Name.exe",
        "%LOCALAPPDATA%\Programs\$Name\$Name.exe"
    )) {
        $expanded = [Environment]::ExpandEnvironmentVariables($f)
        if (Test-Path -LiteralPath $expanded) { return $expanded }
    }
    return $null
}

$path = Resolve-App $App

if (-not $path) {
    # A hotkey that silently does nothing is worse than one that complains.
    Add-Type -AssemblyName PresentationFramework -ErrorAction SilentlyContinue
    try {
        [void][System.Windows.MessageBox]::Show(
            "Could not find $App.`n`nLooked on PATH, in the App Paths registry, in the Start menu, and in the usual install folders.",
            "omacheese", [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Warning)
    } catch {
        Write-Host "Could not find $App." -ForegroundColor Red
    }
    exit 1
}

try {
    if (-not (Test-Path -LiteralPath $ConfigHome)) {
        New-Item -ItemType Directory -Path $ConfigHome -Force | Out-Null
    }
    $existing = @()
    if (Test-Path -LiteralPath $CacheFile) {
        $existing = @(Get-Content -LiteralPath $CacheFile | Where-Object { $_ -notmatch "^$([regex]::Escape($App))\|" })
    }
    ($existing + "$App|$path") | Set-Content -LiteralPath $CacheFile -Encoding UTF8
} catch { }

if ($Arguments -and $Arguments.Count) {
    Start-Process -FilePath $path -ArgumentList $Arguments
} else {
    Start-Process -FilePath $path
}
