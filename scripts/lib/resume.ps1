# Carrying a setup across a Windows restart.
#
# Enabling WSL needs Windows restarted before any distro can boot. That used to
# end the setup with "restart, then run wsl --install -d AlmaLinux-9 and then
# setup.ps1 -Modules localllm" - three things to remember across a reboot. Now
# the steps that could not run are written to a state file, a RunOnce entry
# starts setup.ps1 -Resume at the next sign-in, and it carries on with them.
#
# The Linux password, asked before the restart, is stored with DPAPI for the
# current user: only this user on this machine can decrypt it. The file is
# deleted as it is read, and RunOnce entries are removed by Windows as they run,
# so both fire once.
#
# ProtectedData directly, not ConvertTo/ConvertFrom-SecureString. Those live in
# Microsoft.PowerShell.Security, and Windows PowerShell started from a pwsh 7
# session inherits pwsh 7's module directories first in PSModulePath, loads the
# Core build of that module and fails: "The 'ConvertTo-SecureString' command was
# found in the module 'Microsoft.PowerShell.Security', but the module could not
# be loaded." Measured: fails with the inherited path, loads with the Windows
# PowerShell default. A .NET call has no module to get wrong.
#
# PowerShell 5.1 compatible. No StrictMode.

Add-Type -AssemblyName System.Security

function Protect-ForCurrentUser {
    param([string]$Text)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $enc = [System.Security.Cryptography.ProtectedData]::Protect($bytes, $null,
        [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
    return [Convert]::ToBase64String($enc)
}

function Unprotect-ForCurrentUser {
    param([string]$Blob)
    $dec = [System.Security.Cryptography.ProtectedData]::Unprotect([Convert]::FromBase64String($Blob), $null,
        [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
    return [System.Text.Encoding]::UTF8.GetString($dec)
}

function Get-SetupResumeFile {
    return (Join-Path $env:LOCALAPPDATA "Omacheese\resume.json")
}

function Save-SetupResume {
    param(
        [Parameter(Mandatory = $true)][string[]]$Modules,
        [Parameter(Mandatory = $true)][string]$SetupScript,
        [string]$DistroAgents = "",
        [string[]]$OpenApps = @(),
        [string]$LinuxPassword,
        [string]$File = (Get-SetupResumeFile),
        [string]$RunOnceName = "OmacheeseSetup"
    )

    $blob = ""
    if ($LinuxPassword) {
        $blob = Protect-ForCurrentUser -Text $LinuxPassword
    }
    $state = [ordered]@{
        Modules       = @($Modules)
        DistroAgents  = $DistroAgents
        OpenApps      = @($OpenApps)
        LinuxPassword = $blob
        Written       = (Get-Date).ToString("s")
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $File) | Out-Null
    $state | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $File -Encoding UTF8

    # Windows PowerShell, whatever host is running now: it is the one that is
    # certainly there at sign-in. -NoExit keeps the window on the summary
    # instead of closing it the moment the run ends.
    $winPs = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    $cmd = '"{0}" -NoProfile -NoExit -ExecutionPolicy Bypass -File "{1}" -Resume' -f $winPs, $SetupScript
    $key = "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce"
    if (-not (Test-Path -LiteralPath $key)) { New-Item -Path $key -Force | Out-Null }
    Set-ItemProperty -Path $key -Name $RunOnceName -Value $cmd
    return $cmd
}

# The saved state with the password decrypted, or $null when there is none.
# Deletes the file either way: a state that cannot be read must not be retried
# on every sign-in.
function Read-SetupResume {
    param([string]$File = (Get-SetupResumeFile))
    if (-not (Test-Path -LiteralPath $File)) { return $null }
    try {
        $saved = Get-Content -LiteralPath $File -Raw | ConvertFrom-Json
    } finally {
        Remove-Item -LiteralPath $File -Force -ErrorAction SilentlyContinue
    }

    $password = $null
    if ($saved.LinuxPassword) {
        try { $password = Unprotect-ForCurrentUser -Blob $saved.LinuxPassword } catch { $password = $null }
    }

    return [pscustomobject]@{
        Modules       = @($saved.Modules)
        DistroAgents  = "" + $saved.DistroAgents
        OpenApps      = @($saved.OpenApps)
        LinuxPassword = $password
    }
}
