#!/usr/bin/env bash
###############################################################################
# @file        scripts/ci/comprehensive-ssot-audit.sh
# @module      ci/comprehensive-ssot-audit
# @description P3 #1533: Comprehensive audit of SSOT, template, and error handling
# @governance  GOV-002: All infrastructure configuration must follow SSOT pattern
# @automation  Generate detailed gap analysis report
###############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Set defaults for audit environment (not all vars needed for static analysis)
export PRIMARY_HOST="${PRIMARY_HOST:-audit-host}"
export REPLICA_HOST="${REPLICA_HOST:-audit-host}"
export NAS_HOST="${NAS_HOST:-audit-host}"
export APEX_DOMAIN="${APEX_DOMAIN:-audit.local}"
export ADMIN_EMAIL="${ADMIN_EMAIL:-audit@local}"

# Source common logging
source "${REPO_ROOT}/scripts/_common/init.sh"

REPORT_FILE="${REPO_ROOT}/artifacts/ssot-gap-analysis-$(date +%Y%m%d-%H%M%S).md"
mkdir -p "$(dirname "${REPORT_FILE}")"

# Counters
SCRIPTS_CHECKED=0
SCRIPTS_WITH_INIT=0
SCRIPTS_MISSING_INIT=0
HARDCODED_VARS=0
TEMPLATE_GAPS=0
ERROR_HANDLING_GAPS=0

# Initialize report
cat > "$REPORT_FILE" <<'EOF'
# SSOT & Configuration Audit Report
Generated: $(date -u +'%Y-%m-%dT%H:%M:%SZ')

## Executive Summary
This report audits the codebase for compliance with SSOT (Single Source of Truth) patterns,
template usage enforcement, and error handling best practices.

---

EOF

log_info "Starting comprehensive SSOT audit..."
log_info "Report: $REPORT_FILE"

# ============================================================================
# SECTION 1: Environment Variable Sourcing Audit
# ============================================================================

