#!/usr/bin/env bash
# @file        scripts/lib/task-completion-framework.sh
# @module      task-management/completion-validation
# @description Enhanced task completion framework that validates DoD before marking complete
# @owner       copilot/task-automation
# @status      PRODUCTION
#

set -euo pipefail

# ============================================================================
# TASK COMPLETION FRAMEWORK
# ============================================================================
# Purpose: Prevent premature task_complete calls by validating Definition of Done
# Context: Hook blocker taught us that agents should not call task_complete until
#          ALL Definition of Done items are ACTUALLY complete, not just planned
# ============================================================================

# Ensure sourcing from correct directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ============================================================================
# DEFINITION OF DONE VALIDATION REGISTRY
# ============================================================================

declare -A DoD_ITEMS
declare -A DoD_STATUS
declare -A DoD_BLOCKER_TYPE
declare -A DoD_NOTES

# Register a DoD item for validation
# Usage: register_dod_item <id> <description> <blocker_type> [notes]
# blocker_type: agent|credentials|manual|external|none
register_dod_item() {
    local item_id="$1"
    local description="$2"
    local blocker_type="$3"
    local notes="${4:-}"
    
    DoD_ITEMS["$item_id"]="$description"
    DoD_BLOCKER_TYPE["$item_id"]="$blocker_type"
    DoD_NOTES["$item_id"]="$notes"
    DoD_STATUS["$item_id"]="pending"
}

# Mark a DoD item as complete
# Usage: mark_dod_complete <id>
mark_dod_complete() {
    local item_id="$1"
    if [[ -z "${DoD_ITEMS[$item_id]:-}" ]]; then
        log_error "DoD item '$item_id' not registered"
        return 1
    fi
    DoD_STATUS["$item_id"]="complete"
}

# Mark a DoD item as blocked
# Usage: mark_dod_blocked <id> <reason>
mark_dod_blocked() {
    local item_id="$1"
    local reason="$2"
    if [[ -z "${DoD_ITEMS[$item_id]:-}" ]]; then
        log_error "DoD item '$item_id' not registered"
        return 1
    fi
    DoD_STATUS["$item_id"]="blocked"
    DoD_NOTES["$item_id"]="$reason"
}

# ============================================================================
# VALIDATION LOGIC
# ============================================================================

# Validate Definition of Done
# Returns: 0 if all DoD items complete, 1 if any are blocked/pending
validate_definition_of_done() {
    local all_complete=0
    local blocked_count=0
    local pending_count=0
    
    log_info "=== DEFINITION OF DONE VALIDATION ==="
    
    for item_id in "${!DoD_ITEMS[@]}"; do
        local status="${DoD_STATUS[$item_id]}"
        local description="${DoD_ITEMS[$item_id]}"
        local blocker="${DoD_BLOCKER_TYPE[$item_id]}"
        local notes="${DoD_NOTES[$item_id]}"
        
        case "$status" in
            complete)
                log_info "✅ $item_id: $description"
                ;;
            blocked)
                log_warn "⏳ $item_id (BLOCKED): $description"
                log_warn "   Type: $blocker | Reason: $notes"
                ((blocked_count++))
                all_complete=1
                ;;
            pending)
                log_warn "⏸️  $item_id (PENDING): $description"
                log_warn "   Type: $blocker"
                ((pending_count++))
                all_complete=1
                ;;
        esac
    done
    
    log_info ""
    log_info "Summary: ${#DoD_ITEMS[@]} items | Complete: $(grep -c 'complete' <(printf '%s\n' "${DoD_STATUS[@]}") || echo 0) | Blocked: $blocked_count | Pending: $pending_count"
    
    return "$all_complete"
}

