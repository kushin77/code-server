#!/usr/bin/env bash
# @file scripts/ci/pre-commit-ssot-enforcement.sh
# @description Pre-commit hook to enforce SSOT compliance
# @governance GOV-002 - Prevents hardcoded values from being committed
# @usage Install as .git/hooks/pre-commit with chmod +x

set -euo pipefail

# =============================================================================
# ERROR HANDLING & CLEANUP
# =============================================================================
trap 'log_error "Script failed at line $LINENO (exit code: $?)"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Counters
VIOLATIONS=0
WARNINGS=0

echo "🔍 Running SSOT pre-commit compliance checks..."

# ==============================================================================
# Check 1: Detect hardcoded IPs in non-test files
# ==============================================================================
echo -n "  Checking for hardcoded IPs... "
HARDCODED_IPS=$(git diff --cached --name-only | \
  grep -vE '\.(test|spec|md|lock)$' | \
  xargs git diff --cached --unified=0 | \
  grep '^+' | \
  grep -E '(192\.168\.|10\.|172\.)' | \
  grep -v test | \
  wc -l || true)

if [[ $HARDCODED_IPS -gt 0 ]]; then
  echo -e "${RED}FAIL${NC}"
  echo "    ❌ Found $HARDCODED_IPS hardcoded IP addresses"
  echo "    Use PRIMARY_HOST, REPLICA_HOST, NAS_HOST variables instead"
  VIOLATIONS=$((VIOLATIONS + 1))
else
  echo -e "${GREEN}PASS${NC}"
fi

# ==============================================================================
# Check 2: Detect hardcoded domains (kushnir.cloud, etc)
# ==============================================================================
echo -n "  Checking for hardcoded domains... "
HARDCODED_DOMAINS=$(git diff --cached --name-only | \
  grep -vE '\.(test|spec|md|lock)$' | \
  xargs git diff --cached --unified=0 2>/dev/null | \
  grep '^+' | \
  grep -E '(kushnir\.cloud|example\.com)' | \
  grep -v test | \
  grep -v '.md:' | \
  wc -l || true)

if [[ $HARDCODED_DOMAINS -gt 0 ]]; then
  echo -e "${RED}FAIL${NC}"
  echo "    ❌ Found $HARDCODED_DOMAINS hardcoded domain references"
  echo "    Use APEX_DOMAIN, IDE_DOMAIN, API_DOMAIN variables instead"
  VIOLATIONS=$((VIOLATIONS + 1))
else
  echo -e "${GREEN}PASS${NC}"
fi

# ==============================================================================
# Check 3: Detect hardcoded ports in configs (not in comments)
# ==============================================================================
echo -n "  Checking for hardcoded service ports... "
HARDCODED_PORTS=$(git diff --cached --name-only | \
  grep -E '\.(yml|yaml|conf)$' | \
  grep -v test | \
  xargs git diff --cached --unified=0 2>/dev/null | \
  grep '^+' | \
  grep -vE '(user|group|uid|gid|#|PORT\}|port\})' | \
  grep -E ':(3000|3100|4180|5000|6333|6379|8001|8020|8050|8080|8181|9090|9092)' | \
  wc -l || true)

if [[ $HARDCODED_PORTS -gt 0 ]]; then
  echo -e "${YELLOW}WARN${NC}"
  echo "    ⚠️  Found $HARDCODED_PORTS potential hardcoded ports"
  echo "    Consider using PORT variables: OAUTH2_PROXY_PORT, POSTGRES_PORT, etc"
  WARNINGS=$((WARNINGS + 1))
else
  echo -e "${GREEN}PASS${NC}"
fi

# ==============================================================================
# Check 4: Verify shell scripts source init.sh
# ==============================================================================
echo -n "  Checking script initialization... "
SCRIPTS_WITHOUT_INIT=$(git diff --cached --name-only | \
  grep -E '\.sh$' | \
  grep -E '(scripts|bin)' | \
  xargs -I {} bash -c "git show :{}; grep -q 'source.*init.sh' {} || echo {}" 2>/dev/null | \
  wc -l || true)

