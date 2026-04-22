@echo off
REM test-image-input.bat
REM
REM Smoke test: sends a text + image request to the local llama.cpp server
REM and checks that it returns a response (proving vision input works).
REM
REM Usage:
REM   scripts\test-image-input.bat
REM   scripts\test-image-input.bat --image C:\path\to\image.png
REM
REM Environment variables:
REM   LLAMA_HOST  - server host (default: 127.0.0.1)
REM   LLAMA_PORT  - server port (default: 8080)
REM   IMAGE_FILE  - path to image for test (default: .\models\test-image.png)

setlocal enabledelayedexpansion

set "LLAMA_HOST=%LLAMA_HOST%"
if "%LLAMA_HOST%"=="" set "LLAMA_HOST=127.0.0.1"
set "LLAMA_PORT=%LLAMA_PORT%"
if "%LLAMA_PORT%"=="" set "LLAMA_PORT=8080"
set "BASE_URL=http://%LLAMA_HOST%:%LLAMA_PORT%/v1"

set "IMAGE_FILE=%IMAGE_FILE%"
if "%IMAGE_FILE%"=="" set "IMAGE_FILE=.\models\test-image.png"

echo === Image Input Smoke Test ===
echo Server: %BASE_URL%

REM Check server health
echo -n Checking server health...
curl -sf "%BASE_URL%/models" >nul 2>&1
if errorlevel 1 (
    echo FAILED - server not reachable at %BASE_URL%
    echo Start llama-server first:
    echo   scripts\run-llama-qwen36-vision.bat
    goto :end_failed
)
echo OK

REM Check if we have an image file
if not exist "%IMAGE_FILE%" (
    echo.
    echo No test image found at: %IMAGE_FILE%
    echo Creating a small test PNG (1x1 red pixel)...
    if not exist "models" mkdir models
    REM Use PowerShell to create a minimal 1x1 red PNG
    powershell -Command ^
      "$b=New-Object System.Drawing.Bitmap(1,1); ^
       $b.SetPixel(0,0,[System.Drawing.Color]::FromArgb(255,255,0,0)); ^
       $b.Save('%IMAGE_FILE%', [System.Drawing.Imaging.ImageFormat]::Png); ^
       $b.Dispose()" 2>nul
    if errorlevel 1 (
        echo Warning: Could not create test image via PowerShell.
        echo Please provide a test image at: %IMAGE_FILE%
        echo Or run: curl -o models\test-image.png https://example.com/test.png
        goto :end_no_image
    )
    echo Created: %IMAGE_FILE%
)

REM Read image as hex then convert to base64 using PowerShell
set "IMAGE_TYPE=image/png"

for %%F in ("%IMAGE_FILE%") do set "FILE_EXT=%%~xF"
if /i "%FILE_EXT%"==".jpg" set "IMAGE_TYPE=image/jpeg"
if /i "%FILE_EXT%"==".jpeg" set "IMAGE_TYPE=image/jpeg"

powershell -Command ^
  "$bytes=[System.IO.File]::ReadAllBytes('%IMAGE_FILE%'); ^
   $b64=[Convert]::ToBase64String($bytes); ^
   $content='{`"model`":`"qwen36-vision`",`"messages`":[{`"role`":`"user`",`"content`":[{`"type`":`"text`",`"text`":`"What is in this image? Describe it briefly.`"},{`"type`":`"image_url`",`"image_url`":{`"url`":`"data:%IMAGE_TYPE%;base64,$b64`"}}]}],`"max_tokens`":200,`"temperature`":0.7}'; ^
   $content | Out-File -Encoding utf8 -FilePath 'test-payload.json'"

if errorlevel 1 (
    echo FAILED - could not read image file
    goto :end_failed
)

echo.
echo Sending vision request...
echo Model: qwen36-vision
echo Image: %IMAGE_FILE% (%IMAGE_TYPE%)
echo.

curl -sf -X POST "%BASE_URL%/chat/completions" ^
    -H "Content-Type: application/json" ^
    -H "Authorization: Bearer sk-no-key-required" ^
    -d @test-payload.json > test-response.json 2>&1

if errorlevel 1 (
    echo FAILED - no response from server
    echo.
    echo Possible causes:
    echo   1. Server not running (start with: scripts\run-llama-qwen36-vision.bat)
    echo   2. Model 'qwen36-vision' not registered - check --mmproj is loaded
    echo   3. Image format not supported - try PNG or JPEG
    echo   4. Model does not support vision - mmproj may be missing
    goto :end_failed
)

echo === Response ===
type test-response.json
echo.
echo === Test complete ===
echo If you see a response above, image input is working!
echo.
echo Troubleshooting:
echo   - 'model not found' -> check model name in opencode.jsonc matches server
echo   - 'unsupported format' -> mmproj may not be loaded; verify --mmproj flag
echo   - 'modalities' error -> ensure opencode.jsonc has modalities for vision model
del /q test-payload.json test-response.json 2>nul
goto :end_success

:end_no_image
echo.
echo Please provide a test image and re-run this script.
goto :end_failed

:end_failed
echo.
echo === TEST FAILED ===
del /q test-payload.json test-response.json 2>nul
exit /b 1

:end_success
exit /b 0
