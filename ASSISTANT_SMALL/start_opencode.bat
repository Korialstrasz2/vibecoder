@echo off
setlocal EnableExtensions
cd /d "%~dp0"

set "ROOT_DIR=%~dp0.."
for %%I in ("%ROOT_DIR%") do set "ROOT_DIR=%%~fI"

set "LOG_FILE=%~dp0start_opencode.log"

if not defined LLAMA_HOST set "LLAMA_HOST=127.0.0.1"
if not defined LLAMA_PORT set "LLAMA_PORT=8075"

call :log ==========================================
call :log Starting ASSISTANT_SMALL OpenCode launcher in "%CD%"
call :log Root dir: %ROOT_DIR%
call :log Timestamp: %DATE% %TIME%

echo.
echo === Starting OpenCode (ASSISTANT_SMALL local config) ===
echo Using config: %~dp0opencode.jsonc
echo.
set "OPENCODE_CONFIG=%~dp0opencode.jsonc"

where opencode >nul 2>nul
if errorlevel 1 (
  call :log ERROR: opencode command not found
  echo [ERROR] opencode command not found.
  echo Install it, then run this again:
  echo   npm install -g opencode-ai
  echo.
  goto :fail
)

echo Checking assistant llama-server at http://%LLAMA_HOST%:%LLAMA_PORT%/v1/models ...
curl.exe -s --max-time 3 "http://%LLAMA_HOST%:%LLAMA_PORT%/v1/models" >nul 2>nul
if errorlevel 1 (
  call :log WARNING: Assistant server check failed
  echo [WARN] Could not reach the ASSISTANT_SMALL model server.
  echo.
  echo Start it first with:
  echo   ASSISTANT_SMALL\start_server.bat
  echo.
  echo Then check this URL in a browser:
  echo   http://%LLAMA_HOST%:%LLAMA_PORT%/v1/models
  echo.
)

echo Voice helper, after server is running:
echo   ASSISTANT_SMALL\voice_to_clipboard.bat 8
echo.

if not exist "%ROOT_DIR%\projects" mkdir "%ROOT_DIR%\projects"
cd /d "%ROOT_DIR%\projects"

echo === Starting OpenCode ===
echo Project folder: "%CD%"
echo Model server:  http://%LLAMA_HOST%:%LLAMA_PORT%/v1
echo Config file:   %OPENCODE_CONFIG%
echo.

opencode
set "OPENCODE_EXIT=%ERRORLEVEL%"
call :log OpenCode exited with code %OPENCODE_EXIT%

endlocal & exit /b %OPENCODE_EXIT%

:fail
echo.
echo Script failed. See log:
echo   "%LOG_FILE%"
call :log Script failed
pause
endlocal & exit /b 1

:log
echo [%DATE% %TIME%] %*>>"%LOG_FILE%"
echo [%DATE% %TIME%] %*
exit /b 0
