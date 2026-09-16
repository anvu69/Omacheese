# Put back what an install run replaced.
#
#   ./scripts/restore-backup.ps1                 restore the most recent run
#   ./scripts/restore-backup.ps1 -List           show every backup run
#   ./scripts/restore-backup.ps1 -From <path>    restore a specific run
#   ./scripts/restore-backup.ps1 -WhatIf         show what would be restored
#
# Reads manifest.tsv, which link-configs.ps1 writes as it goes, so this puts
# every file back exactly where it came from.

[CmdletBinding()]
param(
    [string]$From,
    [switch]$List,
    [switch]$WhatIf,
    [switch]$Yes
)

$ErrorActionPreference = "Stop"

$BackupsDir = Join-Path $env:USERPROFILE ".config\omacheese\backups"

# The project was called windows11-dev-poweruser until it was renamed to
# Omacheese, and backups taken before then are still on disk under the old
# directory. They are the ones most worth restoring - they hold what the
# machine looked like before this repo first touched it - so both locations
# are searched and the combined list is sorted by timestamp.
$legacyDir = Join-Path $env:USERPROFILE ".config\windows11-dev-poweruser\backups"

$searched = @($BackupsDir, $legacyDir) | Where-Object { Test-Path -LiteralPath $_ }
if (-not $searched.Count) {
    Write-Host "No backups yet: $BackupsDir" -ForegroundColor Yellow
    return
}

# Directory names are timestamps, so sorting by name sorts by time.
$runs = @($searched | ForEach-Object { Get-ChildItem -LiteralPath $_ -Directory } |
          Sort-Object Name -Descending)

if (-not $runs.Count) {
    Write-Host "No backup runs under $($searched -join ' or ')" -ForegroundColor Yellow
    return
}

if ($List) {
    Write-Host "Backup runs in $($searched -join ' and ')" -ForegroundColor Green
    foreach ($r in $runs) {
        $m = Join-Path $r.FullName "manifest.tsv"
        $n = 0
        if (Test-Path -LiteralPath $m) {
            $n = @(Get-Content -LiteralPath $m | Where-Object { $_ -notmatch '^#' }).Count
        }
        Write-Host ("  {0,-20} {1,3} file(s)   {2}" -f $r.Name, $n, $r.FullName)
    }
    return
}

if (-not $From) { $From = $runs[0].FullName }

$manifest = Join-Path $From "manifest.tsv"
if (-not (Test-Path -LiteralPath $manifest)) {
    Write-Host "No manifest.tsv in $From" -ForegroundColor Red
    exit 1
}

$entries = @()
foreach ($line in Get-Content -LiteralPath $manifest) {
    if ($line -match '^#') { continue }
    $parts = $line -split "`t"
    if ($parts.Count -lt 2) { continue }
    if ($parts[0] -like "(symlink*") { continue }
    $entries += [pscustomobject]@{
        Backup   = Join-Path $From $parts[0]
        Original = $parts[1]
        Taken    = $(if ($parts.Count -gt 2) { $parts[2] } else { "" })
    }
}

if (-not $entries.Count) {
    Write-Host "Nothing to restore from $From (only symlinks were replaced)." -ForegroundColor Yellow
    return
}

Write-Host "Restoring from $From" -ForegroundColor Green
Write-Host ""

foreach ($e in $entries) {
    $exists = Test-Path -LiteralPath $e.Backup
    $mark = "  +"
    if (-not $exists) { $mark = "  !" }
    Write-Host ("{0} {1}" -f $mark, $e.Original) -ForegroundColor $(if ($exists) { "Gray" } else { "Yellow" })
}

if ($WhatIf) {
    Write-Host ""
    Write-Host "  -WhatIf: nothing was changed." -ForegroundColor Yellow
    return
}

if (-not $Yes) {
    Write-Host ""
    Write-Host "  This overwrites the $($entries.Count) file(s) above with the backed-up versions." -ForegroundColor Yellow
    $answer = Read-Host "  Type yes to continue"
    if ($answer -ne "yes") { Write-Host "Cancelled."; return }
}

$restored = 0
$failed   = 0

foreach ($e in $entries) {
    if (-not (Test-Path -LiteralPath $e.Backup)) {
        Write-Host ("  ! missing in backup: {0}" -f $e.Backup) -ForegroundColor Yellow
        $failed++
        continue
    }
    try {
        $dir = Split-Path -Parent $e.Original
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }

        # The current file may be a symlink into the repo; remove it first so
        # Copy-Item restores a real file rather than writing through the link.
        if (Test-Path -LiteralPath $e.Original) {
            Remove-Item -LiteralPath $e.Original -Force -Recurse
        }
        Copy-Item -LiteralPath $e.Backup -Destination $e.Original -Force -Recurse
        Write-Host ("  restored {0}" -f $e.Original) -ForegroundColor Green
        $restored++
    } catch {
        Write-Host ("  FAILED   {0}: {1}" -f $e.Original, $_.Exception.Message) -ForegroundColor Red
        $failed++
    }
}

Write-Host ""
Write-Host ("  {0} restored, {1} failed." -f $restored, $failed) -ForegroundColor $(if ($failed) { "Yellow" } else { "Green" })
