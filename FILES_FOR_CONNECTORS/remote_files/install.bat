@echo off
setlocal EnableExtensions
cd /d "%~dp0"

set "LOG_FILE=%~dp0install.log"
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

call :main
set "EXIT_CODE=%ERRORLEVEL%"
if not "%EXIT_CODE%"=="0" (
  echo.
  echo [ERROR] install.bat failed with exit code %EXIT_CODE%.
  echo         The console will stay open for troubleshooting.
  echo         Log file: "%LOG_FILE%"
  pause
)
exit /b %EXIT_CODE%

:main
call :log ======================================================================
call :log Starting OpenCode Work Laptop installer in "%CD%"
call :log Timestamp: %DATE% %TIME%
call :log Log file: "%LOG_FILE%"

if not exist "%TEMPLATE_CONFIG%" (
  call :log ERROR: Missing template config "%TEMPLATE_CONFIG%"
  echo [ERROR] Missing template config:
  echo   "%TEMPLATE_CONFIG%"
  exit /b 1
)

set "DEFAULT_MAIN_PC_IP=192.168.1.50"
for /f "usebackq delims=" %%I in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "$ip = $null; try { $route = Get-NetRoute -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -ErrorAction Stop ^| Sort-Object RouteMetric, ifMetric ^| Select-Object -First 1; if ($route) { $ip = Get-NetIPAddress -AddressFamily IPv4 -InterfaceIndex $route.IfIndex -ErrorAction SilentlyContinue ^| Where-Object { $_.IPAddress -match '^\d+\.\d+\.\d+\.\d+$' -and $_.IPAddress -ne '127.0.0.1' -and $_.IPAddress -notlike '169.254*' } ^| Select-Object -First 1 -ExpandProperty IPAddress } } catch { }; if (-not $ip) { try { $ip = (ipconfig ^| Select-String -Pattern 'IPv4[^:]*:\s*([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)' -AllMatches).Matches ^| ForEach-Object { $_.Groups[1].Value } ^| Where-Object { $_ -ne '127.0.0.1' -and $_ -notlike '169.254*' } ^| Select-Object -First 1 } catch { } }; if ($ip) { $parts = $ip.Split('.'); if ($parts.Length -eq 4) { Write-Output ($parts[0] + '.' + $parts[1] + '.' + $parts[2] + '.50') } }"`) do set "DEFAULT_MAIN_PC_IP=%%I"

call :log Suggested default MAIN_PC_IP=%DEFAULT_MAIN_PC_IP%
echo.
echo === OpenCode Work Laptop Installer ===
echo.
echo Common MAIN PC IPv4 examples:
echo   192.168.1.50
if defined DEFAULT_MAIN_PC_IP if /I not "%DEFAULT_MAIN_PC_IP%"=="192.168.1.50" echo   %DEFAULT_MAIN_PC_IP%
echo   192.168.0.50
echo   10.0.0.50
echo.

:prompt_ip
set "MAIN_PC_IP="
set /p "MAIN_PC_IP=Enter MAIN PC LAN IPv4 [default %DEFAULT_MAIN_PC_IP%]: "
if not defined MAIN_PC_IP set "MAIN_PC_IP=%DEFAULT_MAIN_PC_IP%"
call :log User entered MAIN_PC_IP=%MAIN_PC_IP%

call :validate_ip "%MAIN_PC_IP%"
if errorlevel 1 (
  call :log ERROR: Invalid IPv4 format/range: %MAIN_PC_IP%
  echo [ERROR] Invalid IPv4 value: %MAIN_PC_IP%
  echo         Example valid IP: 192.168.1.50
  goto :prompt_ip
)

set "BASE_URL=http://%MAIN_PC_IP%:8076/v1"
call :log BASE_URL=%BASE_URL%

echo Building config with BASE_URL=%BASE_URL%
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$template = Get-Content -Raw $env:TEMPLATE_CONFIG;" ^
  "$output = $template.Replace('__BASE_URL__', $env:BASE_URL);" ^
  "$output | Set-Content -Encoding UTF8 $env:WORK_CONFIG" 1>>"%LOG_FILE%" 2>>&1
if errorlevel 1 (
  call :log ERROR: Failed to generate config.
  echo [ERROR] Failed to generate config.
  echo         See details in:
  echo         "%LOG_FILE%"
  exit /b 1
)
call :log Generated config "%WORK_CONFIG%"

if not exist "%USER_CONFIG_DIR%" mkdir "%USER_CONFIG_DIR%"
copy /Y "%WORK_CONFIG%" "%USER_CONFIG%" >nul
if errorlevel 1 (
  call :log ERROR: Failed to install config to "%USER_CONFIG%"
  echo [ERROR] Failed to install config:
  echo   "%USER_CONFIG%"
  exit /b 1
)

if not exist "%LEGACY_CONFIG_DIR%" mkdir "%LEGACY_CONFIG_DIR%"
copy /Y "%WORK_CONFIG%" "%LEGACY_CONFIG%" >nul 2>nul
call :log Installed config to "%USER_CONFIG%"

call :ensure_opencode
if errorlevel 1 exit /b 1

echo Testing server reachability at:
echo   %BASE_URL%/models
curl -s --max-time 5 "%BASE_URL%/models" >nul 2>nul
if errorlevel 1 (
  call :log WARNING: Could not reach server at %BASE_URL%/models
  echo [WARN] Could not reach server right now. Start the MAIN PC server first.
  echo        start_opencode.bat will let you re-enter IP and retry.
) else (
  call :log Connectivity test passed: %BASE_URL%/models
  echo [OK] Server reachable.
)

echo.
echo Install complete.
echo Next step: run start_opencode.bat
call :log Install completed successfully.
exit /b 0

:ensure_opencode
where opencode >nul 2>nul
if not errorlevel 1 (
  call :log Found opencode on PATH.
  echo [OK] Found opencode on PATH.
  exit /b 0
)

if exist "%LOCAL_OPENCODE%" (
  call :log Found local opencode at "%LOCAL_OPENCODE%"
  echo [OK] Found local opencode at:
  echo      "%LOCAL_OPENCODE%"
  exit /b 0
)

echo opencode not found. Installing local portable dependencies...
call :log opencode not found. Installing local portable dependencies...
if not exist "%TOOLS_DIR%" mkdir "%TOOLS_DIR%"
if errorlevel 1 (
  call :log ERROR: Failed to create tools directory "%TOOLS_DIR%"
  echo [ERROR] Failed to create tools directory:
  echo   "%TOOLS_DIR%"
  exit /b 2
)
if not exist "%NPM_PREFIX%" mkdir "%NPM_PREFIX%"
if errorlevel 1 (
  call :log ERROR: Failed to create npm prefix "%NPM_PREFIX%"
  echo [ERROR] Failed to create npm prefix directory:
  echo   "%NPM_PREFIX%"
  exit /b 2
)
if not exist "%NPM_CACHE%" mkdir "%NPM_CACHE%"
if errorlevel 1 (
  call :log ERROR: Failed to create npm cache "%NPM_CACHE%"
  echo [ERROR] Failed to create npm cache directory:
  echo   "%NPM_CACHE%"
  exit /b 2
)

if not exist "%NODE_EXE%" (
  echo [INFO] Downloading portable Node.js (no admin required)...
  call :log Downloading portable Node.js from %NODE_DOWNLOAD_URL%
  powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$ErrorActionPreference='Stop';" ^
    "Invoke-WebRequest -Uri '%NODE_DOWNLOAD_URL%' -OutFile '%NODE_ZIP%';" ^
    "if (Test-Path '%NODE_DIR%') { Remove-Item -Recurse -Force '%NODE_DIR%' };" ^
    "Expand-Archive -Path '%NODE_ZIP%' -DestinationPath '%TOOLS_DIR%' -Force;" ^
    "$extracted = Get-ChildItem -Path '%TOOLS_DIR%' -Directory ^| Where-Object { $_.Name -like 'node-v*-win-x64' } ^| Sort-Object LastWriteTime -Descending ^| Select-Object -First 1;" ^
    "if (-not $extracted) { throw 'Node archive extraction failed.' };" ^
    "if (Test-Path '%NODE_DIR%') { Remove-Item -Recurse -Force '%NODE_DIR%' };" ^
    "Rename-Item -Path $extracted.FullName -NewName 'node' -Force" 1>>"%LOG_FILE%" 2>>&1
  if errorlevel 1 (
    call :log ERROR: Could not download/extract portable Node.js.
    echo [ERROR] Could not download/extract portable Node.js.
    echo         Check internet/proxy access and rerun install.bat.
    echo         See detailed output in:
    echo         "%LOG_FILE%"
    exit /b 2
  )
)

if not exist "%NODE_NPM_CMD%" (
  call :log ERROR: npm.cmd not found in "%NODE_NPM_CMD%"
  echo [ERROR] npm.cmd not found in portable Node folder:
  echo   "%NODE_NPM_CMD%"
  exit /b 2
)

set "PATH=%NODE_DIR%;%NPM_PREFIX%;%PATH%"
set "npm_config_prefix=%NPM_PREFIX%"
set "npm_config_cache=%NPM_CACHE%"

echo [INFO] Installing opencode-ai into:
echo        %NPM_PREFIX%
call :log Running npm install for opencode-ai
call "%NODE_NPM_CMD%" install -g opencode-ai --prefix "%NPM_PREFIX%" --cache "%NPM_CACHE%" 1>>"%LOG_FILE%" 2>>&1
if errorlevel 1 (
  call :log ERROR: npm install failed for opencode-ai
  echo [ERROR] Failed to install opencode-ai locally.
  echo         npm prefix: %NPM_PREFIX%
  echo         npm cache : %NPM_CACHE%
  echo         Full command output was logged line-by-line to:
  echo         "%LOG_FILE%"
  echo         If on corporate network, configure proxy then retry.
  exit /b 2
)

if not exist "%LOCAL_OPENCODE%" (
  call :log ERROR: Local opencode command missing at "%LOCAL_OPENCODE%" after npm install
  echo [ERROR] Local opencode command not found after install:
  echo   "%LOCAL_OPENCODE%"
  echo Check "%LOG_FILE%" for npm output.
  exit /b 2
)

call :log Local opencode installed at "%LOCAL_OPENCODE%"
echo [OK] Local opencode installed at:
echo      "%LOCAL_OPENCODE%"
exit /b 0

:validate_ip
set "_ip=%~1"
echo %_ip%| findstr /R /C:"^[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*$" >nul || exit /b 1
for /f "tokens=1-4 delims=." %%a in ("%_ip%") do (
  set /a o1=%%a, o2=%%b, o3=%%c, o4=%%d >nul 2>&1
)
if %o1% LSS 0 exit /b 1
if %o1% GTR 255 exit /b 1
if %o2% LSS 0 exit /b 1
if %o2% GTR 255 exit /b 1
if %o3% LSS 0 exit /b 1
if %o3% GTR 255 exit /b 1
if %o4% LSS 0 exit /b 1
if %o4% GTR 255 exit /b 1
exit /b 0

:log
echo [%DATE% %TIME%] %*>>"%LOG_FILE%"
echo [%DATE% %TIME%] %*
exit /b 0
