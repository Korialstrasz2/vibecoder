@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"

if not exist "logs" mkdir "logs"
for /f "delims=" %%I in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set "RUN_ID=%%I"
if not defined RUN_ID set "RUN_ID=%DATE:~-4%%DATE:~4,2%%DATE:~7,2%_%TIME:~0,2%%TIME:~3,2%%TIME:~6,2%"
set "RUN_ID=%RUN_ID: =0%"

set "MAIN_LOG=%CD%\logs\startup_%RUN_ID%.log"
set "SERVER_LOG=%CD%\logs\llama_server_%RUN_ID%.log"
set "LAST_FAILED_STEP="

echo ===============================================================================>"%MAIN_LOG%"
echo VibeCoder full startup run id: %RUN_ID%>>"%MAIN_LOG%"
echo Working directory: %CD%>>"%MAIN_LOG%"
echo Started at: %DATE% %TIME%>>"%MAIN_LOG%"
echo ===============================================================================>>"%MAIN_LOG%"

echo.
echo [INFO] VibeCoder one-click startup
echo [INFO] Main log:   %MAIN_LOG%
echo [INFO] Server log: %SERVER_LOG%
echo.

call :run_step "Load settings" :load_settings || goto :fatal
call :run_step "Check required commands" :check_required_commands || goto :fatal
call :run_step "Ensure opencode" :ensure_opencode || goto :fatal
call :run_step "Validate runtime/model files" :check_runtime_inputs || goto :fatal
call :run_step "Check llama port" :check_port_not_busy || goto :fatal
call :run_step "Install OpenCode config" :install_opencode_config || goto :fatal
call :run_step "Start llama-server" :start_server || goto :fatal
call :run_step "Wait for llama-server health" :wait_for_server || goto :fatal
call :run_step "Launch OpenCode" :launch_opencode || goto :fatal

echo [OK] Startup flow completed successfully.
call :log INFO "Startup flow completed successfully"
exit /b 0

:run_step
call :log INFO "STEP START: %~1"
call %~2
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" (
  set "LAST_FAILED_STEP=%~1"
  call :log ERROR "STEP FAILED: %~1 (exit %RC%)"
  exit /b %RC%
)
call :log INFO "STEP OK: %~1"
exit /b 0

:load_settings
if exist "local_settings.bat" (
  call :log INFO "Loading local_settings.bat"
  call "local_settings.bat" >>"%MAIN_LOG%" 2>&1
  if errorlevel 1 (
    call :log ERROR "local_settings.bat failed"
    echo [ERROR] local_settings.bat failed. See %MAIN_LOG%
    exit /b 1
  )
) else (
  call :log INFO "No local_settings.bat found; using defaults"
)
if "%LLAMA_HOST%"=="" set "LLAMA_HOST=127.0.0.1"
if "%LLAMA_PORT%"=="" set "LLAMA_PORT=8080"
if "%LLAMA_CTX%"=="" set "LLAMA_CTX=32768"
if "%LLAMA_GPU_LAYERS%"=="" set "LLAMA_GPU_LAYERS=999"
if "%LLAMA_ALIAS%"=="" set "LLAMA_ALIAS=qwen-local"
if "%LLAMA_EXE%"=="" set "LLAMA_EXE=%CD%\runtime\llama.cpp\llama-server.exe"
if "%MODEL_FILE%"=="" (
  set "MODEL_FILE="
  for %%F in ("%CD%\models\*.gguf") do (
    if exist "%%~fF" (
      set "MODEL_FILE=%%~fF"
      goto :_model_found
    )
  )
  for /f "delims=" %%F in ('dir /b /s "%CD%\models\*.gguf" 2^>nul') do (
    set "MODEL_FILE=%%~fF"
    goto :_model_found
  )
)
:_model_found
call :log INFO "Resolved settings: host=%LLAMA_HOST% port=%LLAMA_PORT% ctx=%LLAMA_CTX% alias=%LLAMA_ALIAS%"
exit /b 0

:check_required_commands
call :require_cmd powershell "PowerShell is required for health checks and timestamped logs."
if errorlevel 1 exit /b 1
call :require_cmd node "Node.js is required for OpenCode."
if errorlevel 1 exit /b 1
call :require_cmd npm "npm is required for OpenCode installation."
if errorlevel 1 exit /b 1
exit /b 0

:ensure_opencode
where opencode >nul 2>nul
if errorlevel 1 (
  call :log WARN "opencode command not found; attempting npm install -g opencode-ai"
  echo [WARN] opencode was not found. Trying to install globally with npm...
  call npm install -g opencode-ai >>"%MAIN_LOG%" 2>&1
  if errorlevel 1 (
    call :log ERROR "Failed to install opencode-ai globally"
    echo [ERROR] Could not install opencode-ai automatically.
    echo         Please run setup_tools.bat manually and retry.
    exit /b 1
  )
)
where opencode >nul 2>nul
if errorlevel 1 (
  call :log ERROR "opencode still not found after installation attempt"
  echo [ERROR] opencode command is still unavailable after install attempt.
  exit /b 1
)
call :log INFO "opencode command is available"
exit /b 0

