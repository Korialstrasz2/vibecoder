@echo off
setlocal EnableExtensions
cd /d "%~dp0"

set "LOG_FILE=%~dp0start_server.log"

call :log ==========================================
call :log Starting llama-server launcher in "%CD%"
call :log Timestamp: %DATE% %TIME%

rem --- Model picker (multiple GGUFs) ---
set "MODEL_FILE="
set "MODEL_COUNT=0"
for /r "%CD%\models" %%F in (*.gguf) do set /a MODEL_COUNT+=1

if %MODEL_COUNT% GTR 1 (
    call :log Found %MODEL_COUNT% models, creating picker temp file
    set "MODEL_PICKER_TEMP=%TEMP%\opencode_models_%RANDOM%.txt"
    for /r "%CD%\models" %%F in (*.gguf) do echo %%~fF >>"%MODEL_PICKER_TEMP%"

    call :log Listing models:
    set "MODEL_IDX=0"
    for /f "usebackq delims=" %%M in ("%MODEL_PICKER_TEMP%") do (
        set /a MODEL_IDX+=1
        set "MODEL_PICKER_NAME=%%~nxM"
        call :log   !MODEL_IDX!. !MODEL_PICKER_NAME!
    )
    echo.
    choice /t 3 /d 1 /n /c 1234567890 /m "Choose model (1-%MODEL_COUNT%): "
    if errorlevel %MODEL_COUNT% ( set "MODEL_CHOICE=%MODEL_COUNT%" ) else ( set "MODEL_CHOICE=%errorlevel%" )

    call :log Selected model option !MODEL_CHOICE!
    set /a MODEL_IDX=0
    for /f "usebackq delims=" %%M in ("%MODEL_PICKER_TEMP%") do (
        set /a MODEL_IDX+=1
        if !MODEL_IDX!==!MODEL_CHOICE! (
            set "MODEL_FILE=%%~fF"
            goto :picker_done
        )
    )
    :picker_done
    del /q "%MODEL_PICKER_TEMP%" >nul 2>&1

    call :log MODEL_FILE auto-selected: "%MODEL_FILE%"
)

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

rem --- Context profile selection ---
if defined CONTEXT_PROFILE (
    call :log Using preset profile: %CONTEXT_PROFILE%
    if /i "%CONTEXT_PROFILE%"=="short" (
        set "LLAMA_CTX=16384"
        set "PROFILE_DISPLAY=short (16k)"
    ) else if /i "%CONTEXT_PROFILE%"=="long" (
        set "LLAMA_CTX=65536"
        set "PROFILE_DISPLAY=long (64k)"
    ) else if /i "%CONTEXT_PROFILE%"=="ultra" (
        set "LLAMA_CTX=131072"
        set "PROFILE_DISPLAY=ultra (128k)"
    ) else (
        set "PROFILE_DISPLAY=custom (%CONTEXT_PROFILE%)"
    )
)

if not defined LLAMA_CTX set "LLAMA_CTX=32768"

if not defined CONTEXT_PROFILE (
    echo.
    echo --- Context Profile ---
    echo 1. short  - 16k context  (fast, good for simple tasks)
    echo 2. long   - 64k context  (balanced)
    echo 3. ultra  - 128k context (slower, for complex/large codebases)
    echo.
    choice /t 5 /d 2 /n /c 123 /m "Choose profile: "
    if errorlevel 3 ( set "LLAMA_CTX=131072" & set "PROFILE_DISPLAY=ultra (128k)" ) else (
    if errorlevel 2 ( set "LLAMA_CTX=65536"  & set "PROFILE_DISPLAY=long (64k)" ) else (
    if errorlevel 1 ( set "LLAMA_CTX=16384"  & set "PROFILE_DISPLAY=short (16k)" ) ) )
)

if defined PROFILE_DISPLAY (
    call :log Context profile: %PROFILE_DISPLAY%
)

rem --- Resolve executable ---
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

rem --- Resolve model ---
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

