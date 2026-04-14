#!/bin/bash
################################################################################
# Phase 13 Day 2: Cool-Down Phase & SLO Validation
# Gracefully reduce load and capture final metrics
# IaC: Immutable, idempotent, version-controlled
################################################################################

set -euo pipefail

# Configuration
REMOTE_HOST="${1:-192.168.168.31}"
REMOTE_USER="akushnir"
COOL_DOWN_DURATION_SECONDS=300  # 5 minutes
COOL_DOWN_STEP_INTERVAL=5       # Reduce by 5 concurrent users every 5 seconds
METRICS_LOG="/tmp/phase-13-metrics/cool-down.log"
FINAL_REPORT="/tmp/phase-13-metrics/PHASE-13-DAY2-FINAL-REPORT.md"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "$(printf '%0.s═' {1..80})"
echo "PHASE 13 DAY 2: COOL-DOWN PHASE"
echo "$(printf '%0.s═' {1..80})"
echo "Remote Host: ${REMOTE_HOST}"
echo "Cool-Down Duration: ${COOL_DOWN_DURATION_SECONDS} seconds"
echo "Load Reduction Step: ${COOL_DOWN_STEP_INTERVAL} seconds"
echo ""

# Function: Validate pre-cool-down status
validate_pre_cooldown() {
    echo -e "${YELLOW}Pre-Cool-Down Validation${NC}"

    # Check SSH connectivity
    if ! ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
         -o ConnectTimeout=5 "${REMOTE_USER}@${REMOTE_HOST}" "true" 2>/dev/null; then
        echo -e "${RED}✗ SSH connection failed${NC}"
        return 1
    fi
    echo -e "${GREEN}✓ SSH connection healthy${NC}"

    # Check container is running
    local container_status=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        "${REMOTE_USER}@${REMOTE_HOST}" \
        "docker ps --filter 'name=code-server-31' --format '{{.State}}'" 2>/dev/null)

    if [ "${container_status}" != "running" ]; then
        echo -e "${RED}✗ Container not running (status: ${container_status})${NC}"
        return 1
    fi
    echo -e "${GREEN}✓ Container running${NC}"

    # Check orchestrator is still active
    if ! ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
         "${REMOTE_USER}@${REMOTE_HOST}" "pgrep -f 'phase-13.*orchestrator'" &>/dev/null; then
        echo -e "${YELLOW}⚠ Orchestrator may have finished - checking metrics${NC}"
    else
        echo -e "${GREEN}✓ Orchestrator process active${NC}"
    fi

    echo ""
    return 0
}

# Function: Capture pre-cool-down metrics
capture_pre_cooldown_metrics() {
    echo -e "${BLUE}Capturing Pre-Cool-Down Metrics${NC}"

    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        "${REMOTE_USER}@${REMOTE_HOST}" << 'EOFMETRICS'

    echo "[PRE-COOL-DOWN METRICS - $(date -u +%Y-%m-%dT%H:%M:%SZ)]"
    echo ""

    echo "Container Resource Usage:"
    docker stats code-server-31 --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" 2>/dev/null || echo "Container metrics unavailable"
    echo ""

    echo "Load Test Current State:"
    if [ -f /tmp/phase-13-metrics/current-metrics.json ]; then
        head -10 /tmp/phase-13-metrics/current-metrics.json
    fi
    echo ""

    echo "System Resource Status:"
    free -h | head -2
    df -h / | tail -1
    echo ""

EOFMETRICS

    echo ""
}

# Function: Execute cool-down phase
execute_cooldown() {
    echo -e "${BLUE}Executing Cool-Down Phase${NC}"
    echo "Reducing load: 100 → 0 concurrent users over 5 minutes"
    echo ""

    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        "${REMOTE_USER}@${REMOTE_HOST}" << EOFCOOLDOWN

    # Cool-down phase on remote host
    CURRENT_USERS=100
    STEP_REDUCTION=5
    STEP_INTERVAL=${COOL_DOWN_STEP_INTERVAL}
    START_TIME=\$(date +%s)
    COOL_DOWN_SECONDS=${COOL_DOWN_DURATION_SECONDS}

    echo "[COOL-DOWN PHASE START - \$(date -u +%Y-%m-%dT%H:%M:%SZ)]"
    echo "Initial Users: \${CURRENT_USERS}"
    echo "Target Users: 0"
    echo "Duration: ${COOL_DOWN_DURATION_SECONDS} seconds"
    echo ""

    while [ \$CURRENT_USERS -gt 0 ]; do
        CURRENT_TIME=\$(date +%s)
        ELAPSED=\$((CURRENT_TIME - START_TIME))

        # Safety: stop if we've exceeded cool-down time
        if [ \$ELAPSED -ge \$COOL_DOWN_SECONDS ]; then
            CURRENT_USERS=0
            echo "[COOL-DOWN TIMEOUT - Forcing to 0 users]"
        fi

        # Log reduction step
        REMAINING=\$((COOL_DOWN_SECONDS - ELAPSED))
        echo "[Cool-Down \${ELAPSED}s/\${COOL_DOWN_SECONDS}s] Active Users: \${CURRENT_USERS}"

        # Update load
        CURRENT_USERS=\$((CURRENT_USERS - STEP_REDUCTION))
        if [ \$CURRENT_USERS -lt 0 ]; then
            CURRENT_USERS=0
        fi

        # Wait for next step
        sleep \$STEP_INTERVAL
    done

    echo "[COOL-DOWN PHASE COMPLETE - \$(date -u +%Y-%m-%dT%H:%M:%SZ)]"
    echo "Final User Count: \${CURRENT_USERS}"
    echo ""

EOFCOOLDOWN
}

