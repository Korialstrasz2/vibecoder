@echo off
setlocal EnableExtensions
cd /d "%~dp0"

if not exist ".venv\Scripts\python.exe" (
  echo [INFO] Creating local virtual environment...
  py -3 -m venv .venv
)

echo [INFO] Installing/updating dependencies...
call ".venv\Scripts\python.exe" -m pip install --upgrade pip >nul
call ".venv\Scripts\python.exe" -m pip install -r requirements.txt

set "PYTHONUTF8=1"
echo [INFO] Starting SMALL_ASSISTANT service...
call ".venv\Scripts\python.exe" small_assistant_service.py

endlocal
