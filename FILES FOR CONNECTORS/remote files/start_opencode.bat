@echo off
setlocal EnableExtensions
cd /d "%~dp0"

set "CONFIG_SOURCE=%~dp0config\opencode\opencode.jsonc"
set "CONFIG_DIR=%USERPROFILE%\.config\opencode"
set "CONFIG_DEST=%CONFIG_DIR%\opencode.jsonc"
set "LEGACY_CONFIG_DIR=%APPDATA%\opencode"
set "LEGACY_CONFIG_DEST=%LEGACY_CONFIG_DIR%\opencode.jsonc"

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

where opencode >nul 2>nul
if errorlevel 1 (
  echo [ERROR] opencode not found. Run install.bat first.
  exit /b 1
)

for /f "usebackq delims=" %%I in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "$json = Get-Content -Raw '%CONFIG_SOURCE%'; if ($json -match '\"baseURL\"\s*:\s*\"([^\"]+)\"') { Write-Output $matches[1] }"`) do set "BASE_URL=%%I"

if defined BASE_URL (
  echo Checking server: %BASE_URL%/models
  curl -s --max-time 5 "%BASE_URL%/models" >nul 2>nul
  if errorlevel 1 (
    echo [ERROR] Server not reachable at %BASE_URL%/models
    echo Start server on main PC, then retry.
    exit /b 1
  )
)

if not exist "projects" mkdir "projects"
cd /d "%~dp0projects"

echo Starting OpenCode in:
echo   %CD%
opencode
exit /b %ERRORLEVEL%
