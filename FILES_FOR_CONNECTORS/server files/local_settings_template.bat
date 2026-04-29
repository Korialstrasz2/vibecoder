@echo off
rem Copy this file to MAIN_DATA\ as: local_settings.bat
rem Then edit model path/name if needed.

set "LLAMA_PORT=8076"
set "LLAMA_ALIAS=qwen-local"

rem Example: set exact model file to skip selector UI
rem set "MODEL_FILE=D:\models\qwen3-30b-a3b-instruct-2507-q4_k_m.gguf"

rem Optional: force 128k context
set "CONTEXT_PROFILE=ultra"

rem Optional: tune GPU offload
set "LLAMA_GPU_LAYERS=999"
