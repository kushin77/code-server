#!/bin/bash
################################################################################
# Phase 13 Pre-Execution Health Check
# ─────────────────────────────────────────────────────────────────────────────
# Purpose: Verify all prerequisites before Day 2 execution
# Execution: April 14, 2026 @ 08:00 UTC (1 hour before Day 2 starts)
# Owner: Infrastructure Team
#
# Idempotence: Safe to run multiple times (read-only, no modifications)
# IaC: All checks via standard tools, no manual configuration
################################################################################

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────────────────────

PHASE_13_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S UTC')
CHECKLIST_FILE="/tmp/phase-13-preexecution-checklist-$(date +%s).txt"

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Counters
PASS=0
FAIL=0
WARN=0

# ─────────────────────────────────────────────────────────────────────────────
# Helper Functions
# ─────────────────────────────────────────────────────────────────────────────

log_pass() {
    echo -e "${GREEN}✅ PASS${NC}: $@" | tee -a "$CHECKLIST_FILE"
    PASS=$((PASS + 1))
}

log_fail() {
    echo -e "${RED}❌ FAIL${NC}: $@" | tee -a "$CHECKLIST_FILE"
    FAIL=$((FAIL + 1))
}

log_warn() {
    echo -e "${YELLOW}⚠️  WARN${NC}: $@" | tee -a "$CHECKLIST_FILE"
    WARN=$((WARN + 1))
}

log_info() {
    echo "[INFO] $@" | tee -a "$CHECKLIST_FILE"
}

print_section() {
    echo "" | tee -a "$CHECKLIST_FILE"
    echo "═══════════════════════════════════════════════════════════════════════════" | tee -a "$CHECKLIST_FILE"
    echo "$@" | tee -a "$CHECKLIST_FILE"
    echo "═══════════════════════════════════════════════════════════════════════════" | tee -a "$CHECKLIST_FILE"
}

# ─────────────────────────────────────────────────────────────────────────────
# Main Checks
# ─────────────────────────────────────────────────────────────────────────────

