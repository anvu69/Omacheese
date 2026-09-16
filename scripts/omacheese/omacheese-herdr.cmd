@echo off
:: Launch or reattach to the herdr session. Sits on SUPER+CTRL+ENTER.
::
:: herdr is optional in this repo, so this has to behave when it is absent:
:: a hotkey that opens an empty terminal and closes again tells you nothing.
::
:: Not resolved through omacheese-open.cmd, because that starts a GUI app
:: detached. herdr is a TUI and has to run INSIDE the terminal that Alacritty
:: opened, which means being the -e command rather than launching one.

setlocal

set "HERDR="
for %%I in (herdr.exe) do if not "%%~$PATH:I"=="" set "HERDR=%%~$PATH:I"
if not defined HERDR if exist "%LOCALAPPDATA%\Programs\Herdr\bin\herdr.exe" set "HERDR=%LOCALAPPDATA%\Programs\Herdr\bin\herdr.exe"

if not defined HERDR (
    echo herdr is not installed.
    echo.
    echo   Install it:  pwsh -File "%%USERPROFILE%%\.config\omacheese\bin\install-herdr.ps1"
    echo   Or from the repo:  .\scripts\install-herdr.ps1
    echo.
    echo Not 'winget install herdr' - that moniker belongs to an unofficial fork.
    echo.
    pause
    exit /b 1
)

"%HERDR%" %*
