@echo off
setlocal EnableExtensions EnableDelayedExpansion
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
    for /r "%CD%\models" %%F in (*.gguf) do echo %%~fF >>"!MODEL_PICKER_TEMP!"

    call :log Listing models:
    set "MODEL_IDX=0"
    for /f "usebackq delims=" %%M in ("!MODEL_PICKER_TEMP!") do (
        set /a MODEL_IDX+=1
        set "MODEL_PICKER_NAME=%%~nxM"
        call :log   !MODEL_IDX!. !MODEL_PICKER_NAME!
    )
    echo.
    choice /t 3 /d 1 /n /c 1234567890 /m "Choose model (1-%MODEL_COUNT%): "
    if errorlevel %MODEL_COUNT% ( set "MODEL_CHOICE=%MODEL_COUNT%" ) else ( set "MODEL_CHOICE=%errorlevel%" )

    call :log Selected model option !MODEL_CHOICE!
    set /a MODEL_IDX=0
    for /f "usebackq delims=" %%M in ("!MODEL_PICKER_TEMP!") do (
        set /a MODEL_IDX+=1
        if !MODEL_IDX!==!MODEL_CHOICE! (
            set "MODEL_FILE=%%~fM"
            goto :picker_done
        )
    )
    :picker_done
    del /q "!MODEL_PICKER_TEMP!" >nul 2>&1

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
if not defined LLAMA_GPU_LAYERS set "LLAMA_GPU_LAYERS=999"
if not defined LLAMA_ALIAS set "LLAMA_ALIAS=qwen-local"
if not defined LLAMA_EXE set "LLAMA_EXE=%CD%\runtime\llama.cpp\llama-server.exe"
if not defined LLAMA_ENABLE_VISION set "LLAMA_ENABLE_VISION=1"

call :log LLAMA_HOST=%LLAMA_HOST%
call :log LLAMA_PORT=%LLAMA_PORT%
call :log LLAMA_CTX=%LLAMA_CTX%
call :log LLAMA_GPU_LAYERS=%LLAMA_GPU_LAYERS%
call :log LLAMA_ALIAS=%LLAMA_ALIAS%
call :log LLAMA_ENABLE_VISION=%LLAMA_ENABLE_VISION%
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

rem --- Resolve mmproj for vision (optional, but recommended for Qwen3.6 vision) ---
set "MMPROJ_FILE_RESOLVED="
for %%I in ("%MODEL_FILE%") do set "MODEL_FILE_NAME=%%~nxI"
if /I "%LLAMA_ENABLE_VISION%"=="0" (
    call :log LLAMA_ENABLE_VISION=0, skipping mmproj detection
) else (
    if defined MMPROJ_FILE (
        call :log MMPROJ_FILE preset to "%MMPROJ_FILE%"
        if exist "%MMPROJ_FILE%" (
            set "MMPROJ_FILE_RESOLVED=%MMPROJ_FILE%"
        ) else (
            call :log WARNING: preset MMPROJ_FILE does not exist: "%MMPROJ_FILE%"
            echo [WARN] MMPROJ_FILE was set but does not exist:
            echo        "%MMPROJ_FILE%"
        )
    )

    if not defined MMPROJ_FILE_RESOLVED (
        if /I not "%MODEL_FILE_NAME:27B=%"=="%MODEL_FILE_NAME%" (
            for /r "%CD%\model_vision" %%F in (*27B*mmproj*.gguf mmproj*27B*.gguf) do (
                if not defined MMPROJ_FILE_RESOLVED set "MMPROJ_FILE_RESOLVED=%%~fF"
            )
            if not defined MMPROJ_FILE_RESOLVED (
                for /r "%CD%\models" %%F in (*27B*mmproj*.gguf mmproj*27B*.gguf) do (
                    if not defined MMPROJ_FILE_RESOLVED set "MMPROJ_FILE_RESOLVED=%%~fF"
                )
            )
            if defined MMPROJ_FILE_RESOLVED call :log Matched 27B model to mmproj: "%MMPROJ_FILE_RESOLVED%"
        )
    )

    if not defined MMPROJ_FILE_RESOLVED (
        if /I not "%MODEL_FILE_NAME:35B=%"=="%MODEL_FILE_NAME%" (
            for /r "%CD%\model_vision" %%F in (*35B*mmproj*.gguf mmproj*35B*.gguf mmproj-BF16.gguf) do (
                if not defined MMPROJ_FILE_RESOLVED set "MMPROJ_FILE_RESOLVED=%%~fF"
            )
            if not defined MMPROJ_FILE_RESOLVED (
                for /r "%CD%\models" %%F in (*35B*mmproj*.gguf mmproj*35B*.gguf mmproj-BF16.gguf) do (
                    if not defined MMPROJ_FILE_RESOLVED set "MMPROJ_FILE_RESOLVED=%%~fF"
                )
            )
            if defined MMPROJ_FILE_RESOLVED call :log Matched 35B model to mmproj: "%MMPROJ_FILE_RESOLVED%"
        )
    )

    if not defined MMPROJ_FILE_RESOLVED (
        for /r "%CD%\model_vision" %%F in (mmproj*.gguf) do (
            if not defined MMPROJ_FILE_RESOLVED set "MMPROJ_FILE_RESOLVED=%%~fF"
        )
        if defined MMPROJ_FILE_RESOLVED call :log Auto-detected mmproj under model_vision: "%MMPROJ_FILE_RESOLVED%"
    )

    if not defined MMPROJ_FILE_RESOLVED (
        for /r "%CD%\models" %%F in (mmproj*.gguf) do (
            if not defined MMPROJ_FILE_RESOLVED set "MMPROJ_FILE_RESOLVED=%%~fF"
        )
        if defined MMPROJ_FILE_RESOLVED call :log Auto-detected mmproj under models: "%MMPROJ_FILE_RESOLVED%"
    )

    if not defined MMPROJ_FILE_RESOLVED (
        call :log No mmproj file detected; server will start in text-only mode unless model has built-in vision projector
        echo [WARN] No mmproj file detected in model_vision\ or models\.
        echo        Vision/image input may fail unless your model bundles projector weights.
    ) else (
        echo [INFO] Vision projector: "%MMPROJ_FILE_RESOLVED%"
    )
)

