#!/bin/bash
# scripts/validate-topology.sh
# ============================
# Validate the production topology is correct and all hosts are reachable.
#
# Usage:
#   ./scripts/validate-topology.sh          # Check connectivity and DNS
#   ./scripts/validate-topology.sh --verbose # Show detailed output
#   ./scripts/validate-topology.sh --fix     # Auto-fix minor issues

set -e

REPO_ROOT="$(git rev-parse --show-toplevel)"
VERBOSE=${VERBOSE:-0}
FIX=${FIX:-0}

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --verbose)
            VERBOSE=1
            shift
            ;;
        --fix)
            FIX=1
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Color codes for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

PASS_COUNT=0
FAIL_COUNT=0

log_pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((PASS_COUNT++))
}

log_fail() {
    echo -e "${RED}✗${NC} $1"
    ((FAIL_COUNT++))
}

log_warn() {
    echo -e "${YELLOW}!${NC} $1"
}

log_info() {
    if [ "$VERBOSE" = "1" ]; then
        echo "  ℹ $1"
    fi
}

# Source the env helper to load topology
source "$REPO_ROOT/scripts/lib/env.sh"

echo "=========================================="
echo "Production Topology Validation"
echo "=========================================="
echo ""

# ============================================================================
# SECTION 1: INVENTORY FILE VALIDATION
# ============================================================================

echo "1. Inventory File Validation"
echo "----------------------------"

if [ -f "$REPO_ROOT/environments/production/hosts.yml" ]; then
    log_pass "Inventory file exists"
    log_info "Path: $REPO_ROOT/environments/production/hosts.yml"
else
    log_fail "Inventory file not found"
    exit 1
fi

# Validate YAML syntax
if yq eval '.' "$REPO_ROOT/environments/production/hosts.yml" > /dev/null 2>&1; then
    log_pass "Inventory YAML syntax is valid"
else
    log_fail "Inventory YAML syntax is invalid"
    exit 1
fi

echo ""

# ============================================================================
# SECTION 2: TOPOLOGY VARIABLE VALIDATION
# ============================================================================

echo "2. Topology Variables"
echo "---------------------"

# Verify all critical variables are set
REQUIRED_VARS=(
    "PRIMARY_HOST"
    "REPLICA_HOST"
    "VIP"
    "PRIMARY_FQDN"
    "REPLICA_FQDN"
    "SSH_USER"
    "ENV_DOMAIN_INTERNAL"
)

for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var}" ]; then
        log_fail "Required variable not set: $var"
    else
        log_pass "$var = ${!var}"
        log_info "Value: ${!var}"
    fi
done

echo ""

# ============================================================================
# SECTION 3: SSH CONNECTIVITY
# ============================================================================

echo "3. SSH Connectivity"
echo "-------------------"

# Test SSH to primary
if timeout 5 ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new \
    "$SSH_USER@$PRIMARY_HOST" "echo ok" > /dev/null 2>&1; then
    log_pass "SSH to primary ($PRIMARY_HOST) successful"
else
    log_fail "SSH to primary ($PRIMARY_HOST) failed"
fi

# Test SSH to replica
if timeout 5 ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new \
    "$SSH_USER@$REPLICA_HOST" "echo ok" > /dev/null 2>&1; then
    log_pass "SSH to replica ($REPLICA_HOST) successful"
else
    log_fail "SSH to replica ($REPLICA_HOST) failed"
fi

echo ""

# ============================================================================
# SECTION 4: PING TESTS
# ============================================================================

echo "4. Network Connectivity (Ping)"
echo "-------------------------------"

if ping -c 1 -W 2 "$PRIMARY_HOST" > /dev/null 2>&1; then
    log_pass "Ping to primary ($PRIMARY_HOST) successful"
else
    log_fail "Ping to primary ($PRIMARY_HOST) failed"
fi

if ping -c 1 -W 2 "$REPLICA_HOST" > /dev/null 2>&1; then
    log_pass "Ping to replica ($REPLICA_HOST) successful"
else
    log_fail "Ping to replica ($REPLICA_HOST) failed"
fi

if ping -c 1 -W 2 "$VIP" > /dev/null 2>&1; then
    log_pass "Ping to VIP ($VIP) successful"
else
    log_warn "Ping to VIP ($VIP) failed (VIP may not be active yet)"
fi

echo ""

# ============================================================================
# SECTION 5: DNS RESOLUTION
# ============================================================================

echo "5. DNS Resolution"
echo "-----------------"

# Test DNS resolution (against localhost resolver, assumes systemd-resolved)
for fqdn in "$PRIMARY_FQDN" "$REPLICA_FQDN" "$VIP_FQDN"; do
    resolved=$(getent hosts "$fqdn" 2>/dev/null | awk '{print $1}' | head -1)
    if [ -n "$resolved" ]; then
        log_pass "DNS: $fqdn → $resolved"
    else
        log_warn "DNS: $fqdn → not resolved (CoreDNS may not be running)"
    fi
done

echo ""

# ============================================================================
# SECTION 6: SERVICE CONNECTIVITY
# ============================================================================

echo "6. Service Health Checks"
echo "------------------------"

# Test Prometheus
if timeout 3 curl -s -m 3 "http://$PRIMARY_HOST:9090/-/healthy" > /dev/null 2>&1; then
    log_pass "Prometheus health check successful"
else
    log_fail "Prometheus health check failed"
fi

# Test PostgreSQL primary
if timeout 3 nc -z -w 2 "$PRIMARY_HOST" 5432 2>/dev/null; then
    log_pass "PostgreSQL primary (port 5432) is listening"
else
    log_fail "PostgreSQL primary (port 5432) is not listening"
fi

# Test PostgreSQL replica
if timeout 3 nc -z -w 2 "$REPLICA_HOST" 5432 2>/dev/null; then
    log_pass "PostgreSQL replica (port 5432) is listening"
else
    log_fail "PostgreSQL replica (port 5432) is not listening"
fi

# Test Redis primary
if timeout 3 nc -z -w 2 "$PRIMARY_HOST" 6379 2>/dev/null; then
    log_pass "Redis primary (port 6379) is listening"
else
    log_fail "Redis primary (port 6379) is not listening"
fi

echo ""

# ============================================================================
# SUMMARY
# ============================================================================

echo "=========================================="
echo "Summary: $PASS_COUNT passed, $FAIL_COUNT failed"
echo "=========================================="

if [ "$FAIL_COUNT" -eq 0 ]; then
    echo -e "${GREEN}✓ All validation checks passed!${NC}"
    exit 0
else
    echo -e "${RED}✗ Some validation checks failed${NC}"
    exit 1
fi
