#!/bin/bash

###
# @file scripts/ops/infrastructure-health-check.sh
# @module operations/infrastructure
# @description Comprehensive infrastructure health assessment with real-time metrics
# @governance GOV-002: Production health monitoring and incident response automation
###

set -euo pipefail

# =============================================================================
# ERROR HANDLING & CLEANUP
# =============================================================================
trap 'log_error "Script failed at line $LINENO (exit code: $?)"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

log_warn() {
    log_warning "$1"
}

# ============================================================================
# Configuration
# ============================================================================

ARTIFACT_DIR="${REPO_ROOT}/artifacts"
REPORT_FILE="${ARTIFACT_DIR}/infrastructure-health-check-$(date +%s).json"
CRITICAL_THRESHOLD=1
WARNING_THRESHOLD=3

mkdir -p "${ARTIFACT_DIR}"

# ============================================================================
# State Tracking
# ============================================================================

declare -i CRITICAL_COUNT=0
declare -i WARNING_COUNT=0
declare -i INFO_COUNT=0
HEALTH_STATUS="HEALTHY"

log_health_check() {
    local component=$1
    local status=$2
    local message=$3
    
    log_info "  [$status] $component - $message"
}

health_critical() {
    local component=$1
    local message=$2
    log_error "    ❌ CRITICAL: $component - $message"
    CRITICAL_COUNT+=1
    HEALTH_STATUS="CRITICAL"
}

health_warning() {
    local component=$1
    local message=$2
    log_warn "    ⚠️  WARNING: $component - $message"
    WARNING_COUNT+=1
    if [[ "$HEALTH_STATUS" == "HEALTHY" ]]; then
        HEALTH_STATUS="WARNING"
    fi
}

health_ok() {
    local component=$1
    local message=$2
    log_success "    ✅ OK: $component - $message"
    INFO_COUNT+=1
}

# ============================================================================
# SECTION 1: Git Repository Health
# ============================================================================

log_info ""
log_info "=== 1. Git Repository Health ==="

if git -C "${PROJECT_ROOT}" rev-parse HEAD >/dev/null 2>&1; then
    CURRENT_COMMIT=$(git -C "${PROJECT_ROOT}" rev-parse HEAD)
    CURRENT_BRANCH=$(git -C "${PROJECT_ROOT}" rev-parse --abbrev-ref HEAD)
    health_ok "Git Repository" "On branch $CURRENT_BRANCH, commit ${CURRENT_COMMIT:0:7}"
else
    health_critical "Git Repository" "Not a git repository"
fi

# Check for uncommitted changes (acceptable but should be tracked)
UNCOMMITTED=$(git -C "${PROJECT_ROOT}" status --short 2>/dev/null | wc -l || echo 0)
if (( UNCOMMITTED == 0 )); then
    health_ok "Git State" "Repository clean (immutable)"
else
    health_warning "Git State" "$UNCOMMITTED uncommitted changes (should be tracked)"
fi

# Check for unmerged branches
UNMERGED=$(git -C "${PROJECT_ROOT}" branch --no-merged main 2>/dev/null | wc -l || echo 0)
if (( UNMERGED == 0 )); then
    health_ok "Git Branches" "All branches merged to main"
else
    health_warning "Git Branches" "$UNMERGED unmerged branches"
fi

# ============================================================================
# SECTION 2: Infrastructure Files
# ============================================================================

log_info ""
log_info "=== 2. Infrastructure Files ==="

EXPECTED_FILES=(
    "docker-compose.yml"
    ".env.infrastructure"
    "Caddyfile"
    "terraform/main.tf"
    "terraform/variables.tf"
    ".github/workflows/gitops-cd.yml"
)

for file in "${EXPECTED_FILES[@]}"; do
    if [[ -f "${PROJECT_ROOT}/${file}" ]]; then
        health_ok "File Present" "$file"
    else
        health_warning "File Missing" "$file (may be generated)"
    fi
done

# ============================================================================
# SECTION 3: Configuration Compliance
# ============================================================================

log_info ""
log_info "=== 3. Configuration Compliance ==="

# Check for hardcoded values
if grep -r "192\.168\|localhost:3[0-9][0-9][0-9]" "${PROJECT_ROOT}/terraform" 2>/dev/null | grep -v "\.terraform" >/dev/null; then
    health_warning "Configuration" "Possible hardcoded IPs/ports in terraform (review)"
else
    health_ok "Configuration" "No obvious hardcoded values"
fi

# Check environment variables in docker-compose
if [[ -f "${PROJECT_ROOT}/docker-compose.yml" ]] && grep -q '\${' "${PROJECT_ROOT}/docker-compose.yml"; then
    health_ok "Environment Variables" "docker-compose uses environment variable substitution"
else
    health_warning "Environment Variables" "docker-compose may not use env vars"
