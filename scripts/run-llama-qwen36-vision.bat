@echo off
REM run-llama-qwen36-vision.bat
REM
REM Starts llama-server with Qwen3.6 vision-capable model support.
REM
REM Two modes:
REM   A) Hugging Face auto-download (no env vars needed):
REM       scripts\run-llama-qwen36-vision.bat
REM
REM   B) Manual GGUF + mmproj paths (set env vars before running):
REM       set MODEL_GGUF=C:\path\to\model.gguf
REM       set MMPROJ_GGUF=C:\path\to\mmproj.gguf
REM       scripts\run-llama-qwen36-vision.bat
REM
REM Environment variables:
REM   LLAMA_HOST       - bind address (default: 127.0.0.1)
REM   LLAMA_PORT       - port number (default: 8080)
REM   LLAMA_CTX        - context window size (default: 32768)
REM   LLAMA_GPU_LAYERS - layers to offload to GPU (default: 999)
REM   MODEL_GGUF       - path to model GGUF (manual mode)
REM   MMPROJ_GGUF      - path to mmproj GGUF (manual mode, required for vision)
REM   LLAMA_EXE        - path to llama-server.exe (default: runtime\llama.cpp\llama-server.exe)

setlocal EnableExtensions
cd /d "%~dp0.."

set "LLAMA_HOST=%LLAMA_HOST%"
set "LLAMA_PORT=%LLAMA_PORT%"
set "LLAMA_CTX=%LLAMA_CTX%"
set "LLAMA_GPU_LAYERS=%LLAMA_GPU_LAYERS%"
set "LLAMA_EXE=%LLAMA_EXE%"

if not defined LLAMA_HOST set "LLAMA_HOST=127.0.0.1"
if not defined LLAMA_PORT set "LLAMA_PORT=8080"
if not defined LLAMA_CTX set "LLAMA_CTX=32768"
if not defined LLAMA_GPU_LAYERS set "LLAMA_GPU_LAYERS=999"

if not defined LLAMA_EXE (
    if exist "runtime\llama.cpp\llama-server.exe" (
        set "LLAMA_EXE=runtime\llama.cpp\llama-server.exe"
    ) else if exist "runtime\llama.cpp\build\bin\llama-server.exe" (
        set "LLAMA_EXE=runtime\llama.cpp\build\bin\llama-server.exe"
    ) else (
        echo [ERROR] llama-server.exe not found.
        echo Place it in: runtime\llama.cpp\
        goto :fail
    )
)

REM --- Mode B: Manual GGUF + mmproj ---
if defined MODEL_GGUF if defined MMPROJ_GGUF (
    echo === llama-server: Manual GGUF mode ===
    echo Model GGUF : %MODEL_GGUF%
    echo MMProj GGUF: %MMPROJ_GGUF%

    if not exist "%MODEL_GGUF%" (
        echo [ERROR] Model GGUF not found: %MODEL_GGUF%
        goto :fail
    )
    if not exist "%MMPROJ_GGUF%" (
        echo [ERROR] mmproj GGUF not found: %MMPROJ_GGUF%
        echo Vision mode requires the mmproj (multimodal projector) file.
        echo Download it from the same Hugging Face repo as your model.
        goto :fail
    )

    echo Resolved Model GGUF : %MODEL_GGUF%
    echo Resolved MMProj GGUF: %MMPROJ_GGUF%
    echo.

    "%LLAMA_EXE%" ^
        -m "%MODEL_GGUF%" ^
        --mmproj "%MMPROJ_GGUF%" ^
        --host "%LLAMA_HOST%" ^
        --port "%LLAMA_PORT%" ^
        --ctx-size "%LLAMA_CTX%" ^
        --n-gpu-layers "%LLAMA_GPU_LAYERS%" ^
        --alias "qwen36-vision"
    goto :end
)

REM --- Mode A: Hugging Face auto-download ---
echo === llama-server: Hugging Face auto-download mode ===
echo Repo: ggml-org/Qwen3.6-35B-A3B-GGUF
echo This will auto-download the model and mmproj files.
echo.

"%LLAMA_EXE%" ^
    -hf ggml-org/Qwen3.6-35B-A3B-GGUF ^
    --host "%LLAMA_HOST%" ^
    --port "%LLAMA_PORT%" ^
    --ctx-size "%LLAMA_CTX%" ^
    --n-gpu-layers "%LLAMA_GPU_LAYERS%" ^
    --alias "qwen36-vision"

:end
pause
endlocal & exit /b 0

:fail
echo.
echo Script failed.
pause
endlocal & exit /b 1
