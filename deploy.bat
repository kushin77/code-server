@ECHO OFF
REM ════════════════════════════════════════════════════════════════════════════
REM code-server-enterprise Universal Deployment Entrypoint (Windows)
REM File: deploy.bat
REM Purpose: Windows wrapper for unified deployment script
REM Usage: deploy.bat [target] [action] [options]
REM Issue: P2 #421
REM ════════════════════════════════════════════════════════════════════════════

SETLOCAL ENABLEDELAYEDEXPANSION

REM Colors (using esc codes)
FOR /F %%A IN ('echo prompt $H ^| cmd') DO SET "BS=%%A"
SET "RED=!BS![91m"
SET "GREEN=!BS![92m"
SET "YELLOW=!BS![93m"
SET "BLUE=!BS![94m"
SET "NC=!BS![0m"

REM Configuration
SET "SCRIPT_DIR=%~dp0"
SET "PROJECT_ROOT=%SCRIPT_DIR:~0,-1%"
SET "REMOTE_HOST=192.168.168.31"
SET "SSH_USER=akushnir"

ECHO.
ECHO !BLUE!════════════════════════════════════════════════════════════════════════════!NC!
ECHO   code-server-enterprise Universal Deployment (Windows)
ECHO !BLUE!════════════════════════════════════════════════════════════════════════════!NC!
ECHO.

REM Parse arguments
IF "%1"=="" (
  CALL :show_usage
  EXIT /B 1
)

IF /I "%1"=="help" GOTO :show_usage
IF /I "%1"=="-h" GOTO :show_usage
IF /I "%1"=="--help" GOTO :show_usage

SET "TARGET=%1"
SET "ACTION=%2"
IF "%ACTION%"=="" SET "ACTION=status"

REM Execute based on target
IF /I "%TARGET%"=="local" (
  CALL :deploy_local %ACTION% %3 %4 %5
  GOTO :end
)

IF /I "%TARGET%"=="remote" (
  CALL :deploy_remote %ACTION% %3 %4 %5
  GOTO :end
)

IF /I "%TARGET%"=="all" (
  ECHO !YELLOW!This requires a Unix shell environment. Use WSL or deploy to remote host directly.!NC!
  GOTO :end
)

ECHO !RED!✗ Unknown target: %TARGET%!NC!
CALL :show_usage
EXIT /B 1

:deploy_local
  ECHO !BLUE!▸ Local deployment - %1!NC!
  
  IF /I "%1"=="validate" (
    ECHO !BLUE!  ▸ Validating Docker Compose...!NC!
    docker-compose -f "%PROJECT_ROOT%\docker-compose.yml" config --quiet
    IF ERRORLEVEL 1 (
      ECHO !RED!✗ Docker Compose validation failed!NC!
      EXIT /B 1
    )
    ECHO !GREEN!✓ Docker Compose configuration valid!NC!
    EXIT /B 0
  )
  
  IF /I "%1"=="status" (
    ECHO !BLUE!  ▸ Docker Container Status:!NC!
    docker-compose -f "%PROJECT_ROOT%\docker-compose.yml" ps --format "table {{.Service}}\t{{.Status}}"
    EXIT /B 0
  )
  
  IF /I "%1"=="logs" (
    ECHO !BLUE!  ▸ Streaming logs...!NC!
    docker-compose -f "%PROJECT_ROOT%\docker-compose.yml" logs -f
    EXIT /B 0
  )
  
  ECHO !YELLOW!⚠ For Terraform operations, use WSL or SSH to remote host!NC!
  EXIT /B 0

:deploy_remote
  ECHO !BLUE!▸ Remote deployment to %REMOTE_HOST%!NC!
  
  IF "%SSH_KEY%"=="" (
    SET "SSH_OPTS="
  ) ELSE (
    SET "SSH_OPTS=-i %SSH_KEY%"
  )
  
  IF /I "%1"=="status" (
    ECHO !BLUE!  ▸ Checking remote infrastructure status...!NC!
    ssh %SSH_OPTS% %SSH_USER%@%REMOTE_HOST% "cd code-server-enterprise && docker-compose ps --format 'table {{.Service}}\t{{.Status}}' | head -15"
    EXIT /B 0
  )
  
  IF /I "%1"=="logs" (
    ECHO !BLUE!  ▸ Streaming remote logs...!NC!
    ssh %SSH_OPTS% -t %SSH_USER%@%REMOTE_HOST% "cd code-server-enterprise && docker-compose logs -f"
    EXIT /B 0
  )
  
  IF /I "%1"=="shell" (
    ECHO !BLUE!  ▸ Connecting to remote shell...!NC!
    ssh %SSH_OPTS% -t %SSH_USER%@%REMOTE_HOST%
    EXIT /B 0
  )
  
  IF /I "%1"=="apply" (
    ECHO !BLUE!  ▸ Deploying infrastructure (Terraform apply)...!NC!
    ssh %SSH_OPTS% %SSH_USER%@%REMOTE_HOST% "cd code-server-enterprise && terraform -chdir=terraform apply -auto-approve"
    EXIT /B 0
  )
  
  IF /I "%1"=="plan" (
    ECHO !BLUE!  ▸ Planning infrastructure changes...!NC!
    ssh %SSH_OPTS% %SSH_USER%@%REMOTE_HOST% "cd code-server-enterprise && terraform -chdir=terraform plan"
    EXIT /B 0
  )
  
  ECHO !RED!✗ Unknown action for remote: %1!NC!
  EXIT /B 1

:show_usage
  ECHO Usage: deploy.bat [target] [action]
  ECHO.
  ECHO TARGETS:
  ECHO   local      Deploy locally (validation, status, logs)
  ECHO   remote     Deploy to remote host (!REMOTE_HOST!)
  ECHO.
  ECHO ACTIONS:
  ECHO   validate   Validate configuration
  ECHO   plan       Show deployment plan (remote only)
  ECHO   apply      Execute deployment (remote only)
  ECHO   status     Show infrastructure status
  ECHO   logs       Stream service logs
  ECHO   shell      SSH shell to remote (remote only)
  ECHO.
  ECHO EXAMPLES:
  ECHO   deploy.bat local validate
  ECHO   deploy.bat remote status
  ECHO   deploy.bat remote logs
  ECHO   deploy.bat remote shell
  ECHO.
  EXIT /B 0

:end
  ECHO.
  ECHO !GREEN!✓ Deployment command complete!NC!
  ENDLOCAL
  EXIT /B 0
