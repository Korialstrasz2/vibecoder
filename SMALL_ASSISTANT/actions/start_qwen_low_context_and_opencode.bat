@echo off
setlocal EnableExtensions
cd /d "%~dp0\..\.."

echo [INFO] Starting llama-server with profile choice 1 and model choice 3...
start "Qwen Low Context Server" cmd /k "cd /d ""%CD%"" && (echo 1&echo 3) ^| call start_server.bat"

echo [INFO] Waiting for server warmup...
timeout /t 4 /nobreak >nul

echo [INFO] Launching OpenCode...
call start_opencode.bat

endlocal
