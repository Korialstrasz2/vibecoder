@echo off
setlocal EnableExtensions
cd /d "%~dp0"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\list_audio_devices.ps1"
endlocal & exit /b %ERRORLEVEL%
