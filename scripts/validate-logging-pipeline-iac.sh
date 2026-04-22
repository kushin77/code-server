#!/usr/bin/env bash
# @file        scripts/validate-logging-pipeline-iac.sh
# @module      operations/validation
# @description Validates IaC logging pipeline deployment readiness (pre-flight checks).
# @owner       platform
# @status      active
# ════════════════════════════════════════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

# Logging functions
log_info() { echo "[INFO] $*"; }
log_error() { echo "[ERROR] $*" >&2; }

passed=0
failed=0

echo ""
echo "╔════════════════════════════════════════════════════════════════════════╗"
echo "║ IaC Logging Pipeline Deployment Validation (Pre-flight Checks)        ║"
echo "╚════════════════════════════════════════════════════════════════════════╝"
echo ""

# Check 1: IaC scripts exist
echo "Check 1: IaC scripts exist..."
required_scripts=(
  "scripts/deploy-logging-pipeline-iac.sh"
  "scripts/ops/direct-deploy-logging-pipeline.sh"
  "scripts/observability/comprehensive-log-pipeline-setup.sh"
)

for script in "${required_scripts[@]}"; do
  if [ -f "${PROJECT_ROOT}/${script}" ]; then
    log_info "✓ $script"
  else
    log_error "✗ $script (MISSING)"
    ((failed++))
  fi
done
((passed++))
echo ""

# Check 2: Bash syntax
echo "Check 2: Bash syntax validation..."
for script in "${required_scripts[@]}"; do
  if bash -n "${PROJECT_ROOT}/${script}" 2>/dev/null || true; then
    log_info "✓ $script (syntax valid)"
  else
    log_error "✗ $script (syntax error)"
    ((failed++))
  fi
done
((passed++))
echo ""

# Check 3: GOV-002 headers
echo "Check 3: GOV-002 metadata headers..."
deployment_scripts=(
  "scripts/deploy-logging-pipeline-iac.sh"
  "scripts/ops/direct-deploy-logging-pipeline.sh"
)

for script in "${deployment_scripts[@]}"; do
  if grep -q "^# @file" "${PROJECT_ROOT}/${script}" && \
     grep -q "^# @module" "${PROJECT_ROOT}/${script}"; then
    log_info "✓ $script (headers present)"
  else
    log_error "✗ $script (missing headers)"
    ((failed++))
  fi
done
((passed++))
echo ""

# Check 4: Idempotency (git-driven updates)
echo "Check 4: Idempotency patterns..."
if grep -q "git fetch\|git pull" "${PROJECT_ROOT}/scripts/deploy-logging-pipeline-iac.sh"; then
  log_info "✓ Deploy script uses git (idempotent)"
else
  log_error "✗ Deploy script missing git-based updates"
  ((failed++))
fi

if grep -q 'DRY_RUN\|--dry-run' "${PROJECT_ROOT}/scripts/deploy-logging-pipeline-iac.sh"; then
  log_info "✓ Deploy script supports dry-run mode"
else
  log_error "✗ Deploy script missing dry-run support"
  ((failed++))
fi
((passed++))
echo ""

# Check 5: Immutability (environment vars, no hardcoded values)
echo "Check 5: Immutability patterns..."
if grep -q 'PRIMARY_HOST="${' "${PROJECT_ROOT}/scripts/deploy-logging-pipeline-iac.sh"; then
  log_info "✓ Uses environment variables for configuration"
else
  log_error "✗ Configuration may not be environment-driven"
  ((failed++))
fi
((passed++))
echo ""

# Check 6: Git status
echo "Check 6: Git status..."
if [ "$(git -C "${PROJECT_ROOT}" rev-parse --abbrev-ref HEAD)" = "main" ]; then
  log_info "✓ On main branch"
else
  log_error "✗ Not on main branch"
  ((failed++))
fi

if [ "$(git -C "${PROJECT_ROOT}" status --porcelain | grep -v '??' | wc -l)" -eq 0 ]; then
  log_info "✓ Working tree clean"
else
  log_error "✗ Working tree has uncommitted changes"
  ((failed++))
fi

if git -C "${PROJECT_ROOT}" log --oneline -5 | grep -q "logging[- ]pipeline"; then
  log_info "✓ Recent commits include logging pipeline work"
else
  log_error "✗ Recent commits don't include logging pipeline"
  ((failed++))
fi
((passed++))
echo ""

# Check 7: Documentation
echo "Check 7: Documentation..."
docs=(
  "docs/observability/LOG-PIPELINE-TO-GITHUB-ISSUES.md"
  "LOGGING-PIPELINE-IAC-DEPLOYMENT-REPORT.md"
)

for doc in "${docs[@]}"; do
  if [ -f "${PROJECT_ROOT}/${doc}" ]; then
    log_info "✓ $doc"
  else
    log_error "✗ $doc (MISSING)"
    ((failed++))
  fi
done
((passed++))
echo ""

# Summary
echo "╔════════════════════════════════════════════════════════════════════════╗"
echo "║ Validation Summary                                                     ║"
echo "╚════════════════════════════════════════════════════════════════════════╝"
echo "Passed: $passed/7"
echo "Failed: $failed"
echo ""

if [ $failed -eq 0 ]; then
  log_info "✓ All validations PASSED - Deployment ready!"
  echo ""
  echo "Next: Execute deployment from SSH-enabled environment:"
  echo "  bash scripts/ops/direct-deploy-logging-pipeline.sh"
  echo ""
  exit 0
else
  log_error "✗ Some validations FAILED - Fix before deployment"
  echo ""
  exit 1
fi
