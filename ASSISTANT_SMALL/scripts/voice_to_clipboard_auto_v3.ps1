param(
    [int]$Seconds = 8,
    [string]$HostName = $(if ($env:LLAMA_HOST) { $env:LLAMA_HOST } else { "127.0.0.1" }),
    [string]$Port = $(if ($env:LLAMA_PORT) { $env:LLAMA_PORT } else { "8075" }),
    [string]$Language = "en",
    [string]$Prompt = "Transcribe exactly. The speaker may use English or Italian naturally within the same utterance. Topics may include programming, everyday conversation, video games, and fantasy references such as Dunmer, Divayth Fyr, Morrowind, Dwemer, Telvanni, Vivec, or Dagoth Ur. Do not assume the speaker is only talking about games or fantasy. Preserve technical terms, code names, commands, and proper nouns exactly as spoken. Keep the transcription concise and faithful to what was said.",
    [double]$MinActiveDb = -50.0
)

$ErrorActionPreference = "Stop"

function Invoke-NativeTextCapture {
    param([scriptblock]$Command)

    # ffmpeg writes useful probe output to stderr. Capture stderr as normal text.
    $oldEap = $ErrorActionPreference
    $hadNativePref = Test-Path variable:PSNativeCommandUseErrorActionPreference
    if ($hadNativePref) { $oldNativePref = $PSNativeCommandUseErrorActionPreference }

    try {
        $ErrorActionPreference = "Continue"
        if ($hadNativePref) { $script:PSNativeCommandUseErrorActionPreference = $false }
        return @(& $Command 2>&1 | ForEach-Object { $_.ToString() })
    }
    finally {
        $ErrorActionPreference = $oldEap
        if ($hadNativePref) { $script:PSNativeCommandUseErrorActionPreference = $oldNativePref }
    }
}

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
        if (Test-Path $candidate) { return (Resolve-Path $candidate).Path }
    }

    throw "ffmpeg.exe not found. Put ffmpeg.exe on PATH or in runtime\ffmpeg\bin."
}

function Get-ConfigPath {
    return (Join-Path (Get-AssistantDir) "system\cache\.voice_device.json")
}

function Get-LastDeviceListPath {
    return (Join-Path (Get-AssistantDir) "system\cache\.last_dshow_devices.txt")
}

function Read-CachedDevice {
    if ($env:AUDIO_DEVICE) { return [string]$env:AUDIO_DEVICE }

    $configPath = Get-ConfigPath
    if (-not (Test-Path $configPath)) { return $null }

    try {
        $config = Get-Content $configPath -Raw | ConvertFrom-Json
        if ($config.deviceName) { return [string]$config.deviceName }
    } catch {}
    return $null
}

function Save-CachedDevice {
    param(
        [string]$DeviceName,
        [double]$MaxVolumeDb
    )

    $configPath = Get-ConfigPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $configPath) -Force | Out-Null
    $payload = [ordered]@{
        deviceName = $DeviceName
        maxVolumeDb = $MaxVolumeDb
        savedAt = (Get-Date).ToString("o")
        note = "Auto-selected by voice_to_clipboard_auto_v3.ps1. Delete this file to force re-detection."
    }
    $payload | ConvertTo-Json | Set-Content -LiteralPath $configPath -Encoding UTF8
}

