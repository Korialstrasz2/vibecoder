# Qwen + llama.cpp image-input 500 troubleshooting notes

## What the 500 error means
If `llama-server` returns:

- `"image input is not supported - hint: if this is unexpected, you may need to provide the mmproj"`

it indicates the server did not have a usable multimodal projector (`mmproj`) loaded for the active model.

## Current upstream status (as of 2026-04-22)
- The Qwen team’s official `Qwen3.6` repo states `llama.cpp` supports Qwen3.6 text and vision.
- The `llama.cpp` multimodal docs describe vision support as requiring **two GGUF files** in typical cases: the base model GGUF and a matching `mmproj` GGUF.
- There are still model/backend-specific regressions in upstream `llama.cpp` issues (example: Qwen3.5-122B + mmproj issue #21268, opened 2026-04-01 and closed via #21271).

## How to use `mmproj` (where to put it)
Short answer: **yes**, you can store the `mmproj` GGUF in the same folder as your model GGUF.

Important detail: `llama-server` still needs the file path passed explicitly (typically via `--mmproj`).

### Recommended layout

```text
models/
  qwen3.6-vl/
    qwen3.6-vl-q4_k_m.gguf
    mmproj-qwen3.6-vl-f16.gguf
```

### Example launch commands

Linux/macOS:

```bash
./llama-server \
  --model /abs/path/models/qwen3.6-vl/qwen3.6-vl-q4_k_m.gguf \
  --mmproj /abs/path/models/qwen3.6-vl/mmproj-qwen3.6-vl-f16.gguf
```

Windows (PowerShell):

```powershell
.\llama-server.exe `
  --model "D:\models\qwen3.6-vl\qwen3.6-vl-q4_k_m.gguf" `
  --mmproj "D:\models\qwen3.6-vl\mmproj-qwen3.6-vl-f16.gguf"
```

If you only place `mmproj` beside the model but do **not** pass it, image input can still fail with the same 500 error.

## Practical checks
1. Start server with explicit `--mmproj /path/to/mmproj.gguf`.
2. Confirm logs include `loaded multimodal model` and vision encoder lines.
3. Ensure model + mmproj come from the same family/version (avoid mixing random community quants and projector files).
4. If using very new Qwen releases, test with latest llama.cpp build and then one known-good earlier build to detect regressions.

## Bottom line
Your error is consistent with a multimodal projector loading/matching problem (or a current upstream regression), not with "Qwen cannot do images" in principle.
