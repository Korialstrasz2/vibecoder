@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"

set "LOG_FILE=%~dp0start_server.log"

call :log ==========================================
call :log Starting llama-server launcher in "%CD%"
call :log Timestamp: %DATE% %TIME%

rem --- Load optional overrides first ---
if exist "local_settings.bat" (
    call :log Found local_settings.bat, loading it
    call "local_settings.bat"
) else (
    call :log No local_settings.bat found, using defaults
)

rem --- Defaults ---
if not defined LLAMA_HOST set "LLAMA_HOST=127.0.0.1"
if not defined LLAMA_PORT set "LLAMA_PORT=8080"
if not defined LLAMA_CTX set "LLAMA_CTX=32768"
if not defined LLAMA_GPU_LAYERS set "LLAMA_GPU_LAYERS=999"
if not defined LLAMA_ALIAS set "LLAMA_ALIAS=qwen-local"
if not defined LLAMA_EXE set "LLAMA_EXE=%CD%\runtime\llama.cpp\llama-server.exe"
if not defined LLAMA_ENABLE_VISION set "LLAMA_ENABLE_VISION=1"

call :log LLAMA_HOST=!LLAMA_HOST!
call :log LLAMA_PORT=!LLAMA_PORT!
call :log LLAMA_CTX=!LLAMA_CTX!
call :log LLAMA_GPU_LAYERS=!LLAMA_GPU_LAYERS!
call :log LLAMA_ALIAS=!LLAMA_ALIAS!
call :log LLAMA_ENABLE_VISION=!LLAMA_ENABLE_VISION!
call :log Initial LLAMA_EXE=!LLAMA_EXE!

rem --- Context profile selection / preset ---
if defined CONTEXT_PROFILE (
    if /I "!CONTEXT_PROFILE!"=="short" (
        set "LLAMA_CTX=16384"
        set "PROFILE_DISPLAY=short (16k)"
    ) else if /I "!CONTEXT_PROFILE!"=="long" (
        set "LLAMA_CTX=65536"
        set "PROFILE_DISPLAY=long (64k)"
    ) else if /I "!CONTEXT_PROFILE!"=="ultra" (
        set "LLAMA_CTX=131072"
        set "PROFILE_DISPLAY=ultra (128k)"
    ) else (
        set "PROFILE_DISPLAY=custom (!CONTEXT_PROFILE!)"
    )
    call :log Using preset profile: !PROFILE_DISPLAY!
) else (
    echo.
    echo --- Context Profile ---
    echo 1. short  - 16k context  (fast, good for simple tasks)
    echo 2. long   - 64k context  (balanced)
    echo 3. ultra  - 128k context (slower, for complex/large codebases)
    echo.
    :ask_profile
    set "PROFILE_CHOICE="
    set /p "PROFILE_CHOICE=Choose profile (1-3) [default 2]: "
    if not defined PROFILE_CHOICE set "PROFILE_CHOICE=2"

    if "!PROFILE_CHOICE!"=="1" (
        set "LLAMA_CTX=16384"
        set "PROFILE_DISPLAY=short (16k)"
    ) else if "!PROFILE_CHOICE!"=="2" (
        set "LLAMA_CTX=65536"
        set "PROFILE_DISPLAY=long (64k)"
    ) else if "!PROFILE_CHOICE!"=="3" (
        set "LLAMA_CTX=131072"
        set "PROFILE_DISPLAY=ultra (128k)"
    ) else (
        echo [WARN] Invalid selection. Enter 1, 2, or 3.
        goto :ask_profile
    )

    call :log Context profile: !PROFILE_DISPLAY!
)

rem --- Resolve executable ---
if exist "!LLAMA_EXE!" (
    call :log Found llama-server.exe at "!LLAMA_EXE!"
) else if exist "%CD%\runtime\llama.cpp\build\bin\llama-server.exe" (
    set "LLAMA_EXE=%CD%\runtime\llama.cpp\build\bin\llama-server.exe"
    call :log Fallback executable found at "!LLAMA_EXE!"
) else (
    call :log ERROR: llama-server.exe not found
    echo [ERROR] llama-server.exe not found.
    echo Checked:
    echo   "!LLAMA_EXE!"
    echo   "%CD%\runtime\llama.cpp\build\bin\llama-server.exe"
    echo.
    echo Set LLAMA_EXE in local_settings.bat or place llama-server.exe in:
    echo   runtime\llama.cpp\
    echo   or runtime\llama.cpp\build\bin\
    goto :fail
)

