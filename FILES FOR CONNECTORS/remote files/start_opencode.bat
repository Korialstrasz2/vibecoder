@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"

set "CONFIG_SOURCE=%~dp0config\opencode\opencode.jsonc"
set "CONFIG_DIR=%USERPROFILE%\.config\opencode"
set "CONFIG_DEST=%CONFIG_DIR%\opencode.jsonc"
set "LEGACY_CONFIG_DIR=%APPDATA%\opencode"
set "LEGACY_CONFIG_DEST=%LEGACY_CONFIG_DIR%\opencode.jsonc"
set "LOCAL_OPENCODE=%~dp0tools\npm-global\opencode.cmd"

if not exist "%CONFIG_SOURCE%" (
  echo [ERROR] Missing config file:
  echo   "%CONFIG_SOURCE%"
  echo Run install.bat first.
  exit /b 1
)

if not exist "%CONFIG_DIR%" mkdir "%CONFIG_DIR%"
copy /Y "%CONFIG_SOURCE%" "%CONFIG_DEST%" >nul
if not exist "%LEGACY_CONFIG_DIR%" mkdir "%LEGACY_CONFIG_DIR%"
copy /Y "%CONFIG_SOURCE%" "%LEGACY_CONFIG_DEST%" >nul 2>nul

set "OPENCODE_CMD=opencode"
where opencode >nul 2>nul
if errorlevel 1 (
  if exist "%LOCAL_OPENCODE%" (
    set "OPENCODE_CMD=%LOCAL_OPENCODE%"
  ) else (
    echo [ERROR] opencode not found.
    echo Run install.bat first to install local dependencies without admin rights.
    exit /b 1
  )
)

call :read_base_url
if errorlevel 1 exit /b 1

:check_server
if defined BASE_URL (
  echo Checking server: %BASE_URL%/models
  curl -s --max-time 5 "%BASE_URL%/models" >nul 2>nul
  if errorlevel 1 (
    echo.
    echo [WARN] Server not reachable at %BASE_URL%/models
    set /p "NEW_MAIN_PC_IP=Enter MAIN PC IPv4 to retry (blank to cancel): "
    if not defined NEW_MAIN_PC_IP (
      echo Cancelled.
      exit /b 1
    )
    echo %NEW_MAIN_PC_IP%| findstr /R /C:"^[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*$" >nul
    if errorlevel 1 (
      echo [WARN] Invalid IPv4 format. Example: 192.168.1.50
      goto :check_server
    )

    set "BASE_URL=http://%NEW_MAIN_PC_IP%:8076/v1"
    call :write_base_url
    if errorlevel 1 exit /b 1
    goto :check_server
  )
)

if not exist "projects" mkdir "projects"
cd /d "%~dp0projects"

echo Starting OpenCode in:
echo   %CD%
call "%OPENCODE_CMD%"
exit /b %ERRORLEVEL%

:read_base_url
set "BASE_URL="
for /f "usebackq delims=" %%I in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "$json = Get-Content -Raw $env:CONFIG_SOURCE; if ($json -match '\"baseURL\"\s*:\s*\"([^\"]+)\"') { Write-Output $matches[1] }"`) do set "BASE_URL=%%I"
if not defined BASE_URL (
  echo [ERROR] Could not read baseURL from:
  echo   "%CONFIG_SOURCE%"
  exit /b 1
)
exit /b 0

:write_base_url
echo Updating config baseURL to: %BASE_URL%
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$json = Get-Content -Raw $env:CONFIG_SOURCE;" ^
  "$updated = [regex]::Replace($json, '\"baseURL\"\s*:\s*\"[^\"]+\"', ('\"baseURL\": \"' + $env:BASE_URL + '\"'));" ^
  "$updated | Set-Content -Encoding UTF8 $env:CONFIG_SOURCE"
if errorlevel 1 (
  echo [ERROR] Failed to update baseURL in config source.
  exit /b 1
)

copy /Y "%CONFIG_SOURCE%" "%CONFIG_DEST%" >nul
copy /Y "%CONFIG_SOURCE%" "%LEGACY_CONFIG_DEST%" >nul 2>nul
exit /b 0
