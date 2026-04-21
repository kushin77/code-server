#!/usr/bin/env bash
# @file        scripts/task-completion-example.sh
# @module      examples/task-completion
# @description Practical example showing how to use task-completion-framework to prevent hook blockers
# @owner       copilot/examples
# @status      REFERENCE
#

set -euo pipefail

# ============================================================================
# EXAMPLE: Issue #984 / #1017 Deployment Task
# ============================================================================
# This example demonstrates how the task-completion-framework would have
# prevented the 5x hook blocker loop by providing visibility into which
# DoD items were actually blocking task_complete.
# ============================================================================

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common/logging.sh"
source "${SCRIPT_DIR}/lib/task-completion-framework.sh"

# ============================================================================
# SCENARIO: Deployment with Credential-Dependent Steps
# ============================================================================

main() {
    log_info "=== ISSUE #984: OAuth QA User Deployment ==="
    log_info ""
    
    # Step 1: Define What Needs to Be Done
    log_info "STEP 1: Register Definition of Done"
    log_info "--------"
    
    register_dod_item \
        "whitelist-qa-email" \
        "Add qa@kushnir.cloud to allowed-emails.txt" \
        "agent" \
        "Agent can complete this independently"
    
    register_dod_item \
        "gsm-credentials" \
        "Load QA credentials from Google Secret Manager" \
        "credentials" \
        "Requires: gcloud CLI with GCP service account credentials"
    
    register_dod_item \
        "restart-oauth" \
        "Restart oauth2-proxy service on production host" \
        "credentials" \
        "Requires: SSH private key for akushnir@192.168.168.31"
    
    register_dod_item \
        "test-oauth-flow" \
        "Test OAuth login flow with QA user in browser" \
        "manual" \
        "Requires: Browser access to https://kushnir.cloud and manual verification"
    
    log_info ""
    log_info "STEP 2: Execute Agent-Completable Work"
    log_info "--------"
    
    # Simulate work
    log_info "Adding qa@kushnir.cloud to allowed-emails.txt..."
    # ... work happens ...
    mark_dod_complete "whitelist-qa-email"
    log_info "✅ Whitelist step complete"
    
    log_info ""
    log_info "STEP 3: Check Status Before Attempting task_complete"
    log_info "--------"
    log_info ""
    
    # THIS IS THE KEY STEP THAT WOULD HAVE PREVENTED THE BLOCKER
    # Instead of trying to call task_complete and getting blocked,
    # we first validate and show what's blocking:
    
    validate_definition_of_done || true  # Don't fail, just show status
    
    log_info ""
    log_info "STEP 4: Diagnose Blockers"
    log_info "--------"
    log_info ""
    
    diagnose_completion_blockers true
    
    log_info ""
    log_info "STEP 5: Make Informed Decision"
    log_info "--------"
    log_info ""
    
    # Attempt safe completion
    if safe_task_complete 984; then
        log_info ""
        log_info "✅ All DoD items complete - task_complete ready"
    else
        log_info ""
        log_info "⏳ DoD incomplete - showing next steps..."
        log_info ""
        log_info "RECOMMENDED ACTION:"
        log_info "  Provide to Operations Team (Path B):"
        log_info "    1. QA password for step: gsm-credentials"
        log_info "    2. SSH access for step: restart-oauth"
        log_info ""
        log_info "  They will complete steps 2-3, then agent can:"
        log_info "    mark_dod_complete 'gsm-credentials'"
        log_info "    mark_dod_complete 'restart-oauth'"
        log_info ""
        log_info "  Then ops team completes step 4 manually and reports back"
        log_info ""
        log_info "ALTERNATIVE (Path A - NOT RECOMMENDED):"
        log_info "  If you provide GCP credentials and SSH key to agent:"
        log_info "    export GCP_SERVICE_ACCOUNT_JSON='...'"
        log_info "    export SSH_PRIVATE_KEY='...'"
        log_info "    bash this_script --with-credentials"
        log_info ""
        log_info "ACCEPTANCE (Path C - if manual steps acceptable):"
        log_info "  safe_task_complete 984 force"
        log_info "  (with comment in issue explaining credential blockers)"
    fi
}

# ============================================================================
# WHAT THIS PREVENTS
# ============================================================================
# 
# BEFORE (5x Hook Blocker Loop):
# ================================
# 1. Agent calls task_complete
# 2. Hook: "DoD incomplete" (but unclear WHY)
# 3. Agent: "Work is complete!"
# 4. Hook: "No, DoD incomplete" 
# 5. (repeats 3 more times with same error)
# → Loop broken, frustrated user, no clarity
#
# AFTER (With Task Completion Framework):
# =========================================
# 1. Agent calls validate_definition_of_done()
#    → Shows: 1/4 items complete, 3/4 credential blockers
# 2. diagnose_completion_blockers()
#    → Shows: Which items blocked, why, and resolution paths
# 3. Agent: "DoD is incomplete due to credentials. Options:"
#    - PATH A: Provide credentials (not recommended)
#    - PATH B: Operations team completes (recommended)
#    - PATH C: Accept incomplete and hand off
# 4. User makes informed decision
# 5. No hook blocker loop, clear next steps
#

# ============================================================================
# HOW TO USE THIS FILE
# ============================================================================
#
# 1. Run to see the example:
#    bash scripts/task-completion-example.sh
#
# 2. Adapt to your issue in your own script:
#    - Copy the register_dod_item calls
#    - Add your specific items and blocker types
#    - Execute your work and mark_dod_complete() as you go
#    - Before calling task_complete, validate_definition_of_done()
#
# 3. For Issue #984 specifically:
#    bash scripts/task-completion-example.sh | tee artifacts/dod-validation.log
#    gh issue comment 984 --repo kushin77/code-server --body-file artifacts/dod-validation.log
#

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
