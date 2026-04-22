@echo off
setlocal
cd /d "%~dp0"

if not exist "%APPDATA%\opencode" mkdir "%APPDATA%\opencode"

copy /Y "config\opencode\opencode.jsonc" "%APPDATA%\opencode\opencode.jsonc" >nul

echo.
echo === OpenCode config installed ===
echo %APPDATA%\opencode\opencode.jsonc
echo.
echo Make sure start_server.bat is running first.
echo.
echo Choose or create a project folder.
echo.

if not exist "projects" mkdir "projects"
cd projects

where opencode >nul 2>nul
if errorlevel 1 (
  echo [ERROR] opencode command not found.
  echo Run setup_tools.bat first, or install OpenCode manually:
  echo npm install -g opencode-ai
  pause
  exit /b 1
)

opencode

endlocal
