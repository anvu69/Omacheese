# Shared helpers for the Omarchy Raycast script commands.
#
# This file has no @raycast metadata on purpose, so Raycast skips it when it
# scans the directory - only files declaring a schemaVersion become commands.
#
# Every command dot-sources this:
#
#   . (Join-Path $PSScriptRoot "_omarchy-lib.ps1")

$ErrorActionPreference = "Stop"

$OmarchyConfig = Join-Path $env:USERPROFILE ".config"
$OmarchyBin    = Join-Path $OmarchyConfig "omarchy\bin"

# komorebic reads its config from here, and Raycast does not run a login shell,
# so the variable has to be set rather than inherited.
$env:KOMOREBI_CONFIG_HOME = Join-Path $OmarchyConfig "komorebi"

# Raycast launches commands from its own process, which inherits whatever PATH
# that had. Resolve binaries rather than trusting it - this is the same trap
# that made the yasb callbacks silently do nothing.
function Resolve-Bin {
    param([string]$Name, [string[]]$Fallbacks = @())
    $c = Get-Command $Name -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    foreach ($f in $Fallbacks) {
        $expanded = [Environment]::ExpandEnvironmentVariables($f)
        if (Test-Path -LiteralPath $expanded) { return $expanded }
    }
    return $null
}

function Get-Komorebic {
    $k = Resolve-Bin "komorebic" @(
        "%ProgramFiles%\komorebi\bin\komorebic.exe",
        "%LOCALAPPDATA%\Microsoft\WinGet\Links\komorebic.exe"
    )
    if (-not $k) { throw "komorebic not found - is komorebi installed?" }
    return $k
}

# In silent mode Raycast shows the last line of output as a HUD toast, so a
# one-line confirmation is the right amount of feedback.
function Invoke-Komorebic {
    param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
    $k = Get-Komorebic
    & $k @Arguments | Out-Null
}

function Get-Terminal {
    return Resolve-Bin "alacritty" @(
        "%ProgramFiles%\Alacritty\alacritty.exe",
        "%LOCALAPPDATA%\Programs\Alacritty\alacritty.exe"
    )
}

function Start-InTerminal {
    param([Parameter(Mandatory)][string[]]$Command)
    $term = Get-Terminal
    if ($term) {
        Start-Process -FilePath $term -ArgumentList (@("-e") + $Command)
    } else {
        Start-Process -FilePath $Command[0] -ArgumentList ($Command[1..($Command.Count - 1)])
    }
}

function Get-PowerShellExe {
    return Resolve-Bin "pwsh" @("%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe")
}

# Run one of the omarchy helpers without showing a console.
function Start-Helper {
    param([string]$Name, [string[]]$Arguments = @())
    $script = Join-Path $OmarchyBin $Name
    if (-not (Test-Path -LiteralPath $script)) { throw "Missing helper: $script" }
    Start-Process -FilePath (Get-PowerShellExe) -WindowStyle Hidden `
        -ArgumentList (@("-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $script) + $Arguments)
}

# Run an omarchy helper in a terminal, for the ones that print something.
function Start-HelperInTerminal {
    param([string]$Name, [string[]]$Arguments = @())
    $script = Join-Path $OmarchyBin $Name
    if (-not (Test-Path -LiteralPath $script)) { throw "Missing helper: $script" }
    Start-InTerminal (@((Get-PowerShellExe), "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $script) + $Arguments)
}
