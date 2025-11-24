#!/usr/bin/env psrun
###############################################################################
# CONFIG
###############################################################################

$enableExperimentalPause = $false
$ffmpegPath = ""
$defaultSaveDir = Join-Path $env:USERPROFILE "Documents\RosyRecordings"
$defaultFileNamePattern = "Recording_{0:yyyy-MM-dd_HH-mm-ss}.mp3"

###############################################################################
# END CONFIG
###############################################################################

# Cache file location
$script:cacheDir = Join-Path $env:LOCALAPPDATA "RosyRecorder"
$script:cacheFile = Join-Path $script:cacheDir "config.json"

Write-Host "[DEBUG] Script starting..." -ForegroundColor Cyan
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Native Windows API calls for DPI awareness and icon extraction
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public class NativeHelpers {
    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();

    [DllImport("shell32.dll", CharSet = CharSet.Auto)]
    public static extern IntPtr ExtractIcon(IntPtr hInst, string lpszExeFileName, int nIconIndex);
}
"@

# Enable DPI awareness for crisp text rendering
[NativeHelpers]::SetProcessDPIAware() | Out-Null

# Enable visual styles for modern control appearance
[System.Windows.Forms.Application]::EnableVisualStyles()

Write-Host "[DEBUG] Assemblies loaded" -ForegroundColor Green

# Ensure default save directory exists
if (-not [string]::IsNullOrWhiteSpace($defaultSaveDir) -and -not (Test-Path $defaultSaveDir)) {
    New-Item -ItemType Directory -Path $defaultSaveDir -Force | Out-Null
}

###############################################################################
# HELPER FUNCTIONS
###############################################################################

function Get-Config {
    if (Test-Path $script:cacheFile) {
        try {
            return Get-Content $script:cacheFile -Raw | ConvertFrom-Json
        } catch { }
    }
    return $null
}

function Save-Config {
    param(
        [string]$FfmpegPath,
        [int]$MicVolume,
        [int]$SysVolume
    )
    try {
        if (-not (Test-Path $script:cacheDir)) {
            New-Item -ItemType Directory -Path $script:cacheDir -Force | Out-Null
        }
        @{
            ffmpegPath = $FfmpegPath
            micVolume = $MicVolume
            sysVolume = $SysVolume
        } | ConvertTo-Json | Set-Content $script:cacheFile -Encoding UTF8
    } catch { }
}

function Get-CachedFfmpegPath {
    $config = Get-Config
    if ($config -and $config.ffmpegPath -and (Test-Path $config.ffmpegPath)) {
        Write-Host "[DEBUG] Using cached ffmpeg: $($config.ffmpegPath)" -ForegroundColor Green
        return $config.ffmpegPath
    }
    return $null
}

function Set-CachedFfmpegPath {
    param([string]$Path)
    $config = Get-Config
    $micVol = if ($config -and $config.micVolume) { $config.micVolume } else { 100 }
    $sysVol = if ($config -and $config.sysVolume) { $config.sysVolume } else { 100 }
    Save-Config -FfmpegPath $Path -MicVolume $micVol -SysVolume $sysVol
}

function Get-FfmpegPath {
    param([string]$ConfiguredPath)

    # 1) User configured path
    if (-not [string]::IsNullOrWhiteSpace($ConfiguredPath) -and (Test-Path $ConfiguredPath)) {
        $resolved = (Resolve-Path $ConfiguredPath).Path
        Set-CachedFfmpegPath -Path $resolved
        return $resolved
    }

    # 2) Cache
    $cached = Get-CachedFfmpegPath
    if ($cached) { return $cached }

    # 3) PATH
    $cmd = Get-Command ffmpeg -ErrorAction SilentlyContinue
    if ($cmd) {
        Set-CachedFfmpegPath -Path $cmd.Source
        return $cmd.Source
    }

    # 4) Check common ffmpeg installation directories (fast, direct checks)
    Write-Host "[DEBUG] Checking common ffmpeg locations..." -ForegroundColor Yellow
    $commonPaths = @(
        # Chocolatey
        "C:\ProgramData\chocolatey\bin\ffmpeg.exe",
        # Scoop
        (Join-Path $env:USERPROFILE "scoop\shims\ffmpeg.exe"),
        (Join-Path $env:USERPROFILE "scoop\apps\ffmpeg\current\bin\ffmpeg.exe"),
        # Winget / typical program files
        "C:\Program Files\ffmpeg\bin\ffmpeg.exe",
        "C:\Program Files (x86)\ffmpeg\bin\ffmpeg.exe",
        # Common manual installs
        "C:\ffmpeg\bin\ffmpeg.exe",
        "C:\ffmpeg\ffmpeg.exe",
        # Our own install location
        (Join-Path $script:cacheDir "ffmpeg\ffmpeg-*\bin\ffmpeg.exe")
    )

    foreach ($path in $commonPaths) {
        # Handle wildcards
        if ($path -match '\*') {
            $matches = Get-ChildItem -Path $path -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($matches) {
                Set-CachedFfmpegPath -Path $matches.FullName
                return $matches.FullName
            }
        } elseif (Test-Path $path) {
            Set-CachedFfmpegPath -Path $path
            return $path
        }
    }

    # 5) Limited-depth search of user directories (faster than full recursive)
    Write-Host "[DEBUG] Searching user directories..." -ForegroundColor Yellow
    $userDirs = @(
        (Join-Path $env:USERPROFILE "Downloads"),
        (Join-Path $env:USERPROFILE "Documents"),
        (Join-Path $env:USERPROFILE "Desktop")
    ) | Where-Object { $_ -and (Test-Path $_) }

    foreach ($dir in $userDirs) {
        try {
            # Only search 3 levels deep to avoid long searches
            $ff = Get-ChildItem -Path $dir -Filter "ffmpeg.exe" -File -Recurse -Depth 3 -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($ff) {
                Set-CachedFfmpegPath -Path $ff.FullName
                return $ff.FullName
            }
        } catch { }
    }

    # 6) Last resort: search Program Files with limited depth
    Write-Host "[DEBUG] Searching Program Files (limited depth)..." -ForegroundColor Yellow
    $programDirs = @(
        "C:\Program Files",
        "C:\Program Files (x86)"
    ) | Where-Object { Test-Path $_ }

    foreach ($dir in $programDirs) {
        try {
            $ff = Get-ChildItem -Path $dir -Filter "ffmpeg.exe" -File -Recurse -Depth 4 -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($ff) {
                Set-CachedFfmpegPath -Path $ff.FullName
                return $ff.FullName
            }
        } catch { }
    }

    return $null
}

