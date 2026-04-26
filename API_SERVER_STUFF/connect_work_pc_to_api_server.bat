@echo off
setlocal EnableExtensions

REM =====================================================
REM OpenCode client attach helper (work PC)
REM =====================================================

REM ---- SETTINGS (edit these) ----
set "SERVER_IP=192.168.1.50"
set "SERVER_PORT=4096"
set "OPENCODE_PASSWORD=CHANGE_ME_TO_THE_SAME_PASSWORD"

set "SERVER_URL=http://%SERVER_IP%:%SERVER_PORT%"

echo [INFO] Checking opencode availability...
where opencode >nul 2>&1
if errorlevel 1 (
  echo [ERROR] opencode is not installed or not in PATH.
  echo         Run install_work_pc_prereqs.bat first.
  exit /b 1
)

echo [INFO] Attaching to %SERVER_URL%
set "OPENCODE_SERVER_PASSWORD=%OPENCODE_PASSWORD%"
opencode attach %SERVER_URL%

endlocal
