@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"

set "ROOT_DIR=%~dp0.."
for %%I in ("%ROOT_DIR%") do set "ROOT_DIR=%%~fI"

set "LOG_FILE=%~dp0start_server.log"

call :log ==========================================
call :log Starting ASSISTANT_SMALL llama-server launcher in "%CD%"
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
if not defined LLAMA_ALIAS set "LLAMA_ALIAS=gemma-small-vision"
if not defined LLAMA_EXE set "LLAMA_EXE=%ROOT_DIR%\runtime\llama.cpp\llama-server.exe"
if not defined LLAMA_ENABLE_VISION set "LLAMA_ENABLE_VISION=1"

rem --- Sampling defaults ---
if not defined LLAMA_TEMPERATURE set "LLAMA_TEMPERATURE=0.7"
if not defined LLAMA_TOP_K set "LLAMA_TOP_K=40"
if not defined LLAMA_TOP_P set "LLAMA_TOP_P=0.95"
if not defined LLAMA_MIN_P set "LLAMA_MIN_P=0.0"
if not defined LLAMA_PRESENCE_PENALTY set "LLAMA_PRESENCE_PENALTY=0.0"
if not defined LLAMA_REPEAT_PENALTY set "LLAMA_REPEAT_PENALTY=1.0"

call :log LLAMA_HOST=!LLAMA_HOST!
call :log LLAMA_PORT=!LLAMA_PORT!
call :log LLAMA_CTX=!LLAMA_CTX!
call :log LLAMA_GPU_LAYERS=!LLAMA_GPU_LAYERS!
call :log LLAMA_ALIAS=!LLAMA_ALIAS!
call :log LLAMA_ENABLE_VISION=!LLAMA_ENABLE_VISION!
call :log LLAMA_EXE=!LLAMA_EXE!

if not exist "!LLAMA_EXE!" (
    call :log ERROR: llama-server.exe not found
    echo [ERROR] llama-server.exe not found:
    echo   "!LLAMA_EXE!"
    goto :fail
)

for %%I in ("!LLAMA_EXE!") do set "LLAMA_EXE_DIR=%%~dpI"

rem =========================
rem MODEL RESOLUTION (ROBUST)
rem =========================
if not defined MODEL_FILE (
    set "MODEL_FILE="

    rem Prefer vision models
    for /f "delims=" %%F in ('dir /b /s /a-d "%ROOT_DIR%\model_vision\*gemma*vision*.gguf" "%ROOT_DIR%\models\*gemma*vision*.gguf" 2^>nul') do (
        if not defined MODEL_FILE set "MODEL_FILE=%%~fF"
    )

    rem Fallback: any Gemma model
    if not defined MODEL_FILE (
        for /f "delims=" %%F in ('dir /b /s /a-d "%ROOT_DIR%\model_vision\*gemma*.gguf" "%ROOT_DIR%\models\*gemma*.gguf" 2^>nul') do (
            if not defined MODEL_FILE set "MODEL_FILE=%%~fF"
        )
    )
)

if not defined MODEL_FILE (
    call :log ERROR: No Gemma GGUF found
    echo [ERROR] Could not find a Gemma GGUF model.
    goto :fail
)

call :log MODEL_FILE=!MODEL_FILE!

rem =========================
rem MMPROJ RESOLUTION
rem =========================
set "MMPROJ_FILE_RESOLVED="

if /I not "!LLAMA_ENABLE_VISION!"=="0" (

    rem Prefer gemma-specific mmproj
    for /f "delims=" %%F in ('dir /b /s /a-d "%ROOT_DIR%\model_vision\*gemma*mmproj*.gguf" "%ROOT_DIR%\models\*gemma*mmproj*.gguf" "%ROOT_DIR%\model_vision\mmproj*gemma*.gguf" "%ROOT_DIR%\models\mmproj*gemma*.gguf" 2^>nul') do (
        if not defined MMPROJ_FILE_RESOLVED set "MMPROJ_FILE_RESOLVED=%%~fF"
    )

    rem Fallback: any mmproj
    if not defined MMPROJ_FILE_RESOLVED (
        for /f "delims=" %%F in ('dir /b /s /a-d "%ROOT_DIR%\model_vision\mmproj*.gguf" "%ROOT_DIR%\models\mmproj*.gguf" 2^>nul') do (
            if not defined MMPROJ_FILE_RESOLVED set "MMPROJ_FILE_RESOLVED=%%~fF"
        )
    )
)

if defined MMPROJ_FILE_RESOLVED (
    call :log MMPROJ_FILE=!MMPROJ_FILE_RESOLVED!
) else (
    call :log WARNING: no mmproj found
)

echo.
echo === Starting llama-server ===
echo Model: !MODEL_FILE!
if defined MMPROJ_FILE_RESOLVED echo mmproj: !MMPROJ_FILE_RESOLVED!
echo URL: http://!LLAMA_HOST!:!LLAMA_PORT!/v1
echo.

pushd "!LLAMA_EXE_DIR!" >nul

if defined MMPROJ_FILE_RESOLVED (
    "!LLAMA_EXE!" ^
      --model "!MODEL_FILE!" ^
      --mmproj "!MMPROJ_FILE_RESOLVED!" ^
      --host "!LLAMA_HOST!" ^
      --port "!LLAMA_PORT!" ^
      --ctx-size "!LLAMA_CTX!" ^
      --n-gpu-layers "!LLAMA_GPU_LAYERS!" ^
      --alias "!LLAMA_ALIAS!"
) else (
    "!LLAMA_EXE!" ^
      --model "!MODEL_FILE!" ^
      --host "!LLAMA_HOST!" ^
      --port "!LLAMA_PORT!" ^
      --ctx-size "!LLAMA_CTX!" ^
      --n-gpu-layers "!LLAMA_GPU_LAYERS!" ^
      --alias "!LLAMA_ALIAS!"
)

set "EXIT_CODE=!ERRORLEVEL!"
popd

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
pause
endlocal & exit /b 1

:end
pause
endlocal & exit /b 0

:log
echo [%DATE% %TIME%] %*>>"%LOG_FILE%"
echo [%DATE% %TIME%] %*
exit /b 0