@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"

set "DEFAULT_ACTION=pull origin main"

echo ==================================================
echo   VibeCoder Git Update Helper
echo ==================================================
echo.

call :preflight_merge_state
if %errorlevel% neq 0 (
  pause
  exit /b 1
)

echo Fetching latest refs...
git fetch --all --quiet
if %errorlevel% neq 0 (
  echo [ERROR] Fetch failed. Is this a git repository and is network available?
  pause
  exit /b 1
)

echo.
echo Available branches:
git branch -r --no-color | findstr /v "HEAD" | findstr /v "^$"
echo.
set /p ACTION=Git action [%DEFAULT_ACTION%]: 
if "%ACTION%"=="" set "ACTION=%DEFAULT_ACTION%"

echo.
echo Running: git %ACTION%
echo.
git %ACTION%
if %errorlevel% neq 0 (
  call :handle_git_failure "%ACTION%"
  pause
  exit /b 1
)

echo.
echo Done.
pause
exit /b 0

:preflight_merge_state
REM Detect if a merge is already in progress
if exist ".git\MERGE_HEAD" (
  echo [NOTICE] A merge is already in progress.
  git status --short
  echo.
  call :show_merge_help
  echo.
  set /p MERGE_CHOICE=Choose: [c]ontinue merge, [a]bort merge, [q]uit [c]: 
  if /i "!MERGE_CHOICE!"=="" set "MERGE_CHOICE=c"

  if /i "!MERGE_CHOICE!"=="a" (
    git merge --abort
    if !errorlevel! neq 0 (
      echo [ERROR] Could not abort merge.
      exit /b 1
    )
    echo Merge aborted. Re-run update.bat when ready.
    exit /b 1
  )

  if /i "!MERGE_CHOICE!"=="q" (
    echo Quitting so you can resolve manually.
    exit /b 1
  )

  if /i not "!MERGE_CHOICE!"=="c" (
    echo Invalid option. Quitting.
    exit /b 1
  )

  call :maybe_finish_merge
)
exit /b 0

:maybe_finish_merge
for /f %%A in ('git diff --name-only --diff-filter=U ^| find /c /v ""') do set "UNMERGED_COUNT=%%A"
if not defined UNMERGED_COUNT set "UNMERGED_COUNT=0"

if "!UNMERGED_COUNT!"=="0" (
  echo [INFO] No unmerged files remain. You are likely in the commit-message editor step.
  echo        To finish the merge now, we can run:
  echo        git commit --no-edit
  set /p AUTO_COMMIT=Run that now? [Y/n]: 
  if /i "!AUTO_COMMIT!"=="" set "AUTO_COMMIT=Y"
  if /i "!AUTO_COMMIT!"=="Y" (
    git commit --no-edit
    if !errorlevel! neq 0 (
      echo [ERROR] Could not finish merge commit automatically.
      echo        Tip: run ^"git status^" and complete commit manually.
      exit /b 1
    )
    echo [OK] Merge commit created.
  ) else (
    echo [INFO] Leaving merge open for manual commit.
    exit /b 1
  )
) else (
  echo [NOTICE] !UNMERGED_COUNT! conflicted file(s) still need resolution.
  echo.
  call :show_merge_help
  echo.
  set /p OPEN_STATUS=Show full git status now? [Y/n]: 
  if /i "!OPEN_STATUS!"=="" set "OPEN_STATUS=Y"
  if /i "!OPEN_STATUS!"=="Y" git status
  echo.
  echo Resolve files, then run:
  echo   git add ^<file^>
  echo   git commit
  echo and then rerun update.bat.
  exit /b 1
)
exit /b 0

:handle_git_failure
set "FAILED_ACTION=%~1"
echo.
echo [ERROR] 'git %FAILED_ACTION%' failed.

if exist ".git\MERGE_HEAD" (
  echo [DIAGNOSIS] Merge in progress detected.
  call :maybe_finish_merge
  exit /b 1
)

for /f %%A in ('git diff --name-only --diff-filter=U ^| find /c /v ""') do set "UNMERGED_ON_FAIL=%%A"
if not defined UNMERGED_ON_FAIL set "UNMERGED_ON_FAIL=0"
if not "!UNMERGED_ON_FAIL!"=="0" (
  echo [DIAGNOSIS] You have !UNMERGED_ON_FAIL! unmerged/conflicted file(s).
  call :show_merge_help
  git status --short
  exit /b 1
)

echo [TIP] Run "git status" for detailed diagnostics.
exit /b 1

:show_merge_help
echo ---------------- Merge Conflict Helper ----------------
echo 1^) Find conflicted files:
echo    git status
echo 2^) Edit each conflicted file and remove markers:
echo    ^<^<^<^<^<^<^<, =======, ^>^>^>^>^>^>^
echo 3^) Mark resolved files:
echo    git add ^<file^>
echo 4^) Finish merge:
echo    git commit
echo 5^) If you want to cancel merge:
echo    git merge --abort
echo -------------------------------------------------------
exit /b 0
