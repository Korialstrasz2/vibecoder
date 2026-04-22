# Vibe Coding Portable Kit - Windows + GGUF + llama.cpp + OpenCode/Aider

This folder is meant to be portable-ish.

Goal:

1. Put a GGUF model inside `models/`
2. Put `llama-server.exe` and its DLLs inside `runtime/llama.cpp/`
3. Run `start_server.bat`
4. Run `start_opencode.bat` or `start_aider.bat`
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
- Aider is installed in a local Python venv under `.venv-aider`.

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
  start_aider.bat
```

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

or:

```bat
start_aider.bat
```

## llama-server defaults

`start_server.bat` uses:

- host: 127.0.0.1
- port: 8080
- context: 32768
- GPU layers: 999
- model alias: qwen-local

OpenCode config points to:

```text
http://127.0.0.1:8080/v1
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

## Suggested first Aider prompt

```text
Create a new Python project from scratch.

Use:
- pyproject.toml
- src layout
- pytest
- ruff
- typer
- README.md

The app should do X.

Create all needed files, then run tests and fix problems.
```

## Notes

If tool calling behaves badly, reduce ambition:

- use shorter context, e.g. 16384 instead of 32768
- ask for smaller steps
- commit frequently
- use Aider if OpenCode gets too chaotic
