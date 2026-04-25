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

rem --- Fixed defaults for ASSISTANT_SMALL ---
if not defined LLAMA_HOST set "LLAMA_HOST=127.0.0.1"
if not defined LLAMA_PORT set "LLAMA_PORT=8075"
if not defined LLAMA_CTX set "LLAMA_CTX=16384"
if not defined LLAMA_GPU_LAYERS set "LLAMA_GPU_LAYERS=0"
if not defined LLAMA_ALIAS set "LLAMA_ALIAS=gemma-small-vision"
if not defined LLAMA_EXE set "LLAMA_EXE=%ROOT_DIR%\runtime\llama.cpp\llama-server.exe"
if not defined LLAMA_ENABLE_VISION set "LLAMA_ENABLE_VISION=1"

rem --- Sensible default sampling for a lightweight assistant ---
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
    call :log ERROR: llama-server.exe not found at "!LLAMA_EXE!"
    echo [ERROR] llama-server.exe not found:
    echo   "!LLAMA_EXE!"
    echo.
    echo Put llama-server.exe in:
    echo   "%ROOT_DIR%\runtime\llama.cpp\"
    goto :fail
)

for %%I in ("!LLAMA_EXE!") do set "LLAMA_EXE_DIR=%%~dpI"

rem --- Resolve Gemma model (prefer vision-related filenames) ---
if defined MODEL_FILE (
    if not exist "!MODEL_FILE!" (
        call :log ERROR: MODEL_FILE does not exist: "!MODEL_FILE!"
        echo [ERROR] MODEL_FILE does not exist:
        echo   "!MODEL_FILE!"
        goto :fail
    )
) else (
    set "MODEL_FILE="
    for %%P in ("%ROOT_DIR%\model_vision" "%ROOT_DIR%\models") do (
        if exist "%%~fP" (
            for /r "%%~fP" %%F in (*gemma*vision*.gguf *gemma*.gguf) do (
                if not defined MODEL_FILE set "MODEL_FILE=%%~fF"
            )
        )
    )
)

if not defined MODEL_FILE (
    call :log ERROR: Could not find a Gemma GGUF under model_vision/ or models/
    echo [ERROR] Could not find a Gemma GGUF model.
    echo Searched in:
    echo   "%ROOT_DIR%\model_vision\"
    echo   "%ROOT_DIR%\models\"
    echo.
    echo Put a Gemma GGUF there or set MODEL_FILE in local_settings_small.bat.
    goto :fail
)

for %%I in ("!MODEL_FILE!") do set "MODEL_FILE_NAME=%%~nxI"
call :log MODEL_FILE=!MODEL_FILE!

rem --- Resolve mmproj for vision ---
set "MMPROJ_FILE_RESOLVED="
if /I "!LLAMA_ENABLE_VISION!"=="0" (
    call :log LLAMA_ENABLE_VISION=0, skipping mmproj detection
) else (
    if defined MMPROJ_FILE (
        if exist "!MMPROJ_FILE!" (
            set "MMPROJ_FILE_RESOLVED=!MMPROJ_FILE!"
            call :log Using preset MMPROJ_FILE=!MMPROJ_FILE_RESOLVED!
        ) else (
            call :log WARNING: preset MMPROJ_FILE does not exist: "!MMPROJ_FILE!"
        )
    )

    if not defined MMPROJ_FILE_RESOLVED (
        for %%P in ("%ROOT_DIR%\model_vision" "%ROOT_DIR%\models") do (
            if exist "%%~fP" (
                for /r "%%~fP" %%F in (*gemma*mmproj*.gguf mmproj*gemma*.gguf mmproj*.gguf) do (
                    if not defined MMPROJ_FILE_RESOLVED set "MMPROJ_FILE_RESOLVED=%%~fF"
                )
            )
        )
    )
)

if defined MMPROJ_FILE_RESOLVED (
    call :log MMPROJ_FILE_RESOLVED=!MMPROJ_FILE_RESOLVED!
) else (
    call :log WARNING: no mmproj file found; vision input may fail depending on model packaging
)

echo.
echo === Starting ASSISTANT_SMALL llama-server ===
echo Model:       !MODEL_FILE!
echo URL:         http://!LLAMA_HOST!:!LLAMA_PORT!/v1
echo Models API:  http://!LLAMA_HOST!:!LLAMA_PORT!/v1/models
echo Ctx:         !LLAMA_CTX!
echo GPU layers:  !LLAMA_GPU_LAYERS! ^(CPU-only when 0^)
echo Alias:       !LLAMA_ALIAS!
if defined MMPROJ_FILE_RESOLVED echo Vision mmproj: !MMPROJ_FILE_RESOLVED!
echo Log:         !LOG_FILE!
echo.

pushd "!LLAMA_EXE_DIR!" >nul 2>&1
if errorlevel 1 (
    call :log ERROR: could not enter llama executable directory "!LLAMA_EXE_DIR!"
    echo [ERROR] Could not change directory to:
    echo   "!LLAMA_EXE_DIR!"
    goto :fail
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

call :log llama-server exited with code !SERVER_EXIT!

if not "!SERVER_EXIT!"=="0" (
    echo.
    echo [ERROR] llama-server exited with code !SERVER_EXIT!.
    echo Check the log file:
    echo   "!LOG_FILE!"
    goto :fail
)

echo.
echo Server exited normally.
call :log Script finished successfully
goto :end

:fail
echo.
echo Script failed. See log:
echo   "!LOG_FILE!"
call :log Script failed
pause
endlocal & exit /b 1

:end
pause
endlocal & exit /b 0

:log
echo [%DATE% %TIME%] %*>>"%LOG_FILE%"
echo [%DATE% %TIME%] %*
exit /b 0
