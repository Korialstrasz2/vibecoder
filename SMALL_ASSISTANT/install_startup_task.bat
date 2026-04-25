@echo off
setlocal EnableExtensions
cd /d "%~dp0"

set "TASK_NAME=VibeSmallAssistant"
set "RUNNER=%CD%\run_small_assistant.bat"

schtasks /Query /TN "%TASK_NAME%" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
  schtasks /Delete /TN "%TASK_NAME%" /F >nul
)

schtasks /Create /TN "%TASK_NAME%" /TR "\"%RUNNER%\"" /SC ONLOGON /RL LIMITED /F
if %ERRORLEVEL% NEQ 0 (
  echo [ERROR] Failed to create startup task.
  exit /b 1
)

echo [OK] Startup task created: %TASK_NAME%
echo [OK] It will run at user logon.

endlocal