function Show-DownloadProgress {
    param(
        [string]$Title,
        [string]$Url,
        [string]$DestinationPath
    )

    # Create progress form
    $progressForm = New-Object System.Windows.Forms.Form
    $progressForm.Text = $Title
    $progressForm.Size = New-Object System.Drawing.Size(400, 130)
    $progressForm.StartPosition = "CenterScreen"
    $progressForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $progressForm.MaximizeBox = $false
    $progressForm.MinimizeBox = $false
    $progressForm.TopMost = $true
    $progressForm.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $progressForm.BackColor = [System.Drawing.Color]::FromArgb(250, 250, 250)
    $progressForm.ForeColor = [System.Drawing.Color]::FromArgb(32, 32, 32)

    $progressLabel = New-Object System.Windows.Forms.Label
    $progressLabel.Location = New-Object System.Drawing.Point(15, 15)
    $progressLabel.Size = New-Object System.Drawing.Size(360, 20)
    $progressLabel.Text = "Starting download..."
    $progressForm.Controls.Add($progressLabel)

    $progressBar = New-Object System.Windows.Forms.ProgressBar
    $progressBar.Location = New-Object System.Drawing.Point(15, 40)
    $progressBar.Size = New-Object System.Drawing.Size(355, 25)
    $progressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
    $progressForm.Controls.Add($progressBar)

    $webClient = New-Object System.Net.WebClient

    # Use script-scope variables to avoid closure issues
    $script:dlProgressBar = $progressBar
    $script:dlProgressLabel = $progressLabel
    $script:dlProgressForm = $progressForm
    $script:dlComplete = $false

    # Track download progress
    $webClient.add_DownloadProgressChanged({
        param($sender, $e)
        $script:dlProgressBar.Value = $e.ProgressPercentage
        $mb = [math]::Round($e.BytesReceived / 1MB, 1)
        $totalMb = [math]::Round($e.TotalBytesToReceive / 1MB, 1)
        $script:dlProgressLabel.Text = "Downloading: $mb MB / $totalMb MB ($($e.ProgressPercentage)%)"
    })

    $webClient.add_DownloadFileCompleted({
        param($sender, $e)
        $script:dlComplete = $true
    })

    # Show form and start async download
    $progressForm.Show()

    try {
        $webClient.DownloadFileAsync([Uri]$Url, $DestinationPath)

        # Wait for download to complete
        while (-not $script:dlComplete) {
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 50
        }
        $progressForm.Close()
        return $true
    } catch {
        $progressForm.Close()
        throw $_
    } finally {
        $webClient.Dispose()
    }
}

function Install-FFmpeg {
    # Download ffmpeg essentials build from gyan.dev (popular Windows builds)
    $ffmpegUrl = "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip"
    $zipPath = Join-Path $env:TEMP "ffmpeg-essentials.zip"
    $extractPath = Join-Path $script:cacheDir "ffmpeg"

    try {
        Write-Host "[DEBUG] Downloading ffmpeg (~80MB)..." -ForegroundColor Cyan

        # Download with progress dialog
        $null = Show-DownloadProgress -Title "Downloading FFmpeg" -Url $ffmpegUrl -DestinationPath $zipPath

        Write-Host "[DEBUG] Extracting ffmpeg..." -ForegroundColor Cyan

        # Create extraction directory
        if (-not (Test-Path $extractPath)) {
            New-Item -ItemType Directory -Path $extractPath -Force | Out-Null
        }

        # Extract zip
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $extractPath)

        # Find ffmpeg.exe in extracted folder (it's in a versioned subdirectory)
        $ffmpegExe = Get-ChildItem -Path $extractPath -Filter "ffmpeg.exe" -Recurse | Select-Object -First 1

        if ($ffmpegExe) {
            $ffmpegPath = $ffmpegExe.FullName
            Set-CachedFfmpegPath -Path $ffmpegPath
            Write-Host "[DEBUG] FFmpeg installed to: $ffmpegPath" -ForegroundColor Green

            [System.Windows.Forms.MessageBox]::Show(
                "FFmpeg installed successfully!",
                "Done",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            ) | Out-Null

            return $ffmpegPath
        } else {
            throw "ffmpeg.exe not found in extracted archive"
        }
    } catch {
        Write-Host "[DEBUG] FFmpeg installation failed: $_" -ForegroundColor Red
        [System.Windows.Forms.MessageBox]::Show(
            "FFmpeg installation failed: $_`n`nDownload manually from:`nhttps://ffmpeg.org/download.html",
            "Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
        return $null
    } finally {
        if (Test-Path $zipPath) { Remove-Item $zipPath -ErrorAction SilentlyContinue }
    }
}

