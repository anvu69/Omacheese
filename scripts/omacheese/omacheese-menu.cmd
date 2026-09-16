@echo off
:: Open the omacheese menu.
::
::   omacheese-menu.cmd [section]
::   omacheese-menu.cmd -Menu system
::
:: Fast path: if the menu server is running, drop a signal file and get out. The
:: server already has the window built, so it only has to show it. Building one
:: from scratch costs ~770ms, most of it XAML parsing and PowerShell startup,
:: which is far too slow for a keystroke.
::
:: Slow path: no server, so build a one-shot window. Nothing depends on the
:: server being up - it only makes it quick.
::
:: The branching is done with labels, not parenthesised blocks. `if errorlevel`
:: inside a block reads the errorlevel from before the block was entered, which
:: silently sent every request down the slow path even with a healthy server.
::
:: Why a .cmd at all: yasb runs callbacks through subprocess.Popen with no
:: shell, so %USERPROFILE% is never expanded, and a GUI process inherits the
:: PATH of whatever started it - which for a bar restarted from an old session
:: may not have pwsh on it.

setlocal

set "SECTION=%~1"
if /I "%SECTION%"=="-Menu" set "SECTION=%~2"
if "%SECTION%"=="" set "SECTION=root"

set "SIGNAL=%USERPROFILE%\.config\omacheese\menu.show"
set "SERVERPID=%USERPROFILE%\.config\omacheese\menu-server.pid"

if not exist "%SERVERPID%" goto oneshot

set "SPID="
set /p SPID=<"%SERVERPID%"
if not defined SPID goto oneshot

:: Match the recorded pid, not just "some pwsh is running" - there is always a
:: pwsh running somewhere.
:: Full paths to tasklist and find, not bare names. Whatever launches the
:: menu hands down its PATH, and a PATH with Git usr\bin ahead of System32
:: resolves `find` to GNU find, which does not understand /I, fails, and sent
:: every request down the slow path with the server sitting right there.
"%SystemRoot%\System32\tasklist.exe" /FI "PID eq %SPID%" /NH 2>nul | "%SystemRoot%\System32\find.exe" /I "pwsh" >nul
if errorlevel 1 goto oneshot

>"%SIGNAL%" echo %SECTION%
endlocal
exit /b

:oneshot
:: `where` is a process spawn on a latency-sensitive path, so try the usual
:: install locations first.
set "PS="
if exist "%ProgramFiles%\PowerShell\7\pwsh.exe" set "PS=%ProgramFiles%\PowerShell\7\pwsh.exe"
if not defined PS if exist "%LOCALAPPDATA%\Microsoft\WindowsApps\pwsh.exe" set "PS=%LOCALAPPDATA%\Microsoft\WindowsApps\pwsh.exe"
if not defined PS for /f "delims=" %%I in ('"%SystemRoot%\System32\where.exe" pwsh.exe 2^>nul') do if not defined PS set "PS=%%I"
if not defined PS set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"

start "" /b "%PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden ^
    -File "%~dp0omacheese-menu.ps1" -Menu "%SECTION%"

endlocal
exit /b
