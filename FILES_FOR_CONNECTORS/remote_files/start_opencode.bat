@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"

set "LOG_FILE=%~dp0start_opencode.log"
set "CONFIG_SOURCE=%~dp0config\opencode\opencode.jsonc"
set "CONFIG_DIR=%USERPROFILE%\.config\opencode"
set "CONFIG_DEST=%CONFIG_DIR%\opencode.jsonc"
set "LEGACY_CONFIG_DIR=%APPDATA%\opencode"
set "LEGACY_CONFIG_DEST=%LEGACY_CONFIG_DIR%\opencode.jsonc"
set "TOOLS_DIR=%~dp0tools"
set "NODE_DIR=%TOOLS_DIR%\node"
set "NODE_EXE=%NODE_DIR%\node.exe"
set "LOCAL_OPENCODE=%~dp0tools\npm-global\opencode.cmd"

call :log ======================================================================
call :log Starting remote start_opencode launcher in "%CD%"
call :log Timestamp: %DATE% %TIME%

if not exist "%CONFIG_SOURCE%" (
  call :log ERROR: Missing config source "%CONFIG_SOURCE%"
  echo [ERROR] Missing config file:
  echo   "%CONFIG_SOURCE%"
  echo Run install.bat first.
  goto :fatal
)

if not exist "%CONFIG_DIR%" mkdir "%CONFIG_DIR%"
copy /Y "%CONFIG_SOURCE%" "%CONFIG_DEST%" >nul
if not exist "%LEGACY_CONFIG_DIR%" mkdir "%LEGACY_CONFIG_DIR%"
copy /Y "%CONFIG_SOURCE%" "%LEGACY_CONFIG_DEST%" >nul 2>nul
call :log Installed config to "%CONFIG_DEST%"

set "OPENCODE_CMD=opencode"
where opencode >nul 2>nul
if errorlevel 1 (
  if exist "%LOCAL_OPENCODE%" (
    set "OPENCODE_CMD=%LOCAL_OPENCODE%"
    call :log Using local opencode command "%OPENCODE_CMD%"
    if exist "%NODE_EXE%" (
      set "PATH=%NODE_DIR%;%~dp0tools\npm-global;%PATH%"
      call :log Added portable Node.js to PATH from "%NODE_DIR%"
    ) else (
      call :log WARNING: Local opencode exists but portable Node.js is missing at "%NODE_EXE%"
      echo [WARN] Portable Node.js is missing:
      echo   "%NODE_EXE%"
      echo Run install.bat again to repair local dependencies.
      goto :fatal
    )
  ) else (
    call :log ERROR: opencode command not found on PATH or local tools folder
    echo [ERROR] opencode not found.
    echo Run install.bat first to install local dependencies without admin rights.
    goto :fatal
  )
)

call :read_base_url
if errorlevel 1 goto :fatal

:check_server
if defined BASE_URL (
  call :log Checking server URL: %BASE_URL%/models
  echo Checking server: %BASE_URL%/models
  curl -s --max-time 5 "%BASE_URL%/models" >nul 2>nul
  if errorlevel 1 (
    call :log WARNING: Server unreachable at %BASE_URL%/models
    echo.
    echo [WARN] Server not reachable at %BASE_URL%/models
    set /p "NEW_MAIN_PC_IP=Enter MAIN PC IPv4 to retry (blank to cancel): "
    if not defined NEW_MAIN_PC_IP (
      call :log User cancelled retry prompt.
      echo Cancelled.
      goto :fatal
    )
    echo !NEW_MAIN_PC_IP!| findstr /R /C:"^[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*$" >nul
    if errorlevel 1 (
      call :log WARNING: Invalid IPv4 entered: !NEW_MAIN_PC_IP!
      echo [WARN] Invalid IPv4 format. Example: 192.168.1.50
      goto :check_server
    )

    set "BASE_URL=http://!NEW_MAIN_PC_IP!:8076/v1"
    call :write_base_url
    if errorlevel 1 goto :fatal
    goto :check_server
  )
)

