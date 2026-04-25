# Captures a screenshot of the primary monitor and saves it to screenshots/ folder
# Usage: .\scripts\capture-screenshot.ps1
# Optional: .\scripts\capture-screenshot.ps1 -Filename "my-shot.png"

param(
    [string]$Filename = ""
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$rootDir = Split-Path -Parent $scriptDir
$screenshotDir = Join-Path $rootDir "screenshots"

if (-not (Test-Path $screenshotDir)) {
    New-Item -ItemType Directory -Force -Path $screenshotDir | Out-Null
}

if ([string]::IsNullOrWhiteSpace($Filename)) {
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $Filename = "screenshot_${timestamp}.png"
}

$outputPath = Join-Path $screenshotDir $Filename

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$screen = [System.Windows.Forms.Screen]::PrimaryScreen
$bounds = $screen.Bounds

$bitmap = New-Object System.Drawing.Bitmap($bounds.Width, $bounds.Height)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)

$bitmap.Save($outputPath, ([System.Drawing.Imaging.ImageFormat]::Png))
$graphics.Dispose()
$bitmap.Dispose()

Write-Output $outputPath
