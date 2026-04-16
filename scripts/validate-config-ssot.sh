#!/bin/bash
# ==============================================================================
# validate-config-ssot.sh - Phase 1 Configuration Consolidation Validation
# Validates master SSOT configurations are in place and no duplicates remain
# Exit Code: 0 = all validation passed | 1 = validation failures found
# ==============================================================================

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Counters
PASSED=0
FAILED=0
WARNINGS=0

# Helper functions
pass() {
  echo -e "${GREEN}✓ PASS${NC}: $1"
  ((PASSED++))
}

fail() {
  echo -e "${RED}✗ FAIL${NC}: $1"
  ((FAILED++))
}

warn() {
  echo -e "${YELLOW}⚠ WARN${NC}: $1"
  ((WARNINGS++))
}

info() {
  echo -e "${CYAN}ℹ INFO${NC}: $1"
}

# ==============================================================================
# VALIDATION CHECKS
# ==============================================================================

echo -e "\n${CYAN}=== Phase 1 Configuration Consolidation Validation ===${NC}\n"

# 1. Master Caddyfile SSOT
echo -e "${CYAN}[1] Validating Master Caddyfile SSOT${NC}"
if [ -f "Caddyfile" ]; then
  if grep -q "security_headers_strict\|cache_control\|internal_only" Caddyfile; then
    pass "Master Caddyfile exists with consolidation markers"
  else
    warn "Master Caddyfile exists but missing consolidation features"
  fi
else
  fail "Master Caddyfile not found"
fi

# Check no competing Caddyfile in root
if [ -f "Caddyfile.production" ] || [ -f "Caddyfile.dev" ] || [ -f "Caddyfile.base" ]; then
  fail "Orphaned Caddyfile variants still in root directory"
else
  pass "No orphaned Caddyfile variants in root"
fi

# 2. Prometheus Template
echo -e "\n${CYAN}[2] Validating Prometheus Template${NC}"
if [ -f "prometheus.tpl" ]; then
  if grep -q "global:\|route:\|receivers:" prometheus.tpl; then
    pass "prometheus.tpl template exists with required sections"
  else
    fail "prometheus.tpl missing required YAML sections"
  fi
else
  warn "prometheus.tpl template not found (expected for Terraform-based deployment)"
fi

# Check deprecated prometheus configs moved to archive
DEPRECATED_PROMETHEUS=0
for file in prometheus.yml prometheus.default.yml prometheus-production.yml; do
  if [ -f "$file" ]; then
    fail "Deprecated $file still in root (should be archived)"
    ((DEPRECATED_PROMETHEUS++))
  fi
done

if [ $DEPRECATED_PROMETHEUS -eq 0 ]; then
  pass "All deprecated prometheus configs archived"
fi

# 3. AlertManager Template
echo -e "\n${CYAN}[3] Validating AlertManager Template${NC}"
if [ -f "alertmanager.tpl" ]; then
  if grep -q "global:\|route:\|receivers:" alertmanager.tpl; then
    if grep -q "critical-team\|high-team\|medium-team\|low-team" alertmanager.tpl; then
      pass "alertmanager.tpl template exists with priority-based receivers"
    else
      warn "alertmanager.tpl exists but missing priority-based routing"
    fi
  else
    fail "alertmanager.tpl missing required YAML sections"
  fi
else
  warn "alertmanager.tpl not found (expected for Terraform-based deployment)"
fi

# 4. Alert Rules Consolidation
echo -e "\n${CYAN}[4] Validating Alert Rules Consolidation${NC}"
if [ -f "alert-rules.yml" ]; then
  # Check for all required alert groups
  GROUPS_FOUND=0
  for group in "core_sla_alerts" "production_slos" "gpu_alerts" "nas_alerts" "application_alerts" "system_alerts"; do
    if grep -q "name: $group" alert-rules.yml; then
      ((GROUPS_FOUND++))
    else
      fail "Alert group '$group' not found in master alert-rules.yml"
    fi
  done
  
  if [ $GROUPS_FOUND -eq 6 ]; then
    pass "Master alert-rules.yml contains all 6 alert groups"
  fi
else
  fail "Master alert-rules.yml not found"
fi

# Check no duplicate alert-rules in config/
if [ -f "config/alert-rules.yml" ]; then
  fail "Duplicate config/alert-rules.yml should be deleted"
