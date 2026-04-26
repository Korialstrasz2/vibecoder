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
set "TOOLS_DIR=%SCRIPT_DIR%tools"
set "NODE_DIR=%TOOLS_DIR%\node"
set "NODE_EXE=%NODE_DIR%\node.exe"
set "NODE_NPM_CMD=%NODE_DIR%\npm.cmd"
set "NPM_PREFIX=%TOOLS_DIR%\npm-global"
set "NPM_CACHE=%TOOLS_DIR%\npm-cache"
set "LOCAL_OPENCODE=%NPM_PREFIX%\opencode.cmd"
set "NODE_DOWNLOAD_URL=https://nodejs.org/dist/v20.19.5/node-v20.19.5-win-x64.zip"
set "NODE_ZIP=%TEMP%\node-v20.19.5-win-x64.zip"

if not exist "%TEMPLATE_CONFIG%" (
  echo [ERROR] Missing template config:
  echo   "%TEMPLATE_CONFIG%"
  exit /b 1
)

set "DEFAULT_MAIN_PC_IP=192.168.1.50"
for /f "usebackq delims=" %%I in (`powershell -NoProfile -Command "$ip = Get-NetIPAddress -AddressFamily IPv4 ^| Where-Object { $_.IPAddress -match '^\d+\.\d+\.\d+\.\d+$' -and $_.IPAddress -ne '127.0.0.1' -and $_.IPAddress -notlike '169.254*' } ^| Select-Object -First 1 -ExpandProperty IPAddress; if ($ip) { $parts = $ip.Split('.'); if ($parts.Length -eq 4) { Write-Output ($parts[0] + '.' + $parts[1] + '.' + $parts[2] + '.50') } }"`) do set "DEFAULT_MAIN_PC_IP=%%I"

echo.
echo === OpenCode Work Laptop Installer ===
echo.
echo Common MAIN PC IPv4 examples:
echo   192.168.1.50
if defined DEFAULT_MAIN_PC_IP if /I not "%DEFAULT_MAIN_PC_IP%"=="192.168.1.50" echo   %DEFAULT_MAIN_PC_IP%
echo   192.168.0.50
echo   10.0.0.50
echo.
set /p "MAIN_PC_IP=Enter MAIN PC LAN IPv4 [default %DEFAULT_MAIN_PC_IP%]: "
if not defined MAIN_PC_IP set "MAIN_PC_IP=%DEFAULT_MAIN_PC_IP%"
echo %MAIN_PC_IP%| findstr /R /C:"^[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*$" >nul
if errorlevel 1 (
  echo [ERROR] Invalid IPv4 format: %MAIN_PC_IP%
  echo         Example: 192.168.1.50
  exit /b 1
)

set "BASE_URL=http://%MAIN_PC_IP%:8076/v1"

echo Building config with BASE_URL=%BASE_URL%
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$template = Get-Content -Raw $env:TEMPLATE_CONFIG;" ^
  "$output = $template.Replace('__BASE_URL__', $env:BASE_URL);" ^
  "$output | Set-Content -Encoding UTF8 $env:WORK_CONFIG"
if errorlevel 1 (
  echo [ERROR] Failed to generate config.
  echo         TEMPLATE_CONFIG=%TEMPLATE_CONFIG%
  echo         WORK_CONFIG=%WORK_CONFIG%
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

call :ensure_opencode
if errorlevel 1 exit /b 1

echo Testing server reachability at:
echo   %BASE_URL%/models
curl -s --max-time 5 "%BASE_URL%/models" >nul 2>nul
if errorlevel 1 (
  echo [WARN] Could not reach server right now. Start the MAIN PC server first.
  echo        start_opencode.bat will let you re-enter IP and retry.
) else (
  echo [OK] Server reachable.
)

echo.
echo Install complete.
echo Next step: run start_opencode.bat
exit /b 0

:ensure_opencode
where opencode >nul 2>nul
if not errorlevel 1 (
  echo [OK] Found opencode on PATH.
  exit /b 0
)

if exist "%LOCAL_OPENCODE%" (
  echo [OK] Found local opencode at:
  echo      "%LOCAL_OPENCODE%"
  exit /b 0
)

echo opencode not found. Installing local portable dependencies...
if not exist "%TOOLS_DIR%" mkdir "%TOOLS_DIR%"
if not exist "%NPM_PREFIX%" mkdir "%NPM_PREFIX%"
if not exist "%NPM_CACHE%" mkdir "%NPM_CACHE%"

if not exist "%NODE_EXE%" (
  echo [INFO] Downloading portable Node.js (no admin required)...
  powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$ErrorActionPreference='Stop';" ^
    "Invoke-WebRequest -Uri '%NODE_DOWNLOAD_URL%' -OutFile '%NODE_ZIP%';" ^
    "if (Test-Path '%NODE_DIR%') { Remove-Item -Recurse -Force '%NODE_DIR%' };" ^
    "Expand-Archive -Path '%NODE_ZIP%' -DestinationPath '%TOOLS_DIR%' -Force;" ^
    "$extracted = Get-ChildItem -Path '%TOOLS_DIR%' -Directory ^| Where-Object { $_.Name -like 'node-v*-win-x64' } ^| Sort-Object LastWriteTime -Descending ^| Select-Object -First 1;" ^
    "if (-not $extracted) { throw 'Node archive extraction failed.' };" ^
    "Rename-Item -Path $extracted.FullName -NewName 'node' -Force"
  if errorlevel 1 (
    echo [ERROR] Could not download/extract portable Node.js.
    echo         Check internet access and rerun install.bat.
    exit /b 1
  )
)

if not exist "%NODE_NPM_CMD%" (
  echo [ERROR] npm.cmd not found in portable Node folder:
  echo   "%NODE_NPM_CMD%"
  exit /b 1
)

set "PATH=%NODE_DIR%;%NPM_PREFIX%;%PATH%"
set "npm_config_prefix=%NPM_PREFIX%"
set "npm_config_cache=%NPM_CACHE%"

echo [INFO] Installing opencode-ai into:
echo        %NPM_PREFIX%
call "%NODE_NPM_CMD%" install -g opencode-ai --prefix "%NPM_PREFIX%" --cache "%NPM_CACHE%"
if errorlevel 1 (
  echo [ERROR] Failed to install opencode-ai locally.
  echo         npm prefix: %NPM_PREFIX%
  echo         npm cache : %NPM_CACHE%
  echo         If on corporate network, try VPN/proxy or run:
  echo         "%NODE_NPM_CMD%" config set proxy http://YOUR_PROXY:PORT
  echo         "%NODE_NPM_CMD%" config set https-proxy http://YOUR_PROXY:PORT
  exit /b 1
)

if not exist "%LOCAL_OPENCODE%" (
  echo [ERROR] Local opencode command not found after install:
  echo   "%LOCAL_OPENCODE%"
  exit /b 1
)

echo [OK] Local opencode installed at:
echo      "%LOCAL_OPENCODE%"
exit /b 0
