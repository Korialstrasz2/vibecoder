@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"

if not exist "logs" mkdir "logs"
for /f "delims=" %%I in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set "RUN_ID=%%I"
if not defined RUN_ID set "RUN_ID=%DATE:~-4%%DATE:~4,2%%DATE:~7,2%_%TIME:~0,2%%TIME:~3,2%%TIME:~6,2%"
set "RUN_ID=%RUN_ID: =0%"

set "MAIN_LOG=%CD%\logs\startup_%RUN_ID%.log"
set "SERVER_LOG=%CD%\logs\llama_server_%RUN_ID%.log"
set "RUNTIME_LOG=%CD%\logs\runtime_validation_%RUN_ID%.log"
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
echo [INFO] Runtime validation log: %RUNTIME_LOG%
echo.

call :run_step "Load settings" :load_settings || goto :fatal
call :run_step "Check required commands" :check_required_commands || goto :fatal
call :run_step "Ensure opencode" :ensure_opencode || goto :fatal
call :run_step "Validate runtime/model files (non-blocking)" :check_runtime_inputs_non_blocking || goto :fatal
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
call :log INFO "Runtime validation: begin"
> "%RUNTIME_LOG%" echo === Runtime validation trace (%DATE% %TIME%) ===
>>"%RUNTIME_LOG%" echo Working directory: %CD%
call :log INFO "Runtime validation: normalizing LLAMA_EXE"
call :normalize_path_var LLAMA_EXE
call :log INFO "Runtime validation: normalized LLAMA_EXE"
call :log INFO "Runtime validation: normalizing MODEL_FILE"
call :normalize_path_var MODEL_FILE
call :log INFO "Runtime validation: normalized MODEL_FILE"
call :log INFO "Runtime validation input: LLAMA_EXE=%LLAMA_EXE%"
call :log INFO "Runtime validation input: MODEL_FILE=%MODEL_FILE%"
echo [INFO] Runtime validation: checking configured runtime/model paths...
call :log INFO "Runtime validation: checking runtime/models directories"
if not exist "%CD%\runtime" (
  call :log WARN "runtime\ directory does not exist under %CD%"
) else (
  call :log INFO "runtime\ directory exists under %CD%"
)
if not exist "%CD%\models" (
  call :log WARN "models\ directory does not exist under %CD%"
) else (
  call :log INFO "models\ directory exists under %CD%"
)
call :log INFO "Runtime validation: verifying LLAMA_EXE path"
call :path_diag "%LLAMA_EXE%" "LLAMA_EXE" >>"%RUNTIME_LOG%" 2>&1
call :path_exists "%LLAMA_EXE%" "LLAMA_EXE"
if errorlevel 1 (
  call :log INFO "LLAMA_EXE not found at configured path; checking fallback build output"
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
    exit /b 1
  )
) else (
  call :log INFO "LLAMA_EXE exists: %LLAMA_EXE%"
)
call :log INFO "Runtime validation: verifying MODEL_FILE path"
call :log INFO "Runtime validation: MODEL_FILE raw (post-normalization)='%MODEL_FILE%'"
call :path_diag "%MODEL_FILE%" "MODEL_FILE" >>"%RUNTIME_LOG%" 2>&1
call :log INFO "Runtime validation: MODEL_FILE diagnostics written to runtime log"
if not defined MODEL_FILE (
  call :log ERROR "No .gguf model found in %CD%\models"
  echo [ERROR] No model file found in models\ (expected *.gguf)
  echo         You can also set MODEL_FILE in local_settings.bat to an absolute path.
  if not exist "%CD%\models" (
    echo         models\ directory does not exist yet.
    echo         Create models\ and copy at least one .gguf model into it.
  )
  exit /b 1
) else (
  call :log INFO "MODEL_FILE is set; checking existence"
  call :path_exists "%MODEL_FILE%" "MODEL_FILE"
  call :log INFO "Runtime validation: MODEL_FILE path_exists exit code=%ERRORLEVEL%"
  if errorlevel 1 (
    call :log ERROR "MODEL_FILE path does not exist: %MODEL_FILE%"
    echo [ERROR] MODEL_FILE points to a file that does not exist:
    echo         %MODEL_FILE%
    echo         Update MODEL_FILE in local_settings.bat or copy the model file to that path.
    call :log INFO "Attempting to log first few .gguf files under %CD%\models for troubleshooting"
    for /f "delims=" %%G in ('dir /b "%CD%\models\*.gguf" 2^>nul') do (
      call :log INFO "models\ candidate: %%~fG"
    )
    exit /b 1
  ) else (
    call :log INFO "MODEL_FILE exists: %MODEL_FILE%"
    call :log INFO "Runtime validation: extracting model extension"
    for %%E in ("%MODEL_FILE%") do set "MODEL_EXT=%%~xE"
    call :log INFO "Runtime validation: MODEL_EXT=!MODEL_EXT!"
    if /I not "!MODEL_EXT!"==".gguf" (
      call :log WARN "MODEL_FILE does not end with .gguf: %MODEL_FILE%"
      echo [WARN] MODEL_FILE does not have .gguf extension:
      echo        %MODEL_FILE%
      echo        llama-server usually expects GGUF models. Verify this is intentional.
    )
  )
)
call :log INFO "Using model file: %MODEL_FILE%"
call :log INFO "Runtime validation: success"
exit /b 0

