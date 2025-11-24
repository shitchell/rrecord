#!/usr/bin/env psrun
# Uninstall script for Rosy Recorder dependencies
# Removes ffmpeg and Screen Capturer Recorder

Write-Host "Uninstalling Rosy Recorder dependencies..." -ForegroundColor Cyan

# Remove ffmpeg
$ffmpegDir = Join-Path $env:LOCALAPPDATA "RosyRecorder\ffmpeg"
if (Test-Path $ffmpegDir) {
    Write-Host "Removing ffmpeg..." -ForegroundColor Yellow
    Remove-Item -Recurse -Force $ffmpegDir
    Write-Host "  Removed: $ffmpegDir" -ForegroundColor Green
} else {
    Write-Host "  ffmpeg not found (already uninstalled)" -ForegroundColor Gray
}

# Clear ffmpeg path from config
$configFile = Join-Path $env:LOCALAPPDATA "RosyRecorder\config.json"
if (Test-Path $configFile) {
    try {
        $config = Get-Content $configFile | ConvertFrom-Json
        $config.ffmpegPath = ""
        $config | ConvertTo-Json | Set-Content $configFile
        Write-Host "  Cleared ffmpeg path from config" -ForegroundColor Green
    } catch {
        Write-Host "  Warning: Could not update config file" -ForegroundColor Yellow
    }
}

# Uninstall Screen Capturer Recorder
$uninstaller = "C:\Program Files (x86)\Screen Capturer Recorder\unins000.exe"
$uninstaller64 = "C:\Program Files\Screen Capturer Recorder\unins000.exe"

if (Test-Path $uninstaller) {
    Write-Host "Uninstalling Screen Capturer Recorder..." -ForegroundColor Yellow
    Start-Process -FilePath $uninstaller -ArgumentList "/SILENT" -Wait
    Write-Host "  Uninstalled Screen Capturer Recorder" -ForegroundColor Green
} elseif (Test-Path $uninstaller64) {
    Write-Host "Uninstalling Screen Capturer Recorder (x64)..." -ForegroundColor Yellow
    Start-Process -FilePath $uninstaller64 -ArgumentList "/SILENT" -Wait
    Write-Host "  Uninstalled Screen Capturer Recorder" -ForegroundColor Green
} else {
    Write-Host "  Screen Capturer Recorder not found (already uninstalled)" -ForegroundColor Gray
}

Write-Host ""
Write-Host "Done!" -ForegroundColor Green
