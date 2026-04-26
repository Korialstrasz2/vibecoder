@echo off
setlocal EnableExtensions

REM =====================================================
REM OpenCode API server launcher (main / powerful PC)
REM =====================================================

REM ---- SETTINGS (edit these) ----
set "OPENCODE_PORT=4096"
set "OPENCODE_HOST=0.0.0.0"
set "OPENCODE_PASSWORD=CHANGE_ME_TO_A_STRONG_PASSWORD"
set "OPENCODE_PROJECT_DIR=C:\opencode-project"

echo [INFO] Checking opencode availability...
where opencode >nul 2>&1
if errorlevel 1 (
  echo [ERROR] opencode is not installed or not in PATH.
  echo         Install Node.js LTS, then run: npm install -g opencode-ai@latest
  exit /b 1
)

if not exist "%OPENCODE_PROJECT_DIR%" (
  echo [ERROR] Project directory does not exist: %OPENCODE_PROJECT_DIR%
  echo         Create it or change OPENCODE_PROJECT_DIR in this file.
  exit /b 1
)

echo [INFO] Starting OpenCode server on %OPENCODE_HOST%:%OPENCODE_PORT%
echo [INFO] Project context on server: %OPENCODE_PROJECT_DIR%
echo [INFO] Press Ctrl+C to stop.

set "OPENCODE_SERVER_PASSWORD=%OPENCODE_PASSWORD%"
cd /d "%OPENCODE_PROJECT_DIR%"
opencode serve --hostname %OPENCODE_HOST% --port %OPENCODE_PORT%

endlocal
