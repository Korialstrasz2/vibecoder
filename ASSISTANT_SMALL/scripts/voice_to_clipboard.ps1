param(
    [int]$Seconds = 8,
    [string]$HostName = $(if ($env:LLAMA_HOST) { $env:LLAMA_HOST } else { "127.0.0.1" }),
    [string]$Port = $(if ($env:LLAMA_PORT) { $env:LLAMA_PORT } else { "8075" }),
    [string]$Language = "en",
    [string]$DeviceName = $env:AUDIO_DEVICE,
    [string]$Prompt = "Transcribe exactly. This may include programming terms and Elder Scrolls names such as Divayth Fyr, Telvanni, Morrowind, Sotha Sil, Vivec, Dagoth Ur, Dwemer, and Nerevarine."
)

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

function Invoke-FFmpegRecord {
    param(
        [string]$FFmpeg,
        [string]$OutputFile,
        [int]$DurationSeconds,
        [string]$InputDevice
    )

    if ($InputDevice) {
        Write-Host "Recording $DurationSeconds seconds from DirectShow device: $InputDevice"
        & $FFmpeg -y -hide_banner -loglevel error -f dshow -i "audio=$InputDevice" -t $DurationSeconds -ar 16000 -ac 1 $OutputFile
        return $LASTEXITCODE
    }

    Write-Host "Recording $DurationSeconds seconds from default WASAPI microphone..."
    & $FFmpeg -y -hide_banner -loglevel error -f wasapi -i default -t $DurationSeconds -ar 16000 -ac 1 $OutputFile
    if ($LASTEXITCODE -eq 0) { return 0 }

    Write-Host "WASAPI default failed. Trying DirectShow audio=default..."
    & $FFmpeg -y -hide_banner -loglevel error -f dshow -i "audio=default" -t $DurationSeconds -ar 16000 -ac 1 $OutputFile
    return $LASTEXITCODE
}

if ($Seconds -lt 1) { throw "Seconds must be >= 1." }
if ($Seconds -gt 60) { throw "Seconds must be <= 60. Use short utterances for best local STT quality." }

$ffmpeg = Find-FFmpeg
$tmp = Join-Path $env:TEMP ("gemma4_voice_{0}.wav" -f ([Guid]::NewGuid().ToString("N")))
$baseUrl = "http://${HostName}:${Port}/v1"

try {
    $code = Invoke-FFmpegRecord -FFmpeg $ffmpeg -OutputFile $tmp -DurationSeconds $Seconds -InputDevice $DeviceName
    if ($code -ne 0 -or -not (Test-Path $tmp)) {
        throw "Recording failed. Run list_audio_devices.bat, then set AUDIO_DEVICE to your exact microphone name."
    }

    Write-Host "Transcribing through $baseUrl/audio/transcriptions ..."
    $response = & curl.exe -s -X POST "$baseUrl/audio/transcriptions" `
        -F "response_format=json" `
        -F "language=$Language" `
        -F "prompt=$Prompt" `
        -F "file=@$tmp"

    if (-not $response) { throw "Empty response from llama-server." }

    $text = $null
    try {
        $json = $response | ConvertFrom-Json
        if ($json.text) { $text = [string]$json.text }
    } catch {
        $text = [string]$response
    }

    if (-not $text) { $text = [string]$response }
    $text = $text.Trim()

    if (-not $text) { throw "Transcription was empty." }

    Set-Clipboard -Value $text
    Write-Host ""
    Write-Host "Copied transcription to clipboard:"
    Write-Host ""
    Write-Host $text
    Write-Host ""
    Write-Host "Paste it into OpenCode."
}
finally {
    if (Test-Path $tmp) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
}
