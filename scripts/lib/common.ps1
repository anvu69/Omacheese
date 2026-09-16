# Shared helpers for the installer scripts.
# Dot-source this file; it defines functions only and has no side effects.
#
# Must stay parseable by Windows PowerShell 5.1 - see scripts/lib/tui.ps1.

function Ensure-Dir {
  param([Parameter(Mandatory)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
  }
}

# =============================================================================
# Backups
# =============================================================================
# Every file this repo would overwrite is copied somewhere first. The previous
# version scattered "<file>.<timestamp>.bak" next to each original, which is
# useless on a machine that already had configs: you end up hunting through
# five directories to undo one run.
#
# Instead there is ONE backup root per run:
#
#   %USERPROFILE%\.config\windows11-dev-poweruser\backups\<timestamp>\
#       C\Users\you\.config\whkdrc
#       C\Users\you\Documents\PowerShell\Microsoft.PowerShell_profile.ps1
#       manifest.tsv
#
# The tree mirrors the original paths, so what a file was is obvious from
# where it sits. manifest.tsv maps backup -> original for restore-backup.ps1.

$script:BackupRoot = $null

function Initialize-BackupRoot {
  param([string]$Root)

  if ($script:BackupRoot) { return $script:BackupRoot }

  if (-not $Root) {
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $Root  = Join-Path $env:USERPROFILE ".config\windows11-dev-poweruser\backups\$stamp"
  }
  Ensure-Dir $Root
  $script:BackupRoot = $Root

  $manifest = Join-Path $Root "manifest.tsv"
  if (-not (Test-Path -LiteralPath $manifest)) {
    Set-Content -LiteralPath $manifest -Encoding utf8 `
      -Value "# backup_relative_path`toriginal_path`ttaken_at"
  }
  return $script:BackupRoot
}

function Get-BackupRoot { return $script:BackupRoot }

# Returns the backup path, or $null when there was nothing to back up.
function Backup-ExistingItem {
  param([Parameter(Mandatory)][string]$Path)

  if (-not (Test-Path -LiteralPath $Path)) { return $null }

  $root = Initialize-BackupRoot

  # C:\Users\you\.config\whkdrc  ->  <root>\C\Users\you\.config\whkdrc
  $full = (Resolve-Path -LiteralPath $Path).Path
  $rel  = $full -replace '^([A-Za-z]):\\', '$1\'
  $rel  = $rel -replace '^\\\\', 'UNC\'
  $dest = Join-Path $root $rel

  Ensure-Dir (Split-Path -Parent $dest)

  # A symlink we created on an earlier run is not worth preserving - copy what
  # it points at only if it is a real file.
  $item = Get-Item -LiteralPath $full -Force
  if ($item.LinkType -eq "SymbolicLink") {
    Add-Content -LiteralPath (Join-Path $root "manifest.tsv") `
      -Value ("{0}`t{1}`t{2}" -f "(symlink, not copied)", $full, (Get-Date -Format "s"))
    return $null
  }

  Copy-Item -LiteralPath $full -Destination $dest -Force -Recurse
  Add-Content -LiteralPath (Join-Path $root "manifest.tsv") `
    -Value ("{0}`t{1}`t{2}" -f $rel, $full, (Get-Date -Format "s"))

  return $dest
}

function Write-BackupSummary {
  if (-not $script:BackupRoot) { return }

  $manifest = Join-Path $script:BackupRoot "manifest.tsv"
  $count = 0
  if (Test-Path -LiteralPath $manifest) {
    $count = @(Get-Content -LiteralPath $manifest | Where-Object { $_ -notmatch '^#' }).Count
  }
  if ($count -eq 0) { return }

  Write-Host ""
  Write-Host ("  {0} existing file(s) were backed up to:" -f $count) -ForegroundColor Yellow
  Write-Host ("  $script:BackupRoot") -ForegroundColor Cyan
  Write-Host ("  Restore with: ./scripts/restore-backup.ps1 -From `"$script:BackupRoot`"") -ForegroundColor DarkGray
}

function Test-IsElevated {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-WingetInstalled {
  param([Parameter(Mandatory)][string]$Id)
  # winget list exits non-zero when nothing matches, so rely on the exit code
  # rather than parsing localized output.
  winget list --id $Id -e --disable-interactivity --accept-source-agreements 1>$null 2>$null
  return ($LASTEXITCODE -eq 0)
}

# Installs every package in the manifest. Never aborts the run on a single
# failure: winget is a native command, so $ErrorActionPreference does not apply
# to it, and a package that is already installed or temporarily unavailable
# must not take the rest of the setup down with it.
function Install-WingetManifest {
  param(
    [Parameter(Mandatory)][object]$Manifest,
    [string[]]$Groups,
    [switch]$Force
  )

  if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    throw "winget not found. Install 'App Installer' from the Microsoft Store, then re-run."
  }

  $names = $Manifest.groups.PSObject.Properties.Name
  if ($Groups) { $names = $names | Where-Object { $Groups -contains $_ } }

  $installed = @(); $skipped = @(); $failed = @()

  foreach ($groupName in $names) {
    $group = $Manifest.groups.$groupName
    Write-Host ""
    Write-Host "[$groupName] $($group.description)" -ForegroundColor Magenta

    foreach ($pkg in $group.packages) {
      # A package can name the architecture it is for. Without this the VC++
      # runtime would install the x64 build on an ARM64 machine: a download
      # that succeeds and leaves the machine without the runtime it needs.
      if ($pkg.PSObject.Properties.Name -contains "arch" -and $pkg.arch) {
        $here = $env:PROCESSOR_ARCHITECTURE
        if ($env:PROCESSOR_ARCHITEW6432) { $here = $env:PROCESSOR_ARCHITEW6432 }
        $want = switch ($pkg.arch) { "x64" { "AMD64" } "arm64" { "ARM64" } "x86" { "X86" } default { $pkg.arch } }
        if ($here -ne $want) {
          Write-Host ("  = {0,-34} skipped ({1} machine)" -f $pkg.id, $here) -ForegroundColor DarkGray
          $skipped += $pkg.id
          continue
        }
      }
      if (-not $Force -and (Test-WingetInstalled -Id $pkg.id)) {
        Write-Host ("  = {0,-34} already installed" -f $pkg.id) -ForegroundColor DarkGray
        $skipped += $pkg.id
        continue
      }

      Write-Host ("  + {0,-34} {1}" -f $pkg.id, $pkg.note) -ForegroundColor Cyan

      # A package can name its own source. Everything here comes from the
      # community repo except Raycast, which ships only as a Store package -
      # msstore ids are opaque numbers, so the note is what identifies it.
      $wingetArgs = @("install", "--id", $pkg.id, "-e",
                      "--accept-source-agreements", "--accept-package-agreements",
                      "--disable-interactivity", "--silent")
      if ($pkg.PSObject.Properties.Name -contains "source" -and $pkg.source) {
        $wingetArgs += @("--source", $pkg.source)
      }
      winget @wingetArgs
      $code = $LASTEXITCODE

      # 0 = ok. -1978335189 (0x8A15002B) = no applicable upgrade, i.e. current.
      if ($code -eq 0 -or $code -eq -1978335189) {
        $installed += $pkg.id
      } else {
        Write-Warning "    $($pkg.id) failed (exit $code)"
        $failed += $pkg.id
      }
    }
  }

  Write-Host ""
  Write-Host "Packages: $($installed.Count) installed/current, $($skipped.Count) already present, $($failed.Count) failed." -ForegroundColor Green
  if ($failed.Count) {
    Write-Host "Failed:" -ForegroundColor Yellow
    $failed | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
    Write-Host "Re-run the script to retry only these." -ForegroundColor Yellow
  }
  return [pscustomobject]@{ Installed = $installed; Skipped = $skipped; Failed = $failed }
}

# Installs the profile's modules INTO POWERSHELL 7, whatever host we are in.
#
# This has to shell out rather than just call Install-Module, because the two
# PowerShells do not share a module directory:
#
#   Windows PowerShell 5.1 -> Documents\WindowsPowerShell\Modules
#   PowerShell 7           -> Documents\PowerShell\Modules
#
# The profile this repo ships is PS7-only, so modules installed from a 5.1
# host land somewhere PS7 never looks and the profile silently degrades:
# no prediction colours, no Ctrl+T, no git prompt.
#
# 5.1 also needs two things PS7 does not: TLS 1.2 (PSGallery dropped 1.0/1.1)
# and the NuGet provider, whose bootstrap is an interactive prompt that would
# hang a non-interactive installer.
function Install-PowerShellModule {
  param([Parameter(Mandatory)][object]$Manifest)

  Write-Host ""
  Write-Host "[modules] PowerShell 7 modules" -ForegroundColor Magenta

  # winget may have installed pwsh moments ago, in which case this process
  # still has the old PATH.
  $env:PATH = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
              [Environment]::GetEnvironmentVariable("Path", "User")

  $pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue
  if (-not $pwsh) {
    Write-Host "  - PowerShell 7 not installed yet; skipping." -ForegroundColor Yellow
    Write-Host "    Install the 'core' group first, then re-run with -Groups core." -ForegroundColor DarkGray
    return
  }

  $names = @($Manifest.powershellModules | ForEach-Object { $_.name })
  $notes = @{}
  foreach ($m in $Manifest.powershellModules) { $notes[$m.name] = $m.note }

  foreach ($name in $names) {
    Write-Host ("  . {0,-24} {1}" -f $name, $notes[$name]) -ForegroundColor DarkGray
  }

  $script = @'
param([string]$Names)
# Split into a NEW variable. Assigning the array back to $Names would hit the
# [string] type constraint on the parameter, and PowerShell coerces an array
# to string by joining with SPACES - so all five module names became one.
$list = @($Names -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
if (-not (Get-PackageProvider -ListAvailable -Name NuGet -ErrorAction SilentlyContinue)) {
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser | Out-Null
}
foreach ($n in $list) {
    if (Get-Module -ListAvailable -Name $n) { "= $n"; continue }
    try {
        Install-Module $n -Scope CurrentUser -Force -AllowClobber -Repository PSGallery -ErrorAction Stop
        "+ $n"
    } catch {
        "! $n : $($_.Exception.Message)"
    }
}
'@

  $tmp = Join-Path $env:TEMP "w11-install-modules.ps1"
  [System.IO.File]::WriteAllText($tmp, $script, (New-Object System.Text.UTF8Encoding($false)))

  # Join into a local first. Passing the expression inline let the array reach
  # the child as separate tokens, which -File then flattened with spaces, and
  # the child tried to install one module called "A B C D E".
  $nameArg = [string]::Join(",", $names)
  $out = & $pwsh.Source -NoProfile -ExecutionPolicy Bypass -File $tmp -Names $nameArg 2>&1
  foreach ($line in $out) {
    $t = [string]$line
    if     ($t.StartsWith("+ ")) { Write-Host ("  + {0}" -f $t.Substring(2)) -ForegroundColor Green }
    elseif ($t.StartsWith("= ")) { Write-Host ("  = {0} already installed" -f $t.Substring(2)) -ForegroundColor DarkGray }
    elseif ($t.StartsWith("! ")) { Write-Host ("  ! {0}" -f $t.Substring(2)) -ForegroundColor Yellow }
  }
}

# Copies a file to $Destination, keeping one timestamped backup of whatever was
# there before. Returns $true when something was written.
function Install-ConfigFile {
  param(
    [Parameter(Mandatory)][string]$Source,
    [Parameter(Mandatory)][string]$Destination,
    [switch]$NoBackup
  )

  if (-not (Test-Path -LiteralPath $Source)) {
    Write-Warning "missing source: $Source"
    return $false
  }

  Ensure-Dir (Split-Path -Parent $Destination)

  if (Test-Path -LiteralPath $Destination) {
    $same = $false
    try {
      $same = (Get-FileHash -LiteralPath $Source).Hash -eq (Get-FileHash -LiteralPath $Destination).Hash
    } catch {
      # A locked or unreadable destination just means "not known to match",
      # so fall through and replace it (after taking the backup below).
      Write-Verbose "Could not hash $Destination : $($_.Exception.Message)"
    }
    if ($same) {
      Write-Host ("  = {0}" -f $Destination) -ForegroundColor DarkGray
      return $false
    }
    if (-not $NoBackup) {
      $backup = Backup-ExistingItem -Path $Destination
      if ($backup) { Write-Host ("  ~ backed up") -ForegroundColor DarkYellow }
    }
  }

  Copy-Item -LiteralPath $Source -Destination $Destination -Force
  Write-Host ("  + {0}" -f $Destination) -ForegroundColor Green
  return $true
}

# Symlinks $Destination -> $Source so edits in the repo take effect live.
# Falls back to a copy when the OS refuses (no Developer Mode and not elevated).
function Install-ConfigLink {
  param(
    [Parameter(Mandatory)][string]$Source,
    [Parameter(Mandatory)][string]$Destination
  )

  if (-not (Test-Path -LiteralPath $Source)) {
    Write-Warning "missing source: $Source"
    return $false
  }

  Ensure-Dir (Split-Path -Parent $Destination)
  $src = (Resolve-Path -LiteralPath $Source).Path

  $existing = Get-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue
  if ($existing) {
    if ($existing.LinkType -eq "SymbolicLink" -and $existing.Target -contains $src) {
      Write-Host ("  = {0} -> repo" -f $Destination) -ForegroundColor DarkGray
      return $true
    }
    $backup = Backup-ExistingItem -Path $Destination
    if ($backup) { Write-Host ("  ~ backed up") -ForegroundColor DarkYellow }
    Remove-Item -LiteralPath $Destination -Force -Recurse
  }

  try {
    New-Item -ItemType SymbolicLink -Path $Destination -Target $src -ErrorAction Stop | Out-Null
    Write-Host ("  @ {0} -> repo" -f $Destination) -ForegroundColor Green
    return $true
  } catch {
    Copy-Item -LiteralPath $src -Destination $Destination -Force
    Write-Host ("  + {0} (copied; symlink needs Developer Mode or admin)" -f $Destination) -ForegroundColor Yellow
    return $true
  }
}

function Set-UserEnvVar {
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$Value
  )
  $current = [Environment]::GetEnvironmentVariable($Name, "User")
  if ($current -ne $Value) {
    [Environment]::SetEnvironmentVariable($Name, $Value, "User")
    Write-Host ("  + {0}={1}" -f $Name, $Value) -ForegroundColor Green
  } else {
    Write-Host ("  = {0}={1}" -f $Name, $Value) -ForegroundColor DarkGray
  }
  Set-Item -Path "env:$Name" -Value $Value
}
