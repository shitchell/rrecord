@echo off
setlocal EnableDelayedExpansion

:: Rosy Recorder Launcher
:: Downloads missing assets and launches the PowerShell script

set "SCRIPT_DIR=%~dp0"
set "PS1_FILE=%SCRIPT_DIR%Record-Audio.ps1"
set "ICO_FILE=%SCRIPT_DIR%rose.ico"

:: URLs for downloading assets
set "PS1_URL=https://raw.githubusercontent.com/YOUR_USERNAME/rosy-recorder/main/Record-Audio.ps1"
set "ICO_URL=https://files.softicons.com/download/holidays-icons/valentines-day-icons-by-design-bolts/ico/Rose-flower-icon.ico"

echo Rosy Recorder
echo ==============
echo.

:: Check for PowerShell script
if not exist "%PS1_FILE%" (
    echo PowerShell script not found, downloading...
    powershell -Command "& {(New-Object System.Net.WebClient).DownloadFile('%PS1_URL%', '%PS1_FILE%')}"
    if not exist "%PS1_FILE%" (
        echo ERROR: Failed to download PowerShell script!
        echo Please download manually from: %PS1_URL%
        pause
        exit /b 1
    )
    echo Downloaded Record-Audio.ps1
)

:: Check for icon
if not exist "%ICO_FILE%" (
    echo Icon not found, downloading...
    powershell -Command "& {(New-Object System.Net.WebClient).DownloadFile('%ICO_URL%', '%ICO_FILE%')}"
    if not exist "%ICO_FILE%" (
        echo WARNING: Failed to download icon, continuing without it...
    ) else (
        echo Downloaded rose.ico
    )
)

echo.
echo Launching Rosy Recorder...
echo.

:: Launch the PowerShell script
:: -ExecutionPolicy Bypass allows running unsigned scripts
:: -WindowStyle Hidden hides the PowerShell console window
powershell -ExecutionPolicy Bypass -WindowStyle Hidden -File "%PS1_FILE%"

exit /b 0