function Install-VirtualAudioCapturer {
    $installerUrl = "https://github.com/rdp/screen-capture-recorder-to-video-windows-free/releases/download/v0.13.3/Setup.Screen.Capturer.Recorder.v0.13.3.exe"
    $installerPath = Join-Path $env:TEMP "Setup.Screen.Capturer.Recorder.exe"

    try {
        Write-Host "[DEBUG] Downloading virtual-audio-capturer..." -ForegroundColor Cyan
        $null = Show-DownloadProgress -Title "Downloading Virtual Audio Capturer" -Url $installerUrl -DestinationPath $installerPath
        Write-Host "[DEBUG] Download complete, running installer..." -ForegroundColor Cyan

        $process = Start-Process -FilePath $installerPath -ArgumentList "/S" -Wait -PassThru

        Write-Host "[DEBUG] Installer exit code: $($process.ExitCode)" -ForegroundColor Cyan

        # Exit code 0 means success, but NSIS installers sometimes return non-zero even on success
        # Check if it's likely installed by looking for the DLL
        $dllPath = Join-Path $env:ProgramFiles "Screen Capturer Recorder\virtual-audio-capturer.dll"
        $dllPathx86 = Join-Path ${env:ProgramFiles(x86)} "Screen Capturer Recorder\virtual-audio-capturer.dll"

        if ($process.ExitCode -eq 0 -or (Test-Path $dllPath) -or (Test-Path $dllPathx86)) {
            [System.Windows.Forms.MessageBox]::Show("Virtual Audio Capturer installed successfully!`n`nThe device list will now refresh.", "Done", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
            return $true
        } else {
            Write-Host "[DEBUG] Installation may have failed. Exit code: $($process.ExitCode)" -ForegroundColor Yellow
            [System.Windows.Forms.MessageBox]::Show("Installation may have failed (exit code: $($process.ExitCode)).`n`nTry running the installer manually from:`nhttps://github.com/rdp/screen-capture-recorder-to-video-windows-free/releases", "Warning", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
            return $false
        }
    } catch {
        Write-Host "[DEBUG] Installation error: $_" -ForegroundColor Red
        [System.Windows.Forms.MessageBox]::Show("Installation failed: $_`n`nDownload manually from:`nhttps://github.com/rdp/screen-capture-recorder-to-video-windows-free/releases", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    } finally {
        if (Test-Path $installerPath) { Remove-Item $installerPath -ErrorAction SilentlyContinue }
    }
    return $false
}

function Get-DShowAudioDevices {
    param([string]$FfmpegPath)

    if ([string]::IsNullOrWhiteSpace($FfmpegPath)) {
        Write-Host "[DEBUG] ERROR: FfmpegPath is empty!" -ForegroundColor Red
        return @()
    }

    if (-not (Test-Path $FfmpegPath)) {
        Write-Host "[DEBUG] ERROR: FfmpegPath does not exist: $FfmpegPath" -ForegroundColor Red
        return @()
    }

    Write-Host "[DEBUG] Listing devices with: $FfmpegPath" -ForegroundColor Cyan

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FfmpegPath
    $psi.Arguments = "-f dshow -list_devices true -i dummy"
    $psi.UseShellExecute = $false
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardOutput = $true
    $psi.CreateNoWindow = $true

    $p = [System.Diagnostics.Process]::Start($psi)
    $stderr = $p.StandardError.ReadToEnd()
    $p.WaitForExit()

    $audioDevices = @()

    foreach ($line in ($stderr -split "`r?`n")) {
        # Look for lines with (audio) that contain a device name in quotes
        # Skip "Alternative name" lines
        if ($line -match '\(audio\)' -and $line -notmatch "Alternative name" -and $line -match '"(.+)"') {
            $audioDevices += $Matches[1]
        }
    }

    return $audioDevices
}

function Get-DeviceTypePrefix {
    param([string]$DeviceName)

    if ($DeviceName -match '(?i)stereo mix|virtual-audio-capturer|loopback|what u hear|wave out') {
        return "[System Audio]"
    }
    elseif ($DeviceName -match '(?i)speakers|headphones|realtek.*output|output') {
        return "[System Audio]"
    }
    elseif ($DeviceName -match '(?i)microphone|mic|input|webcam|usb audio') {
        return "[Microphone]"
    }
    return "[Audio Device]"
}

function Test-HasSystemAudioDevice {
    param([string[]]$Devices)
    foreach ($device in $Devices) {
        if ($device -match '(?i)stereo mix|virtual-audio-capturer|loopback|what u hear|wave out|voicemeeter|vb-audio|cable output') {
            return $true
        }
    }
    return $false
}

function Test-VirtualAudioCapturerInstalled {
    # Check if Screen Capturer Recorder is installed (which includes virtual-audio-capturer)

    # 1) Check common installation directories
    $installDir = Join-Path ${env:ProgramFiles(x86)} "Screen Capturer Recorder"
    $installDir64 = Join-Path $env:ProgramFiles "Screen Capturer Recorder"

    if ((Test-Path $installDir) -or (Test-Path $installDir64)) {
        Write-Host "[DEBUG] Found Screen Capturer Recorder in Program Files" -ForegroundColor Green
        return $true
    }

    # 2) Check for the DLL directly in common locations
    $dllPath = Join-Path $env:ProgramFiles "Screen Capturer Recorder\screen-capture-recorder.dll"
    $dllPathx86 = Join-Path ${env:ProgramFiles(x86)} "Screen Capturer Recorder\screen-capture-recorder.dll"
    if ((Test-Path $dllPath) -or (Test-Path $dllPathx86)) {
        Write-Host "[DEBUG] Found screen-capture-recorder.dll" -ForegroundColor Green
        return $true
    }

    # 3) Fallback: search Program Files with limited depth
    Write-Host "[DEBUG] Searching for screen-capture-recorder..." -ForegroundColor Yellow
    $searchDirs = @(
        "C:\Program Files",
        "C:\Program Files (x86)"
    ) | Where-Object { Test-Path $_ }

    foreach ($dir in $searchDirs) {
        try {
            $found = Get-ChildItem -Path $dir -Filter "screen-capture-recorder*.dll" -File -Recurse -Depth 3 -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($found) {
                Write-Host "[DEBUG] Found screen-capture-recorder at: $($found.FullName)" -ForegroundColor Green
                return $true
            }
        } catch { }
    }

    return $false
}

function Guess-DefaultDevices {
    param([string[]]$Devices)

    $mic = $null
    $sys = $null

    foreach ($d in $Devices) {
        if (-not $mic -and $d -match '(?i)microphone|mic') { $mic = $d }
        if (-not $sys -and $d -match '(?i)stereo mix|virtual-audio-capturer|loopback|speakers|headphones') { $sys = $d }
    }

    if (-not $mic -and $Devices.Count -gt 0) { $mic = $Devices[0] }
    if (-not $sys -and $Devices.Count -gt 1) { $sys = $Devices[1] }
    elseif (-not $sys -and $Devices.Count -gt 0) { $sys = $Devices[0] }

    return @{ MicDevice = $mic; SysDevice = $sys }
}

###############################################################################
# RECORDING FUNCTIONS
###############################################################################

$script:ffmpegFullPath = $null
$script:isRecording = $false
$script:ffmpegProcess = $null
$script:startTime = $null
$script:segmentFiles = New-Object System.Collections.Generic.List[string]
$script:segmentIndex = 0
$script:finalOutputPath = $null
$script:deviceList = @()

function Build-FfmpegArgs {
    param(
        [string]$OutputPath,
        [string[]]$Devices,
        [double[]]$Volumes
    )

    if ($Devices.Count -eq 0) { throw "No devices specified" }
    if (-not $Volumes -or $Volumes.Count -ne $Devices.Count) {
        $Volumes = @(1.0) * $Devices.Count
    }

    $argParts = @("-y")

    foreach ($device in $Devices) {
        $argParts += @("-f", "dshow", "-i", "audio=`"$device`"")
    }

    if ($Devices.Count -gt 1) {
        $filterParts = @()
        $mixInputs = @()
        for ($i = 0; $i -lt $Devices.Count; $i++) {
            $filterParts += "[$i`:a]volume=$($Volumes[$i])[a$i]"
            $mixInputs += "[a$i]"
        }
        $filterComplex = ($filterParts -join ";") + ";" + ($mixInputs -join "") + "amix=inputs=$($Devices.Count):duration=longest:dropout_transition=2"
        $argParts += @("-filter_complex", "`"$filterComplex`"")
    }
    elseif ($Volumes[0] -ne 1.0) {
        $argParts += @("-af", "volume=$($Volumes[0])")
    }

    $argParts += @("-ac", "2", "-ar", "48000", "-c:a", "libmp3lame", "-b:a", "192k", "`"$OutputPath`"")
    return ($argParts -join " ")
}

function Start-RecordingSegment {
    param(
        [string]$SegmentPath,
        [string[]]$Devices,
        [double[]]$Volumes
    )

    if ($script:isRecording -and $script:ffmpegProcess -and -not $script:ffmpegProcess.HasExited) { return }

    $script:isRecording = $true
    $script:startTime = Get-Date

    if ($enableExperimentalPause) {
        $script:segmentIndex++
        $script:segmentFiles.Add($SegmentPath) | Out-Null
    }

    $ffmpegArgs = Build-FfmpegArgs -OutputPath $SegmentPath -Devices $Devices -Volumes $Volumes
    Write-Host "[DEBUG] FFmpeg args: $ffmpegArgs" -ForegroundColor Cyan

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $script:ffmpegFullPath
    $psi.Arguments = $ffmpegArgs
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardError = $false
    $psi.RedirectStandardOutput = $false
    $psi.CreateNoWindow = $true

    $script:ffmpegProcess = [System.Diagnostics.Process]::Start($psi)
}

function Stop-CurrentRecording {
    if ($script:ffmpegProcess -and -not $script:ffmpegProcess.HasExited) {
        try {
            Write-Host "[DEBUG] Stopping ffmpeg..." -ForegroundColor Cyan
            $script:ffmpegProcess.StandardInput.WriteLine("q")
            $script:ffmpegProcess.StandardInput.Close()
            if (-not $script:ffmpegProcess.WaitForExit(5000)) {
                $script:ffmpegProcess.Kill()
            }
        } catch {
            try { $script:ffmpegProcess.Kill() } catch { }
        }
    }
    $script:isRecording = $false
}

function Join-SegmentsWithFfmpeg {
    param([string[]]$Segments, [string]$FinalOutput)

    if ($Segments.Count -eq 0) { return }
    if ($Segments.Count -eq 1) {
        Move-Item -Path $Segments[0] -Destination $FinalOutput -Force
        return
    }

    $tempListPath = Join-Path ([System.IO.Path]::GetDirectoryName($FinalOutput)) "segments_$(Get-Random).txt"
    $Segments | ForEach-Object { "file '$($_.Replace("'", "''"))'" } | Set-Content -Path $tempListPath -Encoding ASCII

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $script:ffmpegFullPath
    $psi.Arguments = "-y -f concat -safe 0 -i `"$tempListPath`" -c copy `"$FinalOutput`""
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    $p = [System.Diagnostics.Process]::Start($psi)
    $p.WaitForExit()

    Remove-Item $tempListPath -ErrorAction SilentlyContinue
    foreach ($seg in $Segments) { Remove-Item $seg -ErrorAction SilentlyContinue }
}

###############################################################################
# MAIN - BUILD GUI WITH TABLELAYOUTPANEL
###############################################################################

Write-Host "[DEBUG] Building GUI..." -ForegroundColor Cyan

# Set up default save path
$now = Get-Date
$script:finalOutputPath = Join-Path $defaultSaveDir ([string]::Format($defaultFileNamePattern, $now))

# Modern color scheme
$script:colors = @{
    Background = [System.Drawing.Color]::FromArgb(250, 250, 250)
    Surface = [System.Drawing.Color]::White
    Primary = [System.Drawing.Color]::FromArgb(0, 120, 212)      # Blue
    Success = [System.Drawing.Color]::FromArgb(16, 124, 16)       # Green
    Danger = [System.Drawing.Color]::FromArgb(196, 43, 28)        # Red
    TextPrimary = [System.Drawing.Color]::FromArgb(32, 32, 32)
    TextSecondary = [System.Drawing.Color]::FromArgb(96, 96, 96)
    Border = [System.Drawing.Color]::FromArgb(200, 200, 200)
}

# Create form with modern styling
$form = New-Object System.Windows.Forms.Form
$form.Text = "Rosy Recorder"
$form.Size = New-Object System.Drawing.Size(620, 420)
$form.MinimumSize = New-Object System.Drawing.Size(515, 415)
$form.StartPosition = "CenterScreen"
$form.TopMost = $true
$form.Padding = New-Object System.Windows.Forms.Padding(10, 10, 10, 10)
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$form.BackColor = $script:colors.Background
$form.ForeColor = $script:colors.TextPrimary

# Set custom icon (rose icon for Rosy!)
try {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
    $iconPath = Join-Path $scriptDir "rose.ico"
    if (Test-Path $iconPath) {
        $form.Icon = New-Object System.Drawing.Icon($iconPath)
    } else {
        # Fallback to microphone icon from shell32.dll
        Write-Host "[DEBUG] Rose icon not found, using fallback microphone icon" -ForegroundColor Yellow
        $iconHandle = [NativeHelpers]::ExtractIcon([IntPtr]::Zero, "C:\Windows\System32\shell32.dll", 168)
        if ($iconHandle -ne [IntPtr]::Zero) {
            $form.Icon = [System.Drawing.Icon]::FromHandle($iconHandle)
        }
    }
} catch {
    Write-Host "[DEBUG] Could not set custom icon: $_" -ForegroundColor Yellow
}

$form.Add_Resize({
    Write-Host "[DEBUG] Window size: $($form.Width) x $($form.Height)" -ForegroundColor Magenta
})

# Main layout panel
$layout = New-Object System.Windows.Forms.TableLayoutPanel
$layout.Dock = [System.Windows.Forms.DockStyle]::Fill
$layout.ColumnCount = 3
$layout.RowCount = 8
$layout.AutoSize = $false

# Column styles: Label (auto), Control (fill), Small (auto)
$layout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::AutoSize))) | Out-Null
$layout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100))) | Out-Null
$layout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::AutoSize))) | Out-Null

