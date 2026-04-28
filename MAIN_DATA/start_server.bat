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
    cmd /d /q /c "call \"local_settings.bat\" >nul 2>&1"
    if errorlevel 1 (
        call :log ERROR: local_settings.bat failed a syntax preflight check
        echo [ERROR] local_settings.bat contains invalid batch syntax.
        echo         Please fix the file, then run start_server again.
        echo         Tip: each setting should look like: set "NAME=value"
        goto :fail
    )
    call "local_settings.bat"
) else (
    call :log No local_settings.bat found, using defaults
)

rem --- Defaults ---
if not defined LLAMA_HOST set "LLAMA_HOST=127.0.0.1"
if not defined LLAMA_PORT set "LLAMA_PORT=8076"
if not defined LLAMA_CTX set "LLAMA_CTX=32768"
if not defined LLAMA_GPU_LAYERS set "LLAMA_GPU_LAYERS=999"
if not defined LLAMA_ALIAS set "LLAMA_ALIAS=qwen-local"
if not defined LLAMA_EXE set "LLAMA_EXE=%CD%\runtime\llama.cpp\llama-server.exe"
if not defined LLAMA_ENABLE_VISION set "LLAMA_ENABLE_VISION=1"

rem --- Compute mode selection ---
rem When CONTEXT_PROFILE is set (UI launch), skip interactive prompt and use preset GPU layers.
rem When LLAMA_GPU_LAYERS is 0, treat as CPU-only; otherwise use GPU with the already-configured layers.
set "LLAMA_GPU_LAYERS_GPU_DEFAULT=!LLAMA_GPU_LAYERS!"

if defined CONTEXT_PROFILE (
    rem UI/automated launch mode: skip interactive prompt
    set "LLAMA_COMPUTE_MODE=GPU"
    if "!LLAMA_GPU_LAYERS!"=="0" set "LLAMA_COMPUTE_MODE=CPU"
    echo [INFO] UI-launch mode: Compute mode=!LLAMA_COMPUTE_MODE! (GPU layers=!LLAMA_GPU_LAYERS!)
    call :log UI launch mode detected, skipping compute-mode prompt: !LLAMA_COMPUTE_MODE!
) else (
    rem Interactive mode
    echo.
    echo --- Compute Mode ---
    echo 1. CPU only  - no GPU offload
    echo 2. GPU       - use configured GPU layers [default]
    echo.
    echo Choose compute mode (1-2) [default 2 in 4 seconds].
    echo Press Enter for GPU.

    powershell -NoProfile -ExecutionPolicy Bypass -Command ^
      "$timeout = 4;" ^
      "$deadline = [DateTime]::UtcNow.AddSeconds($timeout);" ^
      "Write-Host -NoNewline 'Selection: ';" ^
      "while ([DateTime]::UtcNow -lt $deadline) {" ^
      "  if ([Console]::KeyAvailable) {" ^
      "    $key = [Console]::ReadKey($true);" ^
      "    if ($key.Key -eq 'Enter') { Write-Host ''; exit 2 }" ^
      "    if ($key.KeyChar -eq '1') { Write-Host '1'; exit 1 }" ^
      "    if ($key.KeyChar -eq '2') { Write-Host '2'; exit 2 }" ^
      "  }" ^
      "  Start-Sleep -Milliseconds 50;" ^
      "}" ^
      "Write-Host ''; exit 2"

    if errorlevel 2 (
        set "LLAMA_COMPUTE_MODE=GPU"
        set "LLAMA_GPU_LAYERS=!LLAMA_GPU_LAYERS_GPU_DEFAULT!"
    ) else if errorlevel 1 (
        set "LLAMA_COMPUTE_MODE=CPU"
        set "LLAMA_GPU_LAYERS=0"
    ) else (
        rem If PowerShell is unavailable or returns unexpectedly, fail safe to GPU default.
        set "LLAMA_COMPUTE_MODE=GPU"
        set "LLAMA_GPU_LAYERS=!LLAMA_GPU_LAYERS_GPU_DEFAULT!"
    )

    echo [INFO] Compute mode: !LLAMA_COMPUTE_MODE!
    if /I "!LLAMA_COMPUTE_MODE!"=="CPU" echo [INFO] CPU-only selected: LLAMA_GPU_LAYERS=0
    if /I "!LLAMA_COMPUTE_MODE!"=="GPU" echo [INFO] GPU selected: LLAMA_GPU_LAYERS=!LLAMA_GPU_LAYERS!
)

