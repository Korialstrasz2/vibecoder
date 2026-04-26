@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"

set "ROOT_DIR=%~dp0.."
for %%I in ("%ROOT_DIR%") do set "ROOT_DIR=%%~fI"

set "LOG_FILE=%~dp0system\logs\start_server.log"
if not exist "%~dp0system\logs" mkdir "%~dp0system\logs"
if not exist "%~dp0system\cache" mkdir "%~dp0system\cache"

call :log ==========================================
call :log Starting ASSISTANT_LARGE Gemma 4 llama-server launcher in "%CD%"
call :log Root dir: %ROOT_DIR%
call :log Timestamp: %DATE% %TIME%

rem --- Load optional overrides from repo root first ---
if exist "%ROOT_DIR%\local_settings.bat" (
    call :log Found %ROOT_DIR%\local_settings.bat, loading it
    call "%ROOT_DIR%\local_settings.bat"
)

rem --- Load optional assistant-specific overrides ---
if exist "%~dp0local_settings_large.bat" (
    call :log Found local_settings_large.bat, loading it
    call "%~dp0local_settings_large.bat"
) else (
    call :log local_settings_large.bat not found beside launcher; continuing with auto-detection
)

rem --- Fixed defaults ---
if not defined LLAMA_HOST set "LLAMA_HOST=127.0.0.1"
if not defined LLAMA_PORT set "LLAMA_PORT=8075"
if not defined LLAMA_CTX set "LLAMA_CTX=16384"
if not defined LLAMA_GPU_LAYERS set "LLAMA_GPU_LAYERS=0"
if not defined LLAMA_ALIAS set "LLAMA_ALIAS=gemma-4-local-audio"
if not defined LLAMA_EXE set "LLAMA_EXE=%ROOT_DIR%\runtime\llama.cpp\llama-server.exe"
if not defined LLAMA_ENABLE_MULTIMODAL set "LLAMA_ENABLE_MULTIMODAL=1"
if not defined LLAMA_REQUIRE_MMPROJ set "LLAMA_REQUIRE_MMPROJ=1"
if not defined LLAMA_JINJA set "LLAMA_JINJA=1"
if not defined LLAMA_FLASH_ATTN set "LLAMA_FLASH_ATTN=on"

rem =========================
rem CPU / GPU SELECTION
rem =========================
rem Default is CPU if no key is pressed within 4 seconds.
rem Press ENTER or type G/2 to use GPU. Type C/1 to force CPU.
if not defined ASSISTANT_SKIP_ACCEL_PROMPT (
    call :select_acceleration
)


rem --- Gemma 4 recommended-ish generation defaults ---
if not defined LLAMA_TEMPERATURE set "LLAMA_TEMPERATURE=1.0"
if not defined LLAMA_TOP_K set "LLAMA_TOP_K=64"
if not defined LLAMA_TOP_P set "LLAMA_TOP_P=0.95"
if not defined LLAMA_MIN_P set "LLAMA_MIN_P=0.0"
if not defined LLAMA_PRESENCE_PENALTY set "LLAMA_PRESENCE_PENALTY=0.0"
if not defined LLAMA_REPEAT_PENALTY set "LLAMA_REPEAT_PENALTY=1.0"

call :log LLAMA_HOST=!LLAMA_HOST!
call :log LLAMA_PORT=!LLAMA_PORT!
call :log LLAMA_CTX=!LLAMA_CTX!
call :log LLAMA_GPU_LAYERS=!LLAMA_GPU_LAYERS!
call :log LLAMA_ALIAS=!LLAMA_ALIAS!
call :log LLAMA_ENABLE_MULTIMODAL=!LLAMA_ENABLE_MULTIMODAL!
call :log LLAMA_REQUIRE_MMPROJ=!LLAMA_REQUIRE_MMPROJ!
call :log LLAMA_EXE=!LLAMA_EXE!