# Row styles
$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 28))) | Out-Null  # Row 0: Save path (fixed height)
$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize))) | Out-Null  # Row 1: Device label
$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100))) | Out-Null  # Row 2: Device list (fills)
$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize))) | Out-Null  # Row 3: Mic volume
$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize))) | Out-Null  # Row 4: Sys volume
$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize))) | Out-Null  # Row 5: Status
$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize))) | Out-Null  # Row 6: Buttons

# Row 0: Save path
$labelPath = New-Object System.Windows.Forms.Label
$labelPath.Text = "Save to:"
$labelPath.AutoSize = $true
$labelPath.Anchor = [System.Windows.Forms.AnchorStyles]::Left
$labelPath.Margin = New-Object System.Windows.Forms.Padding(0, 5, 5, 0)

$txtSavePath = New-Object System.Windows.Forms.TextBox
$txtSavePath.Text = $script:finalOutputPath
$txtSavePath.Dock = [System.Windows.Forms.DockStyle]::Fill
$txtSavePath.Anchor = [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right -bor [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom
$txtSavePath.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 0)

$btnBrowse = New-Object System.Windows.Forms.Button
$btnBrowse.Text = "Browse..."
$btnBrowse.Dock = [System.Windows.Forms.DockStyle]::Fill
$btnBrowse.Margin = New-Object System.Windows.Forms.Padding(3, 0, 0, 0)
$btnBrowse.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnBrowse.FlatAppearance.BorderColor = $script:colors.Border
$btnBrowse.BackColor = $script:colors.Surface
$btnBrowse.Cursor = [System.Windows.Forms.Cursors]::Hand

$btnBrowse.Add_Click({
    $saveDialog = New-Object System.Windows.Forms.SaveFileDialog
    $saveDialog.Filter = "MP3 Audio|*.mp3|All Files|*.*"
    $saveDialog.FileName = [System.IO.Path]::GetFileName($txtSavePath.Text)
    $saveDialog.InitialDirectory = [System.IO.Path]::GetDirectoryName($txtSavePath.Text)
    if ($saveDialog.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
        $txtSavePath.Text = $saveDialog.FileName
        $script:finalOutputPath = $saveDialog.FileName
    }
})

$layout.Controls.Add($labelPath, 0, 0)
$layout.Controls.Add($txtSavePath, 1, 0)
$layout.Controls.Add($btnBrowse, 2, 0)

# Row 1: Device label
$labelDevices = New-Object System.Windows.Forms.Label
$labelDevices.Text = "Record from:"
$labelDevices.AutoSize = $true
$labelDevices.Margin = New-Object System.Windows.Forms.Padding(0, 10, 0, 3)
$layout.Controls.Add($labelDevices, 0, 1)
$layout.SetColumnSpan($labelDevices, 3)

# Row 2: Device checklist
$deviceCheckList = New-Object System.Windows.Forms.CheckedListBox
$deviceCheckList.Dock = [System.Windows.Forms.DockStyle]::Fill
$deviceCheckList.CheckOnClick = $true
$deviceCheckList.BackColor = $script:colors.Surface
$deviceCheckList.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle

# Custom drawing to replace dotted focus rectangle with solid highlight
$deviceCheckList.DrawMode = [System.Windows.Forms.DrawMode]::OwnerDrawFixed
$deviceCheckList.ItemHeight = 18
$deviceCheckList.Add_DrawItem({
    param($sender, $e)

    if ($e.Index -lt 0) { return }

    $isSelected = ($e.State -band [System.Windows.Forms.DrawItemState]::Selected) -eq [System.Windows.Forms.DrawItemState]::Selected

    # Draw background
    if ($isSelected) {
        $e.Graphics.FillRectangle([System.Drawing.Brushes]::LightSteelBlue, $e.Bounds)
    } else {
        $e.Graphics.FillRectangle([System.Drawing.Brushes]::White, $e.Bounds)
    }

    # Draw checkbox
    $checkSize = 13
    $checkX = $e.Bounds.X + 2
    $checkY = $e.Bounds.Y + (($e.Bounds.Height - $checkSize) / 2)
    $checkRect = New-Object System.Drawing.Rectangle($checkX, $checkY, $checkSize, $checkSize)

    [System.Windows.Forms.ControlPaint]::DrawCheckBox(
        $e.Graphics,
        $checkRect,
        $(if ($sender.GetItemChecked($e.Index)) { [System.Windows.Forms.ButtonState]::Checked } else { [System.Windows.Forms.ButtonState]::Normal })
    )

    # Draw text
    $textX = $checkX + $checkSize + 4
    $textBounds = New-Object System.Drawing.Rectangle($textX, $e.Bounds.Y, $e.Bounds.Width - $textX, $e.Bounds.Height)
    $sf = New-Object System.Drawing.StringFormat
    $sf.LineAlignment = [System.Drawing.StringAlignment]::Center
    $e.Graphics.DrawString($sender.Items[$e.Index].ToString(), $e.Font, [System.Drawing.Brushes]::Black, $textBounds, $sf)
})

$layout.Controls.Add($deviceCheckList, 0, 2)
$layout.SetColumnSpan($deviceCheckList, 3)

# Load saved volume settings
$savedConfig = Get-Config
$savedMicVol = if ($savedConfig -and $savedConfig.micVolume) { $savedConfig.micVolume } else { 100 }
$savedSysVol = if ($savedConfig -and $savedConfig.sysVolume) { $savedConfig.sysVolume } else { 100 }

# Row 3: Mic volume
$labelMicVol = New-Object System.Windows.Forms.Label
$labelMicVol.Text = "Mic Volume:"
$labelMicVol.AutoSize = $true
$labelMicVol.Anchor = [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Top
$labelMicVol.Margin = New-Object System.Windows.Forms.Padding(0, 12, 5, 0)

$sliderMicVol = New-Object System.Windows.Forms.TrackBar
$sliderMicVol.Minimum = 0
$sliderMicVol.Maximum = 200
$sliderMicVol.Value = [Math]::Min($savedMicVol, 200)
$sliderMicVol.TickFrequency = 25
$sliderMicVol.Dock = [System.Windows.Forms.DockStyle]::Fill

$labelMicVolPct = New-Object System.Windows.Forms.Label
$labelMicVolPct.Text = "$savedMicVol%"
$labelMicVolPct.AutoSize = $true
$labelMicVolPct.Anchor = [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Top
$labelMicVolPct.Margin = New-Object System.Windows.Forms.Padding(5, 12, 0, 0)

$sliderMicVol.Add_ValueChanged({ $labelMicVolPct.Text = "$($sliderMicVol.Value)%" })

$layout.Controls.Add($labelMicVol, 0, 3)
$layout.Controls.Add($sliderMicVol, 1, 3)
$layout.Controls.Add($labelMicVolPct, 2, 3)

# Row 4: System volume
$labelSysVol = New-Object System.Windows.Forms.Label
$labelSysVol.Text = "System Volume:"
$labelSysVol.AutoSize = $true
$labelSysVol.Anchor = [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Top
$labelSysVol.Margin = New-Object System.Windows.Forms.Padding(0, 12, 5, 0)

$sliderSysVol = New-Object System.Windows.Forms.TrackBar
$sliderSysVol.Minimum = 0
$sliderSysVol.Maximum = 200
$sliderSysVol.Value = [Math]::Min($savedSysVol, 200)
$sliderSysVol.TickFrequency = 25
$sliderSysVol.Dock = [System.Windows.Forms.DockStyle]::Fill

$labelSysVolPct = New-Object System.Windows.Forms.Label
$labelSysVolPct.Text = "$savedSysVol%"
$labelSysVolPct.AutoSize = $true
$labelSysVolPct.Anchor = [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Top
$labelSysVolPct.Margin = New-Object System.Windows.Forms.Padding(5, 12, 0, 0)

$sliderSysVol.Add_ValueChanged({ $labelSysVolPct.Text = "$($sliderSysVol.Value)%" })

$layout.Controls.Add($labelSysVol, 0, 4)
$layout.Controls.Add($sliderSysVol, 1, 4)
$layout.Controls.Add($labelSysVolPct, 2, 4)

# Row 5: Status/Time
$labelStatus = New-Object System.Windows.Forms.Label
$labelStatus.Text = "Initializing..."
$labelStatus.AutoSize = $true
$labelStatus.ForeColor = [System.Drawing.Color]::Gray
$labelStatus.Margin = New-Object System.Windows.Forms.Padding(0, 10, 0, 5)

$labelTime = New-Object System.Windows.Forms.Label
$labelTime.Text = "Elapsed: 00:00:00"
$labelTime.AutoSize = $true
$labelTime.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
$labelTime.Visible = $false
$labelTime.Margin = New-Object System.Windows.Forms.Padding(0, 10, 0, 5)

$layout.Controls.Add($labelStatus, 0, 5)
$layout.SetColumnSpan($labelStatus, 3)
$layout.Controls.Add($labelTime, 0, 5)
$layout.SetColumnSpan($labelTime, 3)

# Row 6: Buttons
$buttonPanel = New-Object System.Windows.Forms.TableLayoutPanel
$buttonPanel.ColumnCount = 5
$buttonPanel.RowCount = 1
$buttonPanel.AutoSize = $true
$buttonPanel.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
$buttonPanel.Dock = [System.Windows.Forms.DockStyle]::Bottom
$buttonPanel.Margin = New-Object System.Windows.Forms.Padding(0)
$buttonPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::AutoSize))) | Out-Null
$buttonPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::AutoSize))) | Out-Null
$buttonPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::AutoSize))) | Out-Null
$buttonPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100))) | Out-Null  # Spacer
$buttonPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::AutoSize))) | Out-Null
$buttonPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize))) | Out-Null