:check_runtime_inputs_non_blocking
call :check_runtime_inputs
if errorlevel 1 (
  set "RUNTIME_VALIDATION_FAILED=1"
  call :log WARN "Runtime/model validation failed, but continuing to try server startup"
  echo [WARN] Runtime/model validation failed, but startup will still try to launch llama-server.
  echo        Review these logs if startup fails:
  echo        %MAIN_LOG%
  echo        %RUNTIME_LOG%
  exit /b 0
)
set "RUNTIME_VALIDATION_FAILED=0"
exit /b 0

:path_exists
set "_CHECK_PATH=%~1"
set "_CHECK_LABEL=%~2"
if not defined _CHECK_LABEL set "_CHECK_LABEL=path"
set "VC_CHECK_PATH=%_CHECK_PATH%"
call :log INFO "path_exists[%_CHECK_LABEL%]: checking via cmd if exist: '%_CHECK_PATH%'"
if exist "%_CHECK_PATH%" (
  call :log INFO "path_exists[%_CHECK_LABEL%]: cmd if exist => true"
  powershell -NoProfile -ExecutionPolicy Bypass -Command "$p=[Environment]::GetEnvironmentVariable('VC_CHECK_PATH'); if([string]::IsNullOrWhiteSpace($p)){Write-Output 'path_exists[%_CHECK_LABEL%]: VC_CHECK_PATH is blank'; exit 2}; $item=Get-Item -LiteralPath $p -ErrorAction SilentlyContinue; if($null -ne $item){Write-Output ('path_exists[%_CHECK_LABEL%]: item type='+$item.GetType().FullName); if($item.PSIsContainer){Write-Output 'path_exists[%_CHECK_LABEL%]: item is a directory'} else {Write-Output ('path_exists[%_CHECK_LABEL%]: item length='+$item.Length)}} else {Write-Output 'path_exists[%_CHECK_LABEL%]: Get-Item returned null'}; if(Test-Path -LiteralPath $p -PathType Leaf){exit 0}else{exit 1}" >>"%RUNTIME_LOG%" 2>&1
  call :log INFO "path_exists[%_CHECK_LABEL%]: appended successful path diagnostics to runtime log"
  exit /b 0
)
call :log WARN "path_exists[%_CHECK_LABEL%]: cmd if exist => false; retrying with PowerShell Test-Path -LiteralPath"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p=[Environment]::GetEnvironmentVariable('VC_CHECK_PATH'); if([string]::IsNullOrWhiteSpace($p)){exit 2}; if(Test-Path -LiteralPath $p -PathType Leaf){exit 0}else{exit 1}" >>"%MAIN_LOG%" 2>&1
set "_PS_CHECK_EXIT=%ERRORLEVEL%"
call :log INFO "path_exists[%_CHECK_LABEL%]: PowerShell check exit code=%_PS_CHECK_EXIT%"
if "%_PS_CHECK_EXIT%"=="0" (
  call :log WARN "path_exists[%_CHECK_LABEL%]: PowerShell says true; using this result (possible cmd parsing edge-case)"
  exit /b 0
)
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p=[Environment]::GetEnvironmentVariable('VC_CHECK_PATH'); Write-Output ('path_exists[%_CHECK_LABEL%]: debug raw path='+$p); if($null -eq $p){Write-Output 'path_exists[%_CHECK_LABEL%]: debug path is null'} else {Write-Output ('path_exists[%_CHECK_LABEL%]: debug length='+$p.Length); $codes=($p.ToCharArray() | ForEach-Object {[int]$_}) -join ','; Write-Output ('path_exists[%_CHECK_LABEL%]: debug char codes='+$codes)}" >>"%RUNTIME_LOG%" 2>&1
call :log ERROR "path_exists[%_CHECK_LABEL%]: both cmd and PowerShell checks report missing; debug char-code trace appended to runtime log"
exit /b 1


