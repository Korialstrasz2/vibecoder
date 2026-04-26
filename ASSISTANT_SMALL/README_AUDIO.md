# Gemma 4 audio input patch for `ASSISTANT_SMALL`

Copy every file in this zip into your existing `ASSISTANT_SMALL` folder, replacing the existing files when prompted.

## What this patch does

- Updates `opencode.jsonc` so the local OpenAI-compatible model advertises text, image, and audio input with text output.
- Updates `start_server.bat` so it:
  - defaults to the stable alias `gemma-4-local-audio`, matching `opencode.jsonc`;
  - selects E4B by default when both E2B and E4B are present;
  - searches for the matching `mmproj` only in the selected model folder;
  - prefers `*mmproj*BF16*.gguf`;
  - fails loudly if the projector is missing, because audio needs it;
  - passes Gemma 4 sampling flags: temp 1.0, top-k 64, top-p 0.95;
  - passes `--jinja` and `--flash-attn on` by default.
- Adds a direct audio transcription test script.
- Adds a microphone helper that records a short utterance, sends it to llama.cpp `/v1/audio/transcriptions`, and copies the transcription to your clipboard.

## Required layout

Recommended model layout:

```text
vibe-coding-portable\
  runtime\
    llama.cpp\
      llama-server.exe
  models\
    GEMMA_4_LARGE\
      gemma-4-E4B-it-Q4_K_M.gguf
      mmproj-gemma-4-BF16.gguf
  ASSISTANT_SMALL\
    opencode.jsonc
    start_server.bat
    start_opencode.bat
    test_audio_transcription.bat
    voice_to_clipboard.bat
    list_audio_devices.bat
    scripts\
      voice_to_clipboard.ps1
      list_audio_devices.ps1
```

The E4B model and its `mmproj` must sit in the same folder. Do not mix the E4B model with the E2B projector.

## llama.cpp requirement

Use a recent llama.cpp build. You need a build new enough for:

- Gemma 4 E2B/E4B audio projector support.
- The OpenAI-compatible `/v1/audio/transcriptions` endpoint.

Old builds may load text/image but fail on audio.

## Start flow

1. Start the server:

```bat
ASSISTANT_SMALL\start_server.bat
```

Choose `2` for E4B, or wait four seconds for the E4B default.

2. In another terminal, test the server:

```bat
curl.exe http://127.0.0.1:8075/v1/models
```

3. Test transcription with an existing audio file:

```bat
ASSISTANT_SMALL\test_audio_transcription.bat C:\path\to\test.wav
```

4. Start OpenCode:

```bat
ASSISTANT_SMALL\start_opencode.bat
```

## Voice input workflow

Direct live microphone input inside OpenCode is not assumed to work. This patch uses a safer utterance-based flow:

```text
microphone -> short WAV -> /v1/audio/transcriptions -> clipboard -> paste into OpenCode
```

Run:

```bat
ASSISTANT_SMALL\voice_to_clipboard.bat 8
```

Speak for 8 seconds. The script copies the transcription to your clipboard. Paste it into OpenCode.

## ffmpeg requirement for microphone recording

`voice_to_clipboard.bat` needs `ffmpeg.exe` for microphone capture.

Put `ffmpeg.exe` in one of these places:

```text
runtime\ffmpeg\bin\ffmpeg.exe
ASSISTANT_SMALL\ffmpeg.exe
```

or make sure `ffmpeg.exe` is on PATH.

If default microphone capture fails, list devices:

```bat
ASSISTANT_SMALL\list_audio_devices.bat
```

Then set the exact device name:

```bat
set AUDIO_DEVICE=Microphone Array (Realtek(R) Audio)
ASSISTANT_SMALL\voice_to_clipboard.bat 8
```

## Local overrides

Copy:

```bat
local_settings_small.example.bat
```

to:

```bat
local_settings_small.bat
```

Then adjust GPU layers, model path, microphone name, or flags.

Useful overrides:

```bat
set "LLAMA_GPU_LAYERS=99"
set "MODEL_FILE=D:\vibe-coding-portable-kit\vibe-coding-portable\models\GEMMA_4_LAAARGE\gemma-4-E4B-it-Q4_K_M.gguf"
set "AUDIO_DEVICE=Microphone Array (Realtek(R) Audio)"
```

If your llama.cpp build errors on `--flash-attn`, set:

```bat
set "LLAMA_FLASH_ATTN=0"
```

If it errors on `--jinja`, set:

```bat
set "LLAMA_JINJA=0"
```
