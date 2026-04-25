@echo off
setlocal EnableExtensions
cd /d "%~dp0"

set "LLAMA_HOST=0.0.0.0"
if not defined LLAMA_PORT set "LLAMA_PORT=8076"

set "LAN_IP="
for /f "usebackq delims=" %%I in (`powershell -NoProfile -Command "$ip = Get-NetIPAddress -AddressFamily IPv4 ^| Where-Object { $_.IPAddress -ne '127.0.0.1' -and $_.IPAddress -notlike '169.254*' -and $_.PrefixOrigin -ne 'WellKnown' } ^| Select-Object -First 1 -ExpandProperty IPAddress; if (-not $ip) { $ip = (Get-CimInstance Win32_NetworkAdapterConfiguration ^| Where-Object { $_.IPEnabled } ^| ForEach-Object { $_.IPAddress } ^| Where-Object { $_ -match '^\\d+\\.\\d+\\.\\d+\\.\\d+$' -and $_ -ne '127.0.0.1' -and $_ -notlike '169.254*' } ^| Select-Object -First 1) }; if ($ip) { Write-Output $ip }"`) do set "LAN_IP=%%I"

echo.
echo === LAN Server Mode ===
echo Host binding: %LLAMA_HOST%
echo Port:         %LLAMA_PORT%
if defined LAN_IP (
  echo LAN IP:       %LAN_IP%
  echo Base URL:     http://%LAN_IP%:%LLAMA_PORT%/v1
  echo Models API:   http://%LAN_IP%:%LLAMA_PORT%/v1/models
) else (
  echo LAN IP:       [not detected automatically]
  echo Run ^"ipconfig^" and use your active IPv4 manually.
)
echo.
echo NOTE: This exposes your model server on your local network.
echo       Keep this on trusted/private networks only.
echo.

call start_server.bat
set "EXIT_CODE=%ERRORLEVEL%"

endlocal & exit /b %EXIT_CODE%
