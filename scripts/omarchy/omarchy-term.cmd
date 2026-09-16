@echo off
:: Open an omarchy helper in a small floating terminal.
::
::   omarchy-term.cmd <script.ps1> [args...]
::
:: Why this exists rather than calling alacritty from the widget config:
::
::   1. yasb runs callbacks through subprocess.Popen WITHOUT a shell, so
::      %USERPROFILE% in the command string is never expanded and the path is
::      taken literally. Going through cmd.exe expands it.
::   2. A GUI process inherits the PATH of whatever started it. yasb launched
::      from an older session can have a PATH without Alacritty on it, so the
::      callback fails with "cannot find the file alacritty" even though it is
::      installed. This locates the binary instead of trusting PATH.
::
:: It runs PowerShell DIRECTLY as the terminal's command. An earlier version
:: pointed alacritty at omarchy-run.cmd, which meant the window was hosting
:: cmd running a batch file running PowerShell - three shells deep, and what
:: you saw inside the window was cmd.
::
:: The window is deliberately small and centred so it reads as a menu rather
:: than as "a terminal happened to open". komorebi floats it via the
:: `omarchy-menu` class rule in komorebi.json.

setlocal EnableDelayedExpansion

set "SCRIPT=%~1"
set "ARGS=%~2 %~3 %~4 %~5"

:: Single instance. The bar button is easy to click twice, and without this
:: every click stacked another terminal. If one is already up, raise it and
:: stop. tasklist's WINDOWTITLE filter does see GUI windows, and the title is
:: set below.
tasklist /FI "IMAGENAME eq alacritty.exe" /FI "WINDOWTITLE eq omarchy" 2>nul | find /I "alacritty.exe" >nul
if not errorlevel 1 (
    powershell.exe -NoProfile -WindowStyle Hidden -Command ^
      "$w=New-Object -ComObject WScript.Shell; Get-Process alacritty -EA SilentlyContinue | Where-Object MainWindowTitle -eq 'omarchy' | Select-Object -First 1 | ForEach-Object { $w.AppActivate($_.Id) } | Out-Null"
    endlocal
    exit /b
)

:: Prefer PowerShell 7; fall back to Windows PowerShell.
set "PS="
for /f "delims=" %%I in ('where pwsh.exe 2^>nul') do if not defined PS set "PS=%%I"
if not defined PS set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"

:: `where` rather than the %%~$PATH:P modifier - that form only resolves for a
:: real for-variable in a batch context and silently yields nothing otherwise,
:: which is how this quietly fell back to the console host.
set "ALAC="
for /f "delims=" %%I in ('where alacritty.exe 2^>nul') do if not defined ALAC set "ALAC=%%I"
if not defined ALAC if exist "%ProgramFiles%\Alacritty\alacritty.exe" set "ALAC=%ProgramFiles%\Alacritty\alacritty.exe"
if not defined ALAC if exist "%LOCALAPPDATA%\Programs\Alacritty\alacritty.exe" set "ALAC=%LOCALAPPDATA%\Programs\Alacritty\alacritty.exe"

if defined ALAC (
    start "" "!ALAC!" ^
        --class omarchy-menu,omarchy-menu ^
        --title "omarchy" ^
        -o window.dimensions.columns=88 ^
        -o window.dimensions.lines=26 ^
        -o window.padding.x=14 ^
        -o window.padding.y=10 ^
        -o window.decorations=\"none\" ^
        -e "!PS!" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "!SCRIPT!" !ARGS!
) else (
    start "omarchy" "!PS!" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "!SCRIPT!" !ARGS!
)

endlocal
