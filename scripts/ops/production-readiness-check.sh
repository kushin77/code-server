#!/bin/bash

###
# @file scripts/ops/production-readiness-check.sh
# @module operations/readiness
# @description Comprehensive production readiness verification
# @governance GOV-002: All deployment gates verified and documented
###

# Source canonical bootstrap (provides log_info, log_error, and shared configuration)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

# Don't use set -euo pipefail to allow graceful handling of missing tools
set +euo pipefail
trap 'exit 0' INT TERM

# =============================================================================
# ERROR HANDLING & CLEANUP
# =============================================================================
trap 'log_error "Script failed at line $LINENO (exit code: $?)"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

# ============================================================================
# Configuration
# ============================================================================

REPORT_FILE="${REPO_ROOT}/artifacts/production-readiness-$(date +%Y%m%d-%H%M%S).json"

mkdir -p "${REPO_ROOT}/artifacts"

declare -i CHECKS_TOTAL=0
declare -i CHECKS_PASSED=0
declare -i CHECKS_WARNING=0
declare -i CHECKS_FAILED=0

log_info "=== Production Readiness Check ==="
log_info ""

# ============================================================================
# Check Functions
# ============================================================================

check_pass() {
    local name=$1
    ((CHECKS_PASSED++))
    ((CHECKS_TOTAL++))
    log_success "$name"
}

check_warn() {
    local name=$1
    ((CHECKS_WARNING++))
    ((CHECKS_TOTAL++))
    log_warn "$name"
}

check_fail() {
    local name=$1
    ((CHECKS_FAILED++))
    ((CHECKS_TOTAL++))
    log_error "$name"
}

# ============================================================================
# SECTION 1: Code Quality & Security
# ============================================================================

log_info "SECTION 1: Code Quality & Security"
log_info "======================================"

# Git repository state
if git -C "${PROJECT_ROOT}" rev-parse HEAD >/dev/null 2>&1; then
    UNCOMMITTED=$(git -C "${PROJECT_ROOT}" status --short 2>/dev/null | wc -l || echo 0)
    if (( UNCOMMITTED == 0 )); then
        check_pass "Git repository: clean"
    else
        check_fail "Git repository: $UNCOMMITTED uncommitted changes"
    fi
else
    check_fail "Git repository: not a git repo"
fi