:normalize_path_var
set "_VAR_NAME=%~1"
set "_VAR_VALUE="
call set "_VAR_VALUE=%%%_VAR_NAME%%%"
if not defined _VAR_VALUE (
  call :log INFO "normalize_path_var: %~1 is not defined"
  exit /b 0
)
call :log INFO "normalize_path_var: %~1 raw value='%_VAR_VALUE%'"
for /f "tokens=* delims= " %%A in ("%_VAR_VALUE%") do set "_VAR_VALUE=%%A"
:normalize_path_var_trim_tail
if not defined _VAR_VALUE goto normalize_path_var_done
if not "%_VAR_VALUE:~-1%"==" " goto normalize_path_var_done
set "_VAR_VALUE=%_VAR_VALUE:~0,-1%"
goto normalize_path_var_trim_tail
:normalize_path_var_done
if "%_VAR_VALUE:~0,1%"=="""" set "_VAR_VALUE=%_VAR_VALUE:~1%"
:normalize_path_var_strip_quotes_tail
if not defined _VAR_VALUE goto normalize_path_var_assign
if "%_VAR_VALUE:~-1%"=="""" (
  set "_VAR_VALUE=%_VAR_VALUE:~0,-1%"
  goto normalize_path_var_strip_quotes_tail
)
:normalize_path_var_assign
if "%_VAR_VALUE:~0,1%"=="'" set "_VAR_VALUE=%_VAR_VALUE:~1%"
:normalize_path_var_strip_single_quotes_tail
if not defined _VAR_VALUE goto normalize_path_var_assign_done
if "%_VAR_VALUE:~-1%"=="'" (
  set "_VAR_VALUE=%_VAR_VALUE:~0,-1%"
  goto normalize_path_var_strip_single_quotes_tail
)
:normalize_path_var_assign_done
call set "%_VAR_NAME%=%_VAR_VALUE%"
call :log INFO "normalize_path_var: %~1 normalized value='%_VAR_VALUE%'"
exit /b 0