if not exist "!LLAMA_EXE!" (
    call :log ERROR: llama-server.exe not found
    echo [ERROR] llama-server.exe not found:
    echo   "!LLAMA_EXE!"
    echo.
    echo You need a llama.cpp build new enough for Gemma 4 audio and /v1/audio/transcriptions.
    goto :fail
)

for %%I in ("!LLAMA_EXE!") do set "LLAMA_EXE_DIR=%%~dpI"

rem =========================
rem MODEL SELECTION
rem =========================
if defined MODEL_FILE (
    call :log MODEL_FILE preset to "!MODEL_FILE!", skipping auto-detection
) else (
    set "GEMMA_LARGE_MODEL="
    set "GEMMA_LARGE_DIR=%ROOT_DIR%\models\GEMMA_4_LARGE"

    if exist "!GEMMA_LARGE_DIR!" (
        rem Prefer E4B model files, but avoid fragile DIR/FINDSTR pipes.
        for %%F in ("!GEMMA_LARGE_DIR!\*E4B*.gguf") do (
            if not defined GEMMA_LARGE_MODEL if exist "%%~fF" set "GEMMA_LARGE_MODEL=%%~fF"
        )
        if not defined GEMMA_LARGE_MODEL (
            for %%F in ("!GEMMA_LARGE_DIR!\*gemma*.gguf") do (
                echo %%~nxF | findstr /I "mmproj" >nul
                if errorlevel 1 if not defined GEMMA_LARGE_MODEL if exist "%%~fF" set "GEMMA_LARGE_MODEL=%%~fF"
            )
        )
        if not defined GEMMA_LARGE_MODEL if exist "!GEMMA_LARGE_DIR!\gemma-4-E4B-it-Q6_K.gguf" set "GEMMA_LARGE_MODEL=!GEMMA_LARGE_DIR!\gemma-4-E4B-it-Q6_K.gguf"
    ) else (
        call :log GEMMA_LARGE_DIR not found: !GEMMA_LARGE_DIR!
    )

    if defined GEMMA_LARGE_MODEL call :log Detected large model: !GEMMA_LARGE_MODEL!

    if not defined GEMMA_LARGE_MODEL (
        call :log ERROR: No Gemma large model found in GEMMA_4_LARGE
        echo [ERROR] No Gemma large GGUF found. Expected:
        echo   %ROOT_DIR%\models\GEMMA_4_LARGE\*.gguf
        goto :fail
    )

    set "MODEL_FILE=!GEMMA_LARGE_MODEL!"
    set "MODEL_KIND=Gemma-4-E4B"
    call :log Auto-selected Gemma-4-E4B large model
)

rem =========================
rem MMPROJ RESOLUTION
rem =========================
set "MMPROJ_FILE_RESOLVED="
set "HAS_MMPROJ=0"

if defined MMPROJ_FILE (
    if exist "!MMPROJ_FILE!" (
        set "MMPROJ_FILE_RESOLVED=!MMPROJ_FILE!"
        set "HAS_MMPROJ=1"
        call :log MMPROJ_FILE preset to "!MMPROJ_FILE!", skipping detection
    ) else (
        call :log ERROR: MMPROJ_FILE does not exist: "!MMPROJ_FILE!"
        echo [ERROR] MMPROJ_FILE does not exist:
        echo   "!MMPROJ_FILE!"
        goto :fail
    )
)