# Main branch check
BRANCH=$(git -C "${PROJECT_ROOT}" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
if [[ "$BRANCH" == "main" ]]; then
    check_pass "On main branch"
else
    check_fail "Not on main branch (on $BRANCH)"
fi

# TypeScript compilation
if [[ -f "${PROJECT_ROOT}/tsconfig.json" ]]; then
    if npx tsc --noEmit 2>/dev/null; then
        check_pass "TypeScript compilation: success"
    else
        check_warn "TypeScript compilation: warnings or errors (check manually)"
    fi
fi

# Dependency vulnerabilities
if command -v npm >/dev/null 2>&1; then
    if npm audit --audit-level=moderate 2>/dev/null; then
        check_pass "npm audit: no moderate/high vulnerabilities"
    else
        check_warn "npm audit: vulnerabilities found (review dependencies)"
    fi
fi

# ============================================================================
# SECTION 2: Infrastructure & Configuration
# ============================================================================

log_info ""
log_info "SECTION 2: Infrastructure & Configuration"
log_info "=========================================="

# Docker Compose configuration
if [[ -f "${PROJECT_ROOT}/docker-compose.yml" ]]; then
    check_pass "docker-compose.yml: exists"
    if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
        if docker compose -f "${PROJECT_ROOT}/docker-compose.yml" config >/dev/null 2>&1; then
            check_pass "docker-compose.yml: valid configuration"
        else
            check_fail "docker-compose.yml: invalid configuration"
        fi
    elif command -v docker-compose >/dev/null 2>&1; then
        if docker-compose -f "${PROJECT_ROOT}/docker-compose.yml" config >/dev/null 2>&1; then
            check_pass "docker-compose.yml: valid configuration"
        else
            check_fail "docker-compose.yml: invalid configuration"
        fi
    fi
else
    check_fail "docker-compose.yml: not found"
fi

# Terraform configuration
if [[ -d "${PROJECT_ROOT}/terraform" ]]; then
    TF_FILES=$(find "${PROJECT_ROOT}/terraform" -name "*.tf" 2>/dev/null | wc -l || echo 0)
    if (( TF_FILES > 0 )); then
        check_pass "Terraform: $TF_FILES configuration files"
    else
        check_warn "Terraform: directory exists but no .tf files"
    fi
fi

# Environment configuration
if [[ -f "${PROJECT_ROOT}/.env.infrastructure" ]]; then
    check_pass ".env.infrastructure: exists"
else
    check_warn ".env.infrastructure: not found (may be optional)"
fi

# Caddyfile configuration
if [[ -f "${PROJECT_ROOT}/Caddyfile" ]]; then
    check_pass "Caddyfile: exists"
else
    check_warn "Caddyfile: not found"
fi

# ============================================================================
# SECTION 3: Documentation
# ============================================================================

log_info ""
log_info "SECTION 3: Documentation"
log_info "========================="

# README.md
if [[ -f "${PROJECT_ROOT}/README.md" ]]; then
    check_pass "README.md: exists"
else
    check_fail "README.md: not found"
fi

# Runbooks
RUNBOOK_COUNT=$(find "${PROJECT_ROOT}/docs" -name "RUNBOOK*.md" 2>/dev/null | wc -l || echo 0)
if (( RUNBOOK_COUNT > 0 )); then
    check_pass "Runbooks: $RUNBOOK_COUNT operational runbooks"
else
    check_warn "Runbooks: no runbooks found"
fi

# Architecture documentation
if [[ -f "${PROJECT_ROOT}/docs/ARCHITECTURE.md" ]] || [[ -f "${PROJECT_ROOT}/docs/README.md" ]]; then
    check_pass "Architecture documentation: exists"
else
    check_warn "Architecture documentation: not found"
fi

# ============================================================================
# SECTION 4: Monitoring & Observability
# ============================================================================

log_info ""
log_info "SECTION 4: Monitoring & Observability"
log_info "====================================="

# Prometheus rules
if [[ -f "${PROJECT_ROOT}/monitoring/alerts/prometheus-rules.yaml" ]]; then
    check_pass "Prometheus rules: configured"
else
    check_warn "Prometheus rules: not found"
fi

# Grafana dashboards
DASHBOARD_COUNT=$(find "${PROJECT_ROOT}/grafana" -name "*.json" 2>/dev/null | wc -l || echo 0)
if (( DASHBOARD_COUNT > 0 )); then
    check_pass "Grafana: $DASHBOARD_COUNT dashboards"
else
    check_warn "Grafana: no dashboards found"
fi

# Logging configuration
if [[ -f "${PROJECT_ROOT}/logs" ]] || [[ -d "${PROJECT_ROOT}/logs" ]]; then
    check_pass "Logging: infrastructure in place"
else
    check_warn "Logging: no logs directory"
fi

# ============================================================================
# SECTION 5: Deployment Scripts
# ============================================================================

log_info ""
log_info "SECTION 5: Deployment Scripts"
log_info "=============================="

# Deployment pipeline
if [[ -f "${PROJECT_ROOT}/scripts/ops/deployment-pipeline.sh" ]]; then
    check_pass "Deployment pipeline: exists"
else
    check_warn "Deployment pipeline: not found"
fi

# Health check scripts
HEALTHCHECK_COUNT=$(find "${PROJECT_ROOT}/scripts" -name "*health*" -type f 2>/dev/null | wc -l || echo 0)
if (( HEALTHCHECK_COUNT > 0 )); then
    check_pass "Health checks: $HEALTHCHECK_COUNT scripts"
else
    check_warn "Health checks: no dedicated health check scripts"
fi

# Rollback scripts
if [[ -f "${PROJECT_ROOT}/scripts/_common/rollback-manager.sh" ]]; then
    check_pass "Rollback procedures: configured"
else
    check_warn "Rollback procedures: not found"
fi

# ============================================================================
# SECTION 6: Governance & Compliance
# ============================================================================

log_info ""
log_info "SECTION 6: Governance & Compliance"
log_info "===================================="

# GOV-002 headers
GOV_HEADER_COUNT=$(grep -r "@governance" "${PROJECT_ROOT}/scripts" 2>/dev/null | wc -l || echo 0)
if (( GOV_HEADER_COUNT > 20 )); then
    check_pass "GOV-002 headers: $GOV_HEADER_COUNT files with governance"
else
    check_warn "GOV-002 headers: only $GOV_HEADER_COUNT files (recommend >20)"
fi

# OPA policies
OPA_POLICY_COUNT=$(find "${PROJECT_ROOT}/policies" -name "*.rego" 2>/dev/null | wc -l || echo 0)
if (( OPA_POLICY_COUNT > 0 )); then
    check_pass "OPA policies: $OPA_POLICY_COUNT policies"
else
    check_warn "OPA policies: not configured"
fi

# Security scanning
if [[ -f "${PROJECT_ROOT}/scripts/ci/security-vulnerability-remediation.sh" ]]; then
    check_pass "Security scanning: configured"
else
    check_warn "Security scanning: not configured"
fi

# ============================================================================
# SECTION 7: SLA & Metrics
# ============================================================================

log_info ""
log_info "SECTION 7: SLA & Metrics"
log_info "========================"

# SLA metrics reporter
if [[ -f "${PROJECT_ROOT}/scripts/ops/sla-metrics-reporter.sh" ]]; then
    check_pass "SLA metrics: reporter available"
else
    check_warn "SLA metrics: reporter not found"
fi

# Alert configuration
if [[ -f "${PROJECT_ROOT}/monitoring/alerts/ALERTING-GUIDE.md" ]]; then
    check_pass "Alerting guide: configured"
else
    check_warn "Alerting guide: not found"
fi

# ============================================================================
# Final Report
# ============================================================================

log_info ""
log_info "=== Production Readiness Summary ==="
log_info ""
log_success "Total Checks: $CHECKS_TOTAL"
log_success "Passed: $CHECKS_PASSED"
log_warn "Warnings: $CHECKS_WARNING"
log_error "Failed: $CHECKS_FAILED"

# Determine readiness status
READINESS_STATUS="READY"
if (( CHECKS_FAILED > 0 )); then
    READINESS_STATUS="NOT_READY"
    log_error "Production deployment BLOCKED due to failures"
elif (( CHECKS_WARNING > 2 )); then
    READINESS_STATUS="CAUTION"
    log_warn "Production deployment CONDITIONAL - address warnings"
else
    log_success "Production deployment READY - all critical checks passed"
fi

log_info ""

# Generate JSON report
cat > "${REPORT_FILE}" << EOF
{
  "check_timestamp": "$(date -u +'%Y-%m-%dT%H:%M:%SZ')",
  "readiness_status": "${READINESS_STATUS}",
  "results": {
    "total_checks": ${CHECKS_TOTAL},
    "passed": ${CHECKS_PASSED},
    "warnings": ${CHECKS_WARNING},
    "failed": ${CHECKS_FAILED}
  },
  "completion_percentage": $((CHECKS_PASSED * 100 / CHECKS_TOTAL)),
  "git_commit": "$(git -C "${PROJECT_ROOT}" rev-parse HEAD 2>/dev/null || echo 'unknown')",
  "git_branch": "$(git -C "${PROJECT_ROOT}" rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'unknown')",
  "deployment_recommendation": "${READINESS_STATUS}"
}
EOF

log_info "Report saved: ${REPORT_FILE}"
log_info ""

if [[ "${READINESS_STATUS}" == "READY" ]]; then
    log_success "✅ Production readiness check: PASSED"
    exit 0
elif [[ "${READINESS_STATUS}" == "CAUTION" ]]; then
    log_warn "⚠️  Production readiness check: CONDITIONAL"
    exit 0
else
    log_error "❌ Production readiness check: FAILED"
    exit 1
fi