function Add-UniqueDevice {
    param(
        [System.Collections.Generic.List[string]]$List,
        [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($Name)) { return }
    $clean = $Name.Trim()
    if (-not $List.Contains($clean)) { [void]$List.Add($clean) }
}

function Get-DirectShowAudioDevices {
    param([string]$FFmpeg)

    $lines = Invoke-NativeTextCapture { & $FFmpeg -hide_banner -list_devices true -f dshow -i dummy }

    $lastPath = Get-LastDeviceListPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $lastPath) -Force | Out-Null
    try {
        $lines | Set-Content -LiteralPath $lastPath -Encoding UTF8
    } catch {}

    $devices = New-Object System.Collections.Generic.List[string]

    # Format A: one-line classification, e.g.
    # [dshow @ ...] "Microphone Array (Realtek(R) Audio)" (audio)
    foreach ($line in $lines) {
        if ($line -match '"([^"]+)"\s+\(audio\)') {
            Add-UniqueDevice -List $devices -Name $Matches[1]
        }
    }

    # Format B: section classification, e.g.
    # DirectShow audio devices
    #   "Microphone Array (Realtek(R) Audio)"
    if ($devices.Count -eq 0) {
        $inAudio = $false
        foreach ($line in $lines) {
            if ($line -match 'DirectShow\s+audio\s+devices') {
                $inAudio = $true
                continue
            }
            if ($inAudio -and $line -match 'DirectShow\s+video\s+devices') {
                $inAudio = $false
                continue
            }
            if (-not $inAudio) { continue }
            if ($line -match 'Alternative name') { continue }

            if ($line -match '"([^"]+)"') {
                Add-UniqueDevice -List $devices -Name $Matches[1]
            }
        }
    }

    # Last-resort fallback:
    # Some builds print devices without clear sections but with "audio" near the line.
    if ($devices.Count -eq 0) {
        foreach ($line in $lines) {
            if ($line -match 'audio' -and $line -match '"([^"]+)"') {
                $candidate = $Matches[1]
                if ($candidate -notmatch 'Video|Camera|DroidCam Video') {
                    Add-UniqueDevice -List $devices -Name $candidate
                }
            }
        }
    }

    if ($devices.Count -eq 0) {
        Write-Host ""
        Write-Host "Could not parse any DirectShow audio devices."
        Write-Host "Raw ffmpeg device list was saved to:"
        Write-Host "  $lastPath"
        Write-Host ""
        Write-Host "Raw ffmpeg output:"
        Write-Host "------------------"
        foreach ($line in $lines) { Write-Host $line }
        Write-Host "------------------"
        Write-Host ""
    }

    return @($devices)
}

function Invoke-RecordDevice {
    param(
        [string]$FFmpeg,
        [string]$DeviceName,
        [int]$DurationSeconds,
        [string]$OutputFile
    )

    Write-Host "Recording $DurationSeconds seconds from: $DeviceName"
    & $FFmpeg -y -hide_banner -loglevel error -f dshow -i "audio=$DeviceName" -t $DurationSeconds -ar 16000 -ac 1 -c:a pcm_s16le $OutputFile
    if ($LASTEXITCODE -ne 0) { return $false }
    if (-not (Test-Path $OutputFile)) { return $false }
    if ((Get-Item $OutputFile).Length -lt 2048) { return $false }
    return $true
}

function Get-MaxVolumeDb {
    param(
        [string]$FFmpeg,
        [string]$AudioFile
    )

    if (-not (Test-Path $AudioFile)) { return -999.0 }

    $nullSink = "NUL"
    if ($env:OS -ne "Windows_NT") { $nullSink = "/dev/null" }

    $lines = Invoke-NativeTextCapture { & $FFmpeg -hide_banner -nostats -i $AudioFile -af volumedetect -f null $nullSink }
    foreach ($line in $lines) {
        if ($line -match 'max_volume:\s+(-?\d+(?:\.\d+)?)\s+dB') {
            return [double]$Matches[1]
        }
    }
    return -999.0
}

function Record-AllDevicesAndPickBest {
    param(
        [string]$FFmpeg,
        [string[]]$Devices,
        [int]$DurationSeconds,
        [string]$TempDir,
        [double]$MinimumDb
    )

    if (-not $Devices -or $Devices.Count -eq 0) {
        throw "No DirectShow audio devices found or parsed. See ASSISTANT_SMALL\system\cache\.last_dshow_devices.txt."
    }

    Write-Host "No valid cached microphone. Recording all $($Devices.Count) DirectShow audio devices for $DurationSeconds seconds..."
    Write-Host "Speak now. The loudest non-silent device will be cached."
    Write-Host ""

    $jobs = @()
    for ($i = 0; $i -lt $Devices.Count; $i++) {
        $device = $Devices[$i]
        $outFile = Join-Path $TempDir ("device_{0}.wav" -f $i)
        $jobs += Start-Job -ArgumentList $FFmpeg, $device, $DurationSeconds, $outFile -ScriptBlock {
            param($ffmpeg, $deviceName, $duration, $outputFile)
            & $ffmpeg -y -hide_banner -loglevel error -f dshow -i "audio=$deviceName" -t $duration -ar 16000 -ac 1 -c:a pcm_s16le $outputFile 2>&1 | Out-Null
            [pscustomobject]@{
                Device = $deviceName
                OutputFile = $outputFile
                ExitCode = $LASTEXITCODE
            }
        }
    }

    $timeout = [Math]::Max(10, $DurationSeconds + 8)
    [void](Wait-Job -Job $jobs -Timeout $timeout)

    foreach ($job in $jobs) {
        if ($job.State -eq "Running") {
            Stop-Job $job -Force -ErrorAction SilentlyContinue
        }
    }

    $results = @()
    foreach ($job in $jobs) {
        try {
            $r = Receive-Job $job -ErrorAction SilentlyContinue
            if ($r) { $results += $r }
        } finally {
            Remove-Job $job -Force -ErrorAction SilentlyContinue
        }
    }

    $scored = @()
    foreach ($result in $results) {
        if ($result.ExitCode -eq 0 -and (Test-Path $result.OutputFile) -and (Get-Item $result.OutputFile).Length -gt 2048) {
            $db = Get-MaxVolumeDb -FFmpeg $FFmpeg -AudioFile $result.OutputFile
            $scored += [pscustomobject]@{
                Device = [string]$result.Device
                OutputFile = [string]$result.OutputFile
                MaxDb = [double]$db
            }
            Write-Host ("{0,8:N1} dB  {1}" -f $db, $result.Device)
        }
    }

    if (-not $scored -or $scored.Count -eq 0) {
        throw "All microphone recording attempts failed. Check Windows microphone privacy settings and DirectShow support."
    }

    $best = $scored | Sort-Object MaxDb -Descending | Select-Object -First 1
    if ($best.MaxDb -lt $MinimumDb) {
        throw ("No active microphone detected. Loudest device was '{0}' at {1:N1} dB, below threshold {2:N1} dB. Run again and speak during detection, or lower -MinActiveDb." -f $best.Device, $best.MaxDb, $MinimumDb)
    }

    Save-CachedDevice -DeviceName $best.Device -MaxVolumeDb $best.MaxDb
    Write-Host ""
    Write-Host "Selected and cached microphone: $($best.Device)"
    return $best
}

