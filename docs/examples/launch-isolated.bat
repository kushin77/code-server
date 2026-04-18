@echo off
REM ═══════════════════════════════════════════════════════════════════════════
REM launch-isolated.bat — #444: Per-workspace isolated VSCode session launcher
REM
REM Usage: Double-click or run from cmd/pwsh in the repo root.
REM
REM Isolation provided:
REM   --profile code-server-enterprise  → separate extension host, settings, keybindings
REM   --max-memory 2048                 → caps Node.js heap at 2GB (crash isolation)
REM   No cross-workspace Copilot bleed  → each profile has independent context
REM ═══════════════════════════════════════════════════════════════════════════

set REPO_NAME=code-server-enterprise
set REPO_PATH=%~dp0

echo [launch-isolated] Starting %REPO_NAME% with isolated profile...
code --profile %REPO_NAME% --max-memory 2048 %REPO_PATH%

if %ERRORLEVEL% neq 0 (
  echo [launch-isolated] ERROR: code.exe not found. Ensure VS Code is in PATH.
  pause
)