audit_init_sourcing() {
  echo "## 1. Environment Variable Sourcing Audit" >> "$REPORT_FILE"
  echo "" >> "$REPORT_FILE"
  echo "### Requirement: All scripts must source scripts/_common/init.sh" >> "$REPORT_FILE"
  echo "" >> "$REPORT_FILE"

  local missing_scripts=()
  
  while IFS= read -r script; do
    ((SCRIPTS_CHECKED++))
    
    if grep -q "source.*init\.sh\|source.*_common/init\.sh\|source.*_base-config" "$script"; then
      ((SCRIPTS_WITH_INIT++))
    else
      # Skip test/example scripts
      if [[ "$script" =~ (test|example|template|backup|.backups) ]]; then
        continue
      fi
      
      ((SCRIPTS_MISSING_INIT++))
      missing_scripts+=("$script")
    fi
  done < <(find "${REPO_ROOT}/scripts" -name "*.sh" -type f)

  if [ ${#missing_scripts[@]} -gt 0 ]; then
    echo "❌ **FAILED**: ${#missing_scripts[@]} scripts don't source init.sh" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    echo "\`\`\`" >> "$REPORT_FILE"
    for script in "${missing_scripts[@]}"; do
      echo "  $(basename "$script")" >> "$REPORT_FILE"
    done
    echo "\`\`\`" >> "$REPORT_FILE"
  else
    echo "✅ **PASSED**: All scripts source init.sh" >> "$REPORT_FILE"
  fi
  
  echo "" >> "$REPORT_FILE"
  echo "**Stats:**" >> "$REPORT_FILE"
  echo "- Total scripts checked: $SCRIPTS_CHECKED" >> "$REPORT_FILE"
  echo "- Scripts with init.sh: $SCRIPTS_WITH_INIT" >> "$REPORT_FILE"
  echo "- Scripts missing init.sh: $SCRIPTS_MISSING_INIT" >> "$REPORT_FILE"
  echo "" >> "$REPORT_FILE"
}

# ============================================================================
# SECTION 2: Hardcoded Variable Audit
# ============================================================================

audit_hardcoded_vars() {
  echo "## 2. Hardcoded Values Audit" >> "$REPORT_FILE"
  echo "" >> "$REPORT_FILE"
  echo "### Requirement: No hardcoded IPs, domains, or secrets in code" >> "$REPORT_FILE"
  echo "" >> "$REPORT_FILE"

  local offending_files=()
  local patterns=(
    "192\.168\.[0-9]\+\.[0-9]\+"          # IP addresses
    "localhost:[0-9]\+"                    # localhost with port
    "example\.com"                         # example.com
    "kushnir\.cloud"                       # hardcoded domain (should use APEX_DOMAIN)
    "password"                             # password patterns
    "secret"                               # secret patterns (case-insensitive)
  )

  for pattern in "${patterns[@]}"; do
    while IFS= read -r file; do
      if [[ ! "$file" =~ (\.md$|\.txt$|\.backup$|\.backups) ]]; then
        offending_files+=("$file:$pattern")
        ((HARDCODED_VARS++))
      fi
    done < <(grep -r "$pattern" "${REPO_ROOT}/scripts" --include="*.sh" 2>/dev/null | cut -d: -f1 | sort -u)
  done

  if [ $HARDCODED_VARS -gt 0 ]; then
    echo "❌ **WARNING**: Found $HARDCODED_VARS hardcoded values" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    echo "Recommendation: Extract these to _base-config.env and use \${VARIABLE} syntax" >> "$REPORT_FILE"
  else
    echo "✅ **PASSED**: No hardcoded values detected" >> "$REPORT_FILE"
  fi
  echo "" >> "$REPORT_FILE"
}

# ============================================================================
# SECTION 3: Template Usage Audit
# ============================================================================

audit_template_usage() {
  echo "## 3. Template & Variable Substitution Audit" >> "$REPORT_FILE"
  echo "" >> "$REPORT_FILE"
  echo "### Requirement: Configuration files use \${VARIABLE} syntax" >> "$REPORT_FILE"
  echo "" >> "$REPORT_FILE"

  # Check Caddyfile
  if [ -f "${REPO_ROOT}/Caddyfile" ]; then
    local caddy_vars=$(grep -o '\${[^}]*}' "${REPO_ROOT}/Caddyfile" | sort -u)
    echo "**Caddyfile:** Uses $(echo "$caddy_vars" | wc -l) template variables" >> "$REPORT_FILE"
    if grep -q '\${APEX_DOMAIN}\|\${IDE_DOMAIN}\|\${AUTH_DOMAIN}' "${REPO_ROOT}/Caddyfile"; then
      echo "✅ Domain variables templated" >> "$REPORT_FILE"
    else
      echo "⚠️  Missing domain variable templating" >> "$REPORT_FILE"
      ((TEMPLATE_GAPS++))
    fi
  fi
  echo "" >> "$REPORT_FILE"

  # Check docker-compose.yml
  if [ -f "${REPO_ROOT}/docker-compose.yml" ]; then
    local compose_vars=$(grep -o '\${[^}]*}' "${REPO_ROOT}/docker-compose.yml" | sort -u | wc -l)
    echo "**docker-compose.yml:** Uses $compose_vars template variables" >> "$REPORT_FILE"
    if grep -q '\${REGISTRY_URL}\|\${.*_VERSION}' "${REPO_ROOT}/docker-compose.yml"; then
      echo "✅ Registry and version variables templated" >> "$REPORT_FILE"
    else
      echo "⚠️  Missing registry/version variable templating" >> "$REPORT_FILE"
      ((TEMPLATE_GAPS++))
    fi
  fi
  echo "" >> "$REPORT_FILE"
}

# ============================================================================
# SECTION 4: Error Handling Audit
# ============================================================================

audit_error_handling() {
  echo "## 4. Error Handling Patterns Audit" >> "$REPORT_FILE"
  echo "" >> "$REPORT_FILE"
  echo "### Requirement: Scripts use consistent error handling patterns" >> "$REPORT_FILE"
  echo "" >> "$REPORT_FILE"

  local scripts_with_trap=0
  local scripts_with_exit_check=0

  while IFS= read -r script; do
    if [[ "$script" =~ (\.backups|test|example) ]]; then
      continue
    fi

    # Check for error trap
    if grep -q "trap.*ERR\|trap.*EXIT" "$script"; then
      ((scripts_with_trap++))
    fi

    # Check for explicit exit codes
    if grep -q "exit 1\|return 1\||| exit\||| return" "$script"; then
      ((scripts_with_exit_check++))
    fi

    # Check for log_error usage
    if grep -q "log_error" "$script"; then
      ((ERROR_HANDLING_GAPS--))
    fi
  done < <(find "${REPO_ROOT}/scripts" -name "*.sh" -type f)

  echo "**Error Handling Stats:**" >> "$REPORT_FILE"
  echo "- Scripts with error traps: $scripts_with_trap" >> "$REPORT_FILE"
  echo "- Scripts with explicit exit codes: $scripts_with_exit_check" >> "$REPORT_FILE"
  echo "" >> "$REPORT_FILE"

  if [ $scripts_with_trap -lt 10 ]; then
    echo "⚠️  Recommendation: Use \`trap\` for cleanup and error handling" >> "$REPORT_FILE"
    ((ERROR_HANDLING_GAPS++))
  fi
  echo "" >> "$REPORT_FILE"
}

# ============================================================================
# SECTION 5: Documentation Audit
# ============================================================================

audit_documentation() {
  echo "## 5. Documentation Audit" >> "$REPORT_FILE"
  echo "" >> "$REPORT_FILE"
  echo "### Requirement: Documentation refers to canonical configuration sources" >> "$REPORT_FILE"
  echo "" >> "$REPORT_FILE"

  # Check for duplicate environment variable documentation
  local env_docs=()
  while IFS= read -r file; do
    if grep -q "export PRIMARY_HOST\|export REPLICA_HOST" "$file"; then
      env_docs+=("$(basename "$file")")
    fi
  done < <(find "${REPO_ROOT}" -maxdepth 1 -name "*.md" -type f)

  if [ ${#env_docs[@]} -gt 1 ]; then
    echo "❌ **WARNING**: Environment variables documented in multiple files:" >> "$REPORT_FILE"
    for doc in "${env_docs[@]}"; do
      echo "  - $doc" >> "$REPORT_FILE"
    done
    echo "" >> "$REPORT_FILE"
    echo "Recommendation: Reference scripts/_common/_base-config.env instead of duplicating" >> "$REPORT_FILE"
  else
    echo "✅ **INFO**: Environment documentation centralized" >> "$REPORT_FILE"
  fi
  echo "" >> "$REPORT_FILE"
}

# ============================================================================
# SECTION 6: Recommendations & Action Items
# ============================================================================

generate_recommendations() {
  echo "## 6. Recommendations & Action Items" >> "$REPORT_FILE"
  echo "" >> "$REPORT_FILE"

  local action_count=0

  if [ $SCRIPTS_MISSING_INIT -gt 0 ]; then
    ((action_count++))
    echo "### Action ${action_count}: Update ${SCRIPTS_MISSING_INIT} scripts to source init.sh" >> "$REPORT_FILE"
    echo "See scripts/_common/SSOT-PATTERN.md for migration guide" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
  fi

  if [ $HARDCODED_VARS -gt 0 ]; then
    ((action_count++))
    echo "### Action ${action_count}: Extract hardcoded values to _base-config.env" >> "$REPORT_FILE"
    echo "Hardcoded values reduce portability and increase deployment errors" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
  fi

  if [ $TEMPLATE_GAPS -gt 0 ]; then
    ((action_count++))
    echo "### Action ${action_count}: Enforce template variables in all config files" >> "$REPORT_FILE"
    echo "Replace hardcoded values with \${VARIABLE} references" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
  fi

  if [ $ERROR_HANDLING_GAPS -gt 0 ]; then
    ((action_count++))
    echo "### Action ${action_count}: Standardize error handling with trap and log_error" >> "$REPORT_FILE"
    echo "Use consistent patterns across all scripts" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
  fi

  if [ $action_count -eq 0 ]; then
    echo "✅ **No high-priority action items** - Configuration follows SSOT patterns" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
  fi
}

# ============================================================================
# Main Audit Execution
# ============================================================================

run_audit() {
  audit_init_sourcing
  audit_hardcoded_vars
  audit_template_usage
  audit_error_handling
  audit_documentation
  generate_recommendations

  # Summary
  echo "" >> "$REPORT_FILE"
  echo "---" >> "$REPORT_FILE"
  echo "## Summary" >> "$REPORT_FILE"
  echo "" >> "$REPORT_FILE"
  echo "| Metric | Value |" >> "$REPORT_FILE"
  echo "|--------|-------|" >> "$REPORT_FILE"
  echo "| Scripts Checked | $SCRIPTS_CHECKED |" >> "$REPORT_FILE"
  echo "| With init.sh | $SCRIPTS_WITH_INIT |" >> "$REPORT_FILE"
  echo "| Missing init.sh | $SCRIPTS_MISSING_INIT |" >> "$REPORT_FILE"
  echo "| Hardcoded Values | $HARDCODED_VARS |" >> "$REPORT_FILE"
  echo "| Template Gaps | $TEMPLATE_GAPS |" >> "$REPORT_FILE"
  echo "| Error Handling Gaps | $ERROR_HANDLING_GAPS |" >> "$REPORT_FILE"
  echo "" >> "$REPORT_FILE"

  log_success "Audit complete!"
  log_info "Report saved to: $REPORT_FILE"
  cat "$REPORT_FILE"
}

run_audit "$@"
