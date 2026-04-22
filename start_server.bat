@echo off
setlocal
cd /d "%~dp0"

if exist "local_settings.bat" call "local_settings.bat"

if "%LLAMA_HOST%"=="" set LLAMA_HOST=127.0.0.1
if "%LLAMA_PORT%"=="" set LLAMA_PORT=8080
if "%LLAMA_CTX%"=="" set LLAMA_CTX=32768
if "%LLAMA_GPU_LAYERS%"=="" set LLAMA_GPU_LAYERS=999
if "%LLAMA_ALIAS%"=="" set LLAMA_ALIAS=qwen-local

if "%LLAMA_EXE%"=="" set LLAMA_EXE=%CD%\runtime\llama.cpp\llama-server.exe
if not "%LLAMA_EXE%"=="" for %%I in ("%LLAMA_EXE%") do set "LLAMA_EXE=%%~fI"
if not "%MODEL_FILE%"=="" for %%I in ("%MODEL_FILE%") do set "MODEL_FILE=%%~fI"

if not exist "%LLAMA_EXE%" (
  if exist "%CD%\runtime\llama.cpp\build\bin\llama-server.exe" (
    set LLAMA_EXE=%CD%\runtime\llama.cpp\build\bin\llama-server.exe
  ) else (
    echo [ERROR] llama-server.exe not found:
    echo %LLAMA_EXE%
    echo.
    echo Set LLAMA_EXE in local_settings.bat or place llama-server.exe in:
    echo runtime\llama.cpp\    (or runtime\llama.cpp\build\bin\)
    pause
    exit /b 1
  )
)

if "%MODEL_FILE%"=="" (
  set MODEL_FILE=
  for %%F in ("%CD%\models\*.gguf") do (
    if exist "%%~fF" (
      set MODEL_FILE=%%~fF
      goto found_model
    )
  )
  for /f "delims=" %%F in ('dir /b /s "%CD%\models\*.gguf" 2^>nul') do (
    set MODEL_FILE=%%~fF
    goto found_model
  )
)

:found_model
if "%MODEL_FILE%"=="" (
  echo [ERROR] No .gguf model found in:
  echo %CD%\models
  echo.
  echo Put one GGUF file in models\ (including subfolders) and run this again.
  echo Or set MODEL_FILE in local_settings.bat to the model path.
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
