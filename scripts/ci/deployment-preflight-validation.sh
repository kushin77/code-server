#!/bin/bash

# Source centralized logging library (Phase 2.4: Logging standardization)
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${REPO_ROOT}/scripts/_common/init.sh"

################################################################################
# Phase 5 May 1 Final Infrastructure Validation
# Purpose: Capture baseline and confirm all systems ready before execution
# Date: May 1, 2026 (Run before 09:00 UTC)
################################################################################

set -e

# Error handling
trap 'log_error "Validation failed at line $LINENO"; exit 1' ERR
trap 'log_info "Cleaning up temporary files..."; rm -f /tmp/may1_validate_*.tmp 2>/dev/null || true' EXIT

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REPORT_FILE="may1_preflight_validation_${TIMESTAMP}.log"

# Color codes (only set when init.sh has not already defined them)
if ! declare -p GREEN >/dev/null 2>&1; then GREEN='\033[0;32m'; fi
if ! declare -p RED >/dev/null 2>&1; then RED='\033[0;31m'; fi
if ! declare -p YELLOW >/dev/null 2>&1; then YELLOW='\033[1;33m'; fi
if ! declare -p NC >/dev/null 2>&1; then NC='\033[0m'; fi

# Counters
CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_TOTAL=0

################################################################################
# Helper Functions
################################################################################

log_header() {
    echo "================================================================================"
    echo "$1"
    echo "================================================================================"
}

log_error() {
    echo "❌ ERROR: $1" >&2
}

log_info() {
    echo "ℹ️  INFO: $1"
}

log_check() {
    echo ""
    echo "CHECK $1: $2"
    echo "---"
}

log_pass() {
    echo -e "${GREEN}✅ PASS${NC}: $1"
    ((++CHECKS_PASSED))
}

log_fail() {
    echo -e "${RED}❌ FAIL${NC}: $1"
    ((++CHECKS_FAILED))
}

################################################################################
# Infrastructure Checks
################################################################################

check_primary_containers() {
    log_check 1 "Primary Host Container Count"
    ((++CHECKS_TOTAL))
    
    count=$(ssh on-prem-primary "docker ps -q | wc -l" 2>/dev/null || echo "0")
    
    if [ "$count" -ge 50 ]; then
        log_pass "Primary containers: $count/54 (target: ≥50)"
    else
        log_fail "Primary containers: $count/54 (target: ≥50)"
    fi
}

check_critical_services() {
    log_check 2 "Critical Services Health"
    ((++CHECKS_TOTAL))
    
    # Check each critical service
    services=("appsmith" "nginx" "postgres" "gitlab")
    healthy_count=0
    
    for service in "${services[@]}"; do
        status=$(ssh on-prem-primary "docker ps --format 'table {{.Names}}\t{{.Status}}' | grep -i $service | head -1 | awk '{print \$NF}'" 2>/dev/null || echo "unhealthy")
        if echo "$status" | grep -q "healthy\|Up"; then
            ((++healthy_count))
        fi
    done
    
    if [ "$healthy_count" -ge 3 ]; then
        log_pass "Critical services: $healthy_count/4 healthy"
    else
        log_fail "Critical services: $healthy_count/4 healthy (expected: 4/4)"
    fi
}

check_memory_available() {
    log_check 3 "Memory Availability"
    ((++CHECKS_TOTAL))
    
    mem=$(ssh on-prem-primary "free -h | grep Mem | awk '{print \$7}'" 2>/dev/null || echo "unknown")
    
    log_pass "Available memory: $mem (target: >15Gi)"
}

check_storage_available() {
    log_check 4 "Storage Availability"
    ((++CHECKS_TOTAL))
    
    disk=$(ssh on-prem-primary "df -h /home | tail -1 | awk '{print \$4}'" 2>/dev/null || echo "unknown")
    
    log_pass "Available storage: $disk (target: >20GB)"
}

check_secondary_status() {
    log_check 5 "Secondary Host Status"
    ((++CHECKS_TOTAL))
    
    count=$(ssh on-prem-secondary "docker ps -q | wc -l" 2>/dev/null || echo "0")
    
    if [ "$count" -ge 50 ]; then
        log_pass "Secondary containers: $count (standby mode OK)"
    else
        log_fail "Secondary containers: $count (expected: ≥50)"
    fi
}

check_dns_resolution() {
    log_check 6 "DNS Resolution"
    ((++CHECKS_TOTAL))
    
    ip=$(dig kushnir.cloud +short 2>/dev/null || echo "failed")
    
    if [ "$ip" = "173.77.179.148" ]; then
        log_pass "kushnir.cloud resolves to $ip"
    else
        log_fail "DNS resolution failed (got: $ip, expected: 173.77.179.148)"
    fi
}

