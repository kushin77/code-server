#!/bin/bash
# Deployment Orchestration Script - Phase 9-12 Automation
# Monitors CI, auto-merges, and triggers Phase 12 deployment

set -e

##############################################################################
# CONFIGURATION
##############################################################################
REPO="kushin77/code-server"
PHASE_9_PR=167
PHASE_10_PR=136
PHASE_11_PR=137

# Timing configuration
POLLING_INTERVAL=30  # seconds
CHECK_TIMEOUT=3600   # 1 hour max wait per phase
LOG_FILE="phase-9-12-deployment-$(date +%Y%m%d-%H%M%S).log"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

##############################################################################
# LOGGING FUNCTIONS
##############################################################################
log_info() {
    echo -e "${BLUE}[$(date +'%H:%M:%S')] ℹ️  $1${NC}" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[$(date +'%H:%M:%S')] ✅ $1${NC}" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%H:%M:%S')] ⚠️  $1${NC}" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[$(date +'%H:%M:%S')] ❌ $1${NC}" | tee -a "$LOG_FILE"
}

##############################################################################
# PHASE 9: MERGE WHEN APPROVED
##############################################################################
merge_phase_9() {
    log_info "Checking Phase 9 approval status..."

    local start_time=$(date +%s)

    while true; do
        # Get approval status
        local approval=$(gh pr view $PHASE_9_PR --repo $REPO \
            --json reviewDecision --jq '.reviewDecision' 2>/dev/null || echo "REVIEW_REQUIRED")

        if [ "$approval" = "APPROVED" ]; then
            log_success "Phase 9 APPROVED by reviewer"

            # Execute merge
            log_info "Executing Phase 9 merge..."
            if gh pr merge $PHASE_9_PR --repo $REPO --squash \
                --body "Phase 9 Remediation - Auto-merged upon reviewer approval"; then
                log_success "Phase 9 MERGED SUCCESSFULLY"
                return 0
            else
                log_error "Phase 9 merge failed"
                return 1
            fi
        fi

        # Check timeout
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))

        if [ $elapsed -gt $CHECK_TIMEOUT ]; then
            log_error "Phase 9 approval timeout after $((elapsed / 60)) minutes"
            return 1
        fi

        # Show wait status every 60 seconds
        if [ $((elapsed % 60)) -eq 0 ]; then
            log_warning "Still waiting for Phase 9 approval (${elapsed}s elapsed)"
        fi

        sleep $POLLING_INTERVAL
    done
}

##############################################################################
# PHASE 10: MONITOR CI AND AUTO-MERGE
##############################################################################
merge_phase_10() {
    log_info "Waiting for Phase 10 CI to complete..."

    local start_time=$(date +%s)
    local last_check_count=0

    while true; do
        # Get CI status
        local check_status=$(gh pr checks $PHASE_10_PR --repo $REPO 2>/dev/null | \
            grep -E "passing|passing|failure|pending" | wc -l || echo "0")

        # Get specific check details
        local all_passed=$(gh pr checks $PHASE_10_PR --repo $REPO 2>/dev/null | \
            grep -c "PASSED" || echo "0")
        local still_pending=$(gh pr checks $PHASE_10_PR --repo $REPO 2>/dev/null | \
            grep -c "PENDING\|QUEUED\|RUNNING" || echo "0")
        local failed=$(gh pr checks $PHASE_10_PR --repo $REPO 2>/dev/null | \
            grep -c "FAILED" || echo "0")

        # Log progress every 60 seconds
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))

        if [ $((elapsed % 60)) -eq 0 ] && [ $elapsed -gt 0 ]; then
            log_info "Phase 10 CI Status: Passed=$all_passed Pending=$still_pending Failed=$failed"
        fi

        # Check for failures
        if [ "$failed" -gt 0 ]; then
            log_error "Phase 10 CI FAILED - Manual intervention required"
            return 1
        fi

        # Check for completion
        if [ "$still_pending" -eq 0 ] && [ "$all_passed" -gt 0 ]; then
            log_success "Phase 10 CI COMPLETED - All checks PASSED"

            # Verify mergeable and execute merge
            log_info "Executing Phase 10 auto-merge..."
            if gh pr merge $PHASE_10_PR --repo $REPO --merge \
                --body "Phase 10 Complete - Auto-merged upon CI success"; then
                log_success "Phase 10 MERGED SUCCESSFULLY"
                return 0
            else
                log_warning "Phase 10 auto-merge may have already executed"
                return 0
            fi
        fi

        # Check timeout
        if [ $elapsed -gt $CHECK_TIMEOUT ]; then
            log_error "Phase 10 CI timeout after $((elapsed / 60)) minutes"
            return 1
        fi

        sleep $POLLING_INTERVAL
    done
}

