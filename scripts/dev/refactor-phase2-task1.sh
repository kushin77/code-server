#!/usr/bin/env bash
# @file        scripts/dev/refactor-phase2-task1.sh
# @module      dev/refactoring
# @description Phase 2 Task 1 automation — migrate 24 scripts to canonical init pattern
# @owner       platform
# @status      active

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

# Target scripts for refactoring (24 remaining after Phase 1)
SCRIPTS_TO_REFACTOR=(
  "scripts/automated-deployment-orchestration.sh"
  "scripts/automated-iac-validation.sh"
  "scripts/bootstrap-node.sh"
  "scripts/automated-env-generator.sh"
  "scripts/deploy/deploy-iac.sh"
  "scripts/deploy/deploy-security.sh"
  "scripts/deploy/DEPLOYMENT-READINESS-VERIFICATION.sh"
  "scripts/deploy/execute-p0-p3-complete.sh"
  "scripts/backup.sh"
  "scripts/apply-governance.sh"
  "scripts/configure-audit-logging-phase4.sh"
  "scripts/configure-oidc-providers-phase1.sh"
  "scripts/configure-rbac-enforcement-phase3.sh"
  "scripts/configure-workload-federation-phase1.sh"
  "scripts/configure-workload-federation-phase2.sh"
  "scripts/monitor-disk-space.sh"
  "scripts/cleanup-container-overlap.sh"
  "scripts/dev/fix-onprem.sh"
  "scripts/dev/add-metadata-headers.sh"
  "scripts/generate-env-docs.sh"
  "scripts/gmail-agent/run.sh"
  "scripts/governance/generate-monthly-report.sh"
  "scripts/lib/global-quality-gate.sh"
  "scripts/memory-budget-guard.sh"
  "scripts/setup-git-credentials.sh"
)

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
REFACTORED_COUNT=0
SKIPPED_COUNT=0

log_info "Starting Phase 2 Task 1 refactoring..."
log_info "Target: 24 scripts → canonical init + logging"
log_info ""

for script in "${SCRIPTS_TO_REFACTOR[@]}"; do
    SCRIPT_PATH="${REPO_ROOT}/${script}"
    
    if [[ ! -f "$SCRIPT_PATH" ]]; then
        log_warn "Script not found: $script"
        ((SKIPPED_COUNT++))
        continue
    fi
    
    log_info "Refactoring: $script"
    
    # Check if already migrated (has _common/init.sh)
    if grep -q "source.*_common/init.sh" "$SCRIPT_PATH"; then
        log_info "  ✓ Already uses canonical init.sh"
        ((SKIPPED_COUNT++))
        continue
    fi
    
    # Pattern 1: Replace inline echo "ERROR:" with log_error
    # This is safe - we already have init.sh which sources logging.sh
    sed -i.bak 's/echo "ERROR: /log_error "/g' "$SCRIPT_PATH"
    
    # Pattern 2: Clean up PARENT_DIR duplicate calculations
    # Remove lines that recalculate SCRIPT_DIR if it was already set
    sed -i.bak '/^SCRIPT_DIR=".*SCRIPT_DIR.*/d' "$SCRIPT_PATH"
    
    # Pattern 3: Replace alternate root dir variable names with canonical ones
    # PROJECT_ROOT → use $REPO_ROOT or $PROJECT_ROOT from init.sh
    sed -i.bak 's/PROJECT_ROOT="\$(dirname.*SCRIPT_DIR.*)/# PROJECT_ROOT already exported by init.sh/g' "$SCRIPT_PATH"
    
    # Pattern 4: Remove deprecated logging source lines
    sed -i.bak '/source.*logging\.sh/d' "$SCRIPT_PATH"
    sed -i.bak '/source.*common-functions\.sh/d' "$SCRIPT_PATH"
    
    # Clean up backup files
    rm -f "${SCRIPT_PATH}.bak"
    
    log_info "  ✓ Refactored"
    ((REFACTORED_COUNT++))
done

log_info ""
log_info "═══════════════════════════════════════════════════"
log_info "Phase 2 Task 1 Refactoring Complete"
log_info "═══════════════════════════════════════════════════"
log_info "Refactored: $REFACTORED_COUNT scripts"
log_info "Skipped: $SKIPPED_COUNT scripts (already migrated)"
log_info "Total: ${#SCRIPTS_TO_REFACTOR[@]} scripts"
log_info ""
log_info "Next steps:"
log_info "1. Run: shellcheck scripts/*.sh scripts/**/*.sh (check for errors)"
log_info "2. Test: Local testing of critical scripts"
log_info "3. Commit: git add -A && git commit -m 'feat(scripts) - canonical init pattern phase 2 task 1'"
log_info "4. PR: gh pr create --title 'feat: phase 2 task 1 - canonical init...'"
