@echo off
:: Launcher for the omarchy helper scripts, used by whkdrc.
::
:: whkd used to call `pwsh` directly, which means 11 bindings do nothing on a
:: machine where the `core` group was skipped and PowerShell 7 is not
:: installed - silently, because whkd has nowhere to report it.
::
:: Every helper in scripts/omarchy is verified to parse under Windows
:: PowerShell 5.1 (doctor.ps1 and CI both check), so falling back is safe.
::
:: Usage:  omarchy-run.cmd <script.ps1> [args...]

setlocal
set "SCRIPT=%~1"
shift

where pwsh.exe >nul 2>&1
if %ERRORLEVEL%==0 (
    pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %1 %2 %3 %4 %5 %6 %7 %8 %9
) else (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %1 %2 %3 %4 %5 %6 %7 %8 %9
)
endlocal
