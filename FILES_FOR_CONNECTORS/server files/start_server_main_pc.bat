@echo off
setlocal EnableExtensions
cd /d "%~dp0"

rem MAIN PC launcher for LAN use
set "ROOT_DIR=%~dp0..\.."
cd /d "%ROOT_DIR%"

set "LLAMA_HOST=0.0.0.0"
if not defined LLAMA_PORT set "LLAMA_PORT=8076"
if not defined CONTEXT_PROFILE set "CONTEXT_PROFILE=ultra"

set "LAN_IP="
set "IP_LIST="
for /f "usebackq delims=" %%I in (`powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ips = @();" ^
  "try {" ^
  "  $route = Get-NetRoute -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -ErrorAction Stop ^| Sort-Object RouteMetric, ifMetric ^| Select-Object -First 1;" ^
  "  if ($route) {" ^
  "    $primary = Get-NetIPAddress -AddressFamily IPv4 -InterfaceIndex $route.IfIndex -ErrorAction SilentlyContinue ^| Where-Object { $_.IPAddress -match '^\d+\.\d+\.\d+\.\d+$' -and $_.IPAddress -ne '127.0.0.1' -and $_.IPAddress -notlike '169.254*' } ^| Select-Object -ExpandProperty IPAddress;" ^
  "    if ($primary) { $ips += $primary }" ^
  "  }" ^
  "} catch { }" ^
  "if (-not $ips) {" ^
  "  try { $ips += Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop ^| Where-Object { $_.IPAddress -match '^\d+\.\d+\.\d+\.\d+$' -and $_.IPAddress -ne '127.0.0.1' -and $_.IPAddress -notlike '169.254*' } ^| Select-Object -ExpandProperty IPAddress } catch { }" ^
  "}" ^
  "if (-not $ips) {" ^
  "  try { $ips += (ipconfig ^| Select-String -Pattern 'IPv4[^:]*:\s*([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)' -AllMatches).Matches ^| ForEach-Object { $_.Groups[1].Value } } catch { }" ^
  "}" ^
  "$ips = $ips ^| Where-Object { $_ -and $_ -ne '127.0.0.1' -and $_ -notlike '169.254*' } ^| Select-Object -Unique;" ^
  "if ($ips.Count -gt 0) { Write-Output ('PRIMARY=' + $ips[0]); Write-Output ('ALL=' + ($ips -join ', ')) }"`) do (
  echo %%I| findstr /B /C:"PRIMARY=" >nul && set "LAN_IP=%%I"
  echo %%I| findstr /B /C:"ALL=" >nul && set "IP_LIST=%%I"
)

if defined LAN_IP set "LAN_IP=%LAN_IP:PRIMARY=%"
if defined IP_LIST set "IP_LIST=%IP_LIST:ALL=%"

cls
echo.
echo ###########################################################################
echo ############################# MAIN PC SERVER ###############################
echo ###########################################################################
echo.
echo   COPY THIS TO YOUR WORK LAPTOP INSTALLER:
echo.
if defined LAN_IP (
  echo   MAIN PC IPv4:   %LAN_IP%
  echo   API BASE URL:   http://%LAN_IP%:%LLAMA_PORT%/v1
  echo   MODELS URL:     http://%LAN_IP%:%LLAMA_PORT%/v1/models
  if defined IP_LIST (
    echo.
    echo   Detected IPv4 candidates: %IP_LIST%
    echo   ^(Use the first one above unless your work PC is on a different adapter.^)
  )
) else (
  echo   MAIN PC IPv4:   [AUTO-DETECT FAILED]
  echo   Run ipconfig and use your active IPv4 address.
  echo   API BASE URL:   http://YOUR_MAIN_PC_IP:%LLAMA_PORT%/v1
)
echo.
echo   Keep this server window open while using OpenCode on your work laptop.
echo.
echo ###########################################################################
echo.

set "SERVER_SCRIPT=%ROOT_DIR%\MAIN_DATA\start_server.bat"
if exist "%SERVER_SCRIPT%" (
  call "%SERVER_SCRIPT%"
  set "EXIT_CODE=%ERRORLEVEL%"
  if not "%EXIT_CODE%"=="0" (
    echo.
    echo [ERROR] Server exited with code %EXIT_CODE%.
    echo Press any key to keep this console open for troubleshooting.
    pause >nul
  )
  exit /b %EXIT_CODE%
)

echo [ERROR] Could not find server startup script in:
echo   "%SERVER_SCRIPT%"
pause
exit /b 1
