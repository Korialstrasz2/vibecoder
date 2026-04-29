@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"

rem =============================================================================
rem start_server_with_params.bat
rem
rem Fully standalone server launcher -- does NOT delegate to start_server.bat.
rem All parameters are passed as command-line arguments. No interactive prompts.
rem
rem Usage:
rem   start_server_with_params.bat <model_file> <context> <gpu_layers> <gpu_selection>
rem
rem   model_file     -- absolute or relative path to a .gguf model
rem   context        -- context size in tokens (e.g. 32768)
rem   gpu_layers     -- number of layers to offload to GPU (0 = CPU)
rem   gpu_selection  -- "cpu", "all", or a GPU index like "0"
rem
rem This file works independently from start_server.bat.
rem =============================================================================

set "LOG_FILE=%~dp0start_server_with_params.log"

rem --- Check required args ---
if "%~1"=="" (
    echo [ERROR] Missing required parameters.
    echo Usage: start_server_with_params.bat ^<model_file^> ^<context^> ^<gpu_layers^> ^<gpu_selection^>
    pause
    exit /b 1
)

echo [%DATE% %TIME%] ==========================================>>"!LOG_FILE!"
echo [%DATE% %TIME%] start_server_with_params.bat launched>>"!LOG_FILE!"
echo [%DATE% %TIME%] ==========================================>>"!LOG_FILE!"

set "MODEL_FILE=%~1"
set "LLAMA_CTX=%~2"
set "LLAMA_GPU_LAYERS=%~3"
set "GPU_SELECTION=%~4"

echo [%DATE% %TIME%] MODEL_FILE=!MODEL_FILE!>>"!LOG_FILE!"
echo [%DATE% %TIME%] LLAMA_CTX=!LLAMA_CTX!>>"!LOG_FILE!"
echo [%DATE% %TIME%] LLAMA_GPU_LAYERS=!LLAMA_GPU_LAYERS!>>"!LOG_FILE!"
echo [%DATE% %TIME%] GPU_SELECTION=!GPU_SELECTION!>>"!LOG_FILE!"

rem --- Apply GPU selection (CUDA_VISIBLE_DEVICES) ---
rem NOTE: GGML_CUDA_DEVICE is intentionally NOT set here.
rem CUDA_VISIBLE_DEVICES handles both numeric indices and GPU UUIDs (e.g. GPU-xxxxxxxx).
rem Setting GGML_CUDA_DEVICE=0 on top of CUDA_VISIBLE_DEVICES is redundant and can
rem cause the wrong physical GPU to be selected in multi-GPU / eGPU setups.
if /I "!GPU_SELECTION!"=="cpu" (
    set "CUDA_VISIBLE_DEVICES="
) else if /I "!GPU_SELECTION!"=="all" (
    set "CUDA_VISIBLE_DEVICES="
) else if not "!GPU_SELECTION!"=="" (
    set "CUDA_VISIBLE_DEVICES=!GPU_SELECTION!"
)

rem --- Load optional local_settings overrides ---
if exist "local_settings.bat" (
    echo [%DATE% %TIME%] Loading local_settings.bat>>"!LOG_FILE!"
    call "local_settings.bat"
) else (
    echo [%DATE% %TIME%] No local_settings.bat found, using defaults>>"!LOG_FILE!"
)

rem --- Defaults (can be overridden by local_settings.bat) ---
if not defined LLAMA_HOST set "LLAMA_HOST=127.0.0.1"
if not defined LLAMA_PORT set "LLAMA_PORT=8076"
if not defined LLAMA_ALIAS set "LLAMA_ALIAS=qwen-local"
if not defined LLAMA_EXE set "LLAMA_EXE=%CD%\runtime\llama.cpp\llama-server.exe"
if not defined LLAMA_ENABLE_VISION set "LLAMA_ENABLE_VISION=1"

