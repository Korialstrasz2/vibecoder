@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"

set "ROOT_DIR=%~dp0.."
for %%I in ("%ROOT_DIR%") do set "ROOT_DIR=%%~fI"

set "LOG_FILE=%~dp0start_server.log"

call :log ==========================================
call :log Starting ASSISTANT_SMALL Gemma 4 llama-server launcher in "%CD%"
call :log Root dir: %ROOT_DIR%
call :log Timestamp: %DATE% %TIME%

rem --- Load optional overrides from repo root first ---
if exist "%ROOT_DIR%\local_settings.bat" (
    call :log Found %ROOT_DIR%\local_settings.bat, loading it
    call "%ROOT_DIR%\local_settings.bat"
)

rem --- Load optional assistant-specific overrides ---
if exist "%~dp0local_settings_small.bat" (
    call :log Found local_settings_small.bat, loading it
    call "%~dp0local_settings_small.bat"
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
    call :log MODEL_FILE preset to "!MODEL_FILE!", skipping selection prompt
) else (
    set "GEMMA_SMALL_MODEL="
    set "GEMMA_LARGE_MODEL="
    set "GEMMA_SMALL_DIR=%ROOT_DIR%\models\GEMMA_4_SMALL"
    set "GEMMA_LARGE_DIR=%ROOT_DIR%\models\GEMMA_4_LAAARGE"

    if exist "!GEMMA_SMALL_DIR!" (
        for /f "delims=" %%F in ('dir /b /a-d "!GEMMA_SMALL_DIR!\*E2B*.gguf" 2^>nul') do (
            if not defined GEMMA_SMALL_MODEL set "GEMMA_SMALL_MODEL=!GEMMA_SMALL_DIR!\%%F"
        )
        if not defined GEMMA_SMALL_MODEL (
            for /f "delims=" %%F in ('dir /b /a-d "!GEMMA_SMALL_DIR!\*gemma*.gguf" 2^>nul ^| findstr /I /V "mmproj"') do (
                if not defined GEMMA_SMALL_MODEL set "GEMMA_SMALL_MODEL=!GEMMA_SMALL_DIR!\%%F"
            )
        )
    )

    if exist "!GEMMA_LARGE_DIR!" (
        for /f "delims=" %%F in ('dir /b /a-d "!GEMMA_LARGE_DIR!\*E4B*.gguf" 2^>nul') do (
            if not defined GEMMA_LARGE_MODEL set "GEMMA_LARGE_MODEL=!GEMMA_LARGE_DIR!\%%F"
        )
        if not defined GEMMA_LARGE_MODEL (
            for /f "delims=" %%F in ('dir /b /a-d "!GEMMA_LARGE_DIR!\*gemma*.gguf" 2^>nul ^| findstr /I /V "mmproj"') do (
                if not defined GEMMA_LARGE_MODEL set "GEMMA_LARGE_MODEL=!GEMMA_LARGE_DIR!\%%F"
            )
        )
    )

    set "HAS_SMALL=0"
    set "HAS_LARGE=0"
    if defined GEMMA_SMALL_MODEL set "HAS_SMALL=1"
    if defined GEMMA_LARGE_MODEL set "HAS_LARGE=1"

    if "!HAS_SMALL!"=="0" if "!HAS_LARGE!"=="0" (
        call :log ERROR: No Gemma models found in GEMMA_4_SMALL or GEMMA_4_LAAARGE
        echo [ERROR] No Gemma GGUF found. Expected one of:
        echo   %ROOT_DIR%\models\GEMMA_4_SMALL\*.gguf
        echo   %ROOT_DIR%\models\GEMMA_4_LAAARGE\*.gguf
        goto :fail
    )

    if "!HAS_SMALL!"=="1" if "!HAS_LARGE!"=="0" (
        set "MODEL_FILE=!GEMMA_SMALL_MODEL!"
        set "MODEL_KIND=Gemma-4-E2B"
        call :log Only small Gemma available, auto-selecting E2B
    ) else if "!HAS_SMALL!"=="0" if "!HAS_LARGE!"=="1" (
        set "MODEL_FILE=!GEMMA_LARGE_MODEL!"
        set "MODEL_KIND=Gemma-4-E4B"
        call :log Only large Gemma available, auto-selecting E4B
    ) else (
        echo.
        echo --- Gemma Model Selection ---
        echo 1. Small  - Gemma-4-E2B ^(faster, less capable^)
        echo 2. Large  - Gemma-4-E4B ^(default, better for voice/coding^)
        echo.
        choice /C 12 /N /T 4 /D 2 /M "Choose model [1-2, default 2 in 4 seconds]: "
        set "CHOICE_CODE=!ERRORLEVEL!"
        if "!CHOICE_CODE!"=="1" (
            set "MODEL_FILE=!GEMMA_SMALL_MODEL!"
            set "MODEL_KIND=Gemma-4-E2B"
            echo [INFO] Selected: Gemma-4-E2B ^(Small^)
            call :log Selected Gemma-4-E2B
        ) else (
            set "MODEL_FILE=!GEMMA_LARGE_MODEL!"
            set "MODEL_KIND=Gemma-4-E4B"
            echo [INFO] Selected/defaulted: Gemma-4-E4B ^(Large^)
            call :log Selected/defaulted Gemma-4-E4B
        )
    )
)

if not defined MODEL_FILE (
    call :log ERROR: MODEL_FILE is not set
    echo [ERROR] Could not determine model file.
    goto :fail
)

if not exist "!MODEL_FILE!" (
    call :log ERROR: MODEL_FILE does not exist: "!MODEL_FILE!"
    echo [ERROR] Model file does not exist:
    echo   "!MODEL_FILE!"
    goto :fail
)

call :log MODEL_FILE=!MODEL_FILE!

rem =========================
rem MMPROJ RESOLUTION
rem =========================
set "MMPROJ_FILE_RESOLVED="
set "HAS_MMPROJ=0"

if /I not "!LLAMA_ENABLE_MULTIMODAL!"=="0" (
    rem Same-folder only by default. Avoid accidental E4B model + E2B projector mismatch.
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
        echo To force text-only startup, set LLAMA_REQUIRE_MMPROJ=0 in local_settings_small.bat.
        if /I not "!LLAMA_REQUIRE_MMPROJ!"=="0" goto :fail
    )
) else (
    call :log LLAMA_ENABLE_MULTIMODAL=0, skipping mmproj detection
)

rem Keep OpenCode stable. One alias works whether the launcher selected E2B or E4B.
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
