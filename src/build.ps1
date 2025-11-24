# Build script for Rosy Recorder
# Requires .NET 6+ SDK

param(
    [switch]$Release,
    [switch]$Publish
)

$ErrorActionPreference = "Stop"

Push-Location $PSScriptRoot

try {
    if ($Publish) {
        Write-Host "Publishing self-contained executable..." -ForegroundColor Cyan
        dotnet publish -c Release -r win-x64 --self-contained -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:EnableCompressionInSingleFile=true

        $output = Join-Path $PSScriptRoot "bin\Release\net6.0-windows\win-x64\publish\RosyRecorder.exe"
        if (Test-Path $output) {
            $size = [math]::Round((Get-Item $output).Length / 1MB, 1)
            Write-Host "`nBuild complete!" -ForegroundColor Green
            Write-Host "Output: $output" -ForegroundColor Yellow
            Write-Host "Size: ${size}MB" -ForegroundColor Yellow
        }
    } else {
        $config = if ($Release) { "Release" } else { "Debug" }
        Write-Host "Building in $config mode..." -ForegroundColor Cyan
        dotnet build -c $config

        Write-Host "`nBuild complete!" -ForegroundColor Green
    }
} finally {
    Pop-Location
}