rem --- Resolve llama-server.exe ---
if exist "!LLAMA_EXE!" (
    echo [%DATE% %TIME%] Found llama-server.exe at "!LLAMA_EXE!">>"!LOG_FILE!"
) else if exist "%CD%\runtime\llama.cpp\build\bin\llama-server.exe" (
    set "LLAMA_EXE=%CD%\runtime\llama.cpp\build\bin\llama-server.exe"
    echo [%DATE% %TIME%] Fallback llama-server.exe at "!LLAMA_EXE!">>"!LOG_FILE!"
) else (
    echo [%DATE% %TIME%] ERROR: llama-server.exe not found>>"!LOG_FILE!"
    echo [ERROR] llama-server.exe not found.
    echo Checked:
    echo   "!LLAMA_EXE!"
    echo   "%CD%\runtime\llama.cpp\build\bin\llama-server.exe"
    echo Set LLAMA_EXE in local_settings.bat or place llama-server.exe in:
    echo   runtime\llama.cpp\
    echo   or runtime\llama.cpp\build\bin\
    pause
    exit /b 1
)

for %%I in ("!LLAMA_EXE!") do set "LLAMA_EXE_DIR=%%~dpI"
echo [%DATE% %TIME%] LLAMA_EXE_DIR="!LLAMA_EXE_DIR!">>"!LOG_FILE!"

rem --- Verify model file exists ---
if not exist "!MODEL_FILE!" (
    echo [%DATE% %TIME%] ERROR: MODEL_FILE not found: "!MODEL_FILE!">>"!LOG_FILE!"
    echo [ERROR] Model file does not exist:
    echo   "!MODEL_FILE!"
    pause
    exit /b 1
)

for %%I in ("!MODEL_FILE!") do set "MODEL_FILE_NAME=%%~nxI"
echo [%DATE% %TIME%] MODEL_FILE_NAME=!MODEL_FILE_NAME!>>"!LOG_FILE!"

rem --- Sampling profile auto-detection (based on model filename) ---
if not defined LLAMA_SAMPLING_PROFILE (
    echo !MODEL_FILE_NAME! | findstr /I /C:"qwen3.6" >nul
    if not errorlevel 1 (
        set "LLAMA_SAMPLING_PROFILE=qwen-coding-precise"
        echo [%DATE% %TIME%] Auto-selected LLAMA_SAMPLING_PROFILE=qwen-coding-precise>>"!LOG_FILE!"
    ) else (
        echo [%DATE% %TIME%] No Qwen3.6 marker in model filename, keeping defaults>>"!LOG_FILE!"
    )
)

if /I "!LLAMA_SAMPLING_PROFILE!"=="qwen-thinking-general" (
    if not defined LLAMA_TEMPERATURE set "LLAMA_TEMPERATURE=1.0"
    if not defined LLAMA_TOP_K set "LLAMA_TOP_K=20"
    if not defined LLAMA_TOP_P set "LLAMA_TOP_P=0.95"
    if not defined LLAMA_MIN_P set "LLAMA_MIN_P=0.0"
    if not defined LLAMA_PRESENCE_PENALTY set "LLAMA_PRESENCE_PENALTY=1.5"
    if not defined LLAMA_REPEAT_PENALTY set "LLAMA_REPEAT_PENALTY=1.0"
) else if /I "!LLAMA_SAMPLING_PROFILE!"=="qwen-coding-precise" (
    if not defined LLAMA_TEMPERATURE set "LLAMA_TEMPERATURE=0.6"
    if not defined LLAMA_TOP_K set "LLAMA_TOP_K=20"
    if not defined LLAMA_TOP_P set "LLAMA_TOP_P=0.95"
    if not defined LLAMA_MIN_P set "LLAMA_MIN_P=0.0"
    if not defined LLAMA_PRESENCE_PENALTY set "LLAMA_PRESENCE_PENALTY=0.0"
    if not defined LLAMA_REPEAT_PENALTY set "LLAMA_REPEAT_PENALTY=1.0"
) else if /I "!LLAMA_SAMPLING_PROFILE!"=="qwen-instruct-general" (
    if not defined LLAMA_TEMPERATURE set "LLAMA_TEMPERATURE=0.7"
    if not defined LLAMA_TOP_K set "LLAMA_TOP_K=20"
    if not defined LLAMA_TOP_P set "LLAMA_TOP_P=0.8"
    if not defined LLAMA_MIN_P set "LLAMA_MIN_P=0.0"
    if not defined LLAMA_PRESENCE_PENALTY set "LLAMA_PRESENCE_PENALTY=1.5"
    if not defined LLAMA_REPEAT_PENALTY set "LLAMA_REPEAT_PENALTY=1.0"
) else if /I "!LLAMA_SAMPLING_PROFILE!"=="llama-defaults" (
    if not defined LLAMA_TEMPERATURE set "LLAMA_TEMPERATURE=0.8"
    if not defined LLAMA_TOP_K set "LLAMA_TOP_K=40"
    if not defined LLAMA_TOP_P set "LLAMA_TOP_P=0.95"
    if not defined LLAMA_MIN_P set "LLAMA_MIN_P=0.05"
    if not defined LLAMA_PRESENCE_PENALTY set "LLAMA_PRESENCE_PENALTY=0.0"
    if not defined LLAMA_REPEAT_PENALTY set "LLAMA_REPEAT_PENALTY=1.0"
)

