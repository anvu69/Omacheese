# Provision the WSL distro: a real user, the dev environment, the configs.
#
#   ./scripts/install-distro.ps1
#   ./scripts/install-distro.ps1 -User alice -Agents claude,codex
#
# Everything the setup used to end with as a list of commands to type:
#
#   wsl --install -d AlmaLinux-9
#   wsl -d AlmaLinux-9 --cd <repo> -- bash scripts/install-almalinux.sh
#   sudo cp ~/.config/wsl/wsl.conf /etc/wsl.conf
#   wsl --shutdown
#
# plus the part nobody wrote down: install-wsl.ps1 installs the distro with
# --no-launch, so no Linux user is ever created and every WSL shell ran as root.
#
# The password comes from $env:OMACHEESE_LINUX_PASSWORD when setup.ps1 runs this
# as a step - it asks before the plan, where there is a console. Run on its own
# with a console, this script asks. With neither, the account is created with no
# usable password, and the next setup run notices and asks for one.
#
# Unelevated on purpose: WSL distros are registered per user, and nothing here
# needs Windows admin. Root inside the distro comes from `wsl -u root`.

[CmdletBinding()]
param(
    [string]$Distro = "AlmaLinux-9",
    [string]$User,
    [string[]]$Agents
)

$ErrorActionPreference = "Continue"   # native commands: every exit code is checked by hand

# powershell.exe -File binds "a,b" to a [string[]] as one element.
if ($Agents) { $Agents = @($Agents -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }

$RepoRoot = Split-Path -Parent $PSScriptRoot

# Invoke-BoundedCommand. detect.ps1 turns StrictMode on for whoever dot-sources
# it; this script is not written to it.
. (Join-Path $RepoRoot "scripts\lib\detect.ps1")
Set-StrictMode -Off
. (Join-Path $RepoRoot "scripts\lib\distro.ps1")

function Say  { param($m) Write-Host "`n==> $m" -ForegroundColor Cyan }
function Good { param($m) Write-Host "    ok   $m" -ForegroundColor Green }
function Bad  { param($m) Write-Host "    FAIL $m" -ForegroundColor Red }

$work = Join-Path $env:TEMP "omacheese-distro"
New-Item -ItemType Directory -Force -Path $work | Out-Null

# A bash script written to a file and run with --cd, rather than `bash -c
# '<text>'`: wsl.exe re-joins its arguments before handing them to the shell,
# and the quoting inside does not survive it. --cd takes a Windows path, so a
# user name with a space in it is not a problem either.
function Invoke-DistroScript {
    param([string]$Name, [string]$Body, [string[]]$Arguments = @(), [switch]$AsRoot)
    $path = Join-Path $work $Name
    [System.IO.File]::WriteAllText($path, ($Body -replace "`r`n", "`n"), (New-Object System.Text.UTF8Encoding($false)))
    $wslArgs = @("-d", $Distro)
    if ($AsRoot) { $wslArgs += @("-u", "root") }
    $wslArgs += @("--cd", $work, "--", "bash", $Name) + $Arguments
    # To the host, not the pipeline. Anything a function writes to the pipeline
    # is part of what it returns, so "created invoker" plus the exit code came
    # back as an array - and `(array) -ne 0` is truthy, which reported a user
    # that had just been created successfully as "could not create".
    & wsl.exe @wslArgs | Out-Host
    return $LASTEXITCODE
}

Write-Host "Distro setup" -ForegroundColor Green

# --- WSL itself --------------------------------------------------------------
$probe = Invoke-BoundedCommand -FilePath "wsl.exe" -ArgumentList @("--version") `
         -TimeoutMs 8000 -StdoutEncoding ([System.Text.Encoding]::Unicode)
if ($probe.ExitCode -ne 0) {
    Bad "WSL does not answer - the wsl step installs it, and may need a restart first."
    exit 1
}

# --- the distro --------------------------------------------------------------
if (-not (Test-DistroInstalled -Distro $Distro)) {
    Say "Installing $Distro"
    & wsl.exe --install -d $Distro --no-launch
    if (-not (Test-DistroInstalled -Distro $Distro)) {
        Bad "wsl --install -d $Distro did not register the distro (exit $LASTEXITCODE)"
        exit 1
    }
}
Good "$Distro installed"

# --- the user ----------------------------------------------------------------
if (-not $User) { $User = ConvertTo-LinuxUserName -Name $env:USERNAME }
if ($User -notmatch '^[a-z_][a-z0-9_-]{0,31}$') {
    Bad "'$User' is not a valid Linux user name"
    exit 1
}

$state = Get-DistroUserState -Distro $Distro -User $User
Say "Linux user '$User' ($state)"

$password = $env:OMACHEESE_LINUX_PASSWORD
Remove-Item Env:OMACHEESE_LINUX_PASSWORD -ErrorAction SilentlyContinue

if (-not $password -and $state -ne "ready") {
    $interactive = ($Host.Name -eq "ConsoleHost")
    try { $interactive = $interactive -and -not [Console]::IsInputRedirected } catch { }
    if ($interactive) { $password = Read-LinuxPassword -User $User }
}

# useradd, wheel, and a sudoers drop-in for the length of this run only.
# install-almalinux.sh runs as the user and calls sudo throughout; with no
# console to type a password into, a real sudo prompt would simply fail. The
# drop-in is removed in the finally below whatever happens.
$prep = @'
set -e
u="$1"
if id -u "$u" >/dev/null 2>&1; then
  usermod -aG wheel "$u"
else
  useradd -m -G wheel -s /bin/bash "$u"
  echo "    created $u"
fi
f=/etc/sudoers.d/90-omacheese-setup
printf '%s ALL=(ALL) NOPASSWD: ALL\n' "$u" > "$f"
chmod 0440 "$f"
if command -v visudo >/dev/null 2>&1; then visudo -cf "$f" >/dev/null; fi
'@

$exitCode = 0
try {
    if ((Invoke-DistroScript -Name "prep-user.sh" -Body $prep -Arguments @($User) -AsRoot) -ne 0) {
        Bad "could not create or update $User"
        exit 1
    }

    if ($password) {
        if (Set-DistroPassword -Distro $Distro -User $User -Password $password) { Good "password set" }
        else { Bad "chpasswd failed - the account has no usable password yet" }
    } elseif ($state -ne "ready") {
        Write-Host "    no password given - the next setup run will ask for one" -ForegroundColor Yellow
    }
    $password = $null

    # --- /etc/wsl.conf -------------------------------------------------------
    # The repo's wsl.conf with the default user filled in. Without [user]
    # default= every `wsl` still opens as root, whatever users exist.
    Say "Writing /etc/wsl.conf (default user $User)"
    $conf = Get-Content -LiteralPath (Join-Path $RepoRoot "configs\wsl\wsl.conf") -Raw
    $conf = Set-WslConfDefaultUser -Conf $conf -User $User
    [System.IO.File]::WriteAllText((Join-Path $work "wsl.conf"), ($conf -replace "`r`n", "`n"),
        (New-Object System.Text.UTF8Encoding($false)))
    $installConf = @'
