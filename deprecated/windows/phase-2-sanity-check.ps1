# DEPRECATED: Windows PowerShell script retained for historical reference only.
# Use Linux-native automation paths under scripts/operations and scripts/health.
# See CONTRIBUTING.md#windows-policy and issue #398.
#
# Phase 2 Sanity Check (PowerShell)
# Validates Phase 2 session-broker integration

Write-Host "=== Phase 2 Sanity Check ===" -ForegroundColor Cyan
Write-Host "Validating session-broker integration..." -ForegroundColor Cyan
Write-Host ""

$checksPass = 0
$checksFail = 0

function Check-Command {
  param([string]$name, [scriptblock]$command)
  
  try {
    $result = & $command 2>$null
    if ($result) {
      Write-Host "✅ $name" -ForegroundColor Green
      $script:checksPass++
    } else {
      Write-Host "❌ $name" -ForegroundColor Red
      $script:checksFail++
    }
  } catch {
    Write-Host "❌ $name" -ForegroundColor Red
    $script:checksFail++
  }
}

function Check-File {
  param([string]$name, [string]$path)
  
  if (Test-Path $path) {
    Write-Host "✅ $name" -ForegroundColor Green
    $script:checksPass++
  } else {
    Write-Host "❌ $name (missing: $path)" -ForegroundColor Red
    $script:checksFail++
  }
}

function Check-Content {
  param([string]$name, [string]$path, [string]$pattern)
  
  if (Select-String -Path $path -Pattern $pattern -Quiet) {
    Write-Host "✅ $name" -ForegroundColor Green
    $script:checksPass++
  } else {
    Write-Host "❌ $name (pattern not found in $path)" -ForegroundColor Red
    $script:checksFail++
  }
}

Write-Host "1. Docker Compose Configuration" -ForegroundColor Yellow
Check-Command "docker-compose.yml is valid" { docker-compose config --quiet 2>$null }
Check-Content "session-broker service defined" "docker-compose.yml" "session-broker:"

Write-Host ""
Write-Host "2. Caddy Configuration" -ForegroundColor Yellow
Check-File "Caddyfile exists" "Caddyfile"
Check-Content "Caddy routes to session-broker" "Caddyfile" "reverse_proxy session-broker:5000"
Check-Content "Caddy logout handler implemented" "Caddyfile" "/oauth2/logout"

Write-Host ""
Write-Host "3. Session Broker Files" -ForegroundColor Yellow
Check-File "Session broker source code" "apps/session-broker/src/index.ts"
Check-File "Session broker Dockerfile" "apps/session-broker/Dockerfile"
Check-File "Session broker package.json" "apps/session-broker/package.json"
Check-File "Database migration script" "apps/session-broker/migrations/001_session_isolation_schema.sql"

Write-Host ""
Write-Host "4. Session Broker Implementation Details" -ForegroundColor Yellow
Check-Content "SessionManager class defined" "apps/session-broker/src/index.ts" "class SessionManager"
Check-Content "getAuthUser function implemented" "apps/session-broker/src/index.ts" "const getAuthUser"
Check-Content "POST /oauth2/callback endpoint" "apps/session-broker/src/index.ts" "app.post\('/oauth2/callback'"
Check-Content "POST /oauth2/logout endpoint" "apps/session-broker/src/index.ts" "app.post\('/oauth2/logout'"
Check-Content "Activity logging middleware" "apps/session-broker/src/index.ts" "Activity"

Write-Host ""
Write-Host "5. Database Schema" -ForegroundColor Yellow
Check-File "Session isolation schema" "apps/session-broker/migrations/001_session_isolation_schema.sql"
Check-Content "sessions table creation" "apps/session-broker/migrations/001_session_isolation_schema.sql" "CREATE TABLE"
Check-Content "session_id primary key" "apps/session-broker/migrations/001_session_isolation_schema.sql" "PRIMARY KEY"

Write-Host ""
Write-Host "6. Documentation" -ForegroundColor Yellow
Check-File "Phase 2 test plan exists" "docs/PHASE-2-INTEGRATION-TEST-PLAN.md"
Check-File "Per-session isolation docs" "docs/P1-752-PER-SESSION-ISOLATION.md"

Write-Host ""
Write-Host "7. Scripts" -ForegroundColor Yellow
Check-File "Session spawner script" "scripts/session-management/session-container-spawner.sh"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Results: $checksPass passed, $checksFail failed" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

if ($checksFail -eq 0) {
  Write-Host "✅ All Phase 2 sanity checks passed!" -ForegroundColor Green
  Write-Host ""
  Write-Host "Next steps:" -ForegroundColor Green
  Write-Host "  1. Deploy: docker-compose up -d session-broker" -ForegroundColor Green
  Write-Host "  2. Verify: bash scripts/test-phase-2-integration.sh" -ForegroundColor Green
  Write-Host "  3. Test: Manual E2E testing via Caddy/oauth2 flow" -ForegroundColor Green
  exit 0
} else {
  Write-Host "❌ Some checks failed. Review items above." -ForegroundColor Red
  exit 1
}
