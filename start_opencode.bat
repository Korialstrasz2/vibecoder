@echo off
setlocal EnableExtensions
cd /d "%~dp0"

set "LOG_FILE=%~dp0start_opencode.log"
set "CONFIG_SOURCE=%~dp0config\opencode\opencode.jsonc"
set "CONFIG_DIR=%USERPROFILE%\.config\opencode"
set "CONFIG_DEST=%CONFIG_DIR%\opencode.jsonc"
set "LEGACY_CONFIG_DIR=%APPDATA%\opencode"
set "LEGACY_CONFIG_DEST=%LEGACY_CONFIG_DIR%\opencode.jsonc"

call :log ==========================================
call :log Starting OpenCode launcher in "%CD%"
call :log Timestamp: %DATE% %TIME%

echo.
echo === Preparing OpenCode local-provider config ===

if not exist "%CONFIG_SOURCE%" (
  call :log ERROR: Missing config source "%CONFIG_SOURCE%"
  echo [ERROR] Could not find your OpenCode config file:
  echo   "%CONFIG_SOURCE%"
  echo.
  echo Put your edited opencode.jsonc here:
  echo   config\opencode\opencode.jsonc
  echo.
  goto :fail
)

if not exist "%CONFIG_DIR%" mkdir "%CONFIG_DIR%"
if errorlevel 1 (
  call :log ERROR: Could not create config directory "%CONFIG_DIR%"
  echo [ERROR] Could not create:
  echo   "%CONFIG_DIR%"
  goto :fail
)

copy /Y "%CONFIG_SOURCE%" "%CONFIG_DEST%" >nul
if errorlevel 1 (
  call :log ERROR: Failed to copy config to "%CONFIG_DEST%"
  echo [ERROR] Failed to copy OpenCode config to:
  echo   "%CONFIG_DEST%"
  goto :fail
)

rem Also copy to the older APPDATA location. Harmless, and useful if your installed OpenCode build still checks it.
if not exist "%LEGACY_CONFIG_DIR%" mkdir "%LEGACY_CONFIG_DIR%"
copy /Y "%CONFIG_SOURCE%" "%LEGACY_CONFIG_DEST%" >nul 2>nul

call :log Config copied to "%CONFIG_DEST%"
echo Config installed:
echo   "%CONFIG_DEST%"
echo.
echo Expected local model in OpenCode:
echo   llama.cpp/qwen-local
echo.

where opencode >nul 2>nul
if errorlevel 1 (
  call :log ERROR: opencode command not found
  echo [ERROR] opencode command not found.
  echo Install it, then run this again:
  echo   npm install -g opencode-ai
  echo.
  goto :fail
)

echo Checking local llama-server at http://127.0.0.1:8080/v1/models ...
curl -s --max-time 3 "http://127.0.0.1:8080/v1/models" >nul 2>nul
if errorlevel 1 (
  call :log ERROR: Local server check failed
  echo [ERROR] Could not reach the local model server.
  echo.
  echo Start it first with:
  echo   start_server.bat
  echo.
  echo Then check this URL in a browser:
  echo   http://127.0.0.1:8080/v1/models
  echo.
  goto :fail
)

call :log Local server check passed
echo Local server is reachable.
echo.

if not exist "projects" mkdir "projects"
cd /d "%~dp0projects"

echo === Starting OpenCode ===
echo Project folder:
echo   "%CD%"
echo.
echo In OpenCode, use:
echo   /models
echo and select:
echo   llama.cpp/qwen-local
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