rem --- Vision mode: auto-detect or use MMPROJ_GGUF ---
set "MMPROJ_FILE="
if defined MMPROJ_GGUF (
    if exist "%MMPROJ_GGUF%" (
        set "MMPROJ_FILE=%MMPROJ_GGUF%"
        call :log MMPROJ_GGUF preset: "%MMPROJ_FILE%"
    ) else (
        call :log WARNING: MMPROJ_GGUF does not exist: "%MMPROJ_GGUF%"
    )
)
if not defined MMPROJ_FILE (
    call :log Searching for mmproj alongside model...
    set "MODEL_DIR=%MODEL_FILE%"
    for %%I in ("%MODEL_FILE%") do set "MODEL_DIR=%%~dpI"
    for /r "%MODEL_DIR%%~nxMODEL_FILE%" %%M in (*.gguf) do (
        for %%P in ("%%~dpM.*mmproj*") do (
            if /i not "%%~xP"==".gguf" (
                set "MMPROJ_FILE=%%~fP"
                goto :found_mmproj
            )
        )
    )
    rem Try matching model name pattern: model-Q4.gguf -> model-mmproj-Q4.gguf
    set "MODEL_BASE=%MODEL_FILE%"
    for %%I in ("%MODEL_FILE%") do set "MODEL_BASE=%%~nI"
    for %%M in ("%MODEL_DIR%%MODEL_BASE%-*mmproj*.gguf") do (
        if exist "%%~fM" (
            set "MMPROJ_FILE=%%~fM"
            goto :found_mmproj
        )
    )
    rem Also try mmproj without .gguf extension
    for %%M in ("%MODEL_DIR%%MODEL_BASE%-*mmproj*") do (
        if exist "%%~fM" (
            set "MMPROJ_FILE=%%~fM"
            goto :found_mmproj
        )
    )
    :found_mmproj
    if not defined MMPROJ_FILE (
        call :log No mmproj found; vision mode disabled
    ) else (
        call :log Found mmproj: "%MMPROJ_FILE%"
    )
)

rem --- Update opencode context limit ---
if defined PROFILE_DISPLAY (
    call :log Updating opencode.jsonc context limit to %LLAMA_CTX%
    powershell -NoProfile -Command "(Get-Content '%CD%\config\opencode\opencode.jsonc') -replace '""context"": \d+', '\"context\": %LLAMA_CTX%' | Set-Content '%CD%\config\opencode\opencode.jsonc'"
    call :log opencode.jsonc updated
)

echo.
echo === Starting llama-server ===
echo Model:       %MODEL_FILE%
if defined MMPROJ_FILE echo Vision mmproj: %MMPROJ_FILE%
echo URL:         http://%LLAMA_HOST%:%LLAMA_PORT%/v1
echo Models API:  http://%LLAMA_HOST%:%LLAMA_PORT%/v1/models
echo Ctx:         %LLAMA_CTX%
echo GPU layers:  %LLAMA_GPU_LAYERS%
echo Alias:       %LLAMA_ALIAS%
echo Log:         %LOG_FILE%
echo.

call :log Launch command:
call :log "%LLAMA_EXE%" --model "%MODEL_FILE%" --host "%LLAMA_HOST%" --port "%LLAMA_PORT%" --ctx-size "%LLAMA_CTX%" --n-gpu-layers "%LLAMA_GPU_LAYERS%" --alias "%LLAMA_ALIAS%"
if defined MMPROJ_FILE call :log   --mmproj "%MMPROJ_FILE%"

pushd "%LLAMA_EXE_DIR%" >nul 2>&1
if errorlevel 1 (
    call :log ERROR: Could not enter llama executable directory "%LLAMA_EXE_DIR%"
    echo [ERROR] Could not change directory to:
    echo   "%LLAMA_EXE_DIR%"
    goto :fail
)

if defined MMPROJ_FILE (
    "%LLAMA_EXE%" ^
      --model "%MODEL_FILE%" ^
      --host "%LLAMA_HOST%" ^
      --port "%LLAMA_PORT%" ^
      --ctx-size "%LLAMA_CTX%" ^
      --n-gpu-layers "%LLAMA_GPU_LAYERS%" ^
      --alias "%LLAMA_ALIAS%" ^
      --mmproj "%MMPROJ_FILE%"
) else (
    "%LLAMA_EXE%" ^
      --model "%MODEL_FILE%" ^
      --host "%LLAMA_HOST%" ^
      --port "%LLAMA_PORT%" ^
      --ctx-size "%LLAMA_CTX%" ^
      --n-gpu-layers "%LLAMA_GPU_LAYERS%" ^
      --alias "%LLAMA_ALIAS%"
)

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
del /q "%TEMP%\opencode_models_*.txt" >nul 2>&1
echo.
echo Server exited normally.
call :log Script finished successfully
goto :_end

:_end
pause
endlocal & exit /b 0

:log
echo [%DATE% %TIME%] %*>>"%LOG_FILE%"
echo [%DATE% %TIME%] %*
exit /b 0
