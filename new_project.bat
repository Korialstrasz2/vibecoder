@echo off
setlocal
cd /d "%~dp0"

if "%~1"=="" (
  set /p PROJECT_NAME=Project folder name: 
) else (
  set PROJECT_NAME=%~1
)

if "%PROJECT_NAME%"=="" (
  echo [ERROR] No project name provided.
  exit /b 1
)

if not exist "projects" mkdir "projects"
cd projects

if exist "%PROJECT_NAME%" (
  echo [ERROR] Project already exists: %PROJECT_NAME%
  pause
  exit /b 1
)

mkdir "%PROJECT_NAME%"
cd "%PROJECT_NAME%"
git init

echo # %PROJECT_NAME%> README.md
echo.>> README.md
echo Created for local vibe coding.>> README.md

echo.
echo Created project:
echo %CD%
echo.
echo Now run start_opencode.bat or start_aider.bat and cd into:
echo %PROJECT_NAME%
echo.
pause
endlocal