set -e
if [ -f /etc/wsl.conf ] && ! cmp -s /etc/wsl.conf wsl.conf; then
  cp /etc/wsl.conf "/etc/wsl.conf.$(date +%Y%m%d-%H%M%S).bak"
fi
install -m 0644 wsl.conf /etc/wsl.conf
'@
    if ((Invoke-DistroScript -Name "install-conf.sh" -Body $installConf -AsRoot) -ne 0) {
        Bad "could not write /etc/wsl.conf"
        exit 1
    }

    # wsl.conf is read when the distro boots. --terminate, not --shutdown: it
    # restarts this distro only, and leaves any other one - and the WSL VM with
    # its running containers - alone.
    & wsl.exe --terminate $Distro | Out-Null
    $who = Invoke-BoundedCommand -FilePath "wsl.exe" -ArgumentList @("-d", $Distro, "--", "id", "-un") -TimeoutMs 60000
    $who = ("" + $who.Output).Trim()
    if ($who -ne $User) {
        Bad "after restarting $Distro the default user is '$who', not '$User'"
        exit 1
    }
    Good "$Distro now opens as $User"

    # --- the dev environment -------------------------------------------------
    Say "Installing the dev environment inside $Distro (dnf, zsh, tools, configs)"
    & wsl.exe -d $Distro --cd $RepoRoot -- bash scripts/install-almalinux.sh
    if ($LASTEXITCODE -ne 0) {
        Bad "install-almalinux.sh exited $LASTEXITCODE"
        $exitCode = 1
    } else {
        Good "dev environment installed"
    }

    # Git identity, copied from the Windows side when it has one - the WSL
    # gitconfig ships without one on purpose, so a commit from WSL otherwise
    # fails with "Please tell me who you are".
    $gitName  = (& git config --global user.name  2>$null)
    $gitEmail = (& git config --global user.email 2>$null)
    if ($gitName -and $gitEmail) {
        $setGit = 'git config --global user.name "$1" && git config --global user.email "$2"'
        if ((Invoke-DistroScript -Name "git-identity.sh" -Body $setGit -Arguments @($gitName, $gitEmail)) -eq 0) {
            Good "git identity: $gitName <$gitEmail>"
        }
    }

    # --- coding agents -------------------------------------------------------
    if ($Agents) {
        Say "Installing agents inside $Distro : $($Agents -join ', ')"
        & wsl.exe -d $Distro --cd $RepoRoot -- bash scripts/install-agents-wsl.sh @Agents
        if ($LASTEXITCODE -ne 0) { Bad "some agents failed (exit $LASTEXITCODE)"; $exitCode = 1 }
    }

    # --- SSH keys from Bitwarden ---------------------------------------------
    # configs/wsl/ssh-agent-bridge.sh relays the Windows agent pipe into WSL
    # through npiperelay.exe. Without it WSL simply has no keys, and nothing
    # says why until an `ssh` fails.
    Say "npiperelay (Bitwarden SSH agent inside WSL)"
    $relayId = Get-WslPackageIds -RepoRoot $RepoRoot
    foreach ($id in $relayId) {
        & winget install --id $id -e --accept-source-agreements --accept-package-agreements --disable-interactivity | Out-Host
        # -1978335189: already installed.
        if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq -1978335189) { Good $id }
        else { Bad "$id (winget exit $LASTEXITCODE)"; $exitCode = 1 }
    }
} finally {
    $password = $null
    $cleanup = 'rm -f /etc/sudoers.d/90-omacheese-setup'
    [void](Invoke-DistroScript -Name "cleanup.sh" -Body $cleanup -AsRoot)
}

# Run the check instead of telling you to. Left to setup.ps1 when this is one of
# its steps; its own process, so it keeps its own preferences.
if (-not $env:OMACHEESE_SETUP_RUN) {
    Write-Host ""
    & (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File (Join-Path $RepoRoot "scripts\doctor.ps1")
}

exit $exitCode
