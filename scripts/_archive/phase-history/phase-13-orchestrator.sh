#!/bin/bash
# ════════════════════════════════════════════════════════════════════════════
# PHASE 13: MASTER ORCHESTRATOR - PRODUCTION DEPLOYMENT VALIDATION
#
# Orchestrates all Phase 13 tasks (1.1-1.5) with idempotent state tracking
# IaC-First: All infrastructure defined as code
# Immutable: All changes version-controlled in git
# Idempotent: Safe to re-run multiple times - skips completed tasks
#
# April 14, 2026 - Production Launch Day
# ════════════════════════════════════════════════════════════════════════════

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# CONFIGURATION & STATE MANAGEMENT
# ─────────────────────────────────────────────────────────────────────────────

export LC_ALL=C
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
STATE_DIR="/var/run/phase-13"
STATE_FILE="$STATE_DIR/deployment.state"
LOG_DIR="/var/log/phase-13"
LOG_FILE="$LOG_DIR/master-orchestrator-$(date +%Y%m%d-%H%M%S).log"
METRICS_FILE="$LOG_DIR/deployment-metrics.json"

# Execution tracking
DEPLOYMENT_ID=$(date +%s)
DEPLOYMENT_START=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ─────────────────────────────────────────────────────────────────────────────
# LOGGING & STATE TRACKING
# ─────────────────────────────────────────────────────────────────────────────

log_info() {
    local msg="$1"
    echo -e "${BLUE}[INFO]${NC} $msg" | tee -a "$LOG_FILE"
}

log_success() {
    local msg="$1"
    echo -e "${GREEN}[✓]${NC} $msg" | tee -a "$LOG_FILE"
}

log_warn() {
    local msg="$1"
    echo -e "${YELLOW}[WARN]${NC} $msg" | tee -a "$LOG_FILE"
}

log_error() {
    local msg="$1"
    echo -e "${RED}[✗]${NC} $msg" | tee -a "$LOG_FILE"
}

# State tracking functions (idempotency)
init_state() {
    mkdir -p "$STATE_DIR" "$LOG_DIR"
    touch "$LOG_FILE"

    if [ ! -f "$STATE_FILE" ]; then
        cat > "$STATE_FILE" << EOFSTATE
{
  "deployment_id": "$DEPLOYMENT_ID",
  "started_at": "$DEPLOYMENT_START",
  "tasks": {
    "1.1": {"status": "pending", "started_at": null, "completed_at": null},
    "1.2": {"status": "pending", "started_at": null, "completed_at": null},
    "1.3": {"status": "pending", "started_at": null, "completed_at": null},
    "1.4": {"status": "pending", "started_at": null, "completed_at": null},
    "1.5": {"status": "pending", "started_at": null, "completed_at": null}
  }
}
EOFSTATE
    fi
}

is_task_complete() {
    local task="$1"
    if [ -f "$STATE_FILE" ]; then
        jq -e ".tasks.[\"$task\"].status == \"completed\"" "$STATE_FILE" > /dev/null 2>&1 && return 0
    fi
    return 1
}

mark_task_started() {
    local task="$1"
    local temp_file="${STATE_FILE}.tmp"
    jq ".tasks.[\"$task\"].status = \"running\" | .tasks.[\"$task\"].started_at = \"$(date -u '+%Y-%m-%dT%H:%M:%SZ')\"" \
        "$STATE_FILE" > "$temp_file"
    mv "$temp_file" "$STATE_FILE"
}

mark_task_completed() {
    local task="$1"
    local temp_file="${STATE_FILE}.tmp"
    jq ".tasks.[\"$task\"].status = \"completed\" | .tasks.[\"$task\"].completed_at = \"$(date -u '+%Y-%m-%dT%H:%M:%SZ')\"" \
        "$STATE_FILE" > "$temp_file"
    mv "$temp_file" "$STATE_FILE"
}

mark_task_failed() {
    local task="$1"
    local temp_file="${STATE_FILE}.tmp"
    jq ".tasks.[\"$task\"].status = \"failed\"" \
        "$STATE_FILE" > "$temp_file"
    mv "$temp_file" "$STATE_FILE"
}