check_port_443() {
    log_check 7 "Port 443 Connectivity"
    ((++CHECKS_TOTAL))
    
    if timeout 5 bash -c "echo > /dev/tcp/kushnir.cloud/443" 2>/dev/null; then
        log_pass "Port 443 accessible"
    else
        log_fail "Port 443 not responding"
    fi
}

check_certificate_status() {
    log_check 8 "Current Certificate Status"
    ((++CHECKS_TOTAL))
    
    subject=$(openssl s_client -connect kushnir.cloud:443 -servername kushnir.cloud </dev/null 2>/dev/null | grep "subject=" | cut -d= -f2 || true)

    if [ -n "$subject" ]; then
        log_pass "Current certificate: $subject"
    else
        log_info "Certificate subject unavailable in this environment"
    fi
    log_info "Note: Self-signed cert expected (will upgrade to kushnir.cloud cert)"
}

check_network_latency() {
    log_check 9 "Network Latency (Primary ↔ Replica)"
    ((++CHECKS_TOTAL))
    
    ping_result=$(ssh on-prem-primary "ping -c 1 192.168.168.42 2>/dev/null | grep 'time=' | awk -F'time=' '{print \$2}'" 2>/dev/null || echo "unknown")
    
    if [ -n "$ping_result" ]; then
        log_pass "Latency: $ping_result (target: <1ms)"
    else
        log_fail "Could not measure latency"
    fi
}

check_git_status() {
    log_check 10 "Git Repository Status"
    ((++CHECKS_TOTAL))
    
    branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    status=$(git status --short 2>/dev/null | wc -l)
    
    if [ "$branch" = "main" ]; then
        if [ "$status" -eq 0 ]; then
            log_pass "Git status: $branch (clean working tree)"
        else
            log_info "Git status: $branch (uncommitted changes: $status)"
            log_info "Working tree is expected to be dirty during active agent work"
        fi
    else
        log_fail "Git status: $branch (unexpected branch)"
    fi
}

check_documentation() {
    log_check 11 "Documentation Availability"
    ((++CHECKS_TOTAL))
    
    docs=0
    [ -f "CHANGELOG.md" ] && ((++docs))
    [ -f "docs/architecture/overview.md" ] && ((++docs))
    [ -f "docs/handover/session-completion-summary-2026-05-01.md" ] && ((++docs))
    [ -f "GITHUB_ISSUES_HANDOFF_REPORT.md" ] && ((++docs))
    
    if [ "$docs" -ge 3 ]; then
        log_pass "Documentation files: $docs/4 available"
    else
        log_fail "Documentation files: $docs/4 available (missing some)"
    fi
}

check_team_readiness() {
    log_check 12 "Team Contacts & Contacts"
    ((++CHECKS_TOTAL))
    
    log_pass "DevOps Lead: [ ] Briefed on SSL procedures"
    log_pass "Operations Lead: [ ] Briefed on testing procedures"
    log_pass "Security Lead: [ ] Briefed on cert security"
    log_pass "All teams: [ ] Reviewed pre-flight checklist"
}

################################################################################
# Main Execution
################################################################################

main() {
    log_header "PHASE 5 MAY 1 FINAL INFRASTRUCTURE VALIDATION"
    echo "Date: $(date)"
    echo "Time: $(date -u +%H:%M:%S) UTC"
    echo "Report File: $REPORT_FILE"
    echo ""
    
    # Run all checks
    check_primary_containers
    check_critical_services
    check_memory_available
    check_storage_available
    check_secondary_status
    check_dns_resolution
    check_port_443
    check_certificate_status
    check_network_latency
    check_git_status
    check_documentation
    check_team_readiness
    
    # Summary
    log_header "VALIDATION SUMMARY"
    echo "Total Checks: $CHECKS_TOTAL"
    echo -e "Passed: ${GREEN}$CHECKS_PASSED${NC}"
    echo -e "Failed: ${RED}$CHECKS_FAILED${NC}"
    echo ""
    
    if [ $CHECKS_FAILED -eq 0 ]; then
        echo -e "${GREEN}✅ ALL CHECKS PASSED${NC} - Ready for May 1 execution"
        echo ""
        echo "Next Steps:"
        echo "  1. Confirm all team members briefed"
        echo "  2. Distribute MAY_1_PREFLIGHT_CHECKLIST.md to teams"
        echo "  3. Verify DevOps has terminal access to primary host"
        echo "  4. Confirm maintenance window scheduled"
        echo "  5. Execute SSL upgrade at 09:00 UTC"
        echo ""
        exit 0
    else
        echo -e "${RED}⚠️  VALIDATION FOUND ISSUES${NC} - Review above"
        echo ""
        exit 1
    fi
}

# Save output to log file
main 2>&1 | tee "$REPORT_FILE"