if /I not "!LLAMA_ENABLE_MULTIMODAL!"=="0" if "!HAS_MMPROJ!"=="0" (
    rem Same-folder only by default. Avoid mismatching a model with the wrong projector.
    for %%I in ("!MODEL_FILE!") do set "MODEL_DIR=%%~dpI"
    call :find_mmproj_in_dir "!MODEL_DIR!"

    if "!HAS_MMPROJ!"=="1" (
        call :log MMPROJ_FILE matched from same folder: !MMPROJ_FILE_RESOLVED!
    ) else (
        call :log ERROR: No mmproj found in same folder as selected model
        echo [ERROR] No mmproj GGUF found beside the selected model.
        echo.
        echo Put the matching BF16 projector in the same folder as:
        echo   "!MODEL_FILE!"
        echo.
        echo Expected something like:
        echo   mmproj-gemma-4-BF16.gguf
        echo.
        echo To force text-only startup, set LLAMA_REQUIRE_MMPROJ=0 in local_settings_large.bat.
        if /I not "!LLAMA_REQUIRE_MMPROJ!"=="0" goto :fail
    )
) else (
    call :log LLAMA_ENABLE_MULTIMODAL=0, skipping mmproj detection
)

rem Keep OpenCode stable with a single large-model alias.
set "LLAMA_ALIAS=gemma-4-local-audio"

set "JINJA_ARG="
if /I "!LLAMA_JINJA!"=="1" set "JINJA_ARG=--jinja"

set "FLASH_ATTN_ARGS="
if /I not "!LLAMA_FLASH_ATTN!"=="0" set "FLASH_ATTN_ARGS=--flash-attn !LLAMA_FLASH_ATTN!"

rem Clear stale success/failure from previous runs in the log display.
call :log Effective alias: !LLAMA_ALIAS!
call :log Sampling: temp=!LLAMA_TEMPERATURE! top-k=!LLAMA_TOP_K! top-p=!LLAMA_TOP_P! min-p=!LLAMA_MIN_P!

echo.
echo === Starting llama-server ===
echo Model:  !MODEL_FILE!
if "!HAS_MMPROJ!"=="1" echo mmproj: !MMPROJ_FILE_RESOLVED!
echo URL:    http://!LLAMA_HOST!:!LLAMA_PORT!/v1
echo Alias:  !LLAMA_ALIAS!
echo Accel:  !ASSISTANT_ACCEL_MODE!
if defined CUDA_VISIBLE_DEVICES echo CUDA_VISIBLE_DEVICES=!CUDA_VISIBLE_DEVICES!
echo.

pushd "!LLAMA_EXE_DIR!" >nul

if "!HAS_MMPROJ!"=="1" (
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
      --repeat-penalty "!LLAMA_REPEAT_PENALTY!" ^
      !JINJA_ARG! ^
      !FLASH_ATTN_ARGS!
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
      --repeat-penalty "!LLAMA_REPEAT_PENALTY!" ^
      !JINJA_ARG! ^
      !FLASH_ATTN_ARGS!
)

set "EXIT_CODE=!ERRORLEVEL!"
popd >nul

call :log Exit code !EXIT_CODE!

if not "!EXIT_CODE!"=="0" (
    echo.
    echo [ERROR] llama-server crashed. See log:
    echo   "!LOG_FILE!"
    goto :fail
)

echo Server exited normally
goto :end


:select_acceleration
set "ASSISTANT_ACCEL_MODE=CPU only"
set "ACCEL_CHOICE_FILE=%TEMP%\assistant_large_accel_choice_%RANDOM%.tmp"
if exist "!ACCEL_CHOICE_FILE!" del "!ACCEL_CHOICE_FILE!" >nul 2>nul

echo.
echo --- Acceleration Selection ---
echo 1. CPU only ^(default if no key is pressed in 4 seconds; hides all CUDA GPUs^)
echo 2. RTX 4070 only ^(recommended; keeps RTX 3090/eGPU idle^)
echo 3. All CUDA GPUs
echo.
echo Press ENTER or type R/G/2 for RTX 4070 only.
echo Type A/3 for all CUDA GPUs.
echo Type C/1 for CPU only.
echo.

