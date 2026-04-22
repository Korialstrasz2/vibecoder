@echo off
setlocal
cd /d "%~dp0"

echo.
echo === Vibe Coding Portable Kit setup ===
echo.

where node >nul 2>nul
if errorlevel 1 (
  echo [ERROR] Node.js was not found.
  echo Install Node.js 20 LTS, then run this again.
  echo https://nodejs.org/
  pause
  exit /b 1
)

where npm >nul 2>nul
if errorlevel 1 (
  echo [ERROR] npm was not found.
  echo Install Node.js 20 LTS, then run this again.
  pause
  exit /b 1
)

where python >nul 2>nul
if errorlevel 1 (
  echo [ERROR] Python was not found.
  echo Install Python 3.11+ or 3.12, then run this again.
  echo https://www.python.org/downloads/windows/
  pause
  exit /b 1
)

echo Installing/updating OpenCode globally via npm...
call npm install -g opencode-ai
if errorlevel 1 (
  echo [WARN] OpenCode npm install failed.
  echo You can also install with Chocolatey/Scoop or download the Windows binary.
) else (
  echo OpenCode installed or updated.
)

echo.
echo Creating local Aider venv...
if not exist ".venv-aider\Scripts\python.exe" (
  python -m venv .venv-aider
)

call ".venv-aider\Scripts\python.exe" -m pip install --upgrade pip
call ".venv-aider\Scripts\pip.exe" install --upgrade aider-chat

echo.
echo Setup complete.
echo Next:
echo 1. Put llama-server.exe in runtime\llama.cpp\
echo 2. Put a GGUF model in models\
echo 3. Run start_server.bat
echo 4. Run start_opencode.bat or start_aider.bat
echo.
pause
endlocal
