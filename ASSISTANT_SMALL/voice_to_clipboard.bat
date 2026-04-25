@echo off
setlocal EnableExtensions
cd /d "%~dp0"

set "SECONDS=%~1"
if "%SECONDS%"=="" set "SECONDS=8"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\voice_to_clipboard.ps1" -Seconds "%SECONDS%"
set "EXIT_CODE=%ERRORLEVEL%"

if not "%EXIT_CODE%"=="0" (
  echo.
  echo [ERROR] Voice helper failed.
  echo Try listing devices:
  echo   ASSISTANT_SMALL\list_audio_devices.bat
  echo Then set AUDIO_DEVICE to the exact microphone name and rerun.
)

endlocal & exit /b %EXIT_CODE%