$btnStart = New-Object System.Windows.Forms.Button
$btnStart.Text = "Start"
$btnStart.Size = New-Object System.Drawing.Size(80, 30)
$btnStart.Margin = New-Object System.Windows.Forms.Padding(0, 0, 3, 0)
$btnStart.Enabled = $false
$btnStart.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnStart.BackColor = $script:colors.Success
$btnStart.ForeColor = [System.Drawing.Color]::White
$btnStart.FlatAppearance.BorderSize = 0
$btnStart.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnStart.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)

$btnStop = New-Object System.Windows.Forms.Button
$btnStop.Text = "Stop"
$btnStop.Size = New-Object System.Drawing.Size(80, 30)
$btnStop.Margin = New-Object System.Windows.Forms.Padding(0, 0, 3, 0)
$btnStop.Enabled = $false
$btnStop.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnStop.BackColor = $script:colors.Danger
$btnStop.ForeColor = [System.Drawing.Color]::White
$btnStop.FlatAppearance.BorderSize = 0
$btnStop.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnStop.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)

$btnQuit = New-Object System.Windows.Forms.Button
$btnQuit.Text = "Quit"
$btnQuit.Size = New-Object System.Drawing.Size(80, 30)
$btnQuit.Margin = New-Object System.Windows.Forms.Padding(0)
$btnQuit.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnQuit.FlatAppearance.BorderColor = $script:colors.Border
$btnQuit.BackColor = $script:colors.Surface
$btnQuit.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnQuit.TabStop = $false  # Disable focus rectangle

