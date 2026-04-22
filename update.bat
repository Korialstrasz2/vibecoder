@echo off
setlocal
cd /d "%~dp0"

echo Fetching latest refs...
git fetch --all --quiet
if %errorlevel% neq 0 (
  echo [ERROR] Fetch failed. Is this a git repository?
  pause
  exit /b 1
)

echo.
echo Available branches:
git branch -r --no-color | findstr /v "HEAD" | findstr /v "^$"
echo.
set /p ACTION=Git action [pull]: 
if "%ACTION%"=="" set ACTION=pull

echo.
echo Running: git %ACTION%
echo.
git %ACTION%
if %errorlevel% neq 0 (
  echo.
  echo [ERROR] 'git %ACTION%' failed.
  pause
  exit /b 1
)

echo.
echo Done.
pause
endlocal
