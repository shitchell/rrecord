# Rosy Recorder

A Rosy recording app for recording ~~stuff~~ works :)

Records audio from your microphone and system audio (what you hear) simultaneously!

## Features

- Record from multiple audio devices at once
- Capture system audio (speakers/headphones output)
- Per-source volume controls (0-200%)
- Auto-installs dependencies (ffmpeg, virtual-audio-capturer)

## Installation

### Quick Start

1. Download `RosyRecorder.vbs` from this repository
2. Double-click to run
3. On first launch, it will automatically download the app and dependencies

That's it! The launcher handles everything else.

### What Gets Installed

All files are stored in `%LOCALAPPDATA%\RosyRecorder\`:
- `Rosy-Recorder.ps1` - Main application
- `rose.ico` - App icon
- `config.json` - Your settings
- `ffmpeg\` - Audio encoding (auto-downloaded, ~80MB)
- `launcher.log` - Launcher logs

Additionally, **Screen Capturer Recorder** is installed to Program Files (requires admin) for system audio capture.

### Manual Installation

If you prefer to install manually:

1. Clone this repository
2. Run `Rosy-Recorder.ps1` with PowerShell:
   ```powershell
   powershell -ExecutionPolicy Bypass -File Rosy-Recorder.ps1
   ```

## Usage

1. Launch via `RosyRecorder.vbs`
2. Select audio devices to record from (mic + system audio recommended)
3. Adjust volume sliders as needed
4. Choose save location
5. Click **Start** to begin recording
6. Click **Stop** when done

Recordings are saved to `Documents\RosyRecordings\` by default.

## Uninstalling

Run `RosyRecorder-Uninstall.vbs` to remove:
- All app data and settings
- FFmpeg
- Screen Capturer Recorder

## Requirements

- Windows 10/11
- PowerShell 5.1+
- Internet connection (for first-time setup)
- Admin rights (for Screen Capturer Recorder installation)

## License

MIT
