@echo off
setlocal
cd /d "%~dp0"

if exist "local_settings.bat" call "local_settings.bat"

if "%LLAMA_HOST%"=="" set LLAMA_HOST=127.0.0.1
if "%LLAMA_PORT%"=="" set LLAMA_PORT=8080
if "%LLAMA_CTX%"=="" set LLAMA_CTX=32768
if "%LLAMA_GPU_LAYERS%"=="" set LLAMA_GPU_LAYERS=999
if "%LLAMA_ALIAS%"=="" set LLAMA_ALIAS=qwen-local

set LLAMA_EXE=%CD%\runtime\llama.cpp\llama-server.exe
if not exist "%LLAMA_EXE%" (
  for /f "delims=" %%F in ('dir /b /s /a:-d "%CD%\runtime\llama.cpp\llama-server*.exe" 2^>nul') do (
    set LLAMA_EXE=%%~fF
    goto found_llama_exe
  )
)

:found_llama_exe

if not exist "%LLAMA_EXE%" (
  echo [ERROR] llama-server.exe not found:
  echo %LLAMA_EXE%
  echo.
  echo Download a Windows CUDA llama.cpp build and extract it into runtime\llama.cpp\
  pause
  exit /b 1
)

set MODEL_FILE=
for /f "delims=" %%F in ('dir /b /a:-d "%CD%\models\*.gguf" 2^>nul') do (
  set MODEL_FILE=%CD%\models\%%~nxF
  goto found_model
)

:found_model
if "%MODEL_FILE%"=="" (
  echo [ERROR] No .gguf model found in:
  echo %CD%\models
  echo.
  echo Put one GGUF file in models\ and run this again.
  pause
  exit /b 1
)

echo.
echo === Starting llama-server ===
echo Model: %MODEL_FILE%
echo URL:   http://%LLAMA_HOST%:%LLAMA_PORT%/v1
echo Ctx:   %LLAMA_CTX%
echo GPU layers: %LLAMA_GPU_LAYERS%
echo Alias: %LLAMA_ALIAS%
echo.

pushd "%CD%\runtime\llama.cpp"

"%LLAMA_EXE%" ^
  --model "%MODEL_FILE%" ^
  --host "%LLAMA_HOST%" ^
  --port "%LLAMA_PORT%" ^
  --ctx-size "%LLAMA_CTX%" ^
  --n-gpu-layers "%LLAMA_GPU_LAYERS%" ^
  --alias "%LLAMA_ALIAS%"

popd
endlocal