# Diagnose blockers and suggest resolution paths
# Usage: diagnose_completion_blockers [show_solutions]
diagnose_completion_blockers() {
    local show_solutions="${1:-true}"
    
    local has_credential_blockers=0
    local has_manual_blockers=0
    local has_external_blockers=0
    
    log_warn ""
    log_warn "=== COMPLETION BLOCKER ANALYSIS ==="
    log_warn ""
    
    for item_id in "${!DoD_ITEMS[@]}"; do
        local status="${DoD_STATUS[$item_id]}"
        if [[ "$status" != "complete" ]]; then
            local blocker_type="${DoD_BLOCKER_TYPE[$item_id]}"
            local description="${DoD_ITEMS[$item_id]}"
            
            case "$blocker_type" in
                credentials)
                    has_credential_blockers=1
                    log_warn "❌ $item_id: Blocked by CREDENTIALS"
                    log_warn "   Description: $description"
                    ;;
                manual)
                    has_manual_blockers=1
                    log_warn "❌ $item_id: Blocked by MANUAL STEPS"
                    log_warn "   Description: $description"
                    ;;
                external)
                    has_external_blockers=1
                    log_warn "❌ $item_id: Blocked by EXTERNAL DEPENDENCY"
                    log_warn "   Description: $description"
                    ;;
                agent)
                    log_error "❌ $item_id: AGENT-EXECUTABLE WORK INCOMPLETE"
                    log_error "   Description: $description"
                    log_error "   This must be completed before task_complete can be called"
                    ;;
            esac
        fi
    done
    
    if [[ "$show_solutions" == "true" ]]; then
        log_warn ""
        log_warn "=== RESOLUTION PATHS ==="
        
        if [[ $has_credential_blockers -eq 1 ]]; then
            log_warn ""
            log_warn "PATH A: Provide Credentials to Agent"
            log_warn "  Risk: Agent has broad credential access"
            log_warn "  Timeline: 15-20 minutes"
            log_warn "  Recommendation: ❌ NOT RECOMMENDED (security best practice)"
        fi
        
        if [[ $has_manual_blockers -eq 1 ]] || [[ $has_credential_blockers -eq 1 ]]; then
            log_warn ""
            log_warn "PATH B: Operations Team Executes Remaining Steps"
            log_warn "  Risk: LOW (credentials stay with appropriate team)"
            log_warn "  Timeline: 30-45 minutes"
            log_warn "  Recommendation: ✅ PREFERRED (follows security best practices)"
        fi
        
        if [[ $has_external_blockers -eq 1 ]]; then
            log_warn ""
            log_warn "PATH C: Await External Dependency Completion"
            log_warn "  Risk: Task remains incomplete until dependency resolves"
            log_warn "  Timeline: Depends on external factor"
            log_warn "  Recommendation: Document and hand off to next team member"
        fi
    fi
}

# Get human-readable completion report
# Usage: get_completion_report [format]
get_completion_report() {
    local format="${1:-text}"
    
    local total=${#DoD_ITEMS[@]}
    local complete_count=0
    local blocked_count=0
    local pending_count=0
    
    for status in "${DoD_STATUS[@]}"; do
        case "$status" in
            complete) ((complete_count++)) ;;
            blocked) ((blocked_count++)) ;;
            pending) ((pending_count++)) ;;
        esac
    done
    
    case "$format" in
        text)
            echo "Definition of Done: $complete_count/$total complete"
            echo "  - Complete: $complete_count"
            echo "  - Blocked: $blocked_count"
            echo "  - Pending: $pending_count"
            ;;
        json)
            printf '{"total":%d,"complete":%d,"blocked":%d,"pending":%d}\n' \
                "$total" "$complete_count" "$blocked_count" "$pending_count"
            ;;
        markdown)
            echo "| Status | Count |"
            echo "|--------|-------|"
            echo "| Complete | $complete_count |"
            echo "| Blocked | $blocked_count |"
            echo "| Pending | $pending_count |"
            echo "| **Total** | **$total** |"
            ;;
    esac
}

# ============================================================================
# SAFE TASK_COMPLETE WRAPPER
# ============================================================================

# Safely call task_complete after validating Definition of Done
# Usage: safe_task_complete <issue_id> [force]
# force: if "force", skip validation and call task_complete anyway
safe_task_complete() {
    local issue_id="${1:-}"
    local force="${2:-false}"
    
    if [[ -z "$issue_id" ]]; then
        log_error "Usage: safe_task_complete <issue_id> [force]"
        return 1
    fi
    
    log_info ""
    log_info "=== TASK COMPLETION DECISION ==="
    
    # Validate Definition of Done
    if ! validate_definition_of_done; then
        log_warn ""
        log_warn "Definition of Done is INCOMPLETE"
        
        # Diagnose blockers
        diagnose_completion_blockers true
        
        if [[ "$force" == "force" ]]; then
            log_warn ""
            log_warn "⚠️  FORCING task_complete despite incomplete DoD"
            log_warn "Reason: --force flag specified"
            log_warn ""
            log_warn "Report to issue #$issue_id:"
            get_completion_report markdown
            return 0
        else
            log_error ""
            log_error "❌ CANNOT CALL task_complete - Definition of Done is incomplete"
            log_error ""
            log_error "Choose an unblocking path:"
            log_error "  1. Run: safe_task_complete $issue_id force"
            log_error "  2. Or: Complete remaining DoD items and run: safe_task_complete $issue_id"
            return 1
        fi
    fi
    
    # All DoD items complete
    log_info ""
    log_info "✅ Definition of Done COMPLETE"
    log_info "🟢 READY TO MARK TASK COMPLETE"
    
    # Show completion report
    log_info ""
    get_completion_report markdown
    
    log_info ""
    log_info "Ready to call task_complete for issue #$issue_id"
    return 0
}

# ============================================================================
# EXPORTS
# ============================================================================

export -f register_dod_item
export -f mark_dod_complete
export -f mark_dod_blocked
export -f validate_definition_of_done
export -f diagnose_completion_blockers
export -f get_completion_report
export -f safe_task_complete
