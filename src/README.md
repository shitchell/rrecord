# Rosy Recorder - C# Version

Native Windows executable version of Rosy Recorder.

## Requirements

- .NET 6 SDK or later
- Windows 10/11

## Building

### Debug build
```powershell
dotnet build
```

### Release build
```powershell
dotnet build -c Release
```

### Publish standalone executable
```powershell
dotnet publish -c Release -r win-x64 --self-contained -p:PublishSingleFile=true
```

Or use the build script:
```powershell
.\build.ps1 -Publish
```

The output will be in `bin\Release\net6.0-windows\win-x64\publish\RosyRecorder.exe`

## Features

Same as the PowerShell version:
- Record from multiple audio devices simultaneously
- Auto-install FFmpeg and Virtual Audio Capturer
- Per-source volume controls (0-200%)
- Modern Windows Forms UI
- Saves to MP3 at 192kbps

## Advantages over PowerShell version

- Single .exe file (no VBS launcher needed)
- Faster startup
- Embedded icon
- Can be code-signed for Windows SmartScreen trust