powershell -NoProfile -ExecutionPolicy Bypass -Command "$p='%ACCEL_CHOICE_FILE%'; $deadline=(Get-Date).AddSeconds(4); $choice='TIMEOUT'; while((Get-Date) -lt $deadline){ if([Console]::KeyAvailable){ $k=[Console]::ReadKey($true); if($k.Key -eq 'Enter'){ $choice='RTX4070'; break }; $ch=([string]$k.KeyChar).Trim(); if($ch -match '^(?i:r|g|2)$'){ Write-Host -NoNewline $k.KeyChar; $choice='RTX4070'; break }; if($ch -match '^(?i:a|3)$'){ Write-Host -NoNewline $k.KeyChar; $choice='ALLGPU'; break }; if($ch -match '^(?i:c|1)$'){ Write-Host -NoNewline $k.KeyChar; $choice='CPU'; break }; Write-Host -NoNewline $k.KeyChar; $choice='INVALID'; break } Start-Sleep -Milliseconds 25 }; [System.IO.File]::WriteAllText($p, $choice, [System.Text.Encoding]::ASCII)"

set "ACCEL_RAW=TIMEOUT"
if exist "!ACCEL_CHOICE_FILE!" (
    set /p ACCEL_RAW=<"!ACCEL_CHOICE_FILE!"
    del "!ACCEL_CHOICE_FILE!" >nul 2>nul
)
set "ACCEL_RAW=!ACCEL_RAW: =!"

echo.
if /I "!ACCEL_RAW!"=="TIMEOUT" (
    echo [INFO] No key within 4 seconds. Defaulting to CPU only.
    call :use_cpu
    exit /b 0
)
if /I "!ACCEL_RAW!"=="RTX4070" (
    echo [INFO] RTX 4070-only mode selected.
    call :use_4070_gpu
    exit /b 0
)
if /I "!ACCEL_RAW!"=="ALLGPU" (
    echo [INFO] All-GPU mode selected.
    call :use_all_gpus
    exit /b 0
)
if /I "!ACCEL_RAW!"=="CPU" (
    echo [INFO] CPU selected.
    call :use_cpu
    exit /b 0
)

echo [INFO] Invalid choice. Defaulting to CPU only.
call :use_cpu
exit /b 0

:use_cpu
set "ASSISTANT_ACCEL_MODE=CPU only"
set "LLAMA_GPU_LAYERS=0"
rem CUDA_VISIBLE_DEVICES=-1 hides all CUDA GPUs, including mmproj/CLIP CUDA use.
set "CUDA_VISIBLE_DEVICES=-1"
set "CUDA_DEVICE_ORDER=PCI_BUS_ID"
call :log Acceleration selected: CPU only, LLAMA_GPU_LAYERS=!LLAMA_GPU_LAYERS!, CUDA_VISIBLE_DEVICES=!CUDA_VISIBLE_DEVICES!
exit /b 0

:use_4070_gpu
set "ASSISTANT_ACCEL_MODE=GPU - RTX 4070 only"
if not defined LLAMA_GPU_LAYERS_GPU set "LLAMA_GPU_LAYERS_GPU=99"
set "LLAMA_GPU_LAYERS=!LLAMA_GPU_LAYERS_GPU!"
set "CUDA_DEVICE_ORDER=PCI_BUS_ID"
call :prefer_4070_gpu
call :log Acceleration selected: !ASSISTANT_ACCEL_MODE!, LLAMA_GPU_LAYERS=!LLAMA_GPU_LAYERS!, CUDA_VISIBLE_DEVICES=!CUDA_VISIBLE_DEVICES!
exit /b 0

:use_all_gpus
set "ASSISTANT_ACCEL_MODE=GPU - all CUDA GPUs"
if not defined LLAMA_GPU_LAYERS_GPU set "LLAMA_GPU_LAYERS_GPU=99"
set "LLAMA_GPU_LAYERS=!LLAMA_GPU_LAYERS_GPU!"
set "CUDA_DEVICE_ORDER=PCI_BUS_ID"
rem Unsetting CUDA_VISIBLE_DEVICES lets llama.cpp see every CUDA GPU.
set "CUDA_VISIBLE_DEVICES="
call :log Acceleration selected: all CUDA GPUs, LLAMA_GPU_LAYERS=!LLAMA_GPU_LAYERS!, CUDA_VISIBLE_DEVICES=ALL
exit /b 0

