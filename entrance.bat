@echo off
setlocal
cd /d "%~dp0"

echo Starting VibeCoder entrance...

del /q launcher.log 2>nul

set "MISSING_FILES=0"
if not exist "launcher.py" (
    echo ERROR: Missing launcher.py in "%CD%".
    set "MISSING_FILES=1"
)
if not exist "entrance.html" (
    echo ERROR: Missing entrance.html in "%CD%".
    set "MISSING_FILES=1"
)
if not exist "entrance.js" (
    echo ERROR: Missing entrance.js in "%CD%".
    set "MISSING_FILES=1"
)
if "%MISSING_FILES%"=="1" (
    echo.
    echo Startup stopped because required launcher files are missing.
    pause
    exit /b 1
)

where py >nul 2>nul
if %errorlevel%==0 (
    start "VibeCoder Launcher API" cmd /c "py launcher.py > launcher.log 2>&1"
) else (
    where python >nul 2>nul
    if %errorlevel%==0 (
        start "VibeCoder Launcher API" cmd /c "python launcher.py > launcher.log 2>&1"
    ) else (
        echo ERROR: Python launcher not found (py/python missing in PATH).
        pause
        exit /b 1
    )
)

set /a retries=0
:wait_for_api
powershell -NoProfile -Command "try { $r=Invoke-WebRequest -UseBasicParsing http://127.0.0.1:8765/health -TimeoutSec 1; if($r.StatusCode -eq 200){exit 0}else{exit 1} } catch { exit 1 }"
if %errorlevel%==0 goto api_ready

set /a retries+=1
if %retries% GEQ 20 goto api_failed
timeout /t 1 /nobreak >nul
goto wait_for_api

:api_ready
echo Launcher API is running.
start "" "http://127.0.0.1:8765/"
exit /b 0

:api_failed
echo ERROR: Launcher API did not start.
echo --- launcher.log ---
if exist launcher.log type launcher.log
pause
exit /b 1
