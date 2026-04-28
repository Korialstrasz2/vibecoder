@echo off
setlocal enabledelayedexpansion

rem Usage: start_server_with_params.bat <model_file> <context> <gpu_layers> <gpu_selection>
rem gpu_selection: "cpu" / "all" / GPU index like "0"
rem All interactive prompts in start_server.bat are skipped (CONTEXT_PROFILE=ui-profile).

cd /d "%~dp0"

if "%~1"=="" (
    echo [ERROR] Missing required parameters. Usage:
    echo   start_server_with_params.bat ^<model_file^> ^<context^> ^<gpu_layers^> ^<gpu_selection^>
    pause
    exit /b 1
)

set "MODEL_FILE=%~1"
set "LLAMA_CTX=%~2"
set "LLAMA_GPU_LAYERS=%~3"
set "CONTEXT_PROFILE=ui-profile"

set "GPU_SELECTION=%~4"

if /I "!GPU_SELECTION!"=="cpu" (
    set "CUDA_VISIBLE_DEVICES="
    set "GGML_CUDA_DEVICE="
) else if /I "!GPU_SELECTION!"=="all" (
    set "CUDA_VISIBLE_DEVICES="
    set "GGML_CUDA_DEVICE="
) else if not "!GPU_SELECTION!"=="" (
    set "CUDA_VISIBLE_DEVICES=!GPU_SELECTION!"
    set "GGML_CUDA_DEVICE=0"
)

echo [LAUNCHER] ========================================
echo [LAUNCHER] Starting server with UI-provided params:
echo [LAUNCHER]   MODEL:   !MODEL_FILE!
echo [LAUNCHER]   CTX:     !LLAMA_CTX!
echo [LAUNCHER]   GPU:     !LLAMA_GPU_LAYERS! layers
echo [LAUNCHER]   DEVICE:  !GPU_SELECTION!
echo [LAUNCHER] ========================================

call "start_server.bat"