function Invoke-Transcription {
    param(
        [string]$AudioFile,
        [string]$BaseUrl,
        [string]$Language,
        [string]$Prompt
    )

    Write-Host "Transcribing through $BaseUrl/audio/transcriptions ..."
    $response = & curl.exe -s -X POST "$BaseUrl/audio/transcriptions" `
        -F "response_format=json" `
        -F "language=$Language" `
        -F "prompt=$Prompt" `
        -F "file=@$AudioFile"

    if (-not $response) { throw "Empty response from llama-server. Is start_server.bat running?" }

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
    return $text
}

if ($Seconds -lt 1) { throw "Seconds must be >= 1." }
if ($Seconds -gt 60) { throw "Seconds must be <= 60. Use short utterances for best local STT quality." }

$ffmpeg = Find-FFmpeg
$baseUrl = "http://${HostName}:${Port}/v1"
$tempDir = Join-Path $env:TEMP ("gemma4_voice_auto_{0}" -f ([Guid]::NewGuid().ToString("N")))
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

try {
    $audioForTranscription = $null
    $cachedDevice = Read-CachedDevice

    if ($cachedDevice) {
        $cachedOut = Join-Path $tempDir "cached.wav"
        Write-Host "Trying cached microphone: $cachedDevice"
        $ok = Invoke-RecordDevice -FFmpeg $ffmpeg -DeviceName $cachedDevice -DurationSeconds $Seconds -OutputFile $cachedOut
        if ($ok) {
            $db = Get-MaxVolumeDb -FFmpeg $ffmpeg -AudioFile $cachedOut
            Write-Host ("Cached microphone max volume: {0:N1} dB" -f $db)
            if ($db -ge $MinActiveDb) {
                $audioForTranscription = $cachedOut
                Save-CachedDevice -DeviceName $cachedDevice -MaxVolumeDb $db
            } else {
                Write-Host "Cached microphone was silent/too quiet. Falling back to auto-detection."
            }
        } else {
            Write-Host "Cached microphone failed. Falling back to auto-detection."
        }
    }

    if (-not $audioForTranscription) {
        $devices = Get-DirectShowAudioDevices -FFmpeg $ffmpeg
        if ($devices -and $devices.Count -gt 0) {
            Write-Host "Detected DirectShow audio devices:"
            foreach ($d in $devices) { Write-Host "  - $d" }
            Write-Host ""
        }

        $best = Record-AllDevicesAndPickBest -FFmpeg $ffmpeg -Devices $devices -DurationSeconds $Seconds -TempDir $tempDir -MinimumDb $MinActiveDb
        $audioForTranscription = $best.OutputFile
    }

    $text = Invoke-Transcription -AudioFile $audioForTranscription -BaseUrl $baseUrl -Language $Language -Prompt $Prompt
    Set-Clipboard -Value $text

    Write-Host ""
    Write-Host "Copied transcription to clipboard:"
    Write-Host ""
    Write-Host $text
    Write-Host ""
    Write-Host "Paste it into OpenCode."
}
finally {
    if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue }
}
