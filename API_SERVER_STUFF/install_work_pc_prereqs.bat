@echo off
setlocal EnableExtensions

REM =====================================================
REM Installs prerequisites on work PC (requires winget)
REM =====================================================

echo [INFO] Checking winget...
where winget >nul 2>&1
if errorlevel 1 (
  echo [ERROR] winget not found. Install App Installer from Microsoft Store.
  exit /b 1
)

echo [INFO] Installing Node.js LTS...
winget install -e --id OpenJS.NodeJS.LTS --accept-package-agreements --accept-source-agreements
if errorlevel 1 (
  echo [WARN] Node.js install may have failed or already exists.
)

echo [INFO] Installing OpenCode CLI globally...
call npm install -g opencode-ai@latest
if errorlevel 1 (
  echo [ERROR] Failed to install opencode-ai globally.
  echo         Open a new Command Prompt as needed and retry.
  exit /b 1
)

echo [INFO] Done. Verify with: opencode --help
endlocal