rem --- Update opencode context limit ---
call :log Updating opencode.jsonc context limit to %LLAMA_CTX%
powershell -NoProfile -Command ^
  "$p='%CD%\config\opencode\opencode.jsonc';" ^
  "$text = Get-Content -Raw $p;" ^
  "$updated = [regex]::Replace($text, '\"context\"\s*:\s*\d+', ('\"context\": ' + %LLAMA_CTX%));" ^
  "Set-Content -Path $p -Value $updated;"
if errorlevel 1 (
    call :log WARNING: failed to update opencode.jsonc context limit
) else (
    call :log opencode.jsonc context limit updated
)

echo.
echo === Starting llama-server ===
echo Model:       %MODEL_FILE%
echo URL:         http://%LLAMA_HOST%:%LLAMA_PORT%/v1
echo Models API:  http://%LLAMA_HOST%:%LLAMA_PORT%/v1/models
echo Ctx:         %LLAMA_CTX%
echo GPU layers:  %LLAMA_GPU_LAYERS%
echo Alias:       %LLAMA_ALIAS%
echo Log:         %LOG_FILE%
echo.

call :log Launch command:
if defined MMPROJ_FILE_RESOLVED (
    call :log "%LLAMA_EXE%" --model "%MODEL_FILE%" --mmproj "%MMPROJ_FILE_RESOLVED%" --host "%LLAMA_HOST%" --port "%LLAMA_PORT%" --ctx-size "%LLAMA_CTX%" --n-gpu-layers "%LLAMA_GPU_LAYERS%" --alias "%LLAMA_ALIAS%"
) else (
    call :log "%LLAMA_EXE%" --model "%MODEL_FILE%" --host "%LLAMA_HOST%" --port "%LLAMA_PORT%" --ctx-size "%LLAMA_CTX%" --n-gpu-layers "%LLAMA_GPU_LAYERS%" --alias "%LLAMA_ALIAS%"
)

pushd "%LLAMA_EXE_DIR%" >nul 2>&1
if errorlevel 1 (
    call :log ERROR: Could not enter llama executable directory "%LLAMA_EXE_DIR%"
    echo [ERROR] Could not change directory to:
    echo   "%LLAMA_EXE_DIR%"
    goto :fail
)

if defined MMPROJ_FILE_RESOLVED (
  "%LLAMA_EXE%" ^
    --model "%MODEL_FILE%" ^
    --mmproj "%MMPROJ_FILE_RESOLVED%" ^
    --host "%LLAMA_HOST%" ^
    --port "%LLAMA_PORT%" ^
    --ctx-size "%LLAMA_CTX%" ^
    --n-gpu-layers "%LLAMA_GPU_LAYERS%" ^
    --alias "%LLAMA_ALIAS%"
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
