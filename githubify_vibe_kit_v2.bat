@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"

echo.
echo ============================================================
echo   GitHubify Vibe Coding Portable Kit - v2
echo ============================================================
echo.
echo This safer version avoids adding projects/ contents.
echo It only stages toolkit files and placeholders.
echo.

where git >nul 2>nul
if errorlevel 1 (
    echo [ERROR] Git was not found.
    echo Install Git for Windows first:
    echo https://git-scm.com/download/win
    pause
    exit /b 1
)

REM ------------------------------------------------------------
REM Optional: normalize line ending warnings for this repo
REM ------------------------------------------------------------
git config --global core.autocrlf true >nul 2>nul

REM ------------------------------------------------------------
REM Create required folders
REM ------------------------------------------------------------
if not exist "models" mkdir "models"
if not exist "runtime" mkdir "runtime"
if not exist "runtime\llama.cpp" mkdir "runtime\llama.cpp"
if not exist "projects" mkdir "projects"
if not exist "logs" mkdir "logs"
if not exist "config" mkdir "config"
if not exist "config\opencode" mkdir "config\opencode"

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

REM ------------------------------------------------------------
REM Write .gitattributes to reduce CRLF noise
REM ------------------------------------------------------------
> ".gitattributes" (
    echo * text=auto
    echo *.bat text eol=crlf
    echo *.cmd text eol=crlf
    echo *.ps1 text eol=crlf
    echo *.md text eol=lf
    echo *.json text eol=lf
    echo *.jsonc text eol=lf
    echo *.yml text eol=lf
    echo *.yaml text eol=lf
)

echo [OK] .gitignore and .gitattributes created/updated.

REM ------------------------------------------------------------
REM Initialize git repo if needed
REM ------------------------------------------------------------
if not exist ".git" (
    echo.
    echo Initializing git repository...
    git init
) else (
    echo.
    echo Git repository already exists.
)

git branch -M main >nul 2>nul

REM ------------------------------------------------------------
REM Remove accidentally staged/tracked ignored paths from index only
REM This does NOT delete local files.
REM ------------------------------------------------------------
git rm -r --cached models >nul 2>nul
git rm -r --cached runtime\llama.cpp >nul 2>nul
git rm -r --cached .venv-aider >nul 2>nul
git rm -r --cached projects >nul 2>nul
git rm -r --cached logs >nul 2>nul

REM ------------------------------------------------------------
REM Stage safe toolkit files explicitly.
REM Do NOT use git add .
REM ------------------------------------------------------------
echo.
echo Staging safe toolkit files only...

git add .gitignore
git add .gitattributes

if exist "README.md" git add README.md
if exist "PROMPTS.md" git add PROMPTS.md

if exist "setup_tools.bat" git add setup_tools.bat
if exist "start_server.bat" git add start_server.bat
if exist "start_opencode.bat" git add start_opencode.bat
if exist "start_aider.bat" git add start_aider.bat
if exist "new_project.bat" git add new_project.bat
if exist "check_server.bat" git add check_server.bat
if exist "githubify_vibe_kit.bat" git add githubify_vibe_kit.bat
if exist "githubify_vibe_kit_v2.bat" git add githubify_vibe_kit_v2.bat

if exist "models\PUT_GGUF_MODEL_HERE.txt" git add models\PUT_GGUF_MODEL_HERE.txt
if exist "models\.gitkeep" git add models\.gitkeep

if exist "runtime\llama.cpp\PUT_LLAMA_CPP_BINARIES_HERE.txt" git add runtime\llama.cpp\PUT_LLAMA_CPP_BINARIES_HERE.txt
if exist "runtime\llama.cpp\.gitkeep" git add runtime\llama.cpp\.gitkeep

if exist "projects\.gitkeep" git add projects\.gitkeep
if exist "logs\.gitkeep" git add logs\.gitkeep

if exist "config\opencode\opencode.jsonc" git add config\opencode\opencode.jsonc

REM Add scripts folder if present, but only ordinary files, not nested .git folders
if exist "scripts" (
    for /r "scripts" %%F in (*) do (
        echo %%F | findstr /i "\\.git\\" >nul
        if errorlevel 1 git add "%%F"
    )
)

REM ------------------------------------------------------------
REM Commit
REM ------------------------------------------------------------
git diff --cached --quiet
if errorlevel 1 (
    echo.
    echo Creating commit...
    git commit -m "Initialize portable vibe coding kit"
) else (
    echo.
    echo No staged changes to commit.
)

REM Check if at least one commit exists
git rev-parse --verify HEAD >nul 2>nul
if errorlevel 1 (
    echo.
    echo [ERROR] No commit exists, so there is nothing to push.
    echo Check git status below:
    git status --short
    echo.
    pause
    exit /b 1
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

    echo.
    echo Pushing to GitHub...
    git push -u origin main

    if errorlevel 1 (
        echo.
        echo [ERROR] Push failed.
        echo Common causes:
        echo   - GitHub authentication not configured
        echo   - remote repo already has commits
        echo   - wrong remote URL
        echo.
        echo Try manually:
        echo git pull --rebase origin main
        echo git push -u origin main
    ) else (
        echo.
        echo [OK] Pushed to GitHub.
    )
) else (
    echo.
    echo Skipped GitHub remote/push.
)

echo.
echo Final git status:
git status --short
echo.
echo Done.
pause
endlocal
