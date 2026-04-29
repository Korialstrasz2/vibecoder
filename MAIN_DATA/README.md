# Vibe Coding Portable Kit - Windows + GGUF + llama.cpp + OpenCode

This folder is meant to be portable-ish.

Goal:

1. Put a GGUF model inside `models/`
2. Put `llama-server.exe` and its DLLs inside `runtime/llama.cpp/`
3. Run `start_server.bat`
4. Run `start_opencode.bat`
5. Create apps inside `projects/`

Recommended model idea:

- Qwen 3.x / Qwen Coder GGUF, Q4_K_M or Q5_K_M
- With a RTX 3090 24 GB, Q4_K_M is a reasonable first test.
- If Qwen 3.6 35B-A3B Q4_K_M fits well, use it.
- If it is unstable or slow, use a Qwen Coder 14B/32B GGUF instead.

Important:

- This kit does not include the model or llama.cpp binaries.
- You must download them yourself.
- OpenCode is installed globally with npm by `setup_tools.bat`, unless already installed.

Expected structure:

```text
vibe-coding-portable/
  models/
    your-model.Q4_K_M.gguf
  runtime/
    llama.cpp/
      llama-server.exe
      *.dll
  projects/
  config/
    opencode/
      opencode.jsonc
  start_server.bat
  start_opencode.bat
```

## Launch with entrance UI (recommended)

Double-click `entrance.bat` (at the repository root). This starts a launcher API on `http://127.0.0.1:8765` and opens a web UI where you can:

- Select GPU target, context size, and model.
- See a VRAM fit estimate before launching.
- Launch **Main Server + OpenCode** and monitor startup progress in real time.
- Launch **Assistant Small** or **Connectors Server** with one click.

When launching Main Server + OpenCode, the launcher:
1. Generates the llama-server command with your chosen GPU, layers, and context.
2. Polls `http://127.0.0.1:8076/v1/models` until the server is healthy.
3. Verifies which GPU the server actually loaded on (logged in the monitor).
4. Launches OpenCode inside `projects\`.

Logs are written to `logs\` and can also be viewed live in the monitor panel.

## OpenCode + local models setup guide

If you want a focused walkthrough for connecting OpenCode to local models, see:

- [`OPENCODE_LOCAL_MODELS.md`](OPENCODE_LOCAL_MODELS.md)

## First run

1. Install NVIDIA drivers.
2. Install Node.js 18+ or 20+.
3. Install Python 3.11+ or 3.12.
4. Download a Windows CUDA build of llama.cpp.
5. Extract `llama-server.exe` and DLLs into `runtime/llama.cpp/`.
6. Download a `.gguf` model into `models/`.
7. Run:

```bat
setup_tools.bat
start_server.bat
```

In another terminal:

```bat
start_opencode.bat
```


## llama-server defaults

`start_server.bat` uses:

- host: 127.0.0.1
- port: 8076
- context: 32768
- GPU layers: 999
- model alias: qwen-local
- sampling defaults: temp 0.8, top_k 40, top_p 0.95, min_p 0.05, presence_penalty 0.0, repeat_penalty 1.0

`start_server.bat` auto-detects Qwen3.6 models by filename (`qwen3.6`, case-insensitive) and applies `qwen-coding-precise` defaults automatically.
For non-Qwen3.6 filenames, it keeps llama.cpp default-like sampling unless overridden in `local_settings.bat`.

OpenCode config points to:

```text
http://127.0.0.1:8076/v1
```

and model:

```text
llama.cpp/qwen-local
```

## Suggested first OpenCode prompt

```text
Create a complete Python CLI project from scratch inside this folder.

Goal:
Build a CLI app that [describe X].

Constraints:
- Python 3.12
- Use uv if available, otherwise venv + pip
- Use pyproject.toml
- Use src/ layout
- Use typer for the CLI
- Use pytest for tests
- Use ruff for linting
- Add README.md
- Keep the first version minimal but working
- Run tests and fix failures

Before editing files, propose the file structure.
```


## Side service voice assistant (ASSISTANT_SMALL)

A local side-service agent is available under [`ASSISTANT_SMALL/`](ASSISTANT_SMALL/README_AUDIO.md).

It provides:

- global hotkey trigger (`Ctrl+Win+Z`)
- local STT with whisper.cpp
- local router LLM (Qwen3 1.7B via Ollama/OpenAI-compatible endpoint)
- local Piper TTS
- whitelisted local action execution
- escalation action support (e.g., opening main OpenCode flow)

It also includes a predefined action script that starts `start_server.bat` with choices `1` then `3`, then opens OpenCode.

For Gemma 4 audio input support, see [`ASSISTANT_SMALL/README_AUDIO.md`](ASSISTANT_SMALL/README_AUDIO.md).

## Notes

If tool calling behaves badly, reduce ambition:

- use shorter context, e.g. 16384 instead of 32768
- ask for smaller steps
- commit frequently

## Qwen3.6 vision (OpenCode + llama.cpp)

For local multimodal (text + image) usage with OpenCode and llama-server, see:

- [`OPENCODE_LOCAL_MODELS.md`](OPENCODE_LOCAL_MODELS.md#opencode--qwen36-vision-with-local-llama-server)

Quick start:

```bash
./scripts/run-llama-qwen36-vision.sh
./scripts/smoke-test-vision-chat.sh
```