for %%I in ("!LLAMA_EXE!") do set "LLAMA_EXE_DIR=%%~dpI"
call :log Using LLAMA_EXE_DIR="!LLAMA_EXE_DIR!"

rem --- Resolve model ---
if defined MODEL_FILE (
    call :log MODEL_FILE preset to "!MODEL_FILE!"
    if not exist "!MODEL_FILE!" (
        call :log ERROR: Preset MODEL_FILE does not exist: "!MODEL_FILE!"
        echo [ERROR] MODEL_FILE does not exist:
        echo   "!MODEL_FILE!"
        goto :fail
    )
) else (
    set "MODEL_FILE="
    set /a MODEL_COUNT=0

    for /r "%CD%\models" %%F in (*.gguf) do (
        set /a MODEL_COUNT+=1
        set "MODEL_PATH_!MODEL_COUNT!=%%~fF"
        set "MODEL_NAME_!MODEL_COUNT!=%%~nxF"
    )

    if !MODEL_COUNT! EQU 0 (
        call :log ERROR: No .gguf model found under "%CD%\models"
        echo [ERROR] No .gguf model found in:
        echo   "%CD%\models"
        echo.
        echo Put one GGUF file in models\ including subfolders, or set MODEL_FILE in local_settings.bat.
        goto :fail
    )

    if !MODEL_COUNT! EQU 1 (
        set "MODEL_CHOICE=1"
        call set "MODEL_FILE=%%MODEL_PATH_1%%"
        call set "MODEL_FILE_NAME=%%MODEL_NAME_1%%"
        call :log Found 1 model, auto-selected: "!MODEL_FILE_NAME!"
    ) else (
        call :log Found !MODEL_COUNT! models
        call :log Listing models:
        for /L %%N in (1,1,!MODEL_COUNT!) do (
            call echo   %%N. %%MODEL_NAME_%%N%%
            call :log   %%N. %%MODEL_NAME_%%N%%
        )
        echo.
        :ask_model
        set "MODEL_CHOICE="
        set /p "MODEL_CHOICE=Choose model (1-!MODEL_COUNT!) [default 1]: "
        if not defined MODEL_CHOICE set "MODEL_CHOICE=1"

        echo(!MODEL_CHOICE!| findstr /R "^[1-9][0-9]*$" >nul
        if errorlevel 1 (
            echo [WARN] Invalid selection. Enter a number from 1 to !MODEL_COUNT!.
            goto :ask_model
        )
        if !MODEL_CHOICE! GTR !MODEL_COUNT! (
            echo [WARN] Invalid selection. Enter a number from 1 to !MODEL_COUNT!.
            goto :ask_model
        )

        call set "MODEL_FILE=%%MODEL_PATH_!MODEL_CHOICE!%%"
        call set "MODEL_FILE_NAME=%%MODEL_NAME_!MODEL_CHOICE!%%"
        call :log Selected model option !MODEL_CHOICE!
        call :log MODEL_FILE selected: "!MODEL_FILE!"
    )
)

if not defined MODEL_FILE_NAME for %%I in ("!MODEL_FILE!") do set "MODEL_FILE_NAME=%%~nxI"
call :log MODEL_FILE_NAME=!MODEL_FILE_NAME!

rem --- Sampling profile selection (auto for Qwen3.6, otherwise keep llama.cpp-like defaults) ---
if not defined LLAMA_SAMPLING_PROFILE (
    echo !MODEL_FILE_NAME! | findstr /I /C:"qwen3.6" >nul
    if not errorlevel 1 (
        set "LLAMA_SAMPLING_PROFILE=qwen-coding-precise"
        call :log Auto-selected LLAMA_SAMPLING_PROFILE=qwen-coding-precise based on model filename
    ) else (
        call :log No Qwen3.6 marker in model filename, keeping llama.cpp-like sampling defaults
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

if not defined LLAMA_TEMPERATURE set "LLAMA_TEMPERATURE=0.8"
if not defined LLAMA_TOP_K set "LLAMA_TOP_K=40"
if not defined LLAMA_TOP_P set "LLAMA_TOP_P=0.95"
if not defined LLAMA_MIN_P set "LLAMA_MIN_P=0.05"
if not defined LLAMA_PRESENCE_PENALTY set "LLAMA_PRESENCE_PENALTY=0.0"
if not defined LLAMA_REPEAT_PENALTY set "LLAMA_REPEAT_PENALTY=1.0"

call :log LLAMA_SAMPLING_PROFILE=!LLAMA_SAMPLING_PROFILE!
call :log LLAMA_TEMPERATURE=!LLAMA_TEMPERATURE!
call :log LLAMA_TOP_K=!LLAMA_TOP_K!
call :log LLAMA_TOP_P=!LLAMA_TOP_P!
call :log LLAMA_MIN_P=!LLAMA_MIN_P!
call :log LLAMA_PRESENCE_PENALTY=!LLAMA_PRESENCE_PENALTY!
call :log LLAMA_REPEAT_PENALTY=!LLAMA_REPEAT_PENALTY!

call :log Using MODEL_FILE="!MODEL_FILE!"

rem --- Resolve mmproj for vision (optional) ---
set "MMPROJ_FILE_RESOLVED="
set "MMPROJ_MATCH_QUALITY="

if /I "!LLAMA_ENABLE_VISION!"=="0" (
    call :log LLAMA_ENABLE_VISION=0, skipping mmproj detection
) else (
    if defined MMPROJ_FILE (
        call :log MMPROJ_FILE preset to "!MMPROJ_FILE!"
        if exist "!MMPROJ_FILE!" (
            set "MMPROJ_FILE_RESOLVED=!MMPROJ_FILE!"
            set "MMPROJ_MATCH_QUALITY=preset"
        ) else (
            call :log WARNING: preset MMPROJ_FILE does not exist: "!MMPROJ_FILE!"
            echo [WARN] MMPROJ_FILE was set but does not exist:
            echo        "!MMPROJ_FILE!"
        )
    )

    if not defined MMPROJ_FILE_RESOLVED (
        call :try_mmproj_family "%CD%\model_vision"
        if not defined MMPROJ_FILE_RESOLVED call :try_mmproj_family "%CD%\models"
    )

    if not defined MMPROJ_FILE_RESOLVED (
        call :try_mmproj_generic "%CD%\model_vision"
        if not defined MMPROJ_FILE_RESOLVED call :try_mmproj_generic "%CD%\models"
    )

    if not defined MMPROJ_FILE_RESOLVED (
        call :log No mmproj file detected; server will start in text-only mode unless the model bundles projector weights
        echo [WARN] No mmproj file detected in model_vision\ or models\.
        echo        Vision/image input may fail unless your model bundles projector weights.
    ) else (
        call :log Vision projector selected [!MMPROJ_MATCH_QUALITY!]: "!MMPROJ_FILE_RESOLVED!"
        echo [INFO] Vision projector: "!MMPROJ_FILE_RESOLVED!"
        if /I "!MMPROJ_MATCH_QUALITY!"=="generic" (
            echo [WARN] The projector match was generic, not family-specific.
            echo        If vision behaves oddly, set MMPROJ_FILE explicitly in local_settings.bat.
            call :log WARNING: mmproj match is generic; explicit MMPROJ_FILE is recommended
        )
    )
)

rem --- Update opencode context limit ---
if exist "%CD%\config\opencode\opencode.jsonc" (
    call :log Updating opencode.jsonc context limit to !LLAMA_CTX!
    powershell -NoProfile -Command ^
      "$p='%CD%\config\opencode\opencode.jsonc';" ^
      "$text = Get-Content -Raw $p;" ^
      "$updated = [regex]::Replace($text, '\"context\"\s*:\s*\d+', ('\"context\": ' + !LLAMA_CTX!));" ^
      "Set-Content -Path $p -Value $updated;"
    if errorlevel 1 (
        call :log WARNING: failed to update opencode.jsonc context limit
    ) else (
        call :log opencode.jsonc context limit updated
    )
) else (
    call :log WARNING: config\opencode\opencode.jsonc not found, skipping context update
)

echo.
echo === Starting llama-server ===
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
echo Log:         !LOG_FILE!
echo.

call :log Launch command:
if defined MMPROJ_FILE_RESOLVED (
    call :log "!LLAMA_EXE!" --model "!MODEL_FILE!" --mmproj "!MMPROJ_FILE_RESOLVED!" --host "!LLAMA_HOST!" --port "!LLAMA_PORT!" --ctx-size "!LLAMA_CTX!" --n-gpu-layers "!LLAMA_GPU_LAYERS!" --alias "!LLAMA_ALIAS!" --temp "!LLAMA_TEMPERATURE!" --top-k "!LLAMA_TOP_K!" --top-p "!LLAMA_TOP_P!" --min-p "!LLAMA_MIN_P!" --presence-penalty "!LLAMA_PRESENCE_PENALTY!" --repeat-penalty "!LLAMA_REPEAT_PENALTY!"
) else (
    call :log "!LLAMA_EXE!" --model "!MODEL_FILE!" --host "!LLAMA_HOST!" --port "!LLAMA_PORT!" --ctx-size "!LLAMA_CTX!" --n-gpu-layers "!LLAMA_GPU_LAYERS!" --alias "!LLAMA_ALIAS!" --temp "!LLAMA_TEMPERATURE!" --top-k "!LLAMA_TOP_K!" --top-p "!LLAMA_TOP_P!" --min-p "!LLAMA_MIN_P!" --presence-penalty "!LLAMA_PRESENCE_PENALTY!" --repeat-penalty "!LLAMA_REPEAT_PENALTY!"
)

pushd "!LLAMA_EXE_DIR!" >nul 2>&1
if errorlevel 1 (
    call :log ERROR: Could not enter llama executable directory "!LLAMA_EXE_DIR!"
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

:try_mmproj_family
if not exist "%~1" exit /b 0

echo !MODEL_FILE_NAME! | findstr /I /C:"Qwen3.6-27B" >nul
if not errorlevel 1 (
    for /r "%~1" %%F in (*Qwen3.6-27B*mmproj*.gguf mmproj*Qwen3.6-27B*.gguf) do (
        if not defined MMPROJ_FILE_RESOLVED (
            set "MMPROJ_FILE_RESOLVED=%%~fF"
            set "MMPROJ_MATCH_QUALITY=family-qwen3.6-27b"
        )
    )
    if defined MMPROJ_FILE_RESOLVED exit /b 0
)

echo !MODEL_FILE_NAME! | findstr /I /C:"Qwen3.6-35B" >nul
if not errorlevel 1 (
    for /r "%~1" %%F in (*Qwen3.6-35B*mmproj*.gguf mmproj*Qwen3.6-35B*.gguf *35B*mmproj*.gguf mmproj*35B*.gguf mmproj-BF16.gguf) do (
        if not defined MMPROJ_FILE_RESOLVED (
            set "MMPROJ_FILE_RESOLVED=%%~fF"
            set "MMPROJ_MATCH_QUALITY=family-qwen3.6-35b"
        )
    )
    if defined MMPROJ_FILE_RESOLVED exit /b 0
)

echo !MODEL_FILE_NAME! | findstr /I /C:"27B" >nul
if not errorlevel 1 (
    for /r "%~1" %%F in (*27B*mmproj*.gguf mmproj*27B*.gguf) do (
        if not defined MMPROJ_FILE_RESOLVED (
            set "MMPROJ_FILE_RESOLVED=%%~fF"
            set "MMPROJ_MATCH_QUALITY=size-27b"
        )
    )
    if defined MMPROJ_FILE_RESOLVED exit /b 0
)

echo !MODEL_FILE_NAME! | findstr /I /C:"35B" >nul
if not errorlevel 1 (
    for /r "%~1" %%F in (*35B*mmproj*.gguf mmproj*35B*.gguf mmproj-BF16.gguf) do (
        if not defined MMPROJ_FILE_RESOLVED (
            set "MMPROJ_FILE_RESOLVED=%%~fF"
            set "MMPROJ_MATCH_QUALITY=size-35b"
        )
    )
    if defined MMPROJ_FILE_RESOLVED exit /b 0
)

exit /b 0

:try_mmproj_generic
if not exist "%~1" exit /b 0
for /r "%~1" %%F in (mmproj*.gguf) do (
    if not defined MMPROJ_FILE_RESOLVED (
        set "MMPROJ_FILE_RESOLVED=%%~fF"
        set "MMPROJ_MATCH_QUALITY=generic"
    )
)
exit /b 0

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
