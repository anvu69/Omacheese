# What both setup.ps1 and install-distro.ps1 need to know about the WSL distro.
#
# setup.ps1 has to ask for the Linux password before the plan - it is the only
# place with a console once steps start - and install-distro.ps1 has to act on
# it. The questions they share live here.
#
# PowerShell 5.1 compatible. Needs Invoke-BoundedCommand from detect.ps1.
# No StrictMode, like lib\debloat.ps1: callers go on to run code not written to it.

# Windows allows names Linux does not: spaces, capitals, non-ASCII. useradd
# wants [a-z_][a-z0-9_-]*, 32 characters at most.
function ConvertTo-LinuxUserName {
    param([string]$Name)
    $n = ("" + $Name).ToLowerInvariant() -replace '[^a-z0-9_-]', ''
    if ($n -notmatch '^[a-z_]') { $n = "u" + $n }
    if ($n.Length -gt 32) { $n = $n.Substring(0, 32) }
    if ($n -eq "u" -or -not $n) { $n = "dev" }
    return $n
}

function Test-DistroInstalled {
    param([string]$Distro)
    $r = Invoke-BoundedCommand -FilePath "wsl.exe" -ArgumentList @("-l", "-q") `
         -TimeoutMs 8000 -StdoutEncoding ([System.Text.Encoding]::Unicode)
    $names = @((("" + $r.Output) -replace "`0", "") -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    return ($names -contains $Distro)
}

# missing      the distro or the account does not exist yet
# no-password  the account exists but cannot authenticate - sudo will not work
# ready        the account has a password
function Get-DistroUserState {
    param([string]$Distro, [string]$User)
    if (-not (Test-DistroInstalled -Distro $Distro)) { return "missing" }
    $r = Invoke-BoundedCommand -FilePath "wsl.exe" `
         -ArgumentList @("-d", $Distro, "-u", "root", "--", "passwd", "-S", $User) -TimeoutMs 60000
    if ($r.TimedOut -or $r.ExitCode -ne 0) { return "missing" }
    # "invoker PS 2026-09-17 0 99999 7 -1 (Password set, SHA512 crypt.)"
    $f = @(("" + $r.Output).Trim() -split '\s+')
    if ($f.Count -ge 2 -and $f[1] -eq "PS") { return "ready" }
    return "no-password"
}

# Asked twice, hidden. $null for "none given" - an empty answer, or three
# mismatches - which the caller treats as "create the account without one".
function Read-LinuxPassword {
    param([string]$User)
    for ($try = 1; $try -le 3; $try++) {
        $a = Read-Host "  Linux password for $User (Enter to skip)" -AsSecureString
        $pa = ConvertFrom-SecureStringPlain $a
        if (-not $pa) { return $null }
        $b = Read-Host "  again" -AsSecureString
        if ($pa -ceq (ConvertFrom-SecureStringPlain $b)) { return $pa }
        Write-Host "  they did not match" -ForegroundColor Yellow
    }
    return $null
}

function ConvertFrom-SecureStringPlain {
    param([System.Security.SecureString]$Secure)
    if (-not $Secure -or $Secure.Length -eq 0) { return "" }
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

# Through chpasswd's STDIN, never its command line, where any process listing
# would show it. Written as raw UTF-8 bytes with a bare LF: piping a string to a
# native command from Windows PowerShell 5.1 re-encodes it with $OutputEncoding
# (ASCII) and ends it with CRLF - the password would silently become "secret\r".
function Set-DistroPassword {
    param([string]$Distro, [string]$User, [string]$Password)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "wsl.exe"
    $psi.Arguments = "-d $Distro -u root -- chpasswd"
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput  = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.CreateNoWindow = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $bytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes("${User}:${Password}`n")
    $p.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
    $p.StandardInput.Close()
    [void]$p.StandardOutput.ReadToEndAsync()
    [void]$p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit(60000)) { try { $p.Kill() } catch { }; return $false }
    return ($p.ExitCode -eq 0)
}

# The repo's wsl.conf ships "# default=youruser" under [user]. Fill it in; add
# the section if a future edit removes it.
function Set-WslConfDefaultUser {
    param([string]$Conf, [string]$User)
    $lines = New-Object System.Collections.Generic.List[string]
    $inUser = $false; $done = $false
    foreach ($l in ($Conf -split "`r?`n")) {
        if ($l -match '^\s*\[(.+)\]\s*$') { $inUser = ($Matches[1] -eq "user") }
        if ($inUser -and -not $done -and $l -match '^\s*#?\s*default\s*=') {
            $lines.Add("default=$User"); $done = $true; continue
        }
        $lines.Add($l)
    }
    if (-not $done) {
        while ($lines.Count -and -not $lines[$lines.Count - 1].Trim()) { $lines.RemoveAt($lines.Count - 1) }
        $lines.Add(""); $lines.Add("[user]"); $lines.Add("default=$User")
    }
    return (($lines -join "`n").TrimEnd() + "`n")
}

# The Windows packages the distro depends on, from the manifest's "wsl" group,
# so the ids are validated by doctor along with every other winget id.
function Get-WslPackageIds {
    param([string]$RepoRoot)
    $m = Get-Content -LiteralPath (Join-Path $RepoRoot "configs\winget\packages.json") -Raw | ConvertFrom-Json
    if (-not $m.groups.wsl) { return @() }
    return @($m.groups.wsl.packages | ForEach-Object { $_.id })
}