rem --- Universal fallback defaults ---
if not defined LLAMA_TEMPERATURE set "LLAMA_TEMPERATURE=0.8"
if not defined LLAMA_TOP_K set "LLAMA_TOP_K=40"
if not defined LLAMA_TOP_P set "LLAMA_TOP_P=0.95"
if not defined LLAMA_MIN_P set "LLAMA_MIN_P=0.05"
if not defined LLAMA_PRESENCE_PENALTY set "LLAMA_PRESENCE_PENALTY=0.0"
if not defined LLAMA_REPEAT_PENALTY set "LLAMA_REPEAT_PENALTY=1.0"

echo [%DATE% %TIME%] LLAMA_SAMPLING_PROFILE=!LLAMA_SAMPLING_PROFILE!>>"!LOG_FILE!"

rem --- Resolve mmproj for vision (optional) ---
set "MMPROJ_FILE_RESOLVED="

if /I "!LLAMA_ENABLE_VISION!"=="0" (
    echo [%DATE% %TIME%] LLAMA_ENABLE_VISION=0, skipping mmproj detection>>"!LOG_FILE!"
) else (
    if defined MMPROJ_FILE (
        if exist "!MMPROJ_FILE!" (
            set "MMPROJ_FILE_RESOLVED=!MMPROJ_FILE!"
            echo [%DATE% %TIME%] MMPROJ preset: "!MMPROJ_FILE!">>"!LOG_FILE!"
        ) else (
            echo [%DATE% %TIME%] WARNING: preset MMPROJ_FILE not found: "!MMPROJ_FILE!">>"!LOG_FILE!"
            echo [WARN] MMPROJ_FILE was set but does not exist: "!MMPROJ_FILE!"
        )
    )

    if not defined MMPROJ_FILE_RESOLVED (
        rem Try same directory as model
        for %%I in ("!MODEL_FILE!") do set "MODEL_DIR=%%~dpI"
        if exist "!MODEL_DIR!" (
            for %%F in ("!MODEL_DIR!*mmproj*.gguf") do (
                if exist "%%~fF" if not defined MMPROJ_FILE_RESOLVED (
                    set "MMPROJ_FILE_RESOLVED=%%~fF"
                    echo [%DATE% %TIME%] MMPROJ same-folder: "%%~fF">>"!LOG_FILE!"
                )
            )
        )
    )

    if not defined MMPROJ_FILE_RESOLVED (
        call :try_mmproj_family "%CD%\model_vision"
        if not defined MMPROJ_FILE_RESOLVED call :try_mmproj_family "%CD%\models"
    )

    if not defined MMPROJ_FILE_RESOLVED (
        echo [%DATE% %TIME%] No compatible mmproj found; server will start text-only>>"!LOG_FILE!"
        echo [WARN] No compatible vision projector found.
        echo        Starting text-only to avoid loading the wrong projector.
        echo        To force vision, set MMPROJ_FILE in local_settings.bat.
    ) else (
        echo [INFO] Vision projector: "!MMPROJ_FILE_RESOLVED!"
    )
)

