@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"

echo.
echo ============================================================
echo   GitHubify Vibe Coding Portable Kit
echo ============================================================
echo.
echo This will:
echo   - create/update .gitignore
echo   - create folder placeholders
echo   - initialize git if needed
echo   - stage safe files only
echo   - create a commit if there are changes
echo   - optionally add a GitHub remote and push
echo.

REM ------------------------------------------------------------
REM Check git
REM ------------------------------------------------------------
where git >nul 2>nul
if errorlevel 1 (
    echo [ERROR] Git was not found.
    echo Install Git for Windows first:
    echo https://git-scm.com/download/win
    echo.
    pause
    exit /b 1
)

REM ------------------------------------------------------------
REM Create folders
REM ------------------------------------------------------------
if not exist "models" mkdir "models"
if not exist "runtime" mkdir "runtime"
if not exist "runtime\llama.cpp" mkdir "runtime\llama.cpp"
if not exist "projects" mkdir "projects"
if not exist "logs" mkdir "logs"
if not exist "config" mkdir "config"

REM ------------------------------------------------------------
REM Create placeholder files
REM ------------------------------------------------------------
if not exist "models\PUT_GGUF_MODEL_HERE.txt" (
    > "models\PUT_GGUF_MODEL_HERE.txt" echo Put your GGUF model files here. Do not commit model files.
)

if not exist "runtime\llama.cpp\PUT_LLAMA_CPP_BINARIES_HERE.txt" (
    > "runtime\llama.cpp\PUT_LLAMA_CPP_BINARIES_HERE.txt" echo Put llama.cpp Windows binaries here. Do not commit exe/dll files.
)

if not exist "projects\.gitkeep" type nul > "projects\.gitkeep"
if not exist "logs\.gitkeep" type nul > "logs\.gitkeep"
if not exist "models\.gitkeep" type nul > "models\.gitkeep"
if not exist "runtime\llama.cpp\.gitkeep" type nul > "runtime\llama.cpp\.gitkeep"

REM ------------------------------------------------------------
REM Write .gitignore
REM ------------------------------------------------------------
> ".gitignore" (
    echo # ============================================================
    echo # Vibe Coding Portable Kit - Git Ignore
    echo # ============================================================
    echo.
    echo # Models: never commit GGUFs or model weights
    echo models/*
    echo !models/PUT_GGUF_MODEL_HERE.txt
    echo !models/.gitkeep
    echo.
    echo *.gguf
    echo *.safetensors
    echo *.bin
    echo *.pt
    echo *.pth
    echo *.onnx
    echo.
    echo # llama.cpp runtime binaries
    echo runtime/llama.cpp/*
    echo !runtime/llama.cpp/PUT_LLAMA_CPP_BINARIES_HERE.txt
    echo !runtime/llama.cpp/.gitkeep
    echo.
    echo *.exe
    echo *.dll
    echo *.lib
    echo *.pdb
    echo.
    echo # Local Python environments
    echo .venv-aider/
    echo .venv/
    echo venv/
    echo env/
    echo ENV/
    echo.
    echo # Generated/user projects
    echo # Recommended: each generated app should be its own separate repo
    echo projects/*
    echo !projects/.gitkeep
    echo.
    echo # Logs and temporary files
    echo logs/*
    echo !logs/.gitkeep
    echo tmp/
    echo temp/
    echo .cache/
    echo.
    echo # Node/npm caches
    echo node_modules/
    echo npm-cache/
    echo .npm/
    echo.
    echo # Python cache/test/lint artifacts
    echo __pycache__/
    echo *.py[cod]
    echo *$py.class
    echo .pytest_cache/
    echo .ruff_cache/
    echo .mypy_cache/
    echo .coverage
    echo htmlcov/
    echo dist/
    echo build/
    echo *.egg-info/
    echo.
    echo # Local settings / private overrides
    echo local_settings.bat
    echo .env
    echo .env.*
    echo !.env.example
    echo.
    echo # OpenCode / Aider local state, if created
    echo .aider*
    echo .opencode/
    echo opencode-state/
    echo conversation-history/
    echo *.log
    echo.
    echo # OS/editor junk
    echo .DS_Store
    echo Thumbs.db
    echo Desktop.ini
    echo .vscode/
    echo .idea/
    echo *.swp
    echo *.swo
)

echo [OK] .gitignore created/updated.

REM ------------------------------------------------------------
REM Initialize git repo
REM ------------------------------------------------------------
if not exist ".git" (
    echo.
    echo Initializing git repository...
    git init
) else (
    echo.
    echo Git repository already exists.
)

REM ------------------------------------------------------------
REM Rename branch to main
REM ------------------------------------------------------------
git branch -M main >nul 2>nul

REM ------------------------------------------------------------
REM Stage safe files
REM ------------------------------------------------------------
echo.
echo Staging safe files...
git add .

REM ------------------------------------------------------------
REM Commit if there are staged changes
REM ------------------------------------------------------------
git diff --cached --quiet
if errorlevel 1 (
    echo Creating commit...
    git commit -m "Initialize portable vibe coding kit"
) else (
    echo No changes to commit.
)

REM ------------------------------------------------------------
REM Optional GitHub remote
REM ------------------------------------------------------------
echo.
set /p REMOTE_URL=Paste GitHub repo URL to connect and push, or press ENTER to skip: 

if not "%REMOTE_URL%"=="" (
    echo.
    echo Configuring remote origin...

    git remote get-url origin >nul 2>nul
    if errorlevel 1 (
        git remote add origin "%REMOTE_URL%"
    ) else (
        git remote set-url origin "%REMOTE_URL%"
    )

    echo Pushing to GitHub...
    git push -u origin main

    if errorlevel 1 (
        echo.
        echo [ERROR] Push failed.
        echo Common causes:
        echo   - wrong repo URL
        echo   - GitHub authentication not configured
        echo   - repo already has unrelated commits
        echo.
        echo You can retry manually:
        echo git push -u origin main
    ) else (
        echo.
        echo [OK] Pushed to GitHub.
    )
) else (
    echo.
    echo Skipped GitHub remote/push.
    echo To push later:
    echo git remote add origin https://github.com/YOUR_USERNAME/YOUR_REPO.git
    echo git push -u origin main
)

echo.
echo Done.
echo.
pause
endlocal