:check_runtime_inputs
set "RUNTIME_ERR=0"
call :log INFO "Runtime validation input: LLAMA_EXE=%LLAMA_EXE%"
call :log INFO "Runtime validation input: MODEL_FILE=%MODEL_FILE%"
if not exist "%CD%\runtime" (
  call :log WARN "runtime\ directory does not exist under %CD%"
)
if not exist "%CD%\models" (
  call :log WARN "models\ directory does not exist under %CD%"
)
if not exist "%LLAMA_EXE%" (
  if exist "%CD%\runtime\llama.cpp\build\bin\llama-server.exe" (
    set "LLAMA_EXE=%CD%\runtime\llama.cpp\build\bin\llama-server.exe"
    call :log INFO "Using llama-server from build output: %LLAMA_EXE%"
  ) else (
    call :log ERROR "llama-server.exe not found at %LLAMA_EXE%"
    echo [ERROR] llama-server.exe not found:
    echo         %LLAMA_EXE%
    echo         Checked fallback path:
    echo         %CD%\runtime\llama.cpp\build\bin\llama-server.exe
    if not exist "%CD%\runtime\llama.cpp" (
      echo         runtime\llama.cpp\ is missing.
      echo         Run setup_runtime.bat first to install/build llama.cpp runtime files.
    ) else (
      echo         Set LLAMA_EXE in local_settings.bat or place llama-server.exe in:
      echo         runtime\llama.cpp\    (or runtime\llama.cpp\build\bin\)
    )
    set "RUNTIME_ERR=1"
  )
)
if "%MODEL_FILE%"=="" (
  call :log ERROR "No .gguf model found in %CD%\models"
  echo [ERROR] No model file found in models\ (expected *.gguf)
  echo         You can also set MODEL_FILE in local_settings.bat to an absolute path.
  if not exist "%CD%\models" (
    echo         models\ directory does not exist yet.
    echo         Create models\ and copy at least one .gguf model into it.
  )
  set "RUNTIME_ERR=1"
) else (
  if not exist "%MODEL_FILE%" (
    call :log ERROR "MODEL_FILE path does not exist: %MODEL_FILE%"
    echo [ERROR] MODEL_FILE points to a file that does not exist:
    echo         %MODEL_FILE%
    echo         Update MODEL_FILE in local_settings.bat or copy the model file to that path.
    set "RUNTIME_ERR=1"
  ) else (
    for %%E in ("%MODEL_FILE%") do set "MODEL_EXT=%%~xE"
    if /I not "!MODEL_EXT!"==".gguf" (
      call :log WARN "MODEL_FILE does not end with .gguf: %MODEL_FILE%"
      echo [WARN] MODEL_FILE does not have .gguf extension:
      echo        %MODEL_FILE%
      echo        llama-server usually expects GGUF models. Verify this is intentional.
    )
  )
)
if "%RUNTIME_ERR%"=="1" (
  echo [INFO] Detected .gguf files under models\ (if any):
  for /f "delims=" %%F in ('dir /b "%CD%\models\*.gguf" 2^>nul') do echo        - %%F
  echo [INFO] Tip: You can override both paths in local_settings.bat:
  echo        set LLAMA_EXE=...
  echo        set MODEL_FILE=...
  exit /b 1
)
call :log INFO "Using model file: %MODEL_FILE%"
exit /b 0

:check_port_not_busy
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $inUse=Get-NetTCPConnection -State Listen -LocalPort %LLAMA_PORT% -ErrorAction SilentlyContinue; if($inUse){exit 10}else{exit 0}" >>"%MAIN_LOG%" 2>&1
if "%ERRORLEVEL%"=="10" (
  call :log ERROR "Port %LLAMA_PORT% already has a listening process"
  echo [ERROR] Port %LLAMA_PORT% is already in use.
  echo         Stop the process using that port or set LLAMA_PORT in local_settings.bat.
  exit /b 1
)
if not "%ERRORLEVEL%"=="0" (
  call :log WARN "Could not reliably query port usage; continuing"
)
exit /b 0

:install_opencode_config
if not defined APPDATA (
  call :log ERROR "APPDATA is not defined; cannot install OpenCode config"
  echo [ERROR] APPDATA is not defined in this shell.
  echo         Run this from a normal Windows user shell and retry.
  exit /b 1
)
if not exist "%APPDATA%\opencode" mkdir "%APPDATA%\opencode" >>"%MAIN_LOG%" 2>&1
copy /Y "config\opencode\opencode.jsonc" "%APPDATA%\opencode\opencode.jsonc" >nul
if errorlevel 1 (
  call :log ERROR "Failed to copy OpenCode config to %APPDATA%\opencode"
  echo [ERROR] Could not install OpenCode config.
  exit /b 1
)
call :log INFO "Installed OpenCode config to %APPDATA%\opencode\opencode.jsonc"
exit /b 0

