@echo off
setlocal EnableExtensions
cd /d "%~dp0"

echo.
echo === SMALL_ASSISTANT first-time setup ===
echo This script creates/uses SMALL_ASSISTANT\.venv only.
echo It will NOT touch the repo root environment or global Python packages.
echo.
echo Need download links opened automatically?
set "OPEN_DOWNLOADS=Y"
set /p "OPEN_DOWNLOADS=Open required download pages now? (Y/n): "
if /I "%OPEN_DOWNLOADS%"=="N" goto :skip_downloads
if /I "%OPEN_DOWNLOADS%"=="NO" goto :skip_downloads

echo [INFO] Opening download pages in new browser windows...
start "" "https://www.python.org/downloads/windows/"
start "" "https://github.com/ggml-org/whisper.cpp"
start "" "https://huggingface.co/ggerganov/whisper.cpp"
start "" "https://github.com/rhasspy/piper/releases"
start "" "https://ollama.com/download/windows"

:skip_downloads
echo.

where py >nul 2>nul
if errorlevel 1 (
  echo [ERROR] Python launcher "py" was not found.
  echo Install Python 3.11+ from https://www.python.org/downloads/windows/
  echo and ensure "py" works in cmd.
  exit /b 1
)

if not exist ".venv\Scripts\python.exe" (
  echo [INFO] Creating isolated virtual environment at:
  echo   %CD%\.venv
  py -3 -m venv .venv
  if errorlevel 1 (
    echo [ERROR] Failed to create virtual environment.
    exit /b 1
  )
) else (
  echo [INFO] Reusing existing isolated virtual environment:
  echo   %CD%\.venv
)

echo [INFO] Upgrading pip/setuptools/wheel inside SMALL_ASSISTANT\.venv...
call ".venv\Scripts\python.exe" -m pip install --upgrade pip setuptools wheel
if errorlevel 1 (
  echo [ERROR] Failed while upgrading pip tooling.
  exit /b 1
)

echo [INFO] Installing SMALL_ASSISTANT Python dependencies...
call ".venv\Scripts\python.exe" -m pip install -r requirements.txt
if errorlevel 1 (
  echo [ERROR] Dependency install failed.
  exit /b 1
)

echo.
echo [OK] Python dependencies are installed in SMALL_ASSISTANT\.venv.
echo.
echo Next steps (manual downloads/config):
echo   1) Install whisper.cpp main.exe and a Whisper model .bin
echo   2) Install Piper (piper.exe + .onnx voice + .onnx.json)
echo   3) Ensure local router endpoint is running (default: Ollama at http://127.0.0.1:11434/v1)
echo   4) Edit config.json paths:
echo      - stt.whisper_cli_path
echo      - stt.model_path
echo      - tts.piper_exe
echo      - tts.piper_model
echo      - tts.piper_config
echo.
echo Then start the assistant with:
echo   run_small_assistant.bat
echo.

endlocal
exit /b 0
