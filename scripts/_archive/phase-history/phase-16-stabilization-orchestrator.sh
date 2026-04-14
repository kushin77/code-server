#!/bin/bash

################################################################################
# Phase 16: Team Training & Stabilization Master Orchestrator
#
# Objective: Orchestrate all Phase 16 components:
#   1. Team training module execution
#   2. 24-hour baseline monitoring (background)
#   3. Incident response drill coordination
#   4. Final assessment and sign-off
#
# Usage: bash scripts/phase-16-stabilization-orchestrator.sh [--quick|--full]
#        --quick: 2-hour training + 4-hour monitoring demo
#        --full: Complete 24-hour phase (default)
#
################################################################################

set -e

# Configuration
MODE="${1:-full}"
PRODUCTION_HOST="192.168.168.31"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="$PROJECT_DIR/phase-16-execution"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Functions
log() { echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"; }
success() { echo -e "${GREEN}✓${NC} $1"; }
error() { echo -e "${RED}✗${NC} $1"; }
section() { echo -e "\n${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━${NC}"; echo -e "${MAGENTA}$1${NC}"; echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━${NC}\n"; }

mkdir -p "$OUTPUT_DIR"
MASTER_LOG="$OUTPUT_DIR/phase-16-master-$(date +%Y%m%d-%H%M%S).log"

{
    log "========================================"
    log "Phase 16: Team Training & Stabilization"
    log "========================================"
    log "Mode: $MODE"
    log "Production Host: $PRODUCTION_HOST"
    log "Start Time: $(date)"
    log ""

    # ========================================================================
    # STAGE 1: PRE-FLIGHT VALIDATION
    # ========================================================================

    section "STAGE 1: PRE-FLIGHT VALIDATION"

    log "Checking infrastructure state..."

    # Check host reachability
    if ping -c 1 -W 2 $PRODUCTION_HOST &> /dev/null; then
        success "Production host reachable"
    else
        error "Cannot reach $PRODUCTION_HOST - aborting"
        exit 1
    fi

    # Check docker
    CONTAINERS=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no akushnir@$PRODUCTION_HOST \
        "docker ps -q 2>/dev/null | wc -l")
    
    if [ "$CONTAINERS" -ge 10 ]; then
        success "Infrastructure healthy: $CONTAINERS containers running"
    else
        error "Only $CONTAINERS containers running (expected 11+)"
        exit 1
    fi

    log "Pre-flight validation complete"
    echo ""

    # ========================================================================
    # STAGE 2: TEAM TRAINING
    # ========================================================================

    section "STAGE 2: TEAM TRAINING MATERIALS"

    log "Generating training package..."
    bash "$PROJECT_DIR/scripts/phase-16-team-training.sh" > "$OUTPUT_DIR/training.log" 2>&1

    success "Training materials ready in: phase-16-training/"
    log "  - architecture-briefing.txt (15 min)"
    log "  - dashboard-walkthrough.txt (20 min)"
    log "  - sre-runbook-summary.txt (30 min)"
    log "  - drill-1-latency-spike.txt (30 min)"
    log "  - drill-2-service-failure.txt (30 min)"
    log "  - drill-3-security-incident.txt (45 min)"
    echo ""

    # ========================================================================
    # STAGE 3: BASELINE MONITORING
    # ========================================================================

    section "STAGE 3: BASELINE MONITORING (BACKGROUND)"

    log "Starting 24-hour metrics collection..."

    if [ "$MODE" = "quick" ]; then
        DURATION=4
        log "Quick mode: 4-hour baseline"
    else
        DURATION=24
        log "Full mode: 24-hour baseline"
    fi

    nohup bash "$PROJECT_DIR/scripts/phase-16-baseline-monitoring.sh" \
        "$OUTPUT_DIR/metrics" $DURATION > "$OUTPUT_DIR/monitoring.log" 2>&1 &

    MONITORING_PID=$!
    success "Monitoring started (PID: $MONITORING_PID)"
    log "Collecting metrics every 60 seconds to: $OUTPUT_DIR/metrics/"
    echo ""

    # ========================================================================
    # STAGE 4: EXECUTION TIMELINE
    # ========================================================================

    section "PHASE 16 TIMELINE ($MODE MODE)"

    if [ "$MODE" = "quick" ]; then
        log "Hour 0-1: Team Training Modules (65 min total)"
        log "  [ ] Architecture overview"
        log "  [ ] Dashboard walkthrough"
        log "  [ ] SRE runbooks"
        log ""
        log "Hour 1-3: Incident Drills (105 min total)"
        log "  [ ] Drill 1: Latency spike"
        log "  [ ] Drill 2: Service failure"
        log "  [ ] Drill 3: Security incident"
        log ""
        log "Hour 3-4: Observation & Assessment"
        log "  [ ] Monitor 4-hour baseline"
        log "  [ ] Quick sign-off"
        echo ""
        log "✓ Expected completion: 4 hours from start"
    else
        log "Hours 0-2: Team Onboarding "
        log "Hours 2-6: Incident Response Drills"
        log "Hours 6-24: Continuous Baseline Monitoring"
        log "Hours 24+: Final Assessment & Sign-Off"
        echo ""
        log "✓ Expected completion: April 14, 2026, 19:30 UTC"
    fi
    echo ""

    # ========================================================================
    # STAGE 5: DASHBOARD ACCESS
    # ========================================================================

    section "STAGE 5: LIVE DASHBOARD ACCESS"

    log "Grafana Dashboards:"
    log "  URL: http://$PRODUCTION_HOST:3000"
    log "  Performance: /d/phase-15-performance"
    log "  SLO Compliance: /d/slo-compliance"
    log ""
    log "Key Metrics to Monitor:"
    log "  p99 latency: <50ms (yellow >100ms, red >200ms)"
    log "  Error rate: <0.05% (yellow >0.1%)"
    log "  Throughput: 250+ req/s sustained"
    log "  Container health: All running"
    echo ""

    # ========================================================================
    # SUCCESS CRITERIA
    # ========================================================================

    section "PHASE 16 GO/NO-GO CRITERIA"

    cat > "$OUTPUT_DIR/success-criteria.txt" << 'EOF'
PHASE 16 SUCCESS CRITERIA (ALL MUST PASS)

Infrastructure Stability:
 [ ] Zero unplanned container restarts
 [ ] All services maintain health status
 [ ] 99.9%+ availability achieved
 [ ] No data loss events

Performance SLOs:
 [ ] p50 latency <30ms
 [ ] p99 latency <50ms (threshold 100ms)
 [ ] Error rate <0.05% (threshold 0.1%)
 [ ] Throughput 300+ req/s

Monitoring & Alerts:
 [ ] All alerts functioning
 [ ] Alert response <2 minutes
 [ ] Zero false positives
 [ ] Dashboard metrics current

Team Readiness:
 [ ] All training completed
 [ ] Drills executed successfully
 [ ] Team confidence 90%+
 [ ] On-call ready

FINAL DECISION: GO TO PRODUCTION ✓
EOF

    success "Success criteria documented: $OUTPUT_DIR/success-criteria.txt"
    echo ""

    # ========================================================================
    # SUMMARY
    # ========================================================================

    section "PHASE 16 ORCHESTRATOR - INITIATED ✓"

    log "Status: Phase 16 execution started successfully"
    log ""
    log "Output Location: $OUTPUT_DIR/"
    log "Monitoring PID: $MONITORING_PID"
    log "Monitoring Duration: $DURATION hours"
    log ""
    log "NEXT STEPS:"
    log "1. Review phase-16-training/ materials with team"
    log "2. Execute incident response drills (guided scenarios)"
    log "3. Monitor dashboard continuously during baseline period"
    log "4. Review metrics in $OUTPUT_DIR/metrics/ (hourly)"
    log "5. Assess team competency and confidence"
    log "6. Make GO/NO-GO decision based on success criteria"
    log ""
    log "Master log: $MASTER_LOG"

} | tee "$MASTER_LOG"

success "Phase 16 orchestration initialized"
log "Full output saved to: $MASTER_LOG"
