@echo off
:: Launch the omarchy menu as a GUI, with no console of its own.
::
::   omarchy-menu.cmd [-Menu <section>]
::
:: Why a .cmd rather than calling PowerShell directly from the bar or whkdrc:
::
::   1. yasb runs callbacks through subprocess.Popen with no shell, so
::      %USERPROFILE% in the command string is never expanded.
::   2. A GUI process inherits the PATH of whatever started it, and a bar
::      restarted from an old session can have a PATH without pwsh on it.
::
:: `start "" /b` plus -WindowStyle Hidden keeps PowerShell from ever showing a
:: console window - the menu should look like part of the desktop, not like a
:: script that happens to draw one.

setlocal

set "PS="
for /f "delims=" %%I in ('where pwsh.exe 2^>nul') do if not defined PS set "PS=%%I"
if not defined PS set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"

start "" /b "%PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden ^
    -File "%~dp0omarchy-menu.ps1" %*

endlocal
