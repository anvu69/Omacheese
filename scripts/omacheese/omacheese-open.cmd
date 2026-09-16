@echo off
:: Launch a GUI app by name. Used by whkdrc for every app hotkey.
::
::   omacheese-open.cmd alacritty
::   omacheese-open.cmd brave --incognito
::   omacheese-open.cmd alacritty -e wsl.exe -d AlmaLinux-9 -- nvim
::
:: `start "" <name>` is a ShellExecute lookup and finds almost no GUI app,
:: because installers register neither on PATH nor in App Paths. Measured:
:: `start "" brave` fails while `start "" brave.exe` works, and alacritty fails
:: both ways. That left SUPER+Enter opening an empty console window instead of
:: a terminal.
::
:: Fast path: read the resolved path out of the cache and start it, no
:: PowerShell involved. This sits on SUPER+Enter, so it has to stay cheap.
:: Slow path, once per app: omacheese-open.ps1 resolves it properly and writes
:: the cache entry.

setlocal EnableDelayedExpansion

:: Our own directory, captured up front so the slow path can find the .ps1
:: next to this file rather than in whatever folder the hotkey fired from.
set "HERE=%~dp0"

set "APP=%~1"
if "%APP%"=="" exit /b 1

:: Take the remaining arguments in one piece. Walking them with shift and %1
:: re-tokenises, and cmd counts a comma as a delimiter, so
:: `--class agent,agent` arrived as `--class agent agent`; Alacritty rejected
:: the extra positional and the agent hotkeys opened nothing at all.
:: `delims= ` splits on space only, and `tokens=1,*` keeps the tail verbatim.
set "ARGS="
for /f "tokens=1,* delims= " %%A in ("%*") do set "ARGS= %%B"
if "%ARGS%"==" " set "ARGS="
set "CACHE=%USERPROFILE%\.config\omacheese\app-paths.txt"
set "EXE="
if not exist "%CACHE%" goto slow

for /f "usebackq tokens=1,* delims=|" %%A in ("%CACHE%") do (
    if /I "%%A"=="%APP%" set "EXE=%%B"
)
if not defined EXE goto slow
if not exist "!EXE!" goto slow

start "" "!EXE!"!ARGS!
endlocal
exit /b

:slow
set "PS="
if exist "%ProgramFiles%\PowerShell\7\pwsh.exe" set "PS=%ProgramFiles%\PowerShell\7\pwsh.exe"
if not defined PS if exist "%LOCALAPPDATA%\Microsoft\WindowsApps\pwsh.exe" set "PS=%LOCALAPPDATA%\Microsoft\WindowsApps\pwsh.exe"
if not defined PS set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"

start "" /b "%PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden ^
    -File "%HERE%omacheese-open.ps1" "%APP%"!ARGS!

endlocal
exit /b
