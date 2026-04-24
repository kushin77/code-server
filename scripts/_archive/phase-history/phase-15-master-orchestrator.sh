#!/bin/bash

################################################################################
# Phase 15: Advanced Performance & Load Testing - Master Orchestrator
#
# PURPOSE: End-to-end orchestration of Phase 15 deployment and validation
#
# COMPONENTS:
#   1. Redis cache layer deployment
#   2. Advanced observability stack
#   3. Extended load testing (quick or full)
#   4. SLO validation and reporting
#
# USAGE:
#   bash scripts/phase-15-master-orchestrator.sh [--quick|--extended|--report]
#
# OPTIONS:
#   --quick      : Run 30-minute quick validation
#   --extended   : Run 24+ hour extended testing
#   --report     : Generate analysis report only
#   --no-cache   : Skip Redis cache deployment
#   --no-obsv    : Skip observability deployment
#   (default)    : Full deployment without tests
#
# TIMELINE:
#   Full deployment: ~30 minutes
#   Quick tests: ~45 minutes
#   Extended tests: 24+ hours
#
################################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() { echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"; }
success() { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }
error() { echo -e "${RED}✗${NC} $1"; }

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="/tmp/phase-15"
LOG_FILE="$LOG_DIR/orchestrator-$(date +%s).log"

# Options
MODE="full"
DEPLOY_CACHE=true
DEPLOY_OBSV=true
RUN_TESTS=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --quick)
            MODE="quick"
            RUN_TESTS=true
            shift
            ;;
        --extended)
            MODE="extended"
            RUN_TESTS=true
            shift
            ;;
        --report)
            MODE="report"
            shift
            ;;
        --no-cache)
            DEPLOY_CACHE=false
            shift
            ;;
        --no-obsv)
            DEPLOY_OBSV=false
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Create log directory
mkdir -p "$LOG_DIR"

log "=========================================="
log "Phase 15: Master Orchestrator Starting"
log "=========================================="
log "Mode: $MODE"
log "Deploy Cache: $DEPLOY_CACHE"
log "Deploy Observability: $DEPLOY_OBSV"
log "Run Tests: $RUN_TESTS"
log "Log File: $LOG_FILE"
log ""

# Save execution start time
START_TIME=$(date +%s)

# ============================================================================
# PRE-FLIGHT VALIDATION
# ============================================================================

log "Step 1: Pre-flight Validation..."

if ! command -v docker &> /dev/null; then
    error "Docker not found. Please install Docker."
    exit 1
fi
success "Docker found"

if ! docker-compose ps &> /dev/null; then
    error "docker-compose not responding. Please check Docker daemon."
    exit 1
fi
success "docker-compose available"

# Check Phase 14 infrastructure
PHASE14_SERVICES=$(docker-compose ps --services 2>/dev/null | wc -l)
if [ "$PHASE14_SERVICES" -lt 5 ]; then
    warn "Phase 14 services not fully deployed. Expected 6+, found $PHASE14_SERVICES"
    warn "Continuing anyway (observability deployment may fail)"
else
    success "Phase 14 infrastructure healthy ($PHASE14_SERVICES services)"
fi

log "Pre-flight validation complete"
echo ""

# ============================================================================
# REDIS CACHE DEPLOYMENT (Optional)
# ============================================================================

if [ "$DEPLOY_CACHE" = true ]; then
    log "Step 2: Deploying Redis Cache Layer..."
    
    if [ -f "$PROJECT_DIR/docker-compose-phase-15.yml" ]; then
        log "Found docker-compose-phase-15.yml"
        
        # Deploy redis cache
        if docker-compose -f "$PROJECT_DIR/docker-compose-phase-15.yml" up -d 2>&1 | tee -a "$LOG_FILE"; then
            sleep 3
            
            # Verify redis
            if echo "ping" | nc -w 1 localhost 6379 2>/dev/null || [ $? -eq 0 ]; then
                success "Redis cache deployed and responding"
            else
                warn "Redis deployed but not responding to ping (may still be initializing)"
            fi
        else
            error "Failed to deploy Redis cache"
            exit 1
        fi
    else
        error "docker-compose-phase-15.yml not found"
        exit 1
    fi
    
    log "Redis deployment complete"
    echo ""
fi

# ============================================================================
# OBSERVABILITY DEPLOYMENT (Optional)
# ============================================================================

if [ "$DEPLOY_OBSV" = true ]; then
    log "Step 3: Deploying Advanced Observability..."
    
    if [ -f "$SCRIPT_DIR/phase-15-advanced-observability.sh" ]; then
        if bash "$SCRIPT_DIR/phase-15-advanced-observability.sh" 2>&1 | tee -a "$LOG_FILE"; then
            success "Advanced observability deployed"
        else
            error "Failed to deploy advanced observability"
            exit 1
        fi
    else
        error "phase-15-advanced-observability.sh not found"
        exit 1
    fi
    
    log "Observability deployment complete"
    echo ""
fi

# ============================================================================
# HEALTH VERIFICATION
# ============================================================================

log "Step 4: Health Verification..."