call :log LLAMA_HOST=!LLAMA_HOST!
call :log LLAMA_PORT=!LLAMA_PORT!
call :log LLAMA_CTX=!LLAMA_CTX!
call :log LLAMA_COMPUTE_MODE=!LLAMA_COMPUTE_MODE!
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
    set "MODEL_SELECTION_FILE=%TEMP%\llama_model_choice_%RANDOM%.txt"
    if exist "!MODEL_SELECTION_FILE!" del "!MODEL_SELECTION_FILE!" >nul 2>&1

    powershell -NoProfile -ExecutionPolicy Bypass -Command ^
      "$root = Join-Path (Get-Location).Path 'models';" ^
      "if (-not (Test-Path $root)) { exit 10 }" ^
      "$models = @(Get-ChildItem -Path $root -Recurse -Filter '*.gguf' -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch 'mmproj' } | Sort-Object DirectoryName, Name);" ^
      "if ($models.Count -eq 0) { exit 11 }" ^
      "function Format-Size([long]$bytes) { if ($bytes -ge 1GB) { return ('{0:N1} GB' -f ($bytes / 1GB)) } elseif ($bytes -ge 1MB) { return ('{0:N0} MB' -f ($bytes / 1MB)) } else { return ('{0:N0} KB' -f ($bytes / 1KB)) } }" ^
      "if ($models.Count -eq 1) { Write-Host ''; Write-Host '=== Available models ==='; Write-Host ('Auto-selected: {0} ({1})' -f $models[0].Name, (Format-Size $models[0].Length)); $models[0].FullName | Set-Content -Encoding ASCII -NoNewline '!MODEL_SELECTION_FILE!'; exit 0 }" ^
      "Write-Host ''; Write-Host '=== Available models ===';" ^
      "Write-Host ('{0,3}  {1,9}  {2}' -f '#','Size','Model');" ^
      "Write-Host ('{0,3}  {1,9}  {2}' -f '---','---------','-----');" ^
      "$i = 1; foreach ($m in $models) { $rel = $m.FullName.Substring($root.Length).TrimStart('\','/'); $folder = Split-Path $rel -Parent; if ([string]::IsNullOrWhiteSpace($folder)) { $folder = '.' }; Write-Host ('{0,3}  {1,9}  {2}' -f $i, (Format-Size $m.Length), $m.Name); Write-Host ('     folder: {0}' -f $folder); $i++ }" ^
      "while ($true) { $choice = Read-Host ('Choose model (1-{0}) [default 1]' -f $models.Count); if ([string]::IsNullOrWhiteSpace($choice)) { $choice = '1' }; $n = 0; if ([int]::TryParse($choice, [ref]$n) -and $n -ge 1 -and $n -le $models.Count) { $models[$n - 1].FullName | Set-Content -Encoding ASCII -NoNewline '!MODEL_SELECTION_FILE!'; exit 0 }; Write-Host '[WARN] Invalid selection. Enter a valid number.' }"

    if errorlevel 11 (
        call :log ERROR: No selectable text .gguf model found under "%CD%\models"
        echo [ERROR] No selectable text .gguf model found in:
        echo   "%CD%\models"
        echo.
        echo Put one non-mmproj GGUF file in models\ including subfolders, or set MODEL_FILE in local_settings.bat.
        goto :fail
    ) else if errorlevel 10 (
        call :log ERROR: models folder not found: "%CD%\models"
        echo [ERROR] models folder not found:
        echo   "%CD%\models"
        goto :fail
    ) else if errorlevel 1 (
        call :log ERROR: PowerShell model selector failed
        echo [ERROR] Model selector failed.
        goto :fail
    )

    if not exist "!MODEL_SELECTION_FILE!" (
        call :log ERROR: Model selector did not write a selection file
        echo [ERROR] Model selector did not return a model.
        goto :fail
    )

    set /p "MODEL_FILE="<"!MODEL_SELECTION_FILE!"
    del "!MODEL_SELECTION_FILE!" >nul 2>&1

    if not exist "!MODEL_FILE!" (
        call :log ERROR: Selected MODEL_FILE does not exist: "!MODEL_FILE!"
        echo [ERROR] Selected model does not exist:
        echo   "!MODEL_FILE!"
        goto :fail
    )

    for %%I in ("!MODEL_FILE!") do set "MODEL_FILE_NAME=%%~nxI"
    set "MODEL_DISPLAY=!MODEL_FILE:%CD%\models\=!"
    call :log MODEL_FILE selected: "!MODEL_FILE!"
    call :log MODEL_DISPLAY=!MODEL_DISPLAY!
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
        call :try_mmproj_same_dir
    )

    if not defined MMPROJ_FILE_RESOLVED (
        call :try_mmproj_family "%CD%\model_vision"
        if not defined MMPROJ_FILE_RESOLVED call :try_mmproj_family "%CD%\models"
    )

    rem Deliberately do not auto-load a generic mmproj*.gguf. Projectors are family-specific.
    rem To force a specific projector, set MMPROJ_FILE in local_settings.bat.

    if not defined MMPROJ_FILE_RESOLVED (
        call :log No compatible family-specific mmproj detected; server will start in text-only mode
        echo [WARN] No compatible family-specific mmproj detected.
        echo        Starting text-only to avoid loading the wrong projector.
        echo        To force vision, set MMPROJ_FILE explicitly in local_settings.bat.
    ) else (
        call :log Vision projector selected [!MMPROJ_MATCH_QUALITY!]: "!MMPROJ_FILE_RESOLVED!"
        echo [INFO] Vision projector: "!MMPROJ_FILE_RESOLVED!"
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

:try_mmproj_same_dir
for %%I in ("!MODEL_FILE!") do set "MODEL_DIR=%%~dpI"
if not exist "!MODEL_DIR!" exit /b 0
for %%F in ("!MODEL_DIR!*mmproj*.gguf") do (
    if exist "%%~fF" (
        if not defined MMPROJ_FILE_RESOLVED (
            set "MMPROJ_FILE_RESOLVED=%%~fF"
            set "MMPROJ_MATCH_QUALITY=same-folder"
        )
    )
)
exit /b 0

:try_mmproj_family
if not exist "%~1" exit /b 0

echo !MODEL_FILE_NAME! | findstr /I /C:"gemma" >nul
if not errorlevel 1 (
    for /r "%~1" %%F in (*gemma*mmproj*.gguf mmproj*gemma*.gguf) do (
        if not defined MMPROJ_FILE_RESOLVED (
            set "MMPROJ_FILE_RESOLVED=%%~fF"
            set "MMPROJ_MATCH_QUALITY=family-gemma"
        )
    )
    if defined MMPROJ_FILE_RESOLVED exit /b 0
)

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

rem Generic projector fallback intentionally disabled. A wrong projector can crash llama-server.
:try_mmproj_generic
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
