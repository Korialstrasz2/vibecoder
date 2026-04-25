@echo off
setlocal EnableExtensions
cd /d "%~dp0"

if not defined LLAMA_HOST set "LLAMA_HOST=127.0.0.1"
if not defined LLAMA_PORT set "LLAMA_PORT=8075"

if "%~1"=="" (
  echo Usage:
  echo   %~nx0 path\to\audio.wav
  echo.
  echo Sends the audio file to llama-server /v1/audio/transcriptions.
  exit /b 2
)

set "AUDIO_FILE=%~1"
if not exist "%AUDIO_FILE%" (
  echo [ERROR] Audio file not found:
  echo   "%AUDIO_FILE%"
  exit /b 1
)

echo POST http://%LLAMA_HOST%:%LLAMA_PORT%/v1/audio/transcriptions
echo File: "%AUDIO_FILE%"
echo.

curl.exe -s -X POST "http://%LLAMA_HOST%:%LLAMA_PORT%/v1/audio/transcriptions" ^
  -F "response_format=json" ^
  -F "language=en" ^
  -F "prompt=Transcribe exactly. This may include Elder Scrolls names such as Divayth Fyr, Telvanni, Morrowind, Sotha Sil, Vivec, Dagoth Ur, Dwemer, and Nerevarine." ^
  -F "file=@%AUDIO_FILE%"

echo.
endlocal