fi

# ============================================================================
# SECTION 4: Governance Compliance
# ============================================================================

log_info ""
log_info "=== 4. Governance Compliance (GOV-002) ==="

SCRIPTS_WITH_HEADERS=$(grep -l "@file" "${PROJECT_ROOT}"/scripts/*/*.sh 2>/dev/null | wc -l)
TOTAL_SCRIPTS=$(find "${PROJECT_ROOT}/scripts" -name "*.sh" -type f 2>/dev/null | wc -l)

if (( SCRIPTS_WITH_HEADERS == TOTAL_SCRIPTS )); then
    health_ok "Governance Headers" "100% of scripts have GOV-002 headers"
else
    PERCENTAGE=$((SCRIPTS_WITH_HEADERS * 100 / TOTAL_SCRIPTS))
    if (( PERCENTAGE >= 80 )); then
        health_warning "Governance Headers" "$PERCENTAGE% of scripts have GOV-002 headers"
    else
        health_warning "Governance Headers" "Only $PERCENTAGE% of scripts compliant (documentation debt)"
    fi
fi

# ============================================================================
# SECTION 5: Dependency Versions
# ============================================================================

log_info ""
log_info "=== 5. Dependency Versions ==="

# Check if package.json exists and has overrides
if [[ -f "${PROJECT_ROOT}/package.json" ]]; then
    if grep -q "overrides" "${PROJECT_ROOT}/package.json"; then
        OVERRIDE_COUNT=$(grep -A 20 "overrides" "${PROJECT_ROOT}/package.json" | grep -c ": \"" || echo "0")
        health_ok "Package Overrides" "pnpm overrides configured ($OVERRIDE_COUNT packages)"
    else
        health_warning "Package Overrides" "No security overrides found in package.json"
    fi
fi

# Check for pinned versions in terraform
if grep -q "version.*=" "${PROJECT_ROOT}/terraform/variables.tf" 2>/dev/null; then
    health_ok "Terraform Versions" "Service versions are pinned"
else
    health_warning "Terraform Versions" "Version pinning not explicit"
fi

# ============================================================================
# SECTION 6: Documentation Quality
# ============================================================================

log_info ""
log_info "=== 6. Documentation Quality ==="

RUNBOOKS=(
    "docs/runbooks/infrastructure-lifecycle-runbook.md"
    "README.md"
)

for runbook in "${RUNBOOKS[@]}"; do
    if [[ -f "${PROJECT_ROOT}/${runbook}" ]]; then
        SIZE=$(wc -l < "${PROJECT_ROOT}/${runbook}")
        if (( SIZE > 50 )); then
            health_ok "Documentation" "$runbook ($SIZE lines)"
        else
            health_warning "Documentation" "$runbook is short ($SIZE lines)"
        fi
    else
        health_warning "Documentation" "$runbook missing"
    fi
done

# ============================================================================
# SECTION 7: Security
# ============================================================================

log_info ""
log_info "=== 7. Security Assessment ==="

# Check for secrets in infrastructure and deployment-critical locations only.
# Documentation examples and audit fixtures are excluded so placeholders do not trigger a critical.
SECRET_SCAN_PATHS=()
SECRET_SCAN_CANDIDATES=(
    "${PROJECT_ROOT}/terraform"
    "${PROJECT_ROOT}/config"
    "${PROJECT_ROOT}/.github/workflows"
    "${PROJECT_ROOT}/docker-compose.yml"
    "${PROJECT_ROOT}/.env.infrastructure"
)

for candidate in "${SECRET_SCAN_CANDIDATES[@]}"; do
    if [[ -e "${candidate}" ]]; then
        SECRET_SCAN_PATHS+=("${candidate#${PROJECT_ROOT}/}")
    fi
done

if [[ ${#SECRET_SCAN_PATHS[@]} -eq 0 ]]; then
    health_warning "Secrets" "No infrastructure paths available for secret scan"
elif git -C "${PROJECT_ROOT}" grep -nE 'ghp_[A-Za-z0-9]{20,}|ghs_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}|-----BEGIN RSA PRIVATE KEY-----|-----BEGIN OPENSSH PRIVATE KEY-----' -- "${SECRET_SCAN_PATHS[@]}" 2>/dev/null | \
    grep -v "scripts/ops/infrastructure-health-check.sh" | \
    grep -q .; then
    health_critical "Secrets" "Potential credential pattern found in infrastructure files"
else
    health_ok "Secrets" "No obvious secrets in infrastructure files"
fi

# Check .gitignore exists
if [[ -f "${PROJECT_ROOT}/.gitignore" ]]; then
    GITIGNORE_SIZE=$(wc -l < "${PROJECT_ROOT}/.gitignore")
    health_ok ".gitignore" "Present ($GITIGNORE_SIZE rules)"
else
    health_warning ".gitignore" "Not found or missing"
fi

# ============================================================================
# SECTION 8: Build & Deployment Infrastructure
# ============================================================================

log_info ""
log_info "=== 8. Build & Deployment Infrastructure ==="

CI_WORKFLOWS=$(find "${PROJECT_ROOT}/.github/workflows" -name "*.yml" -o -name "*.yaml" 2>/dev/null | wc -l)
if (( CI_WORKFLOWS > 0 )); then
    health_ok "CI/CD Workflows" "$CI_WORKFLOWS GitHub Actions workflows configured"
else
    health_warning "CI/CD Workflows" "No GitHub Actions workflows found"
fi

DEPLOYMENT_SCRIPTS=$(find "${PROJECT_ROOT}/scripts/ops" -name "*.sh" 2>/dev/null | wc -l)
if (( DEPLOYMENT_SCRIPTS > 0 )); then
    health_ok "Deployment Scripts" "$DEPLOYMENT_SCRIPTS operational scripts available"
else
    health_critical "Deployment Scripts" "No operational scripts found"
fi

# ============================================================================
# SECTION 9: Monitoring & Observability
# ============================================================================

log_info ""
log_info "=== 9. Monitoring & Observability ==="

MONITORING_SCRIPTS=$(find "${PROJECT_ROOT}/scripts/monitoring" -name "*.sh" 2>/dev/null | wc -l)
if (( MONITORING_SCRIPTS > 0 )); then
    health_ok "Monitoring Setup" "$MONITORING_SCRIPTS monitoring configuration scripts"
else
    health_warning "Monitoring Setup" "No monitoring scripts found"
fi

if [[ -f "${PROJECT_ROOT}/policies/core/audit.rego" ]]; then
    health_ok "Audit Policies" "OPA audit policies present"
else
    health_warning "Audit Policies" "No OPA audit policies found"
fi

# ============================================================================
# SECTION 10: Recent Activity
# ============================================================================

log_info ""
log_info "=== 10. Recent Activity ==="

# Last commit
LAST_COMMIT_AGE=$(git -C "${PROJECT_ROOT}" log -1 --format=%ar 2>/dev/null || echo "unknown")
health_ok "Last Commit" "$LAST_COMMIT_AGE"

# Commit count this week
COMMITS_THIS_WEEK=$(git -C "${PROJECT_ROOT}" rev-list --count --since="1 week ago" main 2>/dev/null || echo "0")
if (( COMMITS_THIS_WEEK > 0 )); then
    health_ok "Recent Activity" "$COMMITS_THIS_WEEK commits in last week"
else
    health_warning "Recent Activity" "No commits in last week"
fi

# ============================================================================
# Generate Health Report
# ============================================================================

log_info ""
log_info "=== Health Check Summary ==="
log_info ""
log_info "Status: $HEALTH_STATUS"
log_info "Critical: $CRITICAL_COUNT | Warning: $WARNING_COUNT | Info: $INFO_COUNT"
log_info ""

# Generate JSON report
cat > "${REPORT_FILE}" << EOF
{
  "timestamp": "$(date -u +'%Y-%m-%dT%H:%M:%SZ')",
  "status": "$HEALTH_STATUS",
  "metrics": {
    "critical": $CRITICAL_COUNT,
    "warning": $WARNING_COUNT,
    "info": $INFO_COUNT,
    "total_checks": $((CRITICAL_COUNT + WARNING_COUNT + INFO_COUNT))
  },
  "git": {
    "commit": "${CURRENT_COMMIT:0:7}",
    "branch": "$CURRENT_BRANCH",
    "uncommitted_changes": $UNCOMMITTED
  },
  "infrastructure": {
    "scripts_total": $TOTAL_SCRIPTS,
    "scripts_compliant": $SCRIPTS_WITH_HEADERS,
    "compliance_percent": $((SCRIPTS_WITH_HEADERS * 100 / TOTAL_SCRIPTS))
  },
  "deployment": {
    "ci_workflows": $CI_WORKFLOWS,
    "deployment_scripts": $DEPLOYMENT_SCRIPTS
  },
  "recommendation": "$([ "$HEALTH_STATUS" == "HEALTHY" ] && echo "Ready for production deployment" || echo "Address issues before production deployment")"
}
EOF

log_info "Health report: ${REPORT_FILE}"
log_info ""

# Exit with appropriate code
if [[ "$HEALTH_STATUS" == "CRITICAL" ]]; then
    log_error "❌ CRITICAL issues detected - DO NOT DEPLOY"
    exit 1
elif [[ "$HEALTH_STATUS" == "WARNING" ]]; then
    log_warn "⚠️  Warnings detected - Review before deployment"
    exit 0
else
    log_success "✅ Infrastructure is HEALTHY - Ready for deployment"
    exit 0
fi