$buttonPanel.Controls.Add($btnStart, 0, 0)
$buttonPanel.Controls.Add($btnStop, 1, 0)
# Column 2-3 are spacers/pause-resume
$buttonPanel.Controls.Add($btnQuit, 4, 0)

$layout.Controls.Add($buttonPanel, 0, 6)
$layout.SetColumnSpan($buttonPanel, 3)

$form.Controls.Add($layout)

###############################################################################
# TIMERS
###############################################################################

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 500
$timer.Add_Tick({
    if ($script:isRecording -and $script:startTime) {
        $elapsed = (Get-Date) - $script:startTime
        $labelTime.Text = "Elapsed: " + $elapsed.ToString("hh\:mm\:ss")
    }
})

$initTimer = New-Object System.Windows.Forms.Timer
$initTimer.Interval = 100
$initTimer.Add_Tick({
    $initTimer.Stop()

    # Find ffmpeg
    $labelStatus.Text = "Searching for ffmpeg..."
    $form.Refresh()

    $script:ffmpegFullPath = Get-FfmpegPath -ConfiguredPath $ffmpegPath

    if (-not $script:ffmpegFullPath) {
        $result = [System.Windows.Forms.MessageBox]::Show(
            "FFmpeg is required but was not found.`n`nWould you like to download and install it automatically?`n`n(~80MB download)`n`nSource: https://www.gyan.dev/ffmpeg/builds/",
            "Install FFmpeg?",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )

        if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
            $labelStatus.Text = "Downloading FFmpeg..."
            $form.Refresh()
            $script:ffmpegFullPath = Install-FFmpeg
        }

        if (-not $script:ffmpegFullPath) {
            $labelStatus.Text = "FFmpeg not found!"
            $labelStatus.ForeColor = [System.Drawing.Color]::Red
            return
        }
    }

    # Discover devices
    $labelStatus.Text = "Discovering audio devices..."
    $form.Refresh()

    $audioDevices = Get-DShowAudioDevices -FfmpegPath $script:ffmpegFullPath
    Write-Host "[DEBUG] Found $($audioDevices.Count) audio device(s)" -ForegroundColor Cyan

    # Check if Virtual Audio Capturer is installed (for system audio recording)
    $vacInstalled = Test-VirtualAudioCapturerInstalled
    Write-Host "[DEBUG] Virtual Audio Capturer installed: $vacInstalled" -ForegroundColor Cyan

    if (-not $vacInstalled) {
        $result = [System.Windows.Forms.MessageBox]::Show(
            "Virtual Audio Capturer is not installed.`n`nThis is required to record system audio (what you hear).`n`nInstall now?`n`nSource: https://github.com/rdp/screen-capture-recorder-to-video-windows-free",
            "Install Virtual Audio Capturer?",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )

        if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
            $labelStatus.Text = "Installing Virtual Audio Capturer..."
            $form.Refresh()
            if (Install-VirtualAudioCapturer) {
                # Refresh device list after installation
                $labelStatus.Text = "Refreshing audio devices..."
                $form.Refresh()
                $audioDevices = Get-DShowAudioDevices -FfmpegPath $script:ffmpegFullPath
                Write-Host "[DEBUG] After install, found $($audioDevices.Count) audio device(s)" -ForegroundColor Cyan
            }
        }
    }

    if (-not $audioDevices -or $audioDevices.Count -eq 0) {
        $labelStatus.Text = "No audio devices found!"
        $labelStatus.ForeColor = [System.Drawing.Color]::Red
        return
    }

    # Populate device list
    $script:deviceList = $audioDevices
    $guessed = Guess-DefaultDevices -Devices $audioDevices

    foreach ($device in $audioDevices) {
        $prefix = Get-DeviceTypePrefix -DeviceName $device
        $index = $deviceCheckList.Items.Add("$prefix $device")
        if ($device -eq $guessed.MicDevice -or $device -eq $guessed.SysDevice) {
            $deviceCheckList.SetItemChecked($index, $true)
        }
    }

    # Ready
    $labelStatus.Visible = $false
    $labelTime.Visible = $true
    $btnStart.Enabled = $true
    Write-Host "[DEBUG] Ready to record" -ForegroundColor Green
})

