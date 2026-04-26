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
for /f "usebackq delims=" %%I in (`powershell -NoProfile -Command "$ip = Get-NetIPAddress -AddressFamily IPv4 ^| Where-Object { $_.IPAddress -ne '127.0.0.1' -and $_.IPAddress -notlike '169.254*' -and $_.PrefixOrigin -ne 'WellKnown' } ^| Select-Object -First 1 -ExpandProperty IPAddress; if (-not $ip) { $ip = (Get-CimInstance Win32_NetworkAdapterConfiguration ^| Where-Object { $_.IPEnabled } ^| ForEach-Object { $_.IPAddress } ^| Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' -and $_ -ne '127.0.0.1' -and $_ -notlike '169.254*' } ^| Select-Object -First 1) }; if ($ip) { Write-Output $ip }"`) do set "LAN_IP=%%I"

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

if exist "start_server_lan.bat" (
  call "start_server_lan.bat"
  exit /b %ERRORLEVEL%
)

echo [ERROR] Could not find start_server_lan.bat in:
echo   "%ROOT_DIR%"
exit /b 1
