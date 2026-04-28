@echo off
setlocal EnableExtensions
cd /d "%~dp0"

set "LOG_FILE=%~dp0setup_work_pc_client.log"
set "CONFIG_SOURCE=%~dp0config\opencode\opencode.jsonc"
set "CONFIG_DIR=%USERPROFILE%\.config\opencode"
set "CONFIG_DEST=%CONFIG_DIR%\opencode.jsonc"
set "LEGACY_CONFIG_DIR=%APPDATA%\opencode"
set "LEGACY_CONFIG_DEST=%LEGACY_CONFIG_DIR%\opencode.jsonc"

call :log ==========================================
call :log Starting work-PC OpenCode client setup in "%CD%"
call :log Timestamp: %DATE% %TIME%

if not exist "%CONFIG_SOURCE%" (
  call :log ERROR: Missing config source "%CONFIG_SOURCE%"
  echo [ERROR] Could not find config template:
  echo   "%CONFIG_SOURCE%"
  goto :fail
)

set "MAIN_PC_IP="
set /p MAIN_PC_IP=Enter MAIN PC IPv4 (example 192.168.1.50): 
if "%MAIN_PC_IP%"=="" (
  echo [ERROR] MAIN PC IPv4 is required.
  goto :fail
)

set "MAIN_PC_PORT=8076"
set /p MAIN_PC_PORT=Enter MAIN PC port [8076]: 
if "%MAIN_PC_PORT%"=="" set "MAIN_PC_PORT=8076"

set "REMOTE_BASE_URL=http://%MAIN_PC_IP%:%MAIN_PC_PORT%/v1"
call :log Using REMOTE_BASE_URL=%REMOTE_BASE_URL%

echo.
echo Creating OpenCode config for:
echo   %REMOTE_BASE_URL%

if not exist "%CONFIG_DIR%" mkdir "%CONFIG_DIR%"
if errorlevel 1 (
  call :log ERROR: Could not create config directory "%CONFIG_DIR%"
  echo [ERROR] Could not create:
  echo   "%CONFIG_DIR%"
  goto :fail
)

powershell -NoProfile -Command "$src='%CONFIG_SOURCE%'; $dst='%CONFIG_DEST%'; $url='%REMOTE_BASE_URL%'; (Get-Content $src) -replace '"baseURL"\s*:\s*"[^"]+"', ('"baseURL": "' + $url + '"') | Set-Content $dst"
if errorlevel 1 (
  call :log ERROR: Failed to write "%CONFIG_DEST%"
  echo [ERROR] Failed to create OpenCode config:
  echo   "%CONFIG_DEST%"
  goto :fail
)

if not exist "%LEGACY_CONFIG_DIR%" mkdir "%LEGACY_CONFIG_DIR%"
copy /Y "%CONFIG_DEST%" "%LEGACY_CONFIG_DEST%" >nul 2>nul

call :log Config written to "%CONFIG_DEST%"
echo Config installed:
echo   "%CONFIG_DEST%"
echo.

echo Checking server:
echo   %REMOTE_BASE_URL%/models
curl -s --max-time 5 "%REMOTE_BASE_URL%/models" >nul 2>nul
if errorlevel 1 (
  call :log WARNING: Connectivity check failed
  echo [WARN] Could not reach the model server right now.
  echo - Verify MAIN PC is running start_server_lan.bat
  echo - Verify firewall allows inbound TCP %MAIN_PC_PORT%
  echo - Verify both PCs are on the same LAN
  echo.
) else (
  call :log Connectivity check passed
  echo [OK] Server reachable from this PC.
  echo.
)

echo Next steps:
echo 1. Run OpenCode in your project folder.
echo 2. In /models choose: llama.cpp/qwen-local
echo.
endlocal & exit /b 0

:fail
echo.
echo Script failed. See log:
echo   "%LOG_FILE%"
call :log Script failed
pause
endlocal & exit /b 1

:log
echo [%DATE% %TIME%] %*>>"%LOG_FILE%"
echo [%DATE% %TIME%] %*
exit /b 0