:start_server
call :log INFO "Starting llama-server in a new window"
echo [INFO] Starting llama-server...
start "vibecoder-llama-server" cmd /c "\"%LLAMA_EXE%\" --model \"%MODEL_FILE%\" --host \"%LLAMA_HOST%\" --port \"%LLAMA_PORT%\" --ctx-size \"%LLAMA_CTX%\" --n-gpu-layers \"%LLAMA_GPU_LAYERS%\" --alias \"%LLAMA_ALIAS%\" 1>>\"%SERVER_LOG%\" 2>&1"
if errorlevel 1 (
  call :log ERROR "Failed to launch llama-server process"
  echo [ERROR] Failed to launch llama-server process.
  exit /b 1
)
exit /b 0

:wait_for_server
call :log INFO "Waiting for llama-server health endpoint"
echo [INFO] Waiting for server health check at http://%LLAMA_HOST%:%LLAMA_PORT%/v1/models ...
set /a WAIT_SEC=0
:wait_loop
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $null = Invoke-RestMethod -Uri 'http://%LLAMA_HOST%:%LLAMA_PORT%/v1/models' -TimeoutSec 3; exit 0 } catch { exit 1 }" >>"%MAIN_LOG%" 2>&1
if not errorlevel 1 goto :wait_ok
set /a WAIT_SEC+=2
if %WAIT_SEC% GEQ 60 (
  call :log ERROR "Server health check timed out after %WAIT_SEC% seconds"
  echo [ERROR] llama-server did not become healthy within %WAIT_SEC% seconds.
  echo         Review server log: %SERVER_LOG%
  exit /b 1
)
timeout /t 2 /nobreak >nul
goto :wait_loop

:wait_ok
call :log INFO "Server health check passed"
echo [OK] llama-server is healthy.
exit /b 0

:launch_opencode
if not exist "projects" mkdir "projects" >>"%MAIN_LOG%" 2>&1
cd projects
call :log INFO "Launching opencode in %CD%"
echo [INFO] Launching OpenCode in projects\ ...
opencode
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" (
  cd /d "%~dp0"
  call :log ERROR "opencode exited with code %RC%"
  echo [ERROR] opencode exited with code %RC%.
  exit /b %RC%
)
cd /d "%~dp0"
call :log INFO "opencode exited successfully"
exit /b 0

:require_cmd
where %~1 >nul 2>nul
if errorlevel 1 (
  call :log ERROR "%~1 command not found"
  echo [ERROR] %~2
  exit /b 1
)
call :log INFO "Found command: %~1"
exit /b 0

:log
set "LEVEL=%~1"
set "MSG=%~2"
set "STAMP="
for /f "delims=" %%I in ('powershell -NoProfile -Command "Get-Date -Format \"yyyy-MM-dd HH:mm:ss\""') do set "STAMP=%%I"
if not defined STAMP set "STAMP=%DATE% %TIME%"
>>"%MAIN_LOG%" echo [%STAMP%] [%LEVEL%] %MSG%
exit /b 0

:fatal
set "RC=%ERRORLEVEL%"
if not defined LAST_FAILED_STEP set "LAST_FAILED_STEP=Unknown step"
echo.
echo [FATAL] Startup aborted at step: %LAST_FAILED_STEP% (exit %RC%)
echo         See logs for details:
echo         %MAIN_LOG%
echo         %SERVER_LOG%
if "%LAST_FAILED_STEP%"=="Validate runtime/model files" (
  echo.
  echo [HINT] Runtime/model validation failed. Common causes:
  echo        1^) llama-server.exe missing in runtime\llama.cpp\ or runtime\llama.cpp\build\bin\
  echo        2^) No *.gguf model in models\
  echo        3^) MODEL_FILE in local_settings.bat points to a missing file
  echo        4^) LLAMA_EXE in local_settings.bat points to a missing file
)
if "%LAST_FAILED_STEP%"=="Check required commands" (
  echo.
  echo [HINT] Install missing tools and re-open terminal:
  echo        - PowerShell (built into Windows)
  echo        - Node.js + npm (https://nodejs.org)
)
if "%LAST_FAILED_STEP%"=="Ensure opencode" (
  echo.
  echo [HINT] opencode install failed. Try:
  echo        npm install -g opencode-ai
  echo        (Run terminal as a user with npm global install permissions)
)
if "%LAST_FAILED_STEP%"=="Check llama port" (
  echo.
  echo [HINT] Another process is using LLAMA_PORT. Either stop that process
  echo        or set LLAMA_PORT to a free port in local_settings.bat.
)
if "%LAST_FAILED_STEP%"=="Wait for llama-server health" (
  echo.
  echo [HINT] llama-server did not come up in time.
  echo        Check SERVER_LOG for model load errors or unsupported GPU flags.
)
if "%LAST_FAILED_STEP%"=="Install OpenCode config" (
  echo.
  echo [HINT] APPDATA was unavailable or config copy failed.
  echo        Run from a normal interactive Windows user session.
)
call :log ERROR "Startup aborted at step: %LAST_FAILED_STEP% (exit %RC%)"
exit /b %RC%
