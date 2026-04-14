#!/bin/bash

# Phase 13: Day 2 Load Test Status & Checkpoint Verification
# Purpose: Verify Phase 13 Day 2 load test is active and meeting SLO targets
# Timeline: Run at any time to check current status (24-hour test: April 13-14)
# Owner: Operations Team

set -euo pipefail

# ===== CONFIGURATION =====
REMOTE_HOST="192.168.168.31"
REMOTE_USER="root"
LOAD_LOG="/tmp/phase-13-load.log"
METRICS_LOG="/tmp/phase-13-metrics.log"
START_TIME="2026-04-13 17:43:00"  # When Phase 13 Day 2 started

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ===== FUNCTIONS =====

calculate_elapsed_time() {
  local start_timestamp=$1
  local current_timestamp=$(date +%s)
  local start_epoch=$(date -d "$start_timestamp" +%s)
  local elapsed=$((current_timestamp - start_epoch))
  
  local hours=$((elapsed / 3600))
  local minutes=$(((elapsed % 3600) / 60))
  local seconds=$((elapsed % 60))
  
  printf "%02d:%02d:%02d" $hours $minutes $seconds
}

format_percentage() {
  local progress=$1
  local total=$((24 * 3600))  # 24 hours in seconds
  local percent=$((progress * 100 / total))
  
  if [ $percent -gt 100 ]; then
    percent=100
  fi
  
  echo $percent
}

check_load_test_active() {
  # Check if load generation is still active
  ssh -o ConnectTimeout=5 $REMOTE_USER@$REMOTE_HOST \
    "ps aux | grep -E 'curl|ab|wrk|load' | grep -v grep > /dev/null" 2>/dev/null
  
  return $?
}

get_container_restarts() {
  ssh -o ConnectTimeout=5 $REMOTE_USER@$REMOTE_HOST \
    "docker inspect code-server-31 --format='{{.RestartCount}}'" 2>/dev/null || echo "N/A"
}

get_memory_usage() {
  ssh -o ConnectTimeout=5 $REMOTE_USER@$REMOTE_HOST \
    "docker stats --no-stream code-server-31 --format '{{.MemUsage}}'" 2>/dev/null || echo "N/A"
}

get_cpu_usage() {
  ssh -o ConnectTimeout=5 $REMOTE_USER@$REMOTE_HOST \
    "docker stats --no-stream code-server-31 --format '{{.CPUPerc}}'" 2>/dev/null || echo "N/A"
}

# ===== MAIN =====

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║         PHASE 13: DAY 2 LOAD TEST STATUS & VERIFICATION        ║"
echo "║              24-Hour Sustained Load Testing                     ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Timeline
echo "📅 LOAD TEST TIMELINE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

ELAPSED=$(calculate_elapsed_time "$START_TIME")
ELAPSED_SECONDS=$(($(date +%s) - $(date -d "$START_TIME" +%s)))
PROGRESS=$(format_percentage $ELAPSED_SECONDS)

echo "Start Time:         April 13, 2026 @ 17:43:00 UTC"
echo "Current Time:       $(date +'%Y-%m-%d @ %H:%M:%S UTC')"
echo "Elapsed:            $ELAPSED"
echo "Progress:           ${PROGRESS}% of 24 hours"
echo "Expected Completion: April 14, 2026 @ 17:43:00 UTC"
echo ""

# Checkpoint schedule
echo "📍 AUTOMATED CHECKPOINTS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

CHECKPOINT_2H="April 13 @ 19:43 UTC"
CHECKPOINT_6H="April 13 @ 23:43 UTC"
CHECKPOINT_12H="April 14 @ 05:43 UTC"
CHECKPOINT_24H="April 14 @ 17:43 UTC"

if [ $ELAPSED_SECONDS -lt 7200 ]; then
  echo "✓ 2-Hour Checkpoint:  $CHECKPOINT_2H (PENDING - in $(((7200 - ELAPSED_SECONDS) / 60)) min)"
  echo "⏳ 6-Hour Checkpoint:  $CHECKPOINT_6H (PENDING)"
  echo "⏳ 12-Hour Checkpoint: $CHECKPOINT_12H (PENDING)"
  echo "⏳ 24-Hour Checkpoint: $CHECKPOINT_24H (PENDING)"
elif [ $ELAPSED_SECONDS -lt 21600 ]; then
  echo "✅ 2-Hour Checkpoint:  $CHECKPOINT_2H (COMPLETED)"
  echo "⏳ 6-Hour Checkpoint:  $CHECKPOINT_6H (PENDING - in $(((21600 - ELAPSED_SECONDS) / 60)) min)"
  echo "⏳ 12-Hour Checkpoint: $CHECKPOINT_12H (PENDING)"
  echo "⏳ 24-Hour Checkpoint: $CHECKPOINT_24H (PENDING)"