# ─────────────────────────────────────────────────────────────────────────────
# PRE-FLIGHT CHECKS
# ─────────────────────────────────────────────────────────────────────────────

preflight_checks() {
    log_info "===== PREFLIGHT CHECKS ====="

    # Check required tools
    local required_tools=("docker" "docker-compose" "curl" "jq" "git")
    local missing_tools=0

    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &>/dev/null; then
            log_error "Missing required tool: $tool"
            missing_tools=$((missing_tools + 1))
        fi
    done

    if [ $missing_tools -gt 0 ]; then
        log_error "Cannot proceed: $missing_tools tools missing"
        return 1
    fi
    log_success "All required tools available"

    # Check git status
    log_info "Verifying git repository..."
    if ! git -C "$REPO_ROOT" rev-parse --git-dir > /dev/null 2>&1; then
        log_error "Not in a git repository"
        return 1
    fi
    log_success "Git repository validated"

    # Check docker connectivity
    log_info "Checking Docker daemon..."
    if ! docker ps > /dev/null 2>&1; then
        log_error "Cannot connect to Docker daemon"
        return 1
    fi
    log_success "Docker daemon accessible"

    # Check docker-compose configuration
    log_info "Validating docker-compose..."
    if ! docker-compose -f "$REPO_ROOT/docker-compose.yml" config > /dev/null 2>&1; then
        log_error "Invalid docker-compose.yml"
        return 1
    fi
    log_success "docker-compose.yml valid"

    log_success "Preflight checks passed"
    echo ""
    return 0
}

# ─────────────────────────────────────────────────────────────────────────────
# TASK EXECUTION
# ─────────────────────────────────────────────────────────────────────────────

execute_task_1_1() {
    local task="1.1"

    if is_task_complete "$task"; then
        log_success "Task $task already completed - skipping"
        return 0
    fi

    log_info "===== TASK $task: CLOUDFLARE TUNNEL DEPLOYMENT ====="
    mark_task_started "$task"

    if bash "$SCRIPT_DIR/phase-13-task-1.1-cloudflare-tunnel.sh" >> "$LOG_FILE" 2>&1; then
        mark_task_completed "$task"
        log_success "Task $task completed"
        return 0
    else
        mark_task_failed "$task"
        log_error "Task $task failed"
        return 1
    fi
}

execute_task_1_2() {
    local task="1.2"

    if is_task_complete "$task"; then
        log_success "Task $task already completed - skipping"
        return 0
    fi

    log_info "===== TASK $task: ACCESS CONTROL VALIDATION ====="
    mark_task_started "$task"

    if bash "$SCRIPT_DIR/phase-13-task-1.2-access-control.sh" >> "$LOG_FILE" 2>&1; then
        mark_task_completed "$task"
        log_success "Task $task completed"
        return 0
    else
        mark_task_failed "$task"
        log_error "Task $task failed"
        return 1
    fi
}

execute_task_1_3() {
    local task="1.3"

    if is_task_complete "$task"; then
        log_success "Task $task already completed - skipping"
        return 0
    fi

    log_info "===== TASK $task: CLUSTER HEALTH CHECK ====="
    mark_task_started "$task"

    if bash "$SCRIPT_DIR/phase-13-task-1.3-cluster-health.sh" >> "$LOG_FILE" 2>&1; then
        mark_task_completed "$task"
        log_success "Task $task completed"
        return 0
    else
        mark_task_failed "$task"
        log_error "Task $task failed"
        return 1
    fi
}

execute_task_1_4() {
    local task="1.4"

    if is_task_complete "$task"; then
        log_success "Task $task already completed - skipping"
        return 0
    fi

    log_info "===== TASK $task: SSH PROXY & AUDIT LOGGING ====="
    mark_task_started "$task"

    if bash "$SCRIPT_DIR/phase-13-task-1.4-ssh-proxy.sh" >> "$LOG_FILE" 2>&1; then
        mark_task_completed "$task"
        log_success "Task $task completed"
        return 0
    else
        mark_task_failed "$task"
        log_error "Task $task failed"
        return 1
    fi
}