# Check Phase 14 services
P14_CHECK=$(curl -s -k https://localhost/health 2>/dev/null | grep -q "ok" && echo "pass" || echo "fail")
if [ "$P14_CHECK" = "pass" ]; then
    success "Phase 14 health check passed"
else
    warn "Phase 14 health check inconclusive"
fi

# Check Redis if deployed
if [ "$DEPLOY_CACHE" = true ]; then
    REDIS_CHECK=$(echo "ping" | nc -w 1 localhost 6379 2>/dev/null && echo "pass" || echo "fail")
    if [ "$REDIS_CHECK" = "pass" ]; then
        success "Redis health check passed"
    else
        warn "Redis health check failed (may still be initializing)"
    fi
fi

# Check observability if deployed
if [ "$DEPLOY_OBSV" = true ]; then
    GRAFANA_CHECK=$(curl -s http://localhost:3000/api/health 2>/dev/null | grep -q '"database":"ok"' && echo "pass" || echo "fail")
    if [ "$GRAFANA_CHECK" = "pass" ]; then
        success "Grafana health check passed"
    else
        warn "Grafana health check failed"
    fi
fi

log "Health verification complete"
echo ""

# ============================================================================
# LOAD TESTING (Optional)
# ============================================================================

if [ "$RUN_TESTS" = true ]; then
    log "Step 5: Executing Load Tests (Mode: $MODE)..."
    
    if [ -f "$SCRIPT_DIR/phase-15-extended-load-test.sh" ]; then
        TEST_ARGS=""
        case $MODE in
            quick)
                TEST_ARGS="--quick"
                ;;
            extended)
                TEST_ARGS="--extended"
                ;;
        esac
        
        if bash "$SCRIPT_DIR/phase-15-extended-load-test.sh" $TEST_ARGS 2>&1 | tee -a "$LOG_FILE"; then
            success "Load tests completed successfully"
        else
            error "Load tests failed or were interrupted"
            exit 1
        fi
    else
        error "phase-15-extended-load-test.sh not found"
        exit 1
    fi
    
    log "Load testing complete"
    echo ""
fi

# ============================================================================
# REPORT GENERATION
# ============================================================================

if [ "$MODE" = "report" ] || [ "$RUN_TESTS" = true ]; then
    log "Step 6: Generating Report..."
    
    REPORT_FILE="$LOG_DIR/phase-15-report-$(date +%s).txt"
    
    {
        echo "=========================================="
        echo "Phase 15 Execution Report"
        echo "=========================================="
        echo "Timestamp: $(date -u)"
        echo "Mode: $MODE"
        echo ""
        echo "Deployment Status:"
        echo "  Cache Layer:     $([ "$DEPLOY_CACHE" = true ] && echo "✓ Deployed" || echo "✗ Skipped")"
        echo "  Observability:   $([ "$DEPLOY_OBSV" = true ] && echo "✓ Deployed" || echo "✗ Skipped")"
        echo "  Tests Executed:  $([ "$RUN_TESTS" = true ] && echo "✓ Yes ($MODE)" || echo "✗ No")"
        echo ""
        echo "Infrastructure Status:"
        docker-compose ps --services 2>/dev/null | while read svc; do
            STATUS=$(docker-compose ps "$svc" 2>/dev/null | tail -1 | awk '{print $NF}')
            echo "  $svc: $STATUS"
        done
        echo ""
        echo "Metrics:"
        echo "  Redis Memory: $(echo "INFO memory" | nc -w 1 localhost 6379 2>/dev/null | head -5 || echo "N/A")"
        echo ""
        echo "Next Steps:"
        if [ "$RUN_TESTS" = true ]; then
            echo "  1. Review dashboards at http://localhost:3000/d/phase-15-performance"
            echo "  2. Check metrics in /tmp/phase-15/metrics.log"
            echo "  3. Make GO/NO-GO decision"
            echo "  4. If GO: Proceed to Phase 16"
        else
            echo "  1. Deploy infrastructure further (see PHASE-15-EXECUTION-PLAN.md)"
            echo "  2. Run tests: bash $SCRIPT_DIR/phase-15-extended-load-test.sh --quick"
            echo "  3. Review results and dashboards"
        fi
        echo ""
        echo "=========================================="
    } | tee "$REPORT_FILE"
    
    log "Report written to: $REPORT_FILE"
fi

# ============================================================================
# COMPLETION SUMMARY
# ============================================================================

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo ""
log "=========================================="
log "Phase 15: Master Orchestrator Complete"
log "=========================================="
success "Execution Duration: $(($DURATION / 60))m $(($DURATION % 60))s"
log ""

case $MODE in
    full)
        log "Infrastructure deployed. Ready for testing."
        log "Next: bash scripts/phase-15-extended-load-test.sh [--quick|--extended]"
        ;;
    quick)
        log "Quick tests completed. Review dashboards:"
        log "  Grafana: http://localhost:3000/d/phase-15-performance"
        log "  Logs: /tmp/phase-15/"
        ;;
    extended)
        log "Extended tests completed. Analysis available in:"
        log "  Report: $LOG_DIR/phase-15-report-*.txt"
        log "  Metrics: $LOG_DIR/metrics.log"
        log "  Dashboards: http://localhost:3000"
        ;;
    report)
        log "Report generated: $REPORT_FILE"
        ;;
esac

log "Full logs: $LOG_FILE"
log ""
success "Phase 15 Master Orchestrator execution complete!"

exit 0
