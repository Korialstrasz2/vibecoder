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
- `run_small_assistant.bat`: creates venv, installs deps, runs assistant.
- `install_startup_task.bat`: installs a Windows startup scheduled task.

## Quick start

1. Edit `config.json` paths for:
   - `stt.whisper_cli_path`
   - `stt.model_path`
   - `tts.piper_exe`
   - `tts.piper_model`
2. Ensure local router endpoint is available (`router.base_url`, `router.model`).
3. Run:

```bat
SMALL_ASSISTANT\run_small_assistant.bat
```

Optional auto-start at login:

```bat
SMALL_ASSISTANT\install_startup_task.bat
```

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