##############################################################################
# PHASE 11: MONITOR CI AND AUTO-MERGE
##############################################################################
merge_phase_11() {
    log_info "Waiting for Phase 11 CI to complete..."

    local start_time=$(date +%s)

    while true; do
        # Get CI status
        local all_passed=$(gh pr checks $PHASE_11_PR --repo $REPO 2>/dev/null | \
            grep -c "PASSED" || echo "0")
        local still_pending=$(gh pr checks $PHASE_11_PR --repo $REPO 2>/dev/null | \
            grep -c "PENDING\|QUEUED\|RUNNING" || echo "0")
        local failed=$(gh pr checks $PHASE_11_PR --repo $REPO 2>/dev/null | \
            grep -c "FAILED" || echo "0")

        # Log progress
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))

        if [ $((elapsed % 60)) -eq 0 ] && [ $elapsed -gt 0 ]; then
            log_info "Phase 11 CI Status: Passed=$all_passed Pending=$still_pending Failed=$failed"
        fi

        # Check for failures
        if [ "$failed" -gt 0 ]; then
            log_error "Phase 11 CI FAILED - Manual intervention required"
            return 1
        fi

        # Check for completion
        if [ "$still_pending" -eq 0 ] && [ "$all_passed" -gt 0 ]; then
            log_success "Phase 11 CI COMPLETED - All checks PASSED"

            # Execute merge
            log_info "Executing Phase 11 auto-merge..."
            if gh pr merge $PHASE_11_PR --repo $REPO --merge \
                --body "Phase 11 Complete - Auto-merged upon CI success"; then
                log_success "Phase 11 MERGED SUCCESSFULLY"
                return 0
            else
                log_warning "Phase 11 auto-merge may have already executed"
                return 0
            fi
        fi

        # Check timeout
        if [ $elapsed -gt $CHECK_TIMEOUT ]; then
            log_error "Phase 11 CI timeout after $((elapsed / 60)) minutes"
            return 1
        fi

        sleep $POLLING_INTERVAL
    done
}

##############################################################################
# PHASE 12: DEPLOYMENT ORCHESTRATION
##############################################################################
deploy_phase_12() {
    log_success "Phase 11 merged - Triggering Phase 12 deployment"

    log_info "Verifying Phase 12 infrastructure..."

    # Check if deployment script exists
    if [ ! -f "scripts/deploy-phase-12-all.sh" ]; then
        log_error "Phase 12 deployment script not found"
        return 1
    fi

    log_success "Phase 12 deployment script found"

    # Execute Phase 12 deployment
    log_info "Starting Phase 12 automated deployment..."

    if bash scripts/deploy-phase-12-all.sh; then
        log_success "Phase 12 DEPLOYMENT COMPLETE"
        return 0
    else
        log_error "Phase 12 deployment failed"
        return 1
    fi
}

##############################################################################
# MAIN ORCHESTRATION
##############################################################################
main() {
    log_info "═══════════════════════════════════════════════════════"
    log_info "PHASE 9-12 DEPLOYMENT ORCHESTRATION START"
    log_info "═══════════════════════════════════════════════════════"
    log_info "Log file: $LOG_FILE"
    log_info ""

    # Phase 9: Merge when approved
    log_info "PHASE 1/4: PHASE 9 APPROVAL & MERGE"
    if merge_phase_9; then
        log_success "Phase 9 complete"
    else
        log_error "Phase 9 merge failed - aborting pipeline"
        return 1
    fi

    sleep 10  # Wait for Phase 10 CI to start

    # Phase 10: Monitor and merge
    log_info ""
    log_info "PHASE 2/4: PHASE 10 CI & MERGE"
    if merge_phase_10; then
        log_success "Phase 10 complete"
    else
        log_error "Phase 10 merge failed - aborting pipeline"
        return 1
    fi

    sleep 10  # Wait for Phase 11 CI to start

    # Phase 11: Monitor and merge
    log_info ""
    log_info "PHASE 3/4: PHASE 11 CI & MERGE"
    if merge_phase_11; then
        log_success "Phase 11 complete"
    else
        log_error "Phase 11 merge failed - aborting pipeline"
        return 1
    fi

    sleep 10  # Wait for Phase 12 trigger

    # Phase 12: Deploy infrastructure
    log_info ""
    log_info "PHASE 4/4: PHASE 12 DEPLOYMENT"
    if deploy_phase_12; then
        log_success "Phase 12 complete"
    else
        log_error "Phase 12 deployment failed"
        return 1
    fi

    # Final summary
    log_info ""
    log_info "═══════════════════════════════════════════════════════"
    log_success "ALL PHASES COMPLETE - PRODUCTION DEPLOYMENT SUCCESSFUL"
    log_info "═══════════════════════════════════════════════════════"
    log_info "Log file: $LOG_FILE"
}

trap 'log_error "Orchestration interrupted"; exit 1' INT TERM

main "$@"
