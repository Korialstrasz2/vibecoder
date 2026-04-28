@echo off
setlocal
cd /d "%~dp0"

echo Starting VibeCoder entrance...

where py >nul 2>nul
if %errorlevel%==0 (
    start "VibeCoder Launcher API" /min py launcher.py
) else (
    where python >nul 2>nul
    if %errorlevel%==0 (
        start "VibeCoder Launcher API" /min python launcher.py
    ) else (
        echo ERROR: Python launcher not found (py/python missing in PATH).
        pause
        exit /b 1
    )
)

timeout /t 1 /nobreak >nul
start "" "%~dp0entrance.html"
exit /b 0