###############################################################################
# BUTTON HANDLERS
###############################################################################

$btnStart.Add_Click({
    if ($script:isRecording) { return }

    $selectedIndices = $deviceCheckList.CheckedIndices
    if ($selectedIndices.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Please select at least one audio device.", "No Device", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }

    $selectedDevices = @()
    foreach ($idx in $selectedIndices) { $selectedDevices += $script:deviceList[$idx] }

    $script:finalOutputPath = $txtSavePath.Text
    if ([string]::IsNullOrWhiteSpace($script:finalOutputPath)) {
        [System.Windows.Forms.MessageBox]::Show("Please specify a save location.", "No Path", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }

    $recordDir = [System.IO.Path]::GetDirectoryName($script:finalOutputPath)
    if (-not (Test-Path $recordDir)) { New-Item -ItemType Directory -Path $recordDir -Force | Out-Null }

    # Calculate volumes
    $micVol = $sliderMicVol.Value / 100.0
    $sysVol = $sliderSysVol.Value / 100.0
    $volumes = @()
    foreach ($device in $selectedDevices) {
        $prefix = Get-DeviceTypePrefix -DeviceName $device
        $volumes += if ($prefix -eq "[Microphone]") { $micVol } else { $sysVol }
    }

    Write-Host "[DEBUG] Recording: $($selectedDevices -join ', ')" -ForegroundColor Cyan

    Start-RecordingSegment -SegmentPath $script:finalOutputPath -Devices $selectedDevices -Volumes $volumes

    $btnStart.Enabled = $false
    $btnStop.Enabled = $true
    $btnBrowse.Enabled = $false
    $txtSavePath.Enabled = $false
    $deviceCheckList.Enabled = $false
    $sliderMicVol.Enabled = $false
    $sliderSysVol.Enabled = $false
    $timer.Start()
})

$btnStop.Add_Click({
    $timer.Stop()
    Stop-CurrentRecording

    if ($enableExperimentalPause -and $script:segmentFiles.Count -gt 0) {
        Join-SegmentsWithFfmpeg -Segments $script:segmentFiles.ToArray() -FinalOutput $script:finalOutputPath
        $script:segmentFiles.Clear()
        $script:segmentIndex = 0
    }

    [System.Windows.Forms.MessageBox]::Show("Recording saved to:`n$($script:finalOutputPath)", "Done", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null

    # Re-enable for next recording
    $btnStart.Enabled = $true
    $btnStop.Enabled = $false
    $btnBrowse.Enabled = $true
    $txtSavePath.Enabled = $true
    $deviceCheckList.Enabled = $true
    $sliderMicVol.Enabled = $true
    $sliderSysVol.Enabled = $true

    # New filename for next recording
    $now = Get-Date
    $script:finalOutputPath = Join-Path $defaultSaveDir ([string]::Format($defaultFileNamePattern, $now))
    $txtSavePath.Text = $script:finalOutputPath
    $labelTime.Text = "Elapsed: 00:00:00"
})

$btnQuit.Add_Click({ $form.Close() })

$form.Add_FormClosing({
    # Save volume settings
    Save-Config -FfmpegPath $script:ffmpegFullPath -MicVolume $sliderMicVol.Value -SysVolume $sliderSysVol.Value

    if ($script:ffmpegProcess -and -not $script:ffmpegProcess.HasExited) {
        try { $script:ffmpegProcess.Kill() } catch { }
    }
})

###############################################################################
# RUN
###############################################################################

$initTimer.Start()
[void]$form.ShowDialog()

Write-Host "Done."
