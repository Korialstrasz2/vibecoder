param(
    [Parameter(Mandatory = $true)]
    [string]$StopFile,

    [int]$MaxSeconds = 60,
    [string]$HostName = $(if ($env:LLAMA_HOST) { $env:LLAMA_HOST } else { "127.0.0.1" }),
    [string]$Port = $(if ($env:LLAMA_PORT) { $env:LLAMA_PORT } else { "8075" }),
    [string]$Language = "en",
    [string]$Prompt = "Transcribe exactly. This may include programming terms and Elder Scrolls names such as Divayth Fyr, Telvanni, Morrowind, Sotha Sil, Vivec, Dagoth Ur, Dwemer, and Nerevarine."
)

$ErrorActionPreference = "Stop"

function Get-AssistantDir {
    if ((Split-Path -Leaf $PSScriptRoot) -ieq "scripts") {
        return (Split-Path -Parent $PSScriptRoot)
    }
    return $PSScriptRoot
}

function Find-FFmpeg {
    $assistantDir = Get-AssistantDir
    $candidates = @(
        (Join-Path $assistantDir "..\runtime\ffmpeg\bin\ffmpeg.exe"),
        (Join-Path $assistantDir "ffmpeg.exe"),
        "ffmpeg.exe"
    )

    foreach ($candidate in $candidates) {
        try {
            $cmd = Get-Command $candidate -ErrorAction Stop
            if ($cmd.Source) { return $cmd.Source }
        } catch {}

        if (Test-Path $candidate) {
            return (Resolve-Path $candidate).Path
        }
    }

    throw "ffmpeg.exe not found. Put ffmpeg.exe on PATH or in runtime\ffmpeg\bin."
}

function Read-CachedDevice {
    if ($env:AUDIO_DEVICE) {
        return [string]$env:AUDIO_DEVICE
    }

    $assistantDir = Get-AssistantDir
    $configPath = Join-Path $assistantDir "system\cache\.voice_device.json"

    if (-not (Test-Path $configPath)) {
        throw "No cached microphone found. Run voice_to_clipboard_auto_v3.bat 2 once, or set AUDIO_DEVICE."
    }

    $config = Get-Content $configPath -Raw | ConvertFrom-Json
    if (-not $config.deviceName) {
        throw "Cached microphone file exists but has no deviceName."
    }

    return [string]$config.deviceName
}

function Quote-Arg {
    param([string]$Value)
    return '"' + ($Value -replace '"', '\"') + '"'
}

function Invoke-Transcription {
    param(
        [string]$AudioFile,
        [string]$BaseUrl,
        [string]$Language,
        [string]$Prompt
    )

    $response = & curl.exe -s -X POST "$BaseUrl/audio/transcriptions" `
        -F "response_format=json" `
        -F "language=$Language" `
        -F "prompt=$Prompt" `
        -F "file=@$AudioFile"

    if ($LASTEXITCODE -ne 0) {
        throw "curl failed while calling $BaseUrl/audio/transcriptions."
    }

    if (-not $response) {
        throw "Empty response from llama-server. Is start_server.bat running?"
    }

    try {
        $json = $response | ConvertFrom-Json
        if ($json.text) {
            return ([string]$json.text).Trim()
        }
    } catch {}

    return ([string]$response).Trim()
}

$assistantDir = Get-AssistantDir
$stateDir = Split-Path -Parent $StopFile
if (-not $stateDir) {
    $stateDir = Join-Path $assistantDir "system\cache\ptt"
}
New-Item -ItemType Directory -Path $stateDir -Force | Out-Null

$errorFile = Join-Path $stateDir "last_error.txt"
Remove-Item -LiteralPath $errorFile -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $StopFile -Force -ErrorAction SilentlyContinue

try {
    $baseUrl = "http://${HostName}:${Port}/v1"

    try {
        Invoke-RestMethod -Uri "$baseUrl/models" -Method Get -TimeoutSec 1 | Out-Null
    } catch {
        throw "Gemma server is not reachable at $baseUrl. Start start_server.bat first."
    }

    $ffmpeg = Find-FFmpeg
    $device = Read-CachedDevice

    $wav = Join-Path $stateDir ("ptt_{0}.wav" -f ([Guid]::NewGuid().ToString("N")))

    $ffArgs = @(
        "-y",
        "-hide_banner",
        "-loglevel", "error",
        "-f", "dshow",
        "-i", "audio=$device",
        "-ar", "16000",
        "-ac", "1",
        "-c:a", "pcm_s16le",
        $wav
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $ffmpeg
    $psi.Arguments = ($ffArgs | ForEach-Object { Quote-Arg $_ }) -join " "
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi

    [void]$proc.Start()

    $started = Get-Date
    while (-not (Test-Path $StopFile)) {
        Start-Sleep -Milliseconds 40

        if ($proc.HasExited) {
            break
        }

        if (((Get-Date) - $started).TotalSeconds -ge $MaxSeconds) {
            break
        }
    }

    if (-not $proc.HasExited) {
        try {
            $proc.StandardInput.WriteLine("q")
            $proc.StandardInput.Flush()
        } catch {}

        if (-not $proc.WaitForExit(3000)) {
            $proc.Kill()
            $proc.WaitForExit()
        }
    }

    Start-Sleep -Milliseconds 150

    if (-not (Test-Path $wav)) {
        throw "Recording failed. WAV file was not created."
    }

    if ((Get-Item $wav).Length -lt 2048) {
        throw "Recording was too short or empty."
    }

    $text = Invoke-Transcription -AudioFile $wav -BaseUrl $baseUrl -Language $Language -Prompt $Prompt

    if (-not $text) {
        throw "Transcription was empty."
    }

    Set-Clipboard -Value $text
    Remove-Item -LiteralPath $wav -Force -ErrorAction SilentlyContinue
    exit 0
}
catch {
    $message = $_.Exception.Message
    $message | Set-Content -LiteralPath $errorFile -Encoding UTF8
    exit 1
}