:path_diag
set "_DIAG_PATH=%~1"
set "_DIAG_LABEL=%~2"
if not defined _DIAG_LABEL set "_DIAG_LABEL=path"
echo [%_DIAG_LABEL%] raw input: '%~1'
if not defined _DIAG_PATH (
  echo [%_DIAG_LABEL%] value is not defined after argument expansion.
  exit /b 0
)
echo [%_DIAG_LABEL%] expanded value: '%_DIAG_PATH%'
set "VC_DIAG_PATH=%_DIAG_PATH%"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p=[Environment]::GetEnvironmentVariable('VC_DIAG_PATH'); if($null -eq $p){Write-Output '[%_DIAG_LABEL%] char length: <null>'} else {Write-Output ('[%_DIAG_LABEL%] char length: '+$p.Length); $codes=($p.ToCharArray() | ForEach-Object {[int]$_}) -join ','; Write-Output ('[%_DIAG_LABEL%] char codes: '+$codes)}; if(Test-Path -LiteralPath $p -PathType Leaf){Write-Output '[%_DIAG_LABEL%] powershell Test-Path => true'} else {Write-Output '[%_DIAG_LABEL%] powershell Test-Path => false'}"
if exist "%_DIAG_PATH%" (
  echo [%_DIAG_LABEL%] cmd if exist => true
) else (
  echo [%_DIAG_LABEL%] cmd if exist => false
)
for %%A in ("%_DIAG_PATH%") do (
  echo [%_DIAG_LABEL%] drive=%%~dA
  echo [%_DIAG_LABEL%] dir=%%~dpA
  echo [%_DIAG_LABEL%] name=%%~nA
  echo [%_DIAG_LABEL%] ext=%%~xA
)
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
set "SERVER_LAUNCHER=%CD%\logs\launch_llama_%RUN_ID%.bat"
>"%SERVER_LAUNCHER%" echo @echo off
>>"%SERVER_LAUNCHER%" echo setlocal
>>"%SERVER_LAUNCHER%" echo cd /d "%CD%\runtime\llama.cpp"
>>"%SERVER_LAUNCHER%" echo echo [%%date%% %%time%%] launcher: starting llama-server ^>^> "%SERVER_LOG%"
>>"%SERVER_LAUNCHER%" echo echo [%%date%% %%time%%] launcher: exe="%LLAMA_EXE%" ^>^> "%SERVER_LOG%"
>>"%SERVER_LAUNCHER%" echo echo [%%date%% %%time%%] launcher: model="%MODEL_FILE%" ^>^> "%SERVER_LOG%"
>>"%SERVER_LAUNCHER%" echo "%LLAMA_EXE%" --model "%MODEL_FILE%" --host "%LLAMA_HOST%" --port "%LLAMA_PORT%" --ctx-size "%LLAMA_CTX%" --n-gpu-layers "%LLAMA_GPU_LAYERS%" --alias "%LLAMA_ALIAS%" ^>^> "%SERVER_LOG%" 2^>^&1
>>"%SERVER_LAUNCHER%" echo set "SERVER_EXIT=%%errorlevel%%"
>>"%SERVER_LAUNCHER%" echo echo [%%date%% %%time%%] launcher: llama-server exited with code %%SERVER_EXIT%% ^>^> "%SERVER_LOG%"
>>"%SERVER_LAUNCHER%" echo endlocal ^& exit /b %%SERVER_EXIT%%
start "vibecoder-llama-server" cmd /c "\"%SERVER_LAUNCHER%\""
if errorlevel 1 (
  call :log ERROR "Failed to launch llama-server process"
  echo [ERROR] Failed to launch llama-server process.
  exit /b 1
)
call :log INFO "Created llama launcher script at %SERVER_LAUNCHER%"
call :log INFO "Quick server startup probe: waiting 5 seconds before initial status check"
echo [INFO] Waiting 5 seconds, then checking if llama-server appears reachable...
timeout /t 5 /nobreak >nul
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $null = Invoke-RestMethod -Uri 'http://%LLAMA_HOST%:%LLAMA_PORT%/v1/models' -TimeoutSec 2; exit 0 } catch { exit 1 }" >>"%MAIN_LOG%" 2>&1
if errorlevel 1 (
  call :log WARN "Quick server startup probe did not confirm readiness after 5 seconds"
  echo [WARN] Could not confirm llama-server readiness after 5 seconds.
  echo        This can be normal while large models are still loading.
  echo        Startup will continue with full health wait checks.
) else (
  call :log INFO "Quick server startup probe succeeded after 5 seconds"
  echo [OK] llama-server responded within 5 seconds.
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
for /f "delims=" %%I in ('powershell -NoProfile -Command "Get-Date -Format \"yyyy-MM-dd HH:mm:ss.fff\""') do set "STAMP=%%I"
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
echo         %RUNTIME_LOG%
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
