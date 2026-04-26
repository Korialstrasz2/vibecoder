@echo off
setlocal EnableExtensions
cd /d "%~dp0"

set "SECONDS=%~1"
if "%SECONDS%"=="" set "SECONDS=8"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\voice_to_clipboard_auto_v3.ps1" -Seconds "%SECONDS%"
set "EXIT_CODE=%ERRORLEVEL%"

if not "%EXIT_CODE%"=="0" (
  echo.
  echo [ERROR] Local voice helper failed.
  echo This window is staying open so you can read the error.
  echo.
  echo If device parsing failed, open:
  echo   %~dp0system\cache\.last_dshow_devices.txt
  echo.
  pause
)

endlocal & exit /b %EXIT_CODE%
