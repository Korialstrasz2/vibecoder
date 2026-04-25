@echo off
rem Copy this file to local_settings_small.bat and adjust values locally.
rem Do not commit your local_settings_small.bat if it contains machine-specific paths.

rem Network
set "LLAMA_HOST=127.0.0.1"
set "LLAMA_PORT=8075"

rem Context / GPU
set "LLAMA_CTX=16384"
rem Set to 99 or higher if your llama.cpp build/GPU can offload all layers.
set "LLAMA_GPU_LAYERS=0"

rem Multimodal/audio. Keep enabled for Gemma 4 E2B/E4B audio input.
set "LLAMA_ENABLE_MULTIMODAL=1"
set "LLAMA_REQUIRE_MMPROJ=1"

rem Gemma 4 generation defaults.
set "LLAMA_TEMPERATURE=1.0"
set "LLAMA_TOP_K=64"
set "LLAMA_TOP_P=0.95"
set "LLAMA_MIN_P=0.0"
set "LLAMA_PRESENCE_PENALTY=0.0"
set "LLAMA_REPEAT_PENALTY=1.0"

rem New llama.cpp builds support these. Set to 0 if your build errors on the flag.
set "LLAMA_JINJA=1"
set "LLAMA_FLASH_ATTN=on"

rem Optional: set a specific model file and skip the startup prompt.
rem set "MODEL_FILE=D:\vibe-coding-portable-kit\vibe-coding-portable\models\GEMMA_4_LAAARGE\gemma-4-E4B-it-Q4_K_M.gguf"

rem Optional: exact microphone name for voice_to_clipboard.bat.
rem Discover with list_audio_devices.bat.
rem set "AUDIO_DEVICE=Microphone Array (Realtek(R) Audio)"
