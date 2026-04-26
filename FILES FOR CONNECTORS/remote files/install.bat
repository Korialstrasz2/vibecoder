@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"

set "SCRIPT_DIR=%~dp0"
set "TEMPLATE_CONFIG=%SCRIPT_DIR%config\opencode\opencode.template.jsonc"
set "WORK_CONFIG=%SCRIPT_DIR%config\opencode\opencode.jsonc"
set "USER_CONFIG_DIR=%USERPROFILE%\.config\opencode"
set "USER_CONFIG=%USER_CONFIG_DIR%\opencode.jsonc"
set "LEGACY_CONFIG_DIR=%APPDATA%\opencode"
set "LEGACY_CONFIG=%LEGACY_CONFIG_DIR%\opencode.jsonc"

if not exist "%TEMPLATE_CONFIG%" (
  echo [ERROR] Missing template config:
  echo   "%TEMPLATE_CONFIG%"
  exit /b 1
)

echo.
echo === OpenCode Work Laptop Installer ===
echo.
set /p "MAIN_PC_IP=Enter MAIN PC LAN IPv4 (example 192.168.1.50): "
if not defined MAIN_PC_IP (
  echo [ERROR] MAIN_PC_IP is required.
  exit /b 1
)

set "BASE_URL=http://%MAIN_PC_IP%:8076/v1"

echo Building config with BASE_URL=%BASE_URL%
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$template = Get-Content -Raw '%TEMPLATE_CONFIG%';" ^
  "$output = $template.Replace('__BASE_URL__', '%BASE_URL%');" ^
  "$output | Set-Content -Encoding UTF8 '%WORK_CONFIG%'"
if errorlevel 1 (
  echo [ERROR] Failed to generate config.
  exit /b 1
)

if not exist "%USER_CONFIG_DIR%" mkdir "%USER_CONFIG_DIR%"
copy /Y "%WORK_CONFIG%" "%USER_CONFIG%" >nul
if errorlevel 1 (
  echo [ERROR] Failed to install config:
  echo   "%USER_CONFIG%"
  exit /b 1
)

if not exist "%LEGACY_CONFIG_DIR%" mkdir "%LEGACY_CONFIG_DIR%"
copy /Y "%WORK_CONFIG%" "%LEGACY_CONFIG%" >nul 2>nul

where opencode >nul 2>nul
if errorlevel 1 (
  echo opencode not found. Installing with npm...
  where npm >nul 2>nul
  if errorlevel 1 (
    echo [ERROR] npm is not installed. Install Node.js LTS first, then rerun install.bat.
    exit /b 1
  )

  call npm install -g opencode-ai
  if errorlevel 1 (
    echo [ERROR] Failed to install opencode-ai globally.
    exit /b 1
  )
)

echo Testing server reachability at:
echo   %BASE_URL%/models
curl -s --max-time 5 "%BASE_URL%/models" >nul 2>nul
if errorlevel 1 (
  echo [WARN] Could not reach server right now. Start the MAIN PC server first.
  echo        You can still run start_opencode.bat after server is online.
) else (
  echo [OK] Server reachable.
)

echo.
echo Install complete.
echo Next step: run start_opencode.bat
exit /b 0