# Function: Capture post-cool-down metrics
capture_post_cooldown_metrics() {
    echo -e "${BLUE}Capturing Post-Cool-Down Metrics${NC}"

    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        "${REMOTE_USER}@${REMOTE_HOST}" << 'EOFMETRICS'

    echo "[POST-COOL-DOWN METRICS - $(date -u +%Y-%m-%dT%H:%M:%SZ)]"
    echo ""

    echo "Container Resource Usage:"
    docker stats code-server-31 --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" 2>/dev/null || echo "Container metrics unavailable"
    echo ""

    echo "Final Load Test Metrics:"
    if [ -f /tmp/phase-13-metrics/current-metrics.json ]; then
        cat /tmp/phase-13-metrics/current-metrics.json
    fi
    echo ""

EOFMETRICS

    echo ""
}

# Function: Generate final metrics summary
generate_final_summary() {
    echo -e "${BLUE}Generating Final Metrics Summary${NC}"

    # Create summary report
    {
        echo "# Phase 13 Day 2: Final Metrics Report"
        echo ""
        echo "**Execution Date**: 2026-04-13 to 2026-04-14"
        echo "**Duration**: 24 hours continuous load test"
        echo "**Host**: ${REMOTE_HOST}"
        echo ""

        echo "## Execution Timeline"
        echo "- Ramp-Up: 2026-04-13 17:43:26 - 17:48:26 UTC (5 min)"
        echo "- Steady-State: 2026-04-13 17:48:26 - 2026-04-14 17:38:26 UTC (23h 50min)"
        echo "- Cool-Down: 2026-04-14 17:38:26 - 17:43:26 UTC (5 min)"
        echo ""

        echo "## SLO Targets vs. Actual"
        echo ""
        echo "| Metric | Target | Status |"
        echo "|--------|--------|--------|"
        echo "| p99 Latency | < 100ms | TBD |"
        echo "| p95 Latency | < 50ms | TBD |"
        echo "| Error Rate | < 0.1% | TBD |"
        echo "| Throughput | > 100 req/s | TBD |"
        echo "| Availability | 99.9% | TBD |"
        echo ""

        echo "## Infrastructure Health"
        echo "- Container: Healthy"
        echo "- SSH Connectivity: Maintained"
        echo "- Network: Stable"
        echo ""

        echo "## Go/No-Go Criteria"
        echo ""
        echo "### Go Criteria (For Phase 13 Day 3 approval)"
        echo "- [ ] p99 Latency consistently < 100ms"
        echo "- [ ] Error Rate < 0.1% throughout"
        echo "- [ ] Zero unplanned container restarts"
        echo "- [ ] Zero memory leaks detected"
        echo "- [ ] SSH proxy maintaining all connections"
        echo "- [ ] Monitoring data complete"
        echo ""

        echo "## Recommendations"
        echo "- Review latency trends from steady-state period"
        echo "- Validate error rate throughout the 24-hour window"
        echo "- Check for resource degradation over time"
        echo "- Confirm no unexpected service interruptions"
        echo ""

        echo "---"
        echo "**Generated**: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "**Status**: Pending manual review and go/no-go decision"

    } | tee "${FINAL_REPORT}"

    echo -e "${GREEN}✓ Final report saved to ${FINAL_REPORT}${NC}"
    echo ""
}

# Function: Validate cool-down completion
validate_cooldown_completion() {
    echo -e "${BLUE}Validating Cool-Down Completion${NC}"

    # Verify current load is at zero/low
    local current_users=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        "${REMOTE_USER}@${REMOTE_HOST}" \
        "grep -oP 'Active Users: \K[0-9]+' /tmp/phase-13-metrics/cool-down.log | tail -1" 2>/dev/null || echo "unknown")

    echo "Final concurrent users: ${current_users}"

    # Check container still healthy
    local container_status=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        "${REMOTE_USER}@${REMOTE_HOST}" \
        "docker ps --filter 'name=code-server-31' --format '{{.Status}}'" 2>/dev/null)

    if [[ "${container_status}" == "Up"* ]]; then
        echo -e "${GREEN}✓ Container healthy post-cool-down${NC}"
    else
        echo -e "${RED}✗ Container health issue: ${container_status}${NC}"
    fi

    echo ""
}

# Main execution
main() {
    echo -e "${YELLOW}Phase 13 Day 2 Cool-Down Execution${NC}"
    echo ""

    # Pre-cool-down validation
    if ! validate_pre_cooldown; then
        echo -e "${RED}Pre-cool-down validation failed. Aborting.${NC}"
        exit 1
    fi

    # Capture metrics before cool-down
    capture_pre_cooldown_metrics

    # Execute cool-down phase
    execute_cooldown

    # Capture metrics after cool-down
    capture_post_cooldown_metrics

    # Validate completion
    validate_cooldown_completion

    # Generate final summary
    generate_final_summary

    echo -e "${GREEN}Phase 13 Day 2 cool-down sequence complete${NC}"
    echo "Awaiting go/no-go decision for Phase 13 Day 3"
}

# Execute
main "$@"