:prefer_4070_gpu
set "GPU_PICKER=%~dp0system\tools\pick_gpu_llama.py"
set "GPU_CHOICE_FILE=%~dp0system\cache\gpu_choice.tmp"
if exist "!GPU_CHOICE_FILE!" del "!GPU_CHOICE_FILE!" >nul 2>nul

call :find_python
if not defined PYTHON_EXE (
    echo [ERROR] Python not found. Falling back to CPU to avoid using the RTX 3090/eGPU.
    call :use_cpu
    exit /b 0
)

if exist "!GPU_PICKER!" (
    "!PYTHON_EXE!" "!GPU_PICKER!" --prefer 4070 --choice-file "!GPU_CHOICE_FILE!"
) else (
    echo [ERROR] system\tools\pick_gpu_llama.py not found. Falling back to CPU to avoid using the RTX 3090/eGPU.
    call :use_cpu
    exit /b 0
)

if exist "!GPU_CHOICE_FILE!" (
    set /p GPU_ID=<"!GPU_CHOICE_FILE!"
    del "!GPU_CHOICE_FILE!" >nul 2>nul
    set "CUDA_VISIBLE_DEVICES=!GPU_ID!"
    set "ASSISTANT_ACCEL_MODE=GPU - RTX 4070 only ^(CUDA_VISIBLE_DEVICES=!GPU_ID!^)"
    echo [INFO] Restricting llama.cpp to RTX 4070: CUDA_VISIBLE_DEVICES=!GPU_ID!.
) else (
    echo [ERROR] GPU picker did not select an RTX 4070. Falling back to CPU to avoid using the RTX 3090/eGPU.
    call :use_cpu
)
exit /b 0
:find_python
set "PYTHON_EXE="
if exist "%ROOT_DIR%\python_embeded\python.exe" set "PYTHON_EXE=%ROOT_DIR%\python_embeded\python.exe"
if not defined PYTHON_EXE if exist "%ROOT_DIR%\ComfyUI_windows_portable\python_embeded\python.exe" set "PYTHON_EXE=%ROOT_DIR%\ComfyUI_windows_portable\python_embeded\python.exe"
if not defined PYTHON_EXE (
    for /f "delims=" %%P in ('where python 2^>nul') do (
        if not defined PYTHON_EXE set "PYTHON_EXE=%%P"
    )
)
exit /b 0

:fail
call :log FAILED
echo.
pause
endlocal & exit /b 1

:end
pause
endlocal & exit /b 0

:find_mmproj_in_dir
set "SEARCH_DIR=%~1"
if not exist "!SEARCH_DIR!" exit /b 0

rem Prefer BF16 for Gemma 4 audio. Quantized projectors can degrade audio quality.
for /f "delims=" %%F in ('dir /b /a-d "!SEARCH_DIR!*mmproj*BF16*.gguf" 2^>nul') do (
    if "!HAS_MMPROJ!"=="0" (
        set "MMPROJ_FILE_RESOLVED=!SEARCH_DIR!%%F"
        set "HAS_MMPROJ=1"
    )
)

if "!HAS_MMPROJ!"=="1" exit /b 0

rem Fallback only if BF16 is unavailable.
for /f "delims=" %%F in ('dir /b /a-d "!SEARCH_DIR!*mmproj*.gguf" 2^>nul') do (
    if "!HAS_MMPROJ!"=="0" (
        set "MMPROJ_FILE_RESOLVED=!SEARCH_DIR!%%F"
        set "HAS_MMPROJ=1"
    )
)
exit /b 0

:log
echo [%DATE% %TIME%] %*>>"%LOG_FILE%"
echo [%DATE% %TIME%] %*
exit /b 0