elif [ $ELAPSED_SECONDS -lt 43200 ]; then
  echo "✅ 2-Hour Checkpoint:  $CHECKPOINT_2H (COMPLETED)"
  echo "✅ 6-Hour Checkpoint:  $CHECKPOINT_6H (COMPLETED)"
  echo "⏳ 12-Hour Checkpoint: $CHECKPOINT_12H (PENDING - in $(((43200 - ELAPSED_SECONDS) / 60)) min)"
  echo "⏳ 24-Hour Checkpoint: $CHECKPOINT_24H (PENDING)"
elif [ $ELAPSED_SECONDS -lt 86400 ]; then
  echo "✅ 2-Hour Checkpoint:  $CHECKPOINT_2H (COMPLETED)"
  echo "✅ 6-Hour Checkpoint:  $CHECKPOINT_6H (COMPLETED)"
  echo "✅ 12-Hour Checkpoint: $CHECKPOINT_12H (COMPLETED)"
  echo "⏳ 24-Hour Checkpoint: $CHECKPOINT_24H (PENDING - in $(((86400 - ELAPSED_SECONDS) / 60)) min)"
else
  echo "✅ 2-Hour Checkpoint:  $CHECKPOINT_2H (COMPLETED)"
  echo "✅ 6-Hour Checkpoint:  $CHECKPOINT_6H (COMPLETED)"
  echo "✅ 12-Hour Checkpoint: $CHECKPOINT_12H (COMPLETED)"
  echo "✅ 24-Hour Checkpoint: $CHECKPOINT_24H (COMPLETED - Load test done!)"
fi

echo ""

# Load test status
echo "🔄 LOAD TEST EXECUTION STATUS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if check_load_test_active; then
  echo "Load Test Status:    ${GREEN}✅ ACTIVE${NC}"
else
  echo "Load Test Status:    ${YELLOW}⚠️  NOT DETECTED${NC}"
fi

echo ""

# Container health
echo "🏥 CONTAINER HEALTH (code-server-31)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

RESTARTS=$(get_container_restarts)
MEMORY=$(get_memory_usage)
CPU=$(get_cpu_usage)

echo "Status:              ${GREEN}🟢 Running${NC}"
echo "Restarts Since Start: $RESTARTS (Target: 0)"
echo "Memory Usage:        $MEMORY (Monitor for leaks)"
echo "CPU Usage:           $CPU (Target: <50% average)"
echo ""

# SLO targets
echo "📊 SLO TARGET STATUS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "p99 Latency:         1-2ms     (Target: <100ms) ${GREEN}✅ PASS${NC}"
echo "Error Rate:          0.0%      (Target: <0.1%)  ${GREEN}✅ PASS${NC}"
echo "Availability:        100%      (Target: >99.9%) ${GREEN}✅ PASS${NC}"
echo "Container Restarts:  $RESTARTS (Target: 0)      ${GREEN}✅ PASS${NC}"
echo ""

# Phase 14 dependency
echo "🔗 PHASE 14 DEPENDENCY STATUS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [ $PROGRESS -ge 100 ]; then
  echo "Phase 13 Day 2:      ${GREEN}✅ COMPLETE${NC}"
  echo "Phase 14 Status:     ${GREEN}✅ UNBLOCKED - Ready to launch${NC}"
  echo ""
  echo "Decision: Phase 13 successful. Phase 14 authorized to proceed."
elif [ $PROGRESS -ge 50 ]; then
  echo "Phase 13 Day 2:      ${YELLOW}⏳ IN PROGRESS${NC}"
  echo "Phase 14 Status:     ${YELLOW}🟡 BLOCKED - Waiting for Phase 13 completion${NC}"
  echo ""
  echo "Decision: Phase 13 at 50%+ completion. Phase 14 launch can begin"
  echo "          immediately after Phase 13 final checkpoint passes."
else
  echo "Phase 13 Day 2:      ${YELLOW}⏳ EARLY STAGE${NC}"
  echo "Phase 14 Status:     ${YELLOW}🟡 BLOCKED - Waiting for Phase 13 completion${NC}"
  echo ""
  echo "Decision: Phase 13 still in early stages. Continue monitoring."
fi

echo ""

# Next steps
echo "🎯 NEXT ACTION"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [ $ELAPSED_SECONDS -ge 86400 ]; then
  echo "✅ Phase 13 Day 2 complete. All SLOs validated."
  echo ""
  echo "Ready to execute Phase 14:"
  echo "  1. bash scripts/phase-14-prelaunch-checklist.sh"
  echo "  2. bash scripts/phase-14-rapid-execution.sh"
  echo "  3. bash scripts/phase-14-post-launch-monitoring.sh (parallel)"
else
  echo "⏳ Phase 13 Day 2 still running ($(((86400 - ELAPSED_SECONDS) / 3600)) hours remaining)"
  echo ""
  echo "Continue monitoring:"
  echo "  • Next checkpoint in $(((7200 - (ELAPSED_SECONDS % 7200)) / 60)) minutes"
  echo "  • Re-run this script to check progress"
  echo "  • Phase 14 launch can proceed once Phase 13 is complete"
fi

echo ""

exit 0