rem --- Update opencode.jsonc context limit ---
if exist "%CD%\config\opencode\opencode.jsonc" (
    echo [%DATE% %TIME%] Updating opencode.jsonc context limit to !LLAMA_CTX!>>"!LOG_FILE!"
    powershell -NoProfile -Command ^
      "$p='%CD%\config\opencode\opencode.jsonc';" ^
      "$text = Get-Content -Raw $p;" ^
      "$updated = [regex]::Replace($text, '\"context\"\s*:\s*\d+', ('\"context\": ' + !LLAMA_CTX!));" ^
      "Set-Content -Path $p -Value $updated;"
    if errorlevel 1 (
        echo [%DATE% %TIME%] WARNING: failed to update opencode.jsonc context>>"!LOG_FILE!"
    ) else (
        echo [%DATE% %TIME%] opencode.jsonc context updated>>"!LOG_FILE!"
    )
) else (
    echo [%DATE% %TIME%] WARNING: config\opencode\opencode.jsonc not found>>"!LOG_FILE!"
)

rem --- Display summary ---
echo.
echo === Starting llama-server (standalone launcher) ===
echo Model:       !MODEL_FILE!
echo URL:         http://!LLAMA_HOST!:!LLAMA_PORT!/v1
echo Models API:  http://!LLAMA_HOST!:!LLAMA_PORT!/v1/models
echo Ctx:         !LLAMA_CTX!
echo GPU layers:  !LLAMA_GPU_LAYERS!
echo Alias:       !LLAMA_ALIAS!
if defined LLAMA_SAMPLING_PROFILE echo Sampling:    !LLAMA_SAMPLING_PROFILE!
if defined LLAMA_TEMPERATURE echo Temp:        !LLAMA_TEMPERATURE!
if defined LLAMA_TOP_K echo Top-K:       !LLAMA_TOP_K!
if defined LLAMA_TOP_P echo Top-P:       !LLAMA_TOP_P!
if defined LLAMA_MIN_P echo Min-P:       !LLAMA_MIN_P!
if defined LLAMA_PRESENCE_PENALTY echo Presence:    !LLAMA_PRESENCE_PENALTY!
if defined LLAMA_REPEAT_PENALTY echo Repeat:      !LLAMA_REPEAT_PENALTY!
echo Log:         "!LOG_FILE!"
echo.

rem --- Launch llama-server directly (no delegation) ---
pushd "!LLAMA_EXE_DIR!" >nul 2>&1
if errorlevel 1 (
    echo [%DATE% %TIME%] ERROR: Could not enter directory "!LLAMA_EXE_DIR!">>"!LOG_FILE!"
    echo [ERROR] Could not change to directory:
    echo   "!LLAMA_EXE_DIR!"
    pause
    exit /b 1
)

if defined MMPROJ_FILE_RESOLVED (
    "!LLAMA_EXE!" ^
      --model "!MODEL_FILE!" ^
      --mmproj "!MMPROJ_FILE_RESOLVED!" ^
      --host "!LLAMA_HOST!" ^
      --port "!LLAMA_PORT!" ^
      --ctx-size "!LLAMA_CTX!" ^
      --n-gpu-layers "!LLAMA_GPU_LAYERS!" ^
      --alias "!LLAMA_ALIAS!" ^
      --temp "!LLAMA_TEMPERATURE!" ^
      --top-k "!LLAMA_TOP_K!" ^
      --top-p "!LLAMA_TOP_P!" ^
      --min-p "!LLAMA_MIN_P!" ^
      --presence-penalty "!LLAMA_PRESENCE_PENALTY!" ^
      --repeat-penalty "!LLAMA_REPEAT_PENALTY!"
) else (
    "!LLAMA_EXE!" ^
      --model "!MODEL_FILE!" ^
      --host "!LLAMA_HOST!" ^
      --port "!LLAMA_PORT!" ^
      --ctx-size "!LLAMA_CTX!" ^
      --n-gpu-layers "!LLAMA_GPU_LAYERS!" ^
      --alias "!LLAMA_ALIAS!" ^
      --temp "!LLAMA_TEMPERATURE!" ^
      --top-k "!LLAMA_TOP_K!" ^
      --top-p "!LLAMA_TOP_P!" ^
      --min-p "!LLAMA_MIN_P!" ^
      --presence-penalty "!LLAMA_PRESENCE_PENALTY!" ^
      --repeat-penalty "!LLAMA_REPEAT_PENALTY!"
)

