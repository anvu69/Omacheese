@echo off
:: Open one of the omarchy helper scripts in a terminal window.
::
::   omarchy-term.cmd <script.ps1> [args...]
::
:: Used by the yasb bar's menu button and anywhere else a GUI process needs to
:: pop up a terminal. Two things make this necessary rather than calling
:: alacritty directly from the widget config:
::
::   1. yasb runs the callback through subprocess.Popen WITHOUT a shell, so
::      %USERPROFILE% in the command string is never expanded and the path is
::      taken literally. Going through cmd.exe expands it.
::   2. A GUI process inherits the PATH of whatever started it. yasb launched
::      from an older session can have a PATH without Alacritty on it, so the
::      callback fails with "cannot find the file alacritty" even though it is
::      installed. This locates the binary instead of trusting PATH.
::
:: Falls back to the Windows console host if Alacritty is not installed at all.

setlocal EnableDelayedExpansion

set "SCRIPT=%~1"
set "ARGS=%~2 %~3 %~4 %~5"

:: `where` rather than the %%~$PATH:P modifier - that form only resolves for a
:: real for-variable in a batch context and silently yields nothing otherwise,
:: which is how this quietly fell back to the console host.
set "ALAC="
for /f "delims=" %%I in ('where alacritty.exe 2^>nul') do if not defined ALAC set "ALAC=%%I"
if not defined ALAC if exist "%ProgramFiles%\Alacritty\alacritty.exe" set "ALAC=%ProgramFiles%\Alacritty\alacritty.exe"
if not defined ALAC if exist "%LOCALAPPDATA%\Programs\Alacritty\alacritty.exe" set "ALAC=%LOCALAPPDATA%\Programs\Alacritty\alacritty.exe"

set "RUNNER=%~dp0omarchy-run.cmd"

if defined ALAC (
    start "" "!ALAC!" --class omarchy-menu,omarchy-menu -e "!RUNNER!" "!SCRIPT!" !ARGS!
) else (
    start "omarchy" cmd.exe /c ""!RUNNER!" "!SCRIPT!" !ARGS!"
)

endlocal
