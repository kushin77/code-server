@echo off
REM Launch VSCode with isolated profile + memory cap
REM Purpose: Prevent extension host OOM from crashing other windows
REM Usage: launch-vscode-budgeted.bat [workspace-path]

setlocal enabledelayedexpansion

set REPO_NAME=code-server-enterprise
set MEMORY_CAP=1024
set WORKSPACE_PATH=%~dp0..

if "%1" neq "" (
    set WORKSPACE_PATH=%1
)

echo [launch] Starting VSCode with profile isolation + memory cap
echo [launch] Profile: %REPO_NAME%
echo [launch] Memory cap: %MEMORY_CAP%MB
echo [launch] Workspace: %WORKSPACE_PATH%
echo.

REM Set Node.js memory limit for extension host
set NODE_OPTIONS=--max-old-space-size=%MEMORY_CAP%
echo [launch] NODE_OPTIONS: %NODE_OPTIONS%
echo.

REM Launch with profile isolation (separate extension host per profile)
code --profile %REPO_NAME% "%WORKSPACE_PATH%"

REM Restore environment
set NODE_OPTIONS=
endlocal
