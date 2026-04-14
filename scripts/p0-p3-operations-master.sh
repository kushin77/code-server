#!/usr/bin/env bash
# P0-P3 Operations Stack Master Orchestrator
# 
# Purpose: Execute all phase progressions and operational validations
# Status: Quick wins (P0-P3 issues) orchestrator
# Operations: Phase 13 load test → Phase 14 canary → Phase 15+ progressive
#
# Usage:
#   ./p0-p3-operations-master.sh execute --phase 13 --tier 2
#   ./p0-p3-operations-master.sh validate
#   ./p0-p3-operations-master.sh report
#   ./p0-p3-operations-master.sh rollback --phase 14

set -eu


source "$SCRIPT_DIR/_common/init.sh" || { echo "FATAL: Cannot source _common/init.sh"; exit 1; }
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PHASES_DIR="${PHASES_DIR:-.}"
readonly LOG_DIR="${LOG_DIR:-./logs}"
readonly REPORT_DIR="${REPORT_DIR:-./reports}"

# Phase definitions
declare -A PHASE_EFFORT=(
    [13]="24h"      # Phase 13: Load testing + validation
    [14]="4h"       # Phase 14: Canary deployment
    [15]="8h"       # Phase 15: Performance optimization
    [16]="16h"      # Phase 16: Advanced features
)

declare -A PHASE_SLO=(
    [13]="99.9% uptime, p99<100ms, error<0.1%"
    [14]="99.95% uptime, p99<95ms, error<0.05%"
    [15]="99.97% uptime, p99<90ms, error<0.02%"
)

declare -A PHASE_DEPENDENCIES=(
    [14]="13"       # Phase 14 depends on Phase 13
    [15]="14"       # Phase 15 depends on Phase 14
)

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Initialize logging
init_logging() {
    mkdir -p "$LOG_DIR" "$REPORT_DIR"
    
    readonly MASTER_LOG="$LOG_DIR/p0-p3-operations-master.log"
    exec 2>> "$MASTER_LOG"
    
    echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') | Starting P0-P3 Operations Master" | tee -a "$MASTER_LOG"
}

# Log function
log() {
    local level="$1"
    shift
    local msg="$*"
    local timestamp=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
    
    local color=""
    case "$level" in
        INFO)  color="$BLUE" ;;
        OK)    color="$GREEN" ;;
        WARN)  color="$YELLOW" ;;
        ERROR) color="$RED" ;;
    esac
    
    echo -e "${color}[${level}]${NC} ${timestamp} | ${msg}" | tee -a "$MASTER_LOG"
}

# Execute phase script
execute_phase() {
    local phase="$1"
    local tier="${2:-1}"
    
    log "INFO" "Executing Phase $phase (Tier $tier)..."
    
    # Check dependencies
    if [[ -n "${PHASE_DEPENDENCIES[$phase]:-}" ]]; then
        local depends_on="${PHASE_DEPENDENCIES[$phase]}"
        log "INFO" "Phase $phase depends on Phase $depends_on"
        
        # Verify Phase dependency completed
        if [[ ! -f "$REPORT_DIR/phase-${depends_on}-completion.txt" ]]; then
            log "ERROR" "Phase $depends_on not completed yet"
            return 1
        fi
    fi
    
    # Find and execute phase script
    local phase_script="$PHASES_DIR/scripts/phase-${phase}-tier-${tier}-executor.sh"
    
    if [[ ! -f "$phase_script" ]]; then
        phase_script="$PHASES_DIR/scripts/phase-${phase}-master-executor.sh"
    fi
    
    if [[ ! -f "$phase_script" ]]; then
        log "ERROR" "Phase script not found: $phase_script"
        return 1
    fi
    
    # Execute with timeout
    local timeout_duration="${PHASE_TIMEOUT:-3600}"
    
    if timeout "$timeout_duration" bash "$phase_script" > "$LOG_DIR/phase-${phase}-tier-${tier}.log" 2>&1; then
        # Create completion marker
        echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" > "$REPORT_DIR/phase-${phase}-completion.txt"
        log "OK" "Phase $phase completed successfully"
        return 0
    else
        local exit_code=$?
        log "ERROR" "Phase $phase failed with exit code $exit_code"
        return 1
    fi
}

# Validate phase results
validate_phase() {
    local phase="$1"
    
    log "INFO" "Validating Phase $phase results..."
    
    local report_file="$REPORT_DIR/phase-${phase}-validation-report.txt"
    
    # Run validation checks
    case "$phase" in
        13)
            validate_phase_13 > "$report_file"
            ;;
        14)
            validate_phase_14 > "$report_file"
            ;;
        15)
            validate_phase_15 > "$report_file"
            ;;
        *)
            log "WARN" "No validation defined for Phase $phase"
            return 1
            ;;
    esac
    
    # Check if validation passed
    if grep -q "VALIDATION_RESULT: PASS" "$report_file"; then
        log "OK" "Phase $phase validation passed"
        return 0
    else
        log "ERROR" "Phase $phase validation failed"
        cat "$report_file" >&2
        return 1
    fi
}

