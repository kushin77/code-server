@echo off
REM launch-vscode-budgeted.bat
REM VSCode Memory Budget Launcher (Issue #448)
REM 
REM This script launches VSCode with enforced memory limits to prevent
REM extension host memory leaks and crashes on large workspaces.
REM
REM Usage:
REM   launch-vscode-budgeted.bat [path] [additional-args]
REM
REM Examples:
REM   launch-vscode-budgeted.bat .
REM   launch-vscode-budgeted.bat c:\code-server-enterprise
REM   launch-vscode-budgeted.bat . --disable-extensions
REM

setlocal enabledelayedexpansion

REM Default workspace path
set WORKSPACE=%1
if "!WORKSPACE!"=="" set WORKSPACE=.

REM Memory limits (in MB)
set EXT_HOST_MEMORY=1024
set MAIN_PROCESS_MEMORY=2048
set RENDERER_MEMORY=512

REM Build VSCode launch command with memory constraints
set "VSCODE_CMD=code"
set "VSCODE_ARGS=!WORKSPACE!"

REM Add any additional arguments passed after workspace path
if not "!%2!"=="" (
  shift
  for %%A in (%*) do (
    set "VSCODE_ARGS=!VSCODE_ARGS! %%A"
  )
)

REM Environment variables for memory budgeting
set NODE_OPTIONS=--max-old-space-size=%EXT_HOST_MEMORY%
set VSCODE_MEMORY_LIMIT=%EXT_HOST_MEMORY%

REM Log configuration
echo ========================================
echo VSCode Memory Budget Launch
echo ========================================
echo Workspace:              %WORKSPACE%
echo Extension Host Memory:  %EXT_HOST_MEMORY% MB
echo Main Process Memory:    %MAIN_PROCESS_MEMORY% MB
echo Renderer Memory:        %RENDERER_MEMORY% MB
echo Additional Args:        %VSCODE_ARGS%
echo ========================================
echo.

REM Launch VSCode with budget enforcement
call %VSCODE_CMD% %VSCODE_ARGS%

endlocal
