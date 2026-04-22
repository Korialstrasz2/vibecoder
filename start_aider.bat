@echo off
setlocal
cd /d "%~dp0"

if not exist ".venv-aider\Scripts\aider.exe" (
  echo [ERROR] Aider venv not found.
  echo Run setup_tools.bat first.
  pause
  exit /b 1
)

if not exist "projects" mkdir "projects"
cd projects

echo.
echo === Starting Aider with local llama.cpp server ===
echo Server must be running at http://127.0.0.1:8080/v1
echo Model alias: qwen-local
echo.

set OPENAI_API_BASE=http://127.0.0.1:8080/v1
set OPENAI_API_KEY=local-not-used

"..\.venv-aider\Scripts\aider.exe" --openai-api-base http://127.0.0.1:8080/v1 --openai-api-key local-not-used --model openai/qwen-local

endlocal
