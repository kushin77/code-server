@echo off
REM Close Duplicate GitHub Issues Script (Windows)
REM Purpose: Close 7 duplicate issues marked as duplicates of canonical issues
REM Requires: GitHub CLI (gh) with admin rights to kushin77/code-server
REM Status: Production-ready
REM Date: April 16, 2026

setlocal enabledelayedexpansion

set REPO=kushin77/code-server
set CLOSED=0
set FAILED=0

echo.
echo ==========================================
echo GitHub Issue Closure Script (Windows)
echo ==========================================
echo.
echo Repository: %REPO%
echo Requires: GitHub CLI (gh) with admin rights
echo.

REM Check for GitHub CLI
where gh >nul 2>nul
if %errorlevel% neq 0 (
    echo ERROR: GitHub CLI (gh) is not installed
    echo Install from: https://cli.github.com
    exit /b 1
)

REM Check authentication
echo Checking GitHub authentication...
gh auth status >nul 2>nul
if %errorlevel% neq 0 (
    echo ERROR: Not authenticated with GitHub
    echo Run: gh auth login
    exit /b 1
)

echo OK - GitHub CLI authenticated
echo.

REM Array of duplicates (issue -> canonical)
setlocal enabledelayedexpansion

for %%I in (386^,389^,391^,392^,395^,396^,397) do (
    set issue=%%I
    if "!issue!"=="386" set canonical=385
    if "!issue!"=="389" set canonical=385
    if "!issue!"=="391" set canonical=385
    if "!issue!"=="392" set canonical=385
    if "!issue!"=="395" set canonical=377
    if "!issue!"=="396" set canonical=377
    if "!issue!"=="397" set canonical=377
    
    echo Closing #!issue! as duplicate of #!canonical!...
    
    gh issue close !issue! --repo %REPO% --reason "duplicate" >nul 2>&1
    if !errorlevel! equ 0 (
        REM Add comment to closed issue
        gh issue comment !issue! --repo %REPO% --body "Closed as duplicate of #!canonical!. See that issue for the consolidated implementation." >nul 2>&1
        echo OK - Closed #!issue!
        set /a CLOSED+=1
    ) else (
        echo ERROR - Failed to close #!issue! (may require admin rights)
        set /a FAILED+=1
    )
)

echo.
echo ==========================================
echo Summary
echo ==========================================
echo Closed: %CLOSED%
echo Failed: %FAILED%
echo.

if %FAILED% equ 0 (
    echo OK - All issues closed successfully!
    exit /b 0
) else (
    echo WARNING - Some issues could not be closed
    echo Ensure you have admin rights to the repository
    exit /b 1
)
