#!/usr/bin/env bash
# run-llama-qwen36-vision.sh
#
# Starts llama-server with Qwen3.6 vision-capable model support.
#
# Two modes:
#   A) Hugging Face auto-download:
#       ./scripts/run-llama-qwen36-vision.sh
#
#   B) Manual GGUF + mmproj paths (set env vars before running):
#       MODEL_GGUF=/path/to/model.gguf MMPROJ_GGUF=/path/to/mmproj.gguf \
#       ./scripts/run-llama-qwen36-vision.sh
#
# Environment variables:
#   LLAMA_HOST      - bind address (default: 127.0.0.1)
#   LLAMA_PORT      - port number (default: 8080)
#   LLAMA_CTX       - context window size (default: 32768)
#   LLAMA_GPU_LAYERS - number of layers to offload to GPU (default: 999)
#   MODEL_GGUF      - path to model GGUF file (for manual mode)
#   MMPROJ_GGUF     - path to mmproj GGUF file (for manual mode, required for vision)
#   LLAMA_EXE       - path to llama-server binary (default: llama-server)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

LLAMA_HOST="${LLAMA_HOST:-127.0.0.1}"
LLAMA_PORT="${LLAMA_PORT:-8080}"
LLAMA_CTX="${LLAMA_CTX:-32768}"
LLAMA_GPU_LAYERS="${LLAMA_GPU_LAYERS:-999}"
LLAMA_EXE="${LLAMA_EXE:-llama-server}"

# --- Mode A: Hugging Face auto-download ---
if [ -n "${MODEL_GGUF:-}" ] && [ -n "${MMPROJ_GGUF:-}" ]; then
    # --- Mode B: Manual GGUF + mmproj ---
    echo "=== llama-server: Manual GGUF mode ==="
    echo "Model GGUF : $MODEL_GGUF"
    echo "MMProj GGUF: $MMPROJ_GGUF"

    if [ ! -f "$MODEL_GGUF" ]; then
        echo "[ERROR] Model GGUF not found: $MODEL_GGUF"
        exit 1
    fi
    if [ ! -f "$MMPROJ_GGUF" ]; then
        echo "[ERROR] mmproj GGUF not found: $MMPROJ_GGUF"
        echo "Vision mode requires the mmproj (multimodal projector) file."
        echo "Download it from the same Hugging Face repo as your model."
        exit 1
    fi

    # Prepend ROOT_DIR paths if they are not absolute
    case "$MODEL_GGUF" in
        /*|\\*|[A-Za-z]:\\*) ;;
        *) MODEL_GGUF="$ROOT_DIR/$MODEL_GGUF" ;;
    esac
    case "$MMPROJ_GGUF" in
        /*|\\*|[A-Za-z]:\\*) ;;
        *) MMPROJ_GGUF="$ROOT_DIR/$MMPROJ_GGUF" ;;
    esac

    echo "Resolved Model GGUF : $MODEL_GGUF"
    echo "Resolved MMProj GGUF: $MMPROJ_GGUF"

    "$LLAMA_EXE" \
        -m "$MODEL_GGUF" \
        --mmproj "$MMPROJ_GGUF" \
        --host "$LLAMA_HOST" \
        --port "$LLAMA_PORT" \
        --ctx-size "$LLAMA_CTX" \
        --n-gpu-layers "$LLAMA_GPU_LAYERS" \
        --alias "qwen36-vision"
else
    # Hugging Face auto-download mode
    echo "=== llama-server: Hugging Face auto-download mode ==="
    echo "Repo: ggml-org/Qwen3.6-35B-A3B-GGUF"
    echo "This will auto-download the model and mmproj files."
    echo ""

    "$LLAMA_EXE" \
        -hf ggml-org/Qwen3.6-35B-A3B-GGUF \
        --host "$LLAMA_HOST" \
        --port "$LLAMA_PORT" \
        --ctx-size "$LLAMA_CTX" \
        --n-gpu-layers "$LLAMA_GPU_LAYERS" \
        --alias "qwen36-vision"
fi
