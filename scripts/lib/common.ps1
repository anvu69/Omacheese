# Shared helpers for install-windows.ps1 and bootstrap-windows.ps1.
# Dot-source this file; it defines functions only and has no side effects.

function Ensure-Dir {
  param([Parameter(Mandatory)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
  }
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
      if (-not $Force -and (Test-WingetInstalled -Id $pkg.id)) {
        Write-Host ("  = {0,-34} already installed" -f $pkg.id) -ForegroundColor DarkGray
        $skipped += $pkg.id
        continue
      }

      Write-Host ("  + {0,-34} {1}" -f $pkg.id, $pkg.note) -ForegroundColor Cyan
      winget install --id $pkg.id -e `
        --accept-source-agreements --accept-package-agreements `
        --disable-interactivity --silent
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

function Install-PowerShellModule {
  param([Parameter(Mandatory)][object]$Manifest)

  Write-Host ""
  Write-Host "[modules] PowerShell modules" -ForegroundColor Magenta

  foreach ($m in $Manifest.powershellModules) {
    if (Get-Module -ListAvailable -Name $m.name) {
      Write-Host ("  = {0,-24} already installed" -f $m.name) -ForegroundColor DarkGray
      continue
    }
    Write-Host ("  + {0,-24} {1}" -f $m.name, $m.note) -ForegroundColor Cyan
    try {
      Install-Module $m.name -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
    } catch {
      Write-Warning "    $($m.name) failed: $($_.Exception.Message)"
    }
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
      $stamp  = Get-Date -Format "yyyyMMdd-HHmmss"
      $backup = "$Destination.$stamp.bak"
      Copy-Item -LiteralPath $Destination -Destination $backup -Force
      Write-Host ("  ~ backed up -> {0}" -f (Split-Path -Leaf $backup)) -ForegroundColor DarkYellow
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
    $stamp  = Get-Date -Format "yyyyMMdd-HHmmss"
    $backup = "$Destination.$stamp.bak"
    Move-Item -LiteralPath $Destination -Destination $backup -Force
    Write-Host ("  ~ backed up -> {0}" -f (Split-Path -Leaf $backup)) -ForegroundColor DarkYellow
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
