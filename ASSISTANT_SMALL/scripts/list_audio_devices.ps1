$ErrorActionPreference = "Stop"

function Find-FFmpeg {
    $candidates = @(
        (Join-Path $PSScriptRoot "..\..\runtime\ffmpeg\bin\ffmpeg.exe"),
        (Join-Path $PSScriptRoot "..\ffmpeg.exe"),
        "ffmpeg.exe"
    )
    foreach ($candidate in $candidates) {
        try {
            $cmd = Get-Command $candidate -ErrorAction Stop
            if ($cmd.Source) { return $cmd.Source }
        } catch {}
        if (Test-Path $candidate) { return (Resolve-Path $candidate).Path }
    }
    throw "ffmpeg.exe not found. Put ffmpeg.exe on PATH or in runtime\ffmpeg\bin."
}

$ffmpeg = Find-FFmpeg
Write-Host "Using ffmpeg: $ffmpeg"
Write-Host ""
Write-Host "DirectShow audio devices:"
Write-Host ""
& $ffmpeg -hide_banner -list_devices true -f dshow -i dummy 2>&1 | ForEach-Object { $_.ToString() }
Write-Host ""
Write-Host "Set AUDIO_DEVICE to the exact device name, for example:"
Write-Host '  set AUDIO_DEVICE=Microphone Array (Realtek(R) Audio)'
