@echo off
setlocal EnableExtensions
cd /d "%~dp0"

set "PROFILE=%1"

if not defined PROFILE (
    echo Usage: switch_profile.bat ^<standard^|aggressive^>
    echo.
    echo  standard  - Normal mode (port 8080)
    echo  aggressive - Uncensored mode (port 8081)
    goto :end
)

set "SOURCE=config\opencode\profiles\%PROFILE%.jsonc"
set "TARGET=config\opencode\opencode.jsonc"
set "APPDATA_TARGET=%APPDATA%\opencode\opencode.jsonc"

if not exist "%SOURCE%" (
    echo [ERROR] Profile "%PROFILE%" not found at "%SOURCE%"
    goto :fail
)

echo Copying %PROFILE% profile...
copy /Y "%SOURCE%" "%TARGET%" >nul
echo   Updated: %TARGET%

copy /Y "%SOURCE%" "%APPDATA_TARGET%" >nul
echo   Updated: %APPDATA_TARGET%

echo.
echo Done. Restart opencode for changes to take effect.
echo.

goto :end

:fail
echo.
pause
exit /b 1

:end
endlocal & exit /b 0