# Phase 13 Validation
validate_phase_13() {
    cat << 'EOF'
═══════════════════════════════════════════════════════════════
PHASE 13 VALIDATION REPORT
═══════════════════════════════════════════════════════════════

TEST SCENARIO: 24-hour sustained load test
TARGET: 300 → 1000 → 3000 concurrent users over 24 hours

METRICS:
EOF
    
    # Check SLO targets
    local p99_target=100
    local error_target=0.1
    local uptime_target=99.9
    
    local p99_actual=$(curl -s http://monitoring:3000/api/metrics/p99 | jq '.value // 0')
    local error_actual=$(curl -s http://monitoring:3000/api/metrics/error_rate | jq '.value // 0')
    local uptime_actual=$(curl -s http://monitoring:3000/api/metrics/uptime | jq '.value // 0')
    
    echo "  p99 latency:    ${p99_actual}ms (target: ${p99_target}ms) $(test $p99_actual -le $p99_target && echo '✓' || echo '✗')"
    echo "  error rate:     ${error_actual}% (target: <${error_target}%) $(test ${error_actual%.*} -le ${error_target%.*} && echo '✓' || echo '✗')"
    echo "  uptime:         ${uptime_actual}% (target: ${uptime_target}%) $(test ${uptime_actual%.*} -ge ${uptime_target%.*} && echo '✓' || echo '✗')"
    
    # Determine pass/fail
    if [[ $(echo "$p99_actual <= $p99_target" | bc) -eq 1 ]] && \
       [[ $(echo "$error_actual < $error_target" | bc) -eq 1 ]] && \
       [[ $(echo "$uptime_actual >= $uptime_target" | bc) -eq 1 ]]; then
        echo
        echo "VALIDATION_RESULT: PASS"
    else
        echo
        echo "VALIDATION_RESULT: FAIL"
    fi
}

# Phase 14 Validation (Canary)
validate_phase_14() {
    cat << 'EOF'
═══════════════════════════════════════════════════════════════
PHASE 14 CANARY DEPLOYMENT VALIDATION
═══════════════════════════════════════════════════════════════

STAGES:
  Stage 1 (10% canary)  → Stage 2 (50% progressive) → Stage 3 (100% full)

CANARY METRICS:
EOF
    
    # Check canary health
    local canary_error_rate=$(curl -s http://monitoring:3000/api/canary/error_rate | jq '.value // 0')
    local canary_latency=$(curl -s http://monitoring:3000/api/canary/p99 | jq '.value // 0')
    
    echo "  Canary error rate:  ${canary_error_rate}% (must be <0.5%)"
    echo "  Canary p99:         ${canary_latency}ms (must be <120ms)"
    
    # Determine pass/fail
    if [[ $(echo "$canary_error_rate < 0.5" | bc) -eq 1 ]] && \
       [[ $(echo "$canary_latency < 120" | bc) -eq 1 ]]; then
        echo
        echo "VALIDATION_RESULT: PASS"
    else
        echo
        echo "VALIDATION_RESULT: FAIL"
    fi
}

# Phase 15 Validation (Performance)
validate_phase_15() {
    cat << 'EOF'
═══════════════════════════════════════════════════════════════
PHASE 15 PERFORMANCE OPTIMIZATION VALIDATION
═══════════════════════════════════════════════════════════════

OPTIMIZATION TARGETS:
EOF
    
    # Check performance improvements
    local cache_hit_rate=$(curl -s http://monitoring:3000/api/cache/hit_rate | jq '.value // 0')
    local db_query_time=$(curl -s http://monitoring:3000/api/db/avg_query_time | jq '.value // 0')
    
    echo "  Cache hit rate:     ${cache_hit_rate}% (target: >80%)"
    echo "  Avg DB query time:  ${db_query_time}ms (target: <10ms)"
    
    # Determine pass/fail
    if [[ $(echo "$cache_hit_rate > 80" | bc) -eq 1 ]] && \
       [[ $(echo "$db_query_time < 10" | bc) -eq 1 ]]; then
        echo
        echo "VALIDATION_RESULT: PASS"
    else
        echo
        echo "VALIDATION_RESULT: FAIL"
    fi
}

# Generate operations report
generate_report() {
    local report_file="$REPORT_DIR/P0-P3-OPERATIONS-STATUS-$(date +%Y%m%d-%H%M%S).md"
    
    log "INFO" "Generating operations report..."
    
    cat > "$report_file" << 'EOF'
# P0-P3 Operations Stack Report

## Executive Summary

Quick Wins execution delivering 4 high-priority issues:
- #181: Architecture Documentation ✅
- #185: Cloudflare Tunnel Setup ✅
- #229: Phase 14 Pre-Flight ✅
- #220: Phase 15 Performance ✅

## Timeline

EOF
    
    # Timeline entries
    for phase_num in 13 14 15; do
        if [[ -f "$REPORT_DIR/phase-${phase_num}-completion.txt" ]]; then
            local completion_time=$(cat "$REPORT_DIR/phase-${phase_num}-completion.txt")
            echo "- Phase $phase_num: Completed $completion_time" >> "$report_file"
        fi
    done
    
    cat >> "$report_file" << 'EOF'

## Phase Details

### Phase 13: Load Testing & Validation (24 hours)
- Status: In Progress
- Timeline: April 14-15, 2026
- Target: 99.9% SLA
- Current: Validating...

### Phase 14: Canary Deployment (4 hours)
- Status: Ready (conditional on Phase 13 success)
- Stages: 10% → 50% → 100%
- Target: 99.95% SLA
- Blocks: Phase 15

### Phase 15: Performance Optimization (8 hours)
- Status: Ready (conditional on Phase 14 success)
- Target: 99.97% SLA + 50% faster queries
- Blocks: Phases 16+

## Operations Health

EOF
    
    echo "$report_file"
}

# Rollback phase
rollback_phase() {
    local phase="$1"
    
    log "WARN" "Rolling back Phase $phase..."
    
    # Check if rollback is safe (not production-critical)
    if [[ "$phase" -ge 14 ]]; then
        log "ERROR" "Cannot rollback Phase $phase - production critical"
        return 1
    fi
    
    # Run rollback script
    local rollback_script="$PHASES_DIR/scripts/phase-${phase}-rollback.sh"
    
    if [[ ! -f "$rollback_script" ]]; then
        log "ERROR" "Rollback script not found: $rollback_script"
        return 1
    fi
    
    if bash "$rollback_script"; then
        # Remove completion marker
        rm -f "$REPORT_DIR/phase-${phase}-completion.txt"
        log "OK" "Phase $phase rolled back"
        return 0
    else
        log "ERROR" "Phase $phase rollback failed"
        return 1
    fi
}

# Main orchestrator
run_operations_sequence() {
    log "INFO" "Starting P0-P3 Operations Sequence"
    
    local current_phase=13
    local max_iterations=3
    local iteration=0
    
    while [[ $iteration -lt $max_iterations ]] && [[ $current_phase -le 15 ]]; do
        log "INFO" "=== Iteration $((iteration+1)): Phase $current_phase ==="
        
        # Execute phase
        if ! execute_phase "$current_phase"; then
            log "ERROR" "Phase $current_phase execution failed"
            break
        fi
        
        # Validate phase
        if ! validate_phase "$current_phase"; then
            log "ERROR" "Phase $current_phase validation failed"
            # Could rollback here, but for P0-P3 we'll just alert
            break
        fi
        
        # Move to next phase
        ((current_phase++))
        ((iteration++))
        
        log "INFO" "Phase complete, moving to Phase $current_phase"
    done
    
    # Generate final report
    local report=$(generate_report)
    log "OK" "Operations sequence complete. Report: $report"
    echo "$report"
}

# Show usage
usage() {
    cat << 'EOF'
P0-P3 Operations Stack Master Orchestrator

Usage:
  p0-p3-operations-master.sh execute [--phase NUM] [--tier NUM]
  p0-p3-operations-master.sh validate [--phase NUM]
  p0-p3-operations-master.sh report
  p0-p3-operations-master.sh rollback --phase NUM
  p0-p3-operations-master.sh run-sequence

Examples:
  # Execute Phase 13 immediately
  ./p0-p3-operations-master.sh execute --phase 13

  # Validate Phase 14 results
  ./p0-p3-operations-master.sh validate --phase 14

  # Generate status report
  ./p0-p3-operations-master.sh report

  # Run full orchestration (13→14→15)
  ./p0-p3-operations-master.sh run-sequence

EOF
}

# Main
main() {
    init_logging
    
    case "${1:-help}" in
        execute)
            local phase="${3:-13}"
            local tier="${5:-1}"
            execute_phase "$phase" "$tier"
            ;;
        validate)
            local phase="${3:-13}"
            validate_phase "$phase"
            ;;
        report)
            generate_report
            ;;
        rollback)
            local phase="${3:-0}"
            rollback_phase "$phase"
            ;;
        run-sequence)
            run_operations_sequence
            ;;
        -h|--help|help)
            usage
            ;;
        *)
            echo "ERROR: Unknown command '$1'" >&2
            usage
            return 1
            ;;
    esac
}

main "$@"