set "SERVER_EXIT=!ERRORLEVEL!"
popd >nul 2>&1

echo [%DATE% %TIME%] llama-server exited with code !SERVER_EXIT!>>"!LOG_FILE!"
echo.
echo Server exited with code !SERVER_EXIT!.
echo Log: "!LOG_FILE!"
pause
exit /b !SERVER_EXIT!

rem ────────────────────────────────────────────────────────────
rem :try_mmproj_family  -- auto-detect mmproj by model family
rem ────────────────────────────────────────────────────────────
:try_mmproj_family
if not exist "%~1" exit /b 0

echo !MODEL_FILE_NAME! | findstr /I /C:"gemma" >nul
if not errorlevel 1 (
    for /r "%~1" %%F in (*gemma*mmproj*.gguf mmproj*gemma*.gguf) do (
        if not defined MMPROJ_FILE_RESOLVED (
            set "MMPROJ_FILE_RESOLVED=%%~fF"
            echo [%DATE% %TIME%] MMPROJ family-gemma: "%%~fF">>"!LOG_FILE!"
        )
    )
    if defined MMPROJ_FILE_RESOLVED exit /b 0
)

echo !MODEL_FILE_NAME! | findstr /I /C:"Qwen3.6-27B" >nul
if not errorlevel 1 (
    for /r "%~1" %%F in (*Qwen3.6-27B*mmproj*.gguf mmproj*Qwen3.6-27B*.gguf) do (
        if not defined MMPROJ_FILE_RESOLVED (
            set "MMPROJ_FILE_RESOLVED=%%~fF"
            echo [%DATE% %TIME%] MMPROJ family-qwen3.6-27b: "%%~fF">>"!LOG_FILE!"
        )
    )
    if defined MMPROJ_FILE_RESOLVED exit /b 0
)

echo !MODEL_FILE_NAME! | findstr /I /C:"Qwen3.6-35B" >nul
if not errorlevel 1 (
    for /r "%~1" %%F in (*Qwen3.6-35B*mmproj*.gguf mmproj*Qwen3.6-35B*.gguf *35B*mmproj*.gguf mmproj*35B*.gguf mmproj-BF16.gguf) do (
        if not defined MMPROJ_FILE_RESOLVED (
            set "MMPROJ_FILE_RESOLVED=%%~fF"
            echo [%DATE% %TIME%] MMPROJ family-qwen3.6-35b: "%%~fF">>"!LOG_FILE!"
        )
    )
    if defined MMPROJ_FILE_RESOLVED exit /b 0
)

echo !MODEL_FILE_NAME! | findstr /I /C:"27B" >nul
if not errorlevel 1 (
    for /r "%~1" %%F in (*27B*mmproj*.gguf mmproj*27B*.gguf) do (
        if not defined MMPROJ_FILE_RESOLVED (
            set "MMPROJ_FILE_RESOLVED=%%~fF"
            echo [%DATE% %TIME%] MMPROJ size-27b: "%%~fF">>"!LOG_FILE!"
        )
    )
    if defined MMPROJ_FILE_RESOLVED exit /b 0
)

echo !MODEL_FILE_NAME! | findstr /I /C:"35B" >nul
if not errorlevel 1 (
    for /r "%~1" %%F in (*35B*mmproj*.gguf mmproj*35B*.gguf mmproj-BF16.gguf) do (
        if not defined MMPROJ_FILE_RESOLVED (
            set "MMPROJ_FILE_RESOLVED=%%~fF"
            echo [%DATE% %TIME%] MMPROJ size-35b: "%%~fF">>"!LOG_FILE!"
        )
    )
    if defined MMPROJ_FILE_RESOLVED exit /b 0
)

exit /b 0
