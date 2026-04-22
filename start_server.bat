@echo off
setlocal EnableExtensions
cd /d "%~dp0"

set "LOG_FILE=%~dp0start_server.log"

call :log ==========================================
call :log Starting llama-server launcher in "%CD%"
call :log Timestamp: %DATE% %TIME%

if exist "local_settings.bat" (
    call :log Found local_settings.bat, loading it
    call "local_settings.bat"
) else (
    call :log No local_settings.bat found, using defaults
)

rem Defaults. Override any of these in local_settings.bat.
if not defined LLAMA_HOST set "LLAMA_HOST=127.0.0.1"
if not defined LLAMA_PORT set "LLAMA_PORT=8080"
if not defined LLAMA_CTX set "LLAMA_CTX=32768"
if not defined LLAMA_GPU_LAYERS set "LLAMA_GPU_LAYERS=0"
if not defined LLAMA_ALIAS set "LLAMA_ALIAS=qwen-local"
if not defined LLAMA_EXE set "LLAMA_EXE=%CD%\runtime\llama.cpp\llama-server.exe"

call :log LLAMA_HOST=%LLAMA_HOST%
call :log LLAMA_PORT=%LLAMA_PORT%
call :log LLAMA_CTX=%LLAMA_CTX%
call :log LLAMA_GPU_LAYERS=%LLAMA_GPU_LAYERS%
call :log LLAMA_ALIAS=%LLAMA_ALIAS%
call :log Initial LLAMA_EXE=%LLAMA_EXE%

rem Resolve executable.
if exist "%LLAMA_EXE%" (
    call :log Found llama-server.exe at "%LLAMA_EXE%"
) else if exist "%CD%\runtime\llama.cpp\build\bin\llama-server.exe" (
    set "LLAMA_EXE=%CD%\runtime\llama.cpp\build\bin\llama-server.exe"
    call :log Fallback executable found at "%LLAMA_EXE%"
) else (
    call :log ERROR: llama-server.exe not found
    echo [ERROR] llama-server.exe not found.
    echo Checked:
    echo   "%LLAMA_EXE%"
    echo   "%CD%\runtime\llama.cpp\build\bin\llama-server.exe"
    echo.
    echo Set LLAMA_EXE in local_settings.bat or place llama-server.exe in:
    echo   runtime\llama.cpp\
    echo   or runtime\llama.cpp\build\bin\
    goto :fail
)

rem Resolve model.
if not defined MODEL_FILE (
    call :log MODEL_FILE not preset, searching models folder
    set "MODEL_FILE="
    for /r "%CD%\models" %%F in (*.gguf) do (
        set "MODEL_FILE=%%~fF"
        goto :found_model
    )
) else (
    call :log MODEL_FILE preset to "%MODEL_FILE%"
)

:found_model
if not defined MODEL_FILE (
    call :log ERROR: No .gguf model found under "%CD%\models"
    echo [ERROR] No .gguf model found in:
    echo   "%CD%\models"
    echo.
    echo Put one GGUF file in models\ including subfolders, or set MODEL_FILE in local_settings.bat.
    goto :fail
)

if not exist "%MODEL_FILE%" (
    call :log ERROR: MODEL_FILE path does not exist: "%MODEL_FILE%"
    echo [ERROR] MODEL_FILE does not exist:
    echo   "%MODEL_FILE%"
    goto :fail
)

for %%I in ("%LLAMA_EXE%") do set "LLAMA_EXE_DIR=%%~dpI"

call :log Using MODEL_FILE="%MODEL_FILE%"
call :log Using LLAMA_EXE_DIR="%LLAMA_EXE_DIR%"

echo.
echo === Starting llama-server ===
echo Model:      %MODEL_FILE%
echo URL:        http://%LLAMA_HOST%:%LLAMA_PORT%/v1
echo Models API: http://%LLAMA_HOST%:%LLAMA_PORT%/v1/models
echo Ctx:        %LLAMA_CTX%
echo GPU layers: %LLAMA_GPU_LAYERS%
echo Alias:      %LLAMA_ALIAS%
echo Log:        %LOG_FILE%
echo.

call :log Launch command:
call :log "%LLAMA_EXE%" --model "%MODEL_FILE%" --host "%LLAMA_HOST%" --port "%LLAMA_PORT%" --ctx-size "%LLAMA_CTX%" --n-gpu-layers "%LLAMA_GPU_LAYERS%" --alias "%LLAMA_ALIAS%"

pushd "%LLAMA_EXE_DIR%" >nul 2>&1
if errorlevel 1 (
    call :log ERROR: Could not enter llama executable directory "%LLAMA_EXE_DIR%"
    echo [ERROR] Could not change directory to:
    echo   "%LLAMA_EXE_DIR%"
    goto :fail
)

"%LLAMA_EXE%" ^
  --model "%MODEL_FILE%" ^
  --host "%LLAMA_HOST%" ^
  --port "%LLAMA_PORT%" ^
  --ctx-size "%LLAMA_CTX%" ^
  --n-gpu-layers "%LLAMA_GPU_LAYERS%" ^
  --alias "%LLAMA_ALIAS%"

set "SERVER_EXIT=%ERRORLEVEL%"
popd >nul 2>&1

call :log llama-server exited with code %SERVER_EXIT%

if not "%SERVER_EXIT%"=="0" (
    echo.
    echo [ERROR] llama-server exited with code %SERVER_EXIT%.
    echo Check the log file:
    echo   "%LOG_FILE%"
    goto :fail
)

echo.
echo Server exited normally.
call :log Script finished successfully
goto :end

:fail
echo.
echo Script failed. See log:
echo   "%LOG_FILE%"
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
