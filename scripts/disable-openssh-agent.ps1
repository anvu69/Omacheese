# Hand the SSH agent pipe to Bitwarden.
#
#   ./scripts/disable-openssh-agent.ps1        (needs admin)
#
# Bitwarden's SSH agent serves \\.\pipe\openssh-ssh-agent - the pipe Windows'
# own "OpenSSH Authentication Agent" service owns when it runs. With both,
# whichever started first wins, and it is usually the service: ssh then sees an
# empty agent and the keys in the vault might as well not exist. This used to be
# a line at the end of install-windows.ps1 telling you to go and change the
# service by hand.

$ErrorActionPreference = "Stop"

$elevated = (New-Object Security.Principal.WindowsPrincipal(
    [Security.Principal.WindowsIdentity]::GetCurrent())
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $elevated) {
    Write-Host "This needs to run as administrator." -ForegroundColor Red
    exit 1
}

$svc = Get-Service ssh-agent -ErrorAction SilentlyContinue
if (-not $svc) {
    Write-Host "  = OpenSSH Authentication Agent is not installed - nothing to hand over" -ForegroundColor DarkGray
    exit 0
}

if ($svc.Status -eq "Running") {
    Stop-Service ssh-agent -Force
    Write-Host "  + stopped OpenSSH Authentication Agent" -ForegroundColor Green
}
if ($svc.StartType -ne "Disabled") {
    Set-Service ssh-agent -StartupType Disabled
    Write-Host "  + OpenSSH Authentication Agent disabled (was $($svc.StartType))" -ForegroundColor Green
} else {
    Write-Host "  = OpenSSH Authentication Agent already disabled" -ForegroundColor DarkGray
}
exit 0