if [[ $SCRIPTS_WITHOUT_INIT -gt 0 ]]; then
  echo -e "${YELLOW}WARN${NC}"
  echo "    ⚠️  Found $SCRIPTS_WITHOUT_INIT scripts that might not source init.sh"
  echo "    Ensure deployment scripts source: source \"\${SCRIPT_DIR}/../_common/init.sh\""
  WARNINGS=$((WARNINGS + 1))
else
  echo -e "${GREEN}PASS${NC}"
fi

# ==============================================================================
# Check 5: Verify docker-compose.yml uses variables
# ==============================================================================
echo -n "  Checking docker-compose.yml compliance... "
if [[ -f docker-compose.yml ]]; then
  # Check if docker-compose.yml was modified
  if git diff --cached --name-only | grep -q 'docker-compose.yml'; then
    HARDCODED_DC_PORTS=$(git diff --cached docker-compose.yml | \
      grep '^+' | \
      grep -vE '(^+++|^+.*#|user|PORT\})' | \
      grep -E '"\s*[0-9]{4}:[0-9]{4}' | \
      grep -v localhost | \
      wc -l || true)
    
    if [[ $HARDCODED_DC_PORTS -gt 0 ]]; then
      echo -e "${RED}FAIL${NC}"
      echo "    ❌ Found $HARDCODED_DC_PORTS hardcoded ports in docker-compose.yml"
      echo "    Use variables: \${OAUTH2_PROXY_PORT}, \${POSTGRES_PORT}, etc"
      VIOLATIONS=$((VIOLATIONS + 1))
    else
      echo -e "${GREEN}PASS${NC}"
    fi
  else
    echo -e "${GREEN}PASS${NC} (not modified)"
  fi
else
  echo -e "${GREEN}PASS${NC} (not found - OK)"
fi

# ==============================================================================
# Check 6: Verify _base-config.env consistency
# ==============================================================================
echo -n "  Checking _base-config.env consistency... "
if git diff --cached --name-only | grep -q '_base-config.env'; then
  # Verify exports have values
  EXPORTS_WITHOUT_VALUES=$(git show :"scripts/_common/_base-config.env" 2>/dev/null | \
    grep '^export ' | \
    grep -v '=' | \
    wc -l || true)
  
  if [[ $EXPORTS_WITHOUT_VALUES -gt 0 ]]; then
    echo -e "${RED}FAIL${NC}"
    echo "    ❌ Found $EXPORTS_WITHOUT_VALUES export statements without values"
    echo "    All exports must have default values: export VAR=\${VAR:-default}"
    VIOLATIONS=$((VIOLATIONS + 1))
  else
    echo -e "${GREEN}PASS${NC}"
  fi
else
  echo -e "${GREEN}PASS${NC} (not modified)"
fi

# ==============================================================================
# Summary and Exit
# ==============================================================================
echo ""
echo "📊 SSOT Compliance Report:"
echo "   Violations: $VIOLATIONS"
echo "   Warnings:   $WARNINGS"

if [[ $VIOLATIONS -gt 0 ]]; then
  echo ""
  echo -e "${RED}❌ COMMIT BLOCKED - SSOT Violations Detected${NC}"
  echo ""
  echo "Fix issues and run:"
  echo "  git add <files>"
  echo "  git commit -m 'message'"
  exit 1
elif [[ $WARNINGS -gt 0 ]]; then
  echo ""
  echo -e "${YELLOW}⚠️  COMMIT ALLOWED - Warnings present (review recommended)${NC}"
  exit 0
else
  echo ""
  echo -e "${GREEN}✅ COMMIT APPROVED - SSOT Compliant${NC}"
  exit 0
fi
