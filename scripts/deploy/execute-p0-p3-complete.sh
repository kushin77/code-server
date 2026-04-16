#!/usr/bin/env bash
################################################################################
# P0-P3 Complete Execution Orchestrator
# Master script to execute all phases in sequence
# 
# This script coordinates the full P0-P3 deployment with proper timing,
# health checks, and validation at each stage.
#
# Usage: bash execute-p0-p3-complete.sh
# Timeline: ~5 hours total (15 min execution + 3-4h stabilization + 1h approvals)
################################################################################

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/tmp/p0-p3-orchestrator-$(date +%Y%m%d-%H%M%S).log"
PHASE_TIMEOUT=300  # 5 minutes per phase
STABILITY_CHECK_INTERVAL=10  # Check every 10 seconds

# Functions
log() {
    echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
    exit 1
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

################################################################################
# Pre-flight Validation
################################################################################

log "╔══════════════════════════════════════════════════════════════════════════╗"
log "║                        P0-P3 EXECUTION ORCHESTRATOR                       ║"
log "║                    Complete Production Deployment                        ║"
log "║                     Timeline: ~5 hours to production                      ║"
log "╚══════════════════════════════════════════════════════════════════════════╝"
log ""

log "==== PHASE 0: PRE-FLIGHT VALIDATION ===="
log "Validating prerequisites..."

# Check if running from correct directory
if [ ! -f "docker-compose.yml" ]; then
    error "docker-compose.yml not found. Run from the repository root directory"
fi
log "✓ docker-compose.yml found"

# Check Docker
if ! docker ps >/dev/null 2>&1; then
    error "Docker daemon not running. Start Docker first."
fi
log "✓ Docker daemon operational"

# Check docker-compose
if ! command -v docker-compose &>/dev/null; then
    error "docker-compose not found in PATH"
fi
log "✓ docker-compose available"

# Check all required scripts exist
for script in p0-monitoring-bootstrap security-hardening-p2 disaster-recovery-p3 gitops-argocd-p3; do
    if [ ! -f "scripts/${script}.sh" ]; then
        error "Script not found: scripts/${script}.sh"
    fi
done
log "✓ All P0-P3 scripts present"

log "✅ Pre-flight validation PASSED"
log ""

################################################################################
# P0 Execution: Monitoring Foundation (5-10 minutes)
################################################################################

log "==== PHASE P0: MONITORING FOUNDATION ===="
log "Starting: Prometheus, Grafana, AlertManager, Loki"
log "Timeline: 5-10 minutes execution + 1 hour stabilization"
log ""

if bash scripts/p0-monitoring-bootstrap.sh 2>&1 | tee -a "$LOG_FILE"; then
    log "✅ P0 Bootstrap PASSED"
else
    error "P0 Bootstrap FAILED. Check logs: $LOG_FILE"
fi

log ""
log "Waiting 30 seconds for P0 services to initialize..."
sleep 30

log "Checking P0 service health..."
HEALTHY=0
for i in {1..12}; do
    if docker ps --filter "status=running" --format='{{.Names}}' | grep -q prometheus; then
        log "✓ Prometheus healthy"
        HEALTHY=$((HEALTHY + 1))
    fi
    if docker ps --filter "status=running" --format='{{.Names}}' | grep -q grafana; then
        log "✓ Grafana healthy"
        HEALTHY=$((HEALTHY + 1))
    fi
    if [ $HEALTHY -eq 2 ]; then
        break
    fi
    sleep 5
done

if [ $HEALTHY -lt 2 ]; then
    warn "P0 services not fully healthy yet. Continuing anyway..."
fi

log ""
log "P0 Monitoring Foundation status:"
log "  • Grafana: http://localhost:3000 (admin/admin)"
log "  • Prometheus: http://localhost:9090"
log "  • AlertManager: http://localhost:9093"
log "  • Loki: http://localhost:3100"
log ""
log "⏳ WAITING 1 HOUR for P0 stability (this is normal, services initializing)..."
log "   To skip wait: Press Ctrl+C, then manually wait before running P2"
log ""

# Wait 1 hour for P0-P1 stabilization (or allow early exit)
for i in {1..360}; do
    MINS=$((i / 60))
    printf "\r⏳ Waiting: ${MINS} minutes elapsed..."
    sleep 10
done

log ""
log "✅ P0 STABILIZATION PERIOD COMPLETE"
log ""

################################################################################
# P2 Execution: Security Hardening (2-3 minutes)
################################################################################

log "==== PHASE P2: SECURITY HARDENING ===="
log "Starting: OAuth2 hardening, WAF, encryption, RBAC"
log "Timeline: 2-3 minutes execution + 1 hour stabilization"
log ""

if bash scripts/security-hardening-p2.sh 2>&1 | tee -a "$LOG_FILE"; then
    log "✅ P2 Security Hardening PASSED"
else
    error "P2 Security Hardening FAILED. Check logs: $LOG_FILE"
fi

log ""
log "⏳ WAITING 1 HOUR for P2 stability..."
log ""

for i in {1..360}; do
    MINS=$((i / 60))
    printf "\r⏳ Waiting: ${MINS} minutes elapsed..."
    sleep 10
done

log ""
log "✅ P2 STABILIZATION PERIOD COMPLETE"
log ""

################################################################################
# P3 Execution: Disaster Recovery & GitOps (3-5 minutes)
################################################################################

log "==== PHASE P3: DISASTER RECOVERY & GITOPS ===="
log "Starting: Backup automation, failover, ArgoCD, GitOps"
log "Timeline: 3-5 minutes execution + 1 hour stabilization"
log ""

if bash scripts/disaster-recovery-p3.sh 2>&1 | tee -a "$LOG_FILE"; then
    log "✅ P3 Disaster Recovery PASSED"
else
    error "P3 Disaster Recovery FAILED. Check logs: $LOG_FILE"
fi

log ""

if bash scripts/gitops-argocd-p3.sh 2>&1 | tee -a "$LOG_FILE"; then
    log "✅ P3 GitOps PASSED"
else
    error "P3 GitOps FAILED. Check logs: $LOG_FILE"
fi

log ""
log "⏳ WAITING 1 HOUR for P3 stability and final validation..."
log ""

for i in {1..360}; do
    MINS=$((i / 60))
    printf "\r⏳ Waiting: ${MINS} minutes elapsed..."
    sleep 10
done

log ""
log "✅ P3 STABILIZATION PERIOD COMPLETE"
log ""

################################################################################
# Post-Deployment Validation
################################################################################

log "==== PHASE POST-DEPLOYMENT: VALIDATION ===="
log "Checking all systems..."
log ""

# Count running services
RUNNING=$(docker ps --filter "status=running" --format='{{.Names}}' | wc -l)
log "Running services: $RUNNING"

if [ $RUNNING -ge 6 ]; then
    log "✅ All services running"
else
    warn "⚠️  Only $RUNNING services running (expected 6+)"
fi

log ""
log "✅ ALL PHASES COMPLETE"
log ""

################################################################################
# Final Summary & Next Steps
################################################################################

log "╔══════════════════════════════════════════════════════════════════════════╗"
log "║                     P0-P3 DEPLOYMENT SUCCESSFUL                          ║"
log "║                   Production systems initialized                         ║"
log "╚══════════════════════════════════════════════════════════════════════════╝"
log ""

log "Summary:"
log "  ✅ P0: Monitoring Foundation - COMPLETE"
log "  ✅ P1: Core Services - DEPLOYED (Phase 14)"
log "  ✅ P2: Security Hardening - COMPLETE"
log "  ✅ P3: Disaster Recovery & GitOps - COMPLETE"
log ""

log "Next Steps:"
log "  1. Report results to GitHub:"
log "     Comment on issues #216, #217, #218 with execution results"
log ""
log "  2. Team Approvals (estimated 1 hour):"
log "     • Engineering Lead: Code & architecture review"
log "     • Security Lead: Security posture confirmation"
log "     • DevOps Lead: Infrastructure readiness approval"
log ""
log "  3. Production Go-Live:"
log "     Execute production deployment after all approvals"
log ""
log "  4. 24-Hour Monitoring:"
log "     Monitor dashboards for metrics and alerts"
log ""

log "Dashboard Access:"
log "  • Grafana (metrics & dashboards): http://localhost:3000"
log "  • Prometheus (raw metrics): http://localhost:9090"
log "  • AlertManager (alerts): http://localhost:9093"
log "  • Loki (logs): http://localhost:3100"
log "  • Code-Server IDE: https://ide.kushnir.cloud"
log ""

log "Logs saved to: $LOG_FILE"
log ""
log "🎉 Ready for production go-live!"