if not exist "projects" mkdir "projects"
cd /d "%~dp0projects"

call :log Starting OpenCode command: "%OPENCODE_CMD%"
echo Starting OpenCode in:
echo   %CD%
call "%OPENCODE_CMD%"
set "EXIT_CODE=%ERRORLEVEL%"
call :log OpenCode exited with code %EXIT_CODE%
if not "%EXIT_CODE%"=="0" (
  echo.
  echo [ERROR] OpenCode exited with code %EXIT_CODE%.
  echo Press any key to keep this console open for troubleshooting.
  pause >nul
)
exit /b %EXIT_CODE%

:read_base_url
set "BASE_URL="
set "BASE_URL_FILE=%TEMP%\opencode_baseurl_%RANDOM%%RANDOM%.txt"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$json = Get-Content -Raw $env:CONFIG_SOURCE; $m = [regex]::Match($json, '(?i)\x22baseurl\x22\s*:\s*\x22([^\x22]+)\x22'); if ($m.Success) { $m.Groups[1].Value | Out-File -Encoding ascii -NoNewline $env:BASE_URL_FILE }"
if exist "%BASE_URL_FILE%" (
  set /p "BASE_URL="<"%BASE_URL_FILE%"
  del /q "%BASE_URL_FILE%" >nul 2>nul
)
if not defined BASE_URL (
  call :log WARNING: Could not parse baseURL from "%CONFIG_SOURCE%"
  echo [WARN] Could not read baseURL from:
  echo   "%CONFIG_SOURCE%"
  echo.
  call :prompt_for_base_url
  if errorlevel 1 exit /b 2

  call :write_base_url
  if errorlevel 1 exit /b 2
)
call :log Parsed BASE_URL=%BASE_URL%
exit /b 0


:prompt_for_base_url
set "NEW_MAIN_PC_IP="
:prompt_for_base_url_loop
set /p "NEW_MAIN_PC_IP=Enter MAIN PC IPv4 (blank to cancel): "
if not defined NEW_MAIN_PC_IP exit /b 2
echo !NEW_MAIN_PC_IP!| findstr /R /C:"^[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*$" >nul
if errorlevel 1 (
  echo [WARN] Invalid IPv4 format. Example: 192.168.1.50
  goto :prompt_for_base_url_loop
)

set "BASE_URL=http://!NEW_MAIN_PC_IP!:8076/v1"
exit /b 0

:write_base_url
call :log Updating config baseURL to %BASE_URL%
echo Updating config baseURL to: %BASE_URL%
powershell -NoProfile -ExecutionPolicy Bypass -Command "$json = Get-Content -Raw $env:CONFIG_SOURCE; $updated = [regex]::Replace($json, '\x22baseURL\x22\s*:\s*\x22[^\x22]+\x22', ('\x22baseURL\x22: \x22' + $env:BASE_URL + '\x22')); $updated | Set-Content -Encoding UTF8 $env:CONFIG_SOURCE" 1>>"%LOG_FILE%" 2>>&1
if errorlevel 1 (
  call :log ERROR: Failed to update baseURL in config source.
  echo [ERROR] Failed to update baseURL in config source.
  exit /b 2
)

copy /Y "%CONFIG_SOURCE%" "%CONFIG_DEST%" >nul
copy /Y "%CONFIG_SOURCE%" "%LEGACY_CONFIG_DEST%" >nul 2>nul
exit /b 0

:fatal
echo.
echo Script failed. Console will stay open.
echo See log:
echo   "%LOG_FILE%"
call :log Script failed with errorlevel %ERRORLEVEL%
pause
exit /b 1

:log
echo [%DATE% %TIME%] %*>>"%LOG_FILE%"
echo [%DATE% %TIME%] %*
exit /b 0