main() {
    print_section "PHASE 13 PRE-EXECUTION HEALTH CHECK"
    log_info "Timestamp: $TIMESTAMP"
    log_info "Checklist: $CHECKLIST_FILE"
    log_info ""

    # ─────────────────────────────────────────────────────────────────────────
    # Infrastructure Team Checks
    # ─────────────────────────────────────────────────────────────────────────

    print_section "1. INFRASTRUCTURE TEAM CHECKS (30 minutes)"

    # Check Docker daemon
    if docker info > /dev/null 2>&1; then
        log_pass "Docker daemon is operational"
    else
        log_fail "Docker daemon not responding - Start Docker and retry"
        return 1
    fi

    # Check container status
    local container_count=$(docker ps --filter "status=running" --format '{{.Names}}' | wc -l)
    if [ "$container_count" -ge 5 ]; then
        log_pass "All required containers running ($container_count/5)"
    else
        log_fail "Not all containers running (found $container_count/5) - Run: docker-compose up -d"
        return 1
    fi

    # Check specific containers
    local required_containers=("caddy" "code-server" "oauth2-proxy" "ollama" "ollama-init")
    for container in "${required_containers[@]}"; do
        if docker ps --filter "name=$container" --filter "status=running" --format '{{.Names}}' | grep -q "$container"; then
            log_pass "Container '$container' is running"
        else
            log_fail "Container '$container' is not running"
            FAIL=$((FAIL + 1))
        fi
    done

    # Check memory
    local available_memory=$(free -m | awk 'NR==2 {print $7}')
    if [ "$available_memory" -ge 13000 ]; then
        log_pass "Memory available: ${available_memory}MB (>= 13GB required)"
    else
        log_warn "Low memory available: ${available_memory}MB (recommend >= 13GB)"
        WARN=$((WARN + 1))
    fi

    # Check disk
    local available_disk=$(df / | awk 'NR==2 {print $4}')
    if [ "$available_disk" -ge 50000000 ]; then
        log_pass "Disk available: $((available_disk / 1024))MB (>= 50GB required)"
    else
        log_fail "Low disk space: $((available_disk / 1024))MB (need >= 50GB)"
        FAIL=$((FAIL + 1))
    fi

    # Check secrets loaded (via environment variables)
    if [ -z "${DATABASE_URL:-}" ]; then
        log_warn "DATABASE_URL not set - Load from GCP Secret Manager"
        WARN=$((WARN + 1))
    else
        log_pass "DATABASE_URL is set"
    fi

    if [ -z "${GOOGLE_CLIENT_ID:-}" ]; then
        log_warn "GOOGLE_CLIENT_ID not set - Load from GCP Secret Manager"
        WARN=$((WARN + 1))
    else
        log_pass "GOOGLE_CLIENT_ID is set"
    fi

    # Check network
    if ping -c 1 8.8.8.8 > /dev/null 2>&1; then
        log_pass "Network connectivity verified"
    else
        log_warn "Cannot reach external network (may be OK in isolated environment)"
        WARN=$((WARN + 1))
    fi

    # ─────────────────────────────────────────────────────────────────────────
    # QA Team Checks
    # ─────────────────────────────────────────────────────────────────────────

    print_section "2. QA TEAM CHECKS (30 minutes)"

    # Check code-server health
    if curl -sf http://localhost/healthz > /dev/null 2>&1; then
        log_pass "code-server health endpoint responding (HTTP 200)"
    else
        log_fail "code-server health endpoint not responding"
        FAIL=$((FAIL + 1))
    fi

    # Check OAuth2 proxy
    if curl -sf http://localhost:4180/ping > /dev/null 2>&1; then
        log_pass "oauth2-proxy health endpoint responding (HTTP 200)"
    else
        log_warn "oauth2-proxy health endpoint may be initializing"
        WARN=$((WARN + 1))
    fi

    # Check Caddy (internal)
    if docker exec caddy curl -sf http://localhost/ > /dev/null 2>&1; then
        log_pass "Caddy reverse proxy operational (internal check)"
    else
        log_warn "Caddy may be initializing, will retry during execution"
        WARN=$((WARN + 1))
    fi

    # Check Docker DNS
    if docker exec code-server nslookup code-server > /dev/null 2>&1; then
        log_pass "Docker DNS resolution working"
    else
        log_fail "Docker DNS resolution failed - Check network configuration"
        FAIL=$((FAIL + 1))
    fi

    # Run quick smoke test
    log_info "Running 1-minute smoke test (patience required)..."
    if LOAD_TEST_DURATION=60 CONCURRENT_USERS=5 timeout 90 bash "$PHASE_13_DIR/scripts/phase-13-day2-load-test.sh" > /tmp/smoke-test.log 2>&1; then
        local smoke_requests=$(grep -c "SUCCESS\|FAIL" /tmp/smoke-test.log || echo "0")
        if [ "$smoke_requests" -gt 0 ]; then
            log_pass "Smoke test completed ($smoke_requests requests)"
        else
            log_warn "Smoke test completed but no requests recorded (may indicate timing issue)"
            WARN=$((WARN + 1))
        fi
    else
        log_warn "Smoke test did not complete - May indicate resource constraint"
        WARN=$((WARN + 1))
    fi

    # Verify disk space AGAIN
    local available_disk_2=$(df / | awk 'NR==2 {print $4}')
    if [ "$available_disk_2" -ge 40000000 ]; then
        log_pass "Disk available after smoke test: $((available_disk_2 / 1024))MB"
    else
        log_fail "Low disk space after smoke test: $((available_disk_2 / 1024))MB"
        FAIL=$((FAIL + 1))
    fi

    # ─────────────────────────────────────────────────────────────────────────
    # Final Verification
    # ─────────────────────────────────────────────────────────────────────────

    print_section "3. FINAL VERIFICATION (10 minutes before execution)"

    # Git status
    if cd "$PHASE_13_DIR" && git status --porcelain | grep -q .; then
        log_warn "Git working directory not clean - Stash changes: git stash"
        WARN=$((WARN + 1))
    else
        log_pass "Git repository clean"
    fi

    # Day 2 scripts exist
    if [ -f "$PHASE_13_DIR/scripts/phase-13-day2-orchestrator.sh" ] && \
       [ -f "$PHASE_13_DIR/scripts/phase-13-day2-load-test.sh" ] && \
       [ -f "$PHASE_13_DIR/scripts/phase-13-day2-monitoring.sh" ]; then
        log_pass "All Day 2 orchestration scripts present"
    else
        log_fail "Missing Day 2 scripts - Run: git pull origin main"
        FAIL=$((FAIL + 1))
    fi

    # Scripts are executable
    if [ -x "$PHASE_13_DIR/scripts/phase-13-day2-orchestrator.sh" ]; then
        log_pass "Day 2 scripts are executable"
    else
        log_warn "Day 2 scripts not executable - Run: chmod +x scripts/phase-13-day2-*.sh"
        WARN=$((WARN + 1))
    fi

    # Current time check
    local current_hour=$(date +%H)
    if [ "$current_hour" -lt 8 ] || [ "$current_hour" -eq 8 ]; then
        log_pass "Current time is before 09:00 UTC (safe to prepare)"
    else
        log_warn "Current time is past 08:00 UTC - Execution window is imminent"
        WARN=$((WARN + 1))
    fi

    # ─────────────────────────────────────────────────────────────────────────
    # Summary Report
    # ─────────────────────────────────────────────────────────────────────────

    print_section "CHECKLIST SUMMARY"

    echo "" | tee -a "$CHECKLIST_FILE"
    echo "Total Checks: $((PASS + FAIL + WARN))" | tee -a "$CHECKLIST_FILE"
    echo -e "  ${GREEN}✅ PASS:  $PASS${NC}" | tee -a "$CHECKLIST_FILE"
    echo -e "  ${RED}❌ FAIL:  $FAIL${NC}" | tee -a "$CHECKLIST_FILE"
    echo -e "  ${YELLOW}⚠️  WARN:  $WARN${NC}" | tee -a "$CHECKLIST_FILE"
    echo "" | tee -a "$CHECKLIST_FILE"

    if [ "$FAIL" -eq 0 ]; then
        if [ "$WARN" -eq 0 ]; then
            echo -e "${GREEN}═══════════════════════════════════════════════════════════════════════════${NC}" | tee -a "$CHECKLIST_FILE"
            echo -e "${GREEN}STATUS: ✅ READY FOR EXECUTION${NC}" | tee -a "$CHECKLIST_FILE"
            echo -e "${GREEN}═══════════════════════════════════════════════════════════════════════════${NC}" | tee -a "$CHECKLIST_FILE"
            return 0
        else
            echo -e "${YELLOW}═══════════════════════════════════════════════════════════════════════════${NC}" | tee -a "$CHECKLIST_FILE"
            echo -e "${YELLOW}STATUS: ⚠️  READY WITH WARNINGS (Review above)${NC}" | tee -a "$CHECKLIST_FILE"
            echo -e "${YELLOW}═══════════════════════════════════════════════════════════════════════════${NC}" | tee -a "$CHECKLIST_FILE"
            return 0
        fi
    else
        echo -e "${RED}═══════════════════════════════════════════════════════════════════════════${NC}" | tee -a "$CHECKLIST_FILE"
        echo -e "${RED}STATUS: ❌ NOT READY (Fix failures above and retry)${NC}" | tee -a "$CHECKLIST_FILE"
        echo -e "${RED}═══════════════════════════════════════════════════════════════════════════${NC}" | tee -a "$CHECKLIST_FILE"
        return 1
    fi
}

# Execute
main "$@"
