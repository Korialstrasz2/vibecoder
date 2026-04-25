# SMALL_ASSISTANT (side service agent)

This folder adds a **fully local/offline-capable side service assistant** for Windows.

## Core behavior implemented

1. Press `Ctrl+Win+Z`.
2. Assistant listens for a short utterance.
3. Audio is transcribed with `whisper.cpp` (local).
4. Transcript is sent to a small local LLM router (`Qwen3 1.7B` via Ollama/OpenAI-compatible endpoint).
5. Router returns structured JSON decision.
6. Service either answers, speaks via local TTS, executes a whitelisted action, or escalates.

## Privacy defaults

- No cloud speech APIs are used.
- Microsoft online voice typing is **not** used.
- STT default: `whisper.cpp` local.
- TTS default: `Piper` local.
- Windows SAPI fallback exists but is disabled by default.
- Works offline after dependencies and models are already installed locally.

## Files

- `small_assistant_service.py`: hotkey service + STT + local router + action executor.
- `config.json`: all runtime parameters and whitelisted actions.
- `actions/start_qwen_low_context_and_opencode.bat`: starts server with menu choices `1` then `3`, then opens OpenCode.
- `first_install.bat`: first-time setup script that installs Python dependencies into `SMALL_ASSISTANT\.venv` only.
- `run_small_assistant.bat`: creates venv, installs deps, runs assistant.
- `install_startup_task.bat`: installs a Windows startup scheduled task.

## Quick start

1. Run first-time setup:

```bat
SMALL_ASSISTANT\first_install.bat
```

`first_install.bat` can open browser windows for required downloads (Python, whisper.cpp, Whisper models, Piper, Ollama), then prepares `SMALL_ASSISTANT\.venv`.

2. Edit `config.json` paths for:
   - `stt.whisper_cli_path`
   - `stt.model_path`
   - `tts.piper_exe`
   - `tts.piper_model`
3. Ensure local router endpoint is available (`router.base_url`, `router.model`).
4. Run:

```bat
SMALL_ASSISTANT\run_small_assistant.bat
```

Optional auto-start at login:

```bat
SMALL_ASSISTANT\install_startup_task.bat
```

## ASAP enablement checklist (Windows)

1. Install Python 3.11+ and verify `py -3` works in `cmd`.
2. Run `first_install.bat` to create and use `SMALL_ASSISTANT\.venv` without modifying the main project environment.
3. Install local runtime dependencies:
   - `whisper.cpp` CLI binary (`main.exe`)
   - a local Whisper model (`.bin`)
   - Piper TTS (`piper.exe` + voice `.onnx` + `.onnx.json`)
   - a local OpenAI-compatible router endpoint (default: Ollama at `http://127.0.0.1:11434/v1`)
4. Update all absolute paths in `config.json` for STT/TTS.
5. Confirm the router model exists (`qwen3:1.7b-instruct` by default).
6. Start service with `run_small_assistant.bat`.
7. Press `Ctrl+Win+Z` and speak.

If the assistant should open OpenCode when needed, keep the default escalation command and ensure `..\start_opencode.bat` works from this repo root.

## Integration model

### With the PC user

- Trigger: global hotkey (`Ctrl+Win+Z`).
- Input: microphone capture for `listen_seconds` (default 5s).
- Output:
  - console text response
  - optional local TTS playback
  - optional action execution
  - optional escalation to OpenCode launcher

### With OpenCode (inside SMALL_ASSISTANT)

- There is no standalone OpenCode config inside `SMALL_ASSISTANT/`.
- The assistant integrates by invoking repo-level scripts:
  - `..\start_opencode.bat` for escalation/open action
  - `actions\start_qwen_low_context_and_opencode.bat` for a guided server+OpenCode startup flow

### With the main OpenCode in the vibe-coding-portable folder

- `start_opencode.bat` copies `config/opencode/opencode.jsonc` into the user config directory and launches OpenCode.
- Therefore, SMALL_ASSISTANT uses the same "main" OpenCode install and provider configuration as the rest of this kit.
- The assistant does not run a second OpenCode backend; it orchestrates the existing one.

## Router JSON contract

The local LLM router is expected to return JSON only:

```json
{
  "action": "answer | speak | execute | escalate",
  "response_text": "text to show/say",
  "tts": false,
  "command_name": "optional_whitelisted_action",
  "reason": "short rationale"
}
```

## Whitelisted action example

`start_qwen_low_context_and_opencode` runs:

- `start_server.bat` with scripted menu inputs:
  - first choice: `1`
  - second choice: `3`
- then launches `start_opencode.bat`

You can add more actions in `config.json` under `actions`.
