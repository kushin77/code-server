#!/bin/bash
# agent-safeguards.sh - Enforce agent execution boundaries
# Source this before performing major autonomous work

set -e

# Error handling
trap 'echo "Safeguards error at line $LINENO"; exit 1' ERR
trap 'rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

# Load safeguard configuration
if [[ -f ".env.agent-safeguards" ]]; then
    source .env.agent-safeguards
fi

# Initialize decision log
log_decision() {
    local msg="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    if [[ "${AGENT_LOG_LEVEL}" == "verbose" ]]; then
        echo "[${timestamp}] ${msg}" | tee -a "${AGENT_DECISION_LOG}"
    fi
}

# Check emergency stop
if [[ "${AGENT_EMERGENCY_STOP}" == "true" ]]; then
    echo "⚠️  AGENT_EMERGENCY_STOP is set - halting execution"
    exit 1
fi

# Verify safeguards are enabled
if [[ "${AGENT_SAFEGUARDS_ENABLED}" != "true" ]]; then
    log_decision "WARNING: Agent safeguards disabled - proceeding without boundaries"
fi

# Enforce task scope
enforce_task_scope() {
    local task_desc="$1"
    
    if [[ "${AGENT_TASK_SCOPE}" == "stated_goal_only" ]]; then
        log_decision "Task: ${task_desc} - Scope is STATED_GOAL_ONLY (will stop after completion)"
        return 0
    elif [[ "${AGENT_TASK_SCOPE}" == "full_handoff" ]]; then
        log_decision "Task: ${task_desc} - Scope is FULL_HANDOFF (will deliver and ask for next step)"
        return 0
    fi
}

# Check file creation limits
check_file_limit() {
    local file_count="$1"
    local max="${MAX_FILES_PER_OPERATION:-10}"
    
    if [[ ${file_count} -gt ${max} ]]; then
        log_decision "WARNING: About to create ${file_count} files (limit: ${max}) - requires confirmation"
        
        if [[ "${REQUIRE_CONFIRMATION_FOR}" == *"doc_generation"* ]]; then
            echo "⚠️  Creating ${file_count} files exceeds limit of ${max}"
            echo "Safeguard: REQUIRE_CONFIRMATION_FOR=doc_generation is active"
            return 1
        fi
    fi
    return 0
}

# Check git commit limits
check_commit_limit() {
    local commit_count="$1"
    local max="${MAX_GIT_COMMITS_PER_TASK:-2}"
    
    if [[ ${commit_count} -gt ${max} ]]; then
        log_decision "WARNING: About to create ${commit_count} commits (limit: ${max}) - requires confirmation"
        
        if [[ "${REQUIRE_CONFIRMATION_FOR}" == *"git_deployment"* ]]; then
            echo "⚠️  Creating ${commit_count} commits exceeds limit of ${max}"
            echo "Safeguard: REQUIRE_CONFIRMATION_FOR=git_deployment is active"
            return 1
        fi
    fi
    return 0
}

# Check auto-expansion behavior
prevent_auto_expansion() {
    local expansion_desc="$1"
    
    if [[ "${AGENT_AUTO_EXPANSION_ENABLED}" != "true" ]]; then
        log_decision "BLOCKED: Auto-expansion attempt - ${expansion_desc}"
        echo "❌ Auto-expansion is DISABLED in safeguards"
        echo "   ${expansion_desc}"
        echo "   To enable, explicitly request with count (e.g., 'expand to phase 700')"
        return 1
    fi
    return 0
}

# Explain major decision
explain_and_confirm() {
    local decision="$1"
    
    if [[ "${AGENT_EXPLAIN_DECISIONS}" == "true" ]]; then
        log_decision "EXPLAINING: ${decision}"
        echo "ℹ️  About to execute: ${decision}"
        echo "   (Set AGENT_EXPLAIN_DECISIONS=false to skip confirmations)"
        return 0
    fi
    return 0
}

# Report task completion
report_completion() {
    local scope="${AGENT_TASK_SCOPE}"
    
    if [[ "${AGENT_MUST_REPORT_COMPLETION}" == "true" ]]; then
        log_decision "Task completed - reporting via task_complete"
        echo "✅ Task complete (Scope: ${scope})"
    fi
}

# Check for auto-loop
check_auto_loop() {
    if [[ "${AGENT_AUTO_LOOP_PREVENTION}" == "true" ]]; then
        log_decision "Auto-loop prevention active - agent must receive new input for next task"
        return 0
    fi
    return 0
}

export -f log_decision
export -f enforce_task_scope
export -f check_file_limit
export -f check_commit_limit
export -f prevent_auto_expansion
export -f explain_and_confirm
export -f report_completion
export -f check_auto_loop

log_decision "Agent safeguards initialized - Mode: ${AGENT_MODE}, Scope: ${AGENT_TASK_SCOPE}"
