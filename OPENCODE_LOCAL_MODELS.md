# OpenCode + Local Models (llama.cpp) Setup Guide

This guide shows how to run OpenCode against a local llama.cpp server and how to verify settings in OpenCode.

## Prerequisites

- `start_server.bat` can start successfully.
- A `.gguf` model exists under `models\` (or `MODEL_FILE` is set in `local_settings.bat`).
- OpenCode is installed (`opencode` command works).

## 1) Start the local model server

From this folder:

```bat
start_server.bat
```

When healthy, your local OpenAI-compatible endpoint is typically:

- Base URL: `http://127.0.0.1:8080/v1`

## 2) Install the OpenCode config

Option A (automatic, recommended):

```bat
start_all.bat
```

This copies `config\opencode\opencode.jsonc` into:

- `%APPDATA%\opencode\opencode.jsonc`

Option B (manual):

- Copy `config\opencode\opencode.jsonc` to `%APPDATA%\opencode\opencode.jsonc` yourself.

## 3) Open OpenCode

Run:

```bat
start_opencode.bat
```

Or run `opencode` directly in your working project folder.

## 4) Configure provider/model in OpenCode settings

Inside OpenCode:

1. Open **Settings**.
2. Go to **Providers** (or equivalent model/provider settings screen).
3. Confirm there is a local llama.cpp/OpenAI-compatible provider entry.
4. Set/check:
   - **Base URL**: `http://127.0.0.1:8080/v1`
   - **Model**: `llama.cpp/qwen-local`
5. Save settings.

> Tip: If your alias in `start_server.bat` (or `local_settings.bat`) is not `qwen-local`, use your actual alias in OpenCode.

## 5) Quick validation

- In OpenCode, start a small prompt (for example: `say hello in one sentence`).
- If it responds, your local model wiring works.
- If it fails, check:
  - `logs\startup_*.log`
  - `logs\llama_server_*.log`
  - Server URL/model alias consistency between server and OpenCode settings.

## 6) Common adjustments (local_settings.bat)

You can create/update `local_settings.bat` in the repo root and set values such as:

```bat
set LLAMA_HOST=127.0.0.1
set LLAMA_PORT=8080
set LLAMA_CTX=32768
set LLAMA_GPU_LAYERS=999
set LLAMA_ALIAS=qwen-local
set MODEL_FILE=C:\path\to\your-model.gguf
```

Then restart `start_server.bat` (or `start_all.bat`) and keep OpenCode model settings aligned with `LLAMA_ALIAS`.

## 7) Recommended daily workflow

1. `start_all.bat`
2. Wait for the health check to pass.
3. Work inside `projects\` with OpenCode.
4. If you change model alias/port, restart server and re-check OpenCode Settings.

## OpenCode + Qwen3.6 vision with local llama-server

### Start llama-server (image-capable)

Use the new script from this repository root:

```bash
# Mode A: Hugging Face mode (llama.cpp auto-handles required files when supported)
./scripts/run-llama-qwen36-vision.sh

# Mode B: Manual GGUF mode (set both model + mmproj)
LLAMA_MODE=gguf \
MODEL_GGUF=/path/to/model.gguf \
MMPROJ_GGUF=/path/to/mmproj.gguf \
./scripts/run-llama-qwen36-vision.sh
```

Equivalent llama-server commands:

```bash
llama-server -hf ggml-org/Qwen3.6-35B-A3B-GGUF --host 127.0.0.1 --port 8080
```

```bash
llama-server -m "$MODEL_GGUF" --mmproj "$MMPROJ_GGUF" --host 127.0.0.1 --port 8080
```

### Start OpenCode

Run OpenCode after your server is up:

```bat
start_opencode.bat
```

or run `opencode` directly in your active project folder.

### Verify image input works

Run the smoke test:

```bash
./scripts/smoke-test-vision-chat.sh
```

It posts a text + image request to `http://127.0.0.1:8080/v1/chat/completions`.

### If OpenCode says the model does not support images

Most likely fixes:

1. Ensure the OpenCode model entry includes:
   - `"modalities": { "input": ["text", "image"], "output": ["text"] }`
2. If using manual GGUF mode, confirm `--mmproj` is provided and points to a valid multimodal projector GGUF.
3. Confirm OpenCode is using the expected model id (`llama.cpp/qwen3.6-vision`) and base URL (`http://127.0.0.1:8080/v1`).
4. Restart llama-server and OpenCode after config changes.

### `model_vision` folder behavior (Windows starter scripts)

`start_server.bat` automatically looks for a projector GGUF in `model_vision\`:

1. First it tries to match by filename against your selected base model.
2. If no match is found, it picks the first file with `mmproj` in the name.
3. If there is still no `mmproj`-named file, it falls back to the first `.gguf` in `model_vision\` and logs a warning.

For best results, keep a single projector file in `model_vision\` and include `mmproj` in the filename (for example `mmproj-qwen3.6-35b-f16.gguf`).
