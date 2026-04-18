#!/usr/bin/env bash
# @file        scripts/phase-2-sanity-check.sh
# @module      testing/phase-2-validation
# @description Quick sanity check for Phase 2 session-broker integration
#
# Validates that all Phase 2 components are properly configured:
# - docker-compose includes session-broker service
# - Caddy Caddyfile routes to session-broker
# - session-broker TypeScript code compiles
# - Database schema migrations are present
# - Environment variables are configured

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=== Phase 2 Sanity Check ==="
echo "Validating session-broker integration..."
echo ""

CHECKS_PASSED=0
CHECKS_FAILED=0

check() {
  local name="$1"
  local command="$2"
  
  if eval "$command" > /dev/null 2>&1; then
    echo -e "${GREEN}✅${NC} $name"
    ((CHECKS_PASSED++))
  else
    echo -e "${RED}❌${NC} $name"
    ((CHECKS_FAILED++))
  fi
}

check_file() {
  local name="$1"
  local file="$2"
  
  if [ -f "$file" ]; then
    echo -e "${GREEN}✅${NC} $name"
    ((CHECKS_PASSED++))
  else
    echo -e "${RED}❌${NC} $name (missing: $file)"
    ((CHECKS_FAILED++))
  fi
}

check_content() {
  local name="$1"
  local file="$2"
  local pattern="$3"
  
  if grep -q "$pattern" "$file" 2>/dev/null; then
    echo -e "${GREEN}✅${NC} $name"
    ((CHECKS_PASSED++))
  else
    echo -e "${RED}❌${NC} $name (pattern not found in $file)"
    ((CHECKS_FAILED++))
  fi
}

echo "1. Docker Compose Configuration"
check "docker-compose.yml is valid" "docker-compose -f '$PROJECT_ROOT/docker-compose.yml' config --quiet"
check_content "session-broker service defined" "$PROJECT_ROOT/docker-compose.yml" "session-broker:"

echo ""
echo "2. Caddy Configuration"
check_file "Caddyfile exists" "$PROJECT_ROOT/Caddyfile"
check_content "Caddy routes to session-broker" "$PROJECT_ROOT/Caddyfile" "reverse_proxy session-broker:5000"
check_content "Caddy logout handler implemented" "$PROJECT_ROOT/Caddyfile" "/oauth2/logout"

echo ""
echo "3. Session Broker Files"
check_file "Session broker source code exists" "$PROJECT_ROOT/apps/session-broker/src/index.ts"
check_file "Session broker Dockerfile exists" "$PROJECT_ROOT/apps/session-broker/Dockerfile"
check_file "Session broker package.json exists" "$PROJECT_ROOT/apps/session-broker/package.json"
check_file "Database migration script exists" "$PROJECT_ROOT/apps/session-broker/migrations/001_session_isolation_schema.sql"

echo ""
echo "4. Session Broker Implementation Details"
check_content "SessionManager class defined" "$PROJECT_ROOT/apps/session-broker/src/index.ts" "class SessionManager"
check_content "getAuthUser function implemented" "$PROJECT_ROOT/apps/session-broker/src/index.ts" "const getAuthUser"
check_content "POST /oauth2/callback endpoint" "$PROJECT_ROOT/apps/session-broker/src/index.ts" "app.post('/oauth2/callback'"
check_content "POST /oauth2/logout endpoint" "$PROJECT_ROOT/apps/session-broker/src/index.ts" "app.post('/oauth2/logout'"
check_content "Activity logging middleware" "$PROJECT_ROOT/apps/session-broker/src/index.ts" "Activity.*Server Error"

echo ""
echo "5. Database Schema"
check_file "Session isolation schema migration" "$PROJECT_ROOT/apps/session-broker/migrations/001_session_isolation_schema.sql"
check_content "sessions table creation" "$PROJECT_ROOT/apps/session-broker/migrations/001_session_isolation_schema.sql" "CREATE TABLE.*sessions"
check_content "session_id primary key" "$PROJECT_ROOT/apps/session-broker/migrations/001_session_isolation_schema.sql" "session_id.*PRIMARY KEY"

echo ""
echo "6. Documentation"
check_file "Phase 2 test plan exists" "$PROJECT_ROOT/docs/PHASE-2-INTEGRATION-TEST-PLAN.md"
check_file "Per-session isolation docs exist" "$PROJECT_ROOT/docs/P1-752-PER-SESSION-ISOLATION.md"

echo ""
echo "7. Script Availability"
check_file "Session spawner script" "$PROJECT_ROOT/scripts/session-management/session-container-spawner.sh"

echo ""
echo "========================================"
echo "Results: ${GREEN}$CHECKS_PASSED passed${NC}, ${RED}$CHECKS_FAILED failed${NC}"
echo "========================================"

if [ $CHECKS_FAILED -eq 0 ]; then
  echo -e "${GREEN}✅ All Phase 2 sanity checks passed!${NC}"
  echo ""
  echo "Next steps:"
  echo "  1. Deploy: docker-compose up -d session-broker"
  echo "  2. Verify: bash scripts/test-phase-2-integration.sh"
  echo "  3. Test: Manual E2E testing via Caddy/oauth2 flow"
  exit 0
else
  echo -e "${RED}❌ Some checks failed. Review items above.${NC}"
  exit 1
fi
