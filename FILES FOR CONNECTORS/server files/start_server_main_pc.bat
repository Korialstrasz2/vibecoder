@echo off
setlocal EnableExtensions
cd /d "%~dp0"

rem MAIN PC launcher for LAN use
set "ROOT_DIR=%~dp0..\.."
cd /d "%ROOT_DIR%"

set "LLAMA_HOST=0.0.0.0"
if not defined LLAMA_PORT set "LLAMA_PORT=8076"
if not defined CONTEXT_PROFILE set "CONTEXT_PROFILE=ultra"

if exist "start_server_lan.bat" (
  call "start_server_lan.bat"
  exit /b %ERRORLEVEL%
)

echo [ERROR] Could not find start_server_lan.bat in:
echo   "%ROOT_DIR%"
exit /b 1
