#!/usr/bin/env bash
set -euo pipefail

HOST="${LLAMA_HOST:-127.0.0.1}"
PORT="${LLAMA_PORT:-8080}"
HF_REPO="${HF_REPO:-ggml-org/Qwen3.6-35B-A3B-GGUF}"
MODE="${LLAMA_MODE:-hf}"

if ! command -v llama-server >/dev/null 2>&1; then
  echo "Error: llama-server not found in PATH." >&2
  exit 1
fi

case "$MODE" in
  hf)
    echo "Starting llama-server in Hugging Face mode"
    echo "Command: llama-server -hf $HF_REPO --host $HOST --port $PORT"
    exec llama-server -hf "$HF_REPO" --host "$HOST" --port "$PORT"
    ;;
  gguf)
    : "${MODEL_GGUF:?MODEL_GGUF is required when LLAMA_MODE=gguf}"
    : "${MMPROJ_GGUF:?MMPROJ_GGUF is required when LLAMA_MODE=gguf}"

    echo "Starting llama-server in manual GGUF mode"
    echo "Command: llama-server -m $MODEL_GGUF --mmproj $MMPROJ_GGUF --host $HOST --port $PORT"
    exec llama-server -m "$MODEL_GGUF" --mmproj "$MMPROJ_GGUF" --host "$HOST" --port "$PORT"
    ;;
  *)
    echo "Invalid LLAMA_MODE='$MODE'. Use 'hf' or 'gguf'." >&2
    exit 1
    ;;
esac