elif [ -f "config/alert-rules-31.yaml" ]; then
  fail "Duplicate config/alert-rules-31.yaml should be merged and deleted"
else
  pass "No duplicate alert-rules files in config/"
fi

# 5. Docker Compose References
echo -e "\n${CYAN}[5] Validating Docker Compose References${NC}"
if grep -q "./alert-rules.yml:/etc/prometheus/alert-rules.yml" docker-compose.yml; then
  pass "docker-compose.yml references master alert-rules.yml"
else
  warn "docker-compose.yml may not reference master alert-rules.yml correctly"
fi

if grep -q "./Caddyfile:" docker-compose.yml; then
  pass "docker-compose.yml references master Caddyfile"
else
  warn "docker-compose.yml may not reference master Caddyfile correctly"
fi

# 6. Archive Validation
echo -e "\n${CYAN}[6] Validating Archive Structure${NC}"
if [ -d ".archived/caddy-variants-historical" ]; then
  CADDY_COUNT=$(find .archived/caddy-variants-historical -name "Caddyfile*" 2>/dev/null | wc -l)
  if [ $CADDY_COUNT -ge 5 ]; then
    pass "Archived $CADDY_COUNT Caddyfile variants"
  else
    warn "Archived only $CADDY_COUNT Caddyfile variants (expected 6+)"
  fi
else
  warn ".archived/caddy-variants-historical directory not found"
fi

if [ -d ".archived/prometheus-variants-historical" ]; then
  PROM_COUNT=$(find .archived/prometheus-variants-historical -name "prometheus*" 2>/dev/null | wc -l)
  if [ $PROM_COUNT -ge 3 ]; then
    pass "Archived $PROM_COUNT prometheus config variants"
  else
    warn "Archived only $PROM_COUNT prometheus variants (expected 3+)"
  fi
else
  warn ".archived/prometheus-variants-historical directory not found"
fi

# 7. YAML Syntax Validation
echo -e "\n${CYAN}[7] Validating YAML Syntax${NC}"
YAML_VALID=true

if command -v yamllint &> /dev/null; then
  if yamllint -d relaxed Caddyfile 2>/dev/null || [ $? -eq 0 ]; then
    pass "Caddyfile YAML syntax valid"
  else
    fail "Caddyfile has YAML syntax errors"
    YAML_VALID=false
  fi
  
  if yamllint -d relaxed alert-rules.yml 2>/dev/null; then
    pass "alert-rules.yml YAML syntax valid"
  else
    fail "alert-rules.yml has YAML syntax errors"
    YAML_VALID=false
  fi
else
  info "yamllint not installed - skipping syntax validation"
fi

# 8. Configuration Size/Sanity Checks
echo -e "\n${CYAN}[8] Configuration Size & Sanity Checks${NC}"
CADDYFILE_SIZE=$(wc -l < Caddyfile)
if [ "$CADDYFILE_SIZE" -gt 50 ]; then
  pass "Caddyfile consolidated ($(($CADDYFILE_SIZE)) lines)"
else
  warn "Caddyfile may be incomplete ($(($CADDYFILE_SIZE)) lines)"
fi

ALERT_RULES_SIZE=$(wc -l < alert-rules.yml)
if [ "$ALERT_RULES_SIZE" -gt 200 ]; then
  pass "alert-rules.yml consolidated ($(($ALERT_RULES_SIZE)) lines)"
else
  warn "alert-rules.yml may be incomplete ($(($ALERT_RULES_SIZE)) lines)"
fi

# ==============================================================================
# SUMMARY
# ==============================================================================

echo ""
echo -e "${CYAN}=== VALIDATION SUMMARY ===${NC}"
echo -e "  ${GREEN}✓ Passed: $PASSED${NC}"
echo -e "  ${RED}✗ Failed: $FAILED${NC}"
echo -e "  ${YELLOW}⚠ Warnings: $WARNINGS${NC}"
echo ""

if [ $FAILED -eq 0 ]; then
  echo -e "${GREEN}Phase 1 Consolidation: ✓ COMPLETE${NC}"
  echo "All configuration consolidation checks passed. Ready for Phase 2-3."
  exit 0
else
  echo -e "${RED}Phase 1 Consolidation: ✗ INCOMPLETE${NC}"
  echo "Please address the above failures before proceeding."
  exit 1
fi