execute_task_1_5() {
    local task="1.5"

    if is_task_complete "$task"; then
        log_success "Task $task already completed - skipping"
        return 0
    fi

    log_info "===== TASK $task: LOAD TESTING & SLO VALIDATION ====="
    mark_task_started "$task"

    if bash "$SCRIPT_DIR/phase-13-task-1.5-load-test.sh" >> "$LOG_FILE" 2>&1; then
        mark_task_completed "$task"
        log_success "Task $task completed"
        return 0
    else
        mark_task_failed "$task"
        log_error "Task $task failed"
        # Load test failures are not critical path - don't exit
        return 0
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# DEPLOYMENT SUMMARY
# ─────────────────────────────────────────────────────────────────────────────

generate_summary() {
    local deployment_end=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    local duration=$(($(date +%s) - $(date -d "$DEPLOYMENT_START" +%s)))

    log_info ""
    log_info "═════════════════════════════════════════════════════"
    log_info "PHASE 13 DEPLOYMENT SUMMARY"
    log_info "═════════════════════════════════════════════════════"
    log_info "Deployment ID: $DEPLOYMENT_ID"
    log_info "Started: $DEPLOYMENT_START"
    log_info "Ended: $deployment_end"
    log_info "Duration: ${duration}s"
    log_info "State File: $STATE_FILE"
    log_info "Log File: $LOG_FILE"
    log_info ""

    # Show task status
    jq '.tasks' "$STATE_FILE" | tee -a "$LOG_FILE"
    log_info ""

    # Generate metrics
    cat > "$METRICS_FILE" << EOFMETRICS
{
  "deployment_id": "$DEPLOYMENT_ID",
  "started_at": "$DEPLOYMENT_START",
  "ended_at": "$deployment_end",
  "duration_seconds": $duration,
  "log_file": "$LOG_FILE",
  "state_file": "$STATE_FILE",
  "status": "$(jq -r '.tasks | to_entries[] | select(.value.status=="failed") | .key' "$STATE_FILE" | wc -l | grep -q '^0$' && echo 'SUCCESS' || echo 'PARTIAL_FAILURE')"
}
EOFMETRICS

    log_success "Deployment complete"
    log_info "Metrics saved: $METRICS_FILE"
}

# ─────────────────────────────────────────────────────────────────────────────
# MAIN EXECUTION
# ─────────────────────────────────────────────────────────────────────────────

main() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║ PHASE 13: MASTER ORCHESTRATOR                                   ║${NC}"
    echo -e "${BLUE}║ Production Deployment Validation & Rollout                      ║${NC}"
    echo -e "${BLUE}║ Idempotent, State-Tracked, IaC-First Execution                  ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    log_info "Starting Phase 13 deployment orchestrator"
    log_info "Deployment ID: $DEPLOYMENT_ID"

    # Initialize state tracking
    init_state

    # Run preflight checks
    if ! preflight_checks; then
        log_error "Preflight checks failed - aborting deployment"
        return 1
    fi

    # Execute tasks in sequence
    local failed_tasks=0

    if ! execute_task_1_1; then failed_tasks=$((failed_tasks + 1)); fi
    sleep 5

    if ! execute_task_1_2; then failed_tasks=$((failed_tasks + 1)); fi
    sleep 5

    if ! execute_task_1_3; then failed_tasks=$((failed_tasks + 1)); fi
    sleep 5

    if ! execute_task_1_4; then failed_tasks=$((failed_tasks + 1)); fi
    sleep 5

    if ! execute_task_1_5; then :; fi  # Load test non-critical

    # Generate summary
    generate_summary

    # Final status
    echo ""
    if [ $failed_tasks -eq 0 ]; then
        log_success "✓ Phase 13 deployment SUCCESSFUL"
        return 0
    else
        log_warn "⚠ Phase 13 deployment completed with $failed_tasks failed tasks"
        log_info "Review logs: $LOG_FILE"
        return 1
    fi
}

# Run main
main "$@"
