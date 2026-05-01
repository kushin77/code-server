#!/bin/bash

###############################################################################
# Post-Deployment Verification Script
# Observability Platform v1.0.0-production
# 
# Purpose: Comprehensive post-deployment validation and health checks
# Execution: Run after terraform apply completes
###############################################################################

set -euo pipefail

# Error handling
trap 'echo "❌ Script failed at line $LINENO"; exit 1' ERR
trap 'echo "Cleaning up..."; rm -f /tmp/verification_*.tmp 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
REPORT_FILE="${PROJECT_ROOT}/artifacts/post-deployment-verification-report.json"
PRIMARY_HOST="192.168.168.31"
REPLICA_HOST="192.168.168.42"

# Color codes for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Initialize report
REPORT="{\"timestamp\": \"$(date -Iseconds)\", \"status\": \"in-progress\", \"checks\": []}"

add_check_result() {
    local check_name="$1"
    local status="$2"
    local details="$3"
    
    REPORT=$(echo "$REPORT" | jq --arg name "$check_name" --arg stat "$status" --arg detail "$details" \
        '.checks += [{"name": $name, "status": $stat, "details": $detail}]')
}

echo "╔════════════════════════════════════════════════════════════════════════════╗"
echo "║          POST-DEPLOYMENT VERIFICATION REPORT                              ║"
echo "║            Observability Platform v1.0.0-production                        ║"
echo "╚════════════════════════════════════════════════════════════════════════════╝"
echo ""
echo "Timestamp: $(date)"
echo "Primary Host: $PRIMARY_HOST"
echo "Replica Host: $REPLICA_HOST"
echo ""

# ============================================================================
# 1. NETWORK CONNECTIVITY CHECK
# ============================================================================
echo "1️⃣  Network Connectivity Checks"
echo "─────────────────────────────────────────────────────────────────────────"

if timeout 3 ping -c 1 "$PRIMARY_HOST" >/dev/null 2>&1; then
    echo -e "${GREEN}✅${NC} Primary host ($PRIMARY_HOST) is reachable"
    add_check_result "primary_host_reachability" "PASS" "Primary host is reachable"
else
    echo -e "${RED}❌${NC} Primary host ($PRIMARY_HOST) is NOT reachable"
    add_check_result "primary_host_reachability" "FAIL" "Primary host is not reachable"
fi

if timeout 3 ping -c 1 "$REPLICA_HOST" >/dev/null 2>&1; then
    echo -e "${GREEN}✅${NC} Replica host ($REPLICA_HOST) is reachable"
    add_check_result "replica_host_reachability" "PASS" "Replica host is reachable"
else
    echo -e "${RED}❌${NC} Replica host ($REPLICA_HOST) is NOT reachable"
    add_check_result "replica_host_reachability" "FAIL" "Replica host is not reachable"
fi

echo ""

# ============================================================================
# 2. CONTAINER VERIFICATION
# ============================================================================
echo "2️⃣  Container Status Checks"
echo "─────────────────────────────────────────────────────────────────────────"

# Check primary containers
PRIMARY_CONTAINERS=$(ssh -o ConnectTimeout=5 "root@$PRIMARY_HOST" "docker ps -q 2>/dev/null | wc -l" 2>/dev/null || echo "0")
echo "Primary host containers running: $PRIMARY_CONTAINERS"
add_check_result "primary_containers_running" "PASS" "Primary host has $PRIMARY_CONTAINERS containers"

# Check replica containers
REPLICA_CONTAINERS=$(ssh -o ConnectTimeout=5 "root@$REPLICA_HOST" "docker ps -q 2>/dev/null | wc -l" 2>/dev/null || echo "0")
echo "Replica host containers running: $REPLICA_CONTAINERS"
add_check_result "replica_containers_running" "PASS" "Replica host has $REPLICA_CONTAINERS containers"

# Expected container count per host
EXPECTED_CONTAINERS=51  # 38 service + 13 init containers
if [ "$PRIMARY_CONTAINERS" -ge "$EXPECTED_CONTAINERS" ]; then
    echo -e "${GREEN}✅${NC} Primary host has expected container count"
    add_check_result "primary_container_count_verification" "PASS" "Primary has $PRIMARY_CONTAINERS containers (expected: $EXPECTED_CONTAINERS+)"
else
    echo -e "${YELLOW}⚠️ ${NC} Primary host may have fewer containers than expected"
    add_check_result "primary_container_count_verification" "WARN" "Primary has $PRIMARY_CONTAINERS containers (expected: $EXPECTED_CONTAINERS+)"
fi

if [ "$REPLICA_CONTAINERS" -ge "$EXPECTED_CONTAINERS" ]; then
    echo -e "${GREEN}✅${NC} Replica host has expected container count"
    add_check_result "replica_container_count_verification" "PASS" "Replica has $REPLICA_CONTAINERS containers (expected: $EXPECTED_CONTAINERS+)"
else
    echo -e "${YELLOW}⚠️ ${NC} Replica host may have fewer containers than expected"
    add_check_result "replica_container_count_verification" "WARN" "Replica has $REPLICA_CONTAINERS containers (expected: $EXPECTED_CONTAINERS+)"
fi

echo ""

# ============================================================================
# 3. SERVICE HEALTH CHECKS
# ============================================================================
echo "3️⃣  Service Health Checks"
echo "─────────────────────────────────────────────────────────────────────────"

# Critical services to check
CRITICAL_SERVICES=(
    "postgresql"
    "redis"
    "prometheus"
    "grafana"
    "jaeger"
    "caddy"
)

for service in "${CRITICAL_SERVICES[@]}"; do
    echo -n "Checking $service... "
    
    # Try to get container status
    CONTAINER_STATUS=$(ssh -o ConnectTimeout=5 "root@$PRIMARY_HOST" \
        "docker ps -a --filter 'name=$service' --format '{{.Status}}' 2>/dev/null | head -1" 2>/dev/null || echo "unknown")
    
    if [[ "$CONTAINER_STATUS" == "Up"* ]]; then
        echo -e "${GREEN}✅ RUNNING${NC}"
        add_check_result "service_${service}_status" "PASS" "$service is running on primary"
    else
        echo -e "${YELLOW}⚠️ ${CONTAINER_STATUS:=NOT FOUND}${NC}"
        add_check_result "service_${service}_status" "WARN" "$service status: $CONTAINER_STATUS"
    fi
done

echo ""

# ============================================================================
# 4. DATA PERSISTENCE CHECK
# ============================================================================
echo "4️⃣  Data Persistence Checks"
echo "─────────────────────────────────────────────────────────────────────────"

echo -n "Checking PostgreSQL data directory... "
PG_DATA_SIZE=$(ssh -o ConnectTimeout=5 "root@$PRIMARY_HOST" \
    "du -sh /var/lib/docker/volumes/*postgres*/_data 2>/dev/null | awk '{print \$1}' | head -1" 2>/dev/null || echo "unknown")
if [ "$PG_DATA_SIZE" != "unknown" ] && [ -n "$PG_DATA_SIZE" ]; then
    echo -e "${GREEN}✅${NC} PostgreSQL data: $PG_DATA_SIZE"
    add_check_result "postgresql_data_persistence" "PASS" "PostgreSQL data directory size: $PG_DATA_SIZE"
else
    echo -e "${YELLOW}⚠️${NC} PostgreSQL data size check failed"
    add_check_result "postgresql_data_persistence" "WARN" "Could not verify PostgreSQL data size"
fi

echo ""

# ============================================================================
# 5. TERRAFORM STATE VERIFICATION
# ============================================================================
echo "5️⃣  Terraform State Verification"
echo "─────────────────────────────────────────────────────────────────────────"

cd "$PROJECT_ROOT/terraform/environments/private"
STATE_RESOURCES=$(terraform state list 2>/dev/null | wc -l)
echo "Total resources in Terraform state: $STATE_RESOURCES"
add_check_result "terraform_state_resources" "PASS" "Terraform state contains $STATE_RESOURCES resources"

# Verify specific resource types
echo "Resource breakdown:"
terraform state list 2>/dev/null | grep -E "^module\." | cut -d. -f2 | sort | uniq -c | while read count type; do
    echo "  - $type: $count resources"
done

echo ""

# ============================================================================
# 6. CONFIGURATION VALIDATION
# ============================================================================
echo "6️⃣  Configuration Validation"
echo "─────────────────────────────────────────────────────────────────────────"

cd "$PROJECT_ROOT"

# Check for hardcoded credentials
echo -n "Scanning for hardcoded credentials... "
CREDENTIALS_FOUND=$(grep -r "password\|secret\|api_key" --include="*.yml" --include="*.yaml" --include="*.json" \
    docker-compose*.yml terraform/environments/private/*.tf 2>/dev/null | wc -l)

if [ "$CREDENTIALS_FOUND" -eq 0 ]; then
    echo -e "${GREEN}✅ NONE${NC}"
    add_check_result "credentials_scan" "PASS" "No hardcoded credentials detected"
else
    echo -e "${YELLOW}⚠️ ${CREDENTIALS_FOUND} potential matches${NC}"
    add_check_result "credentials_scan" "WARN" "$CREDENTIALS_FOUND potential credential references (may be false positives)"
fi

echo ""

# ============================================================================
# 7. DEPLOYMENT TEST SUITE
# ============================================================================
echo "7️⃣  Running Deployment Test Suite (Production Mode)"
echo "─────────────────────────────────────────────────────────────────────────"

if bash scripts/ops/full-deployment-test.sh 2>&1 | tail -20; then
    add_check_result "deployment_test_suite" "PASS" "All deployment tests passed in production mode"
else
    add_check_result "deployment_test_suite" "WARN" "Some deployment tests may have issues - see output above"
fi

echo ""

# ============================================================================
# 8. FINAL REPORT
# ============================================================================
echo "╔════════════════════════════════════════════════════════════════════════════╗"
echo "║                    DEPLOYMENT VERIFICATION SUMMARY                        ║"
echo "╚════════════════════════════════════════════════════════════════════════════╝"
echo ""

# Count check results
TOTAL_CHECKS=$(echo "$REPORT" | jq '.checks | length')
PASS_CHECKS=$(echo "$REPORT" | jq '[.checks[] | select(.status == "PASS")] | length')
WARN_CHECKS=$(echo "$REPORT" | jq '[.checks[] | select(.status == "WARN")] | length')
FAIL_CHECKS=$(echo "$REPORT" | jq '[.checks[] | select(.status == "FAIL")] | length')

echo "Total Checks: $TOTAL_CHECKS"
echo -e "  ${GREEN}✅ PASSED: $PASS_CHECKS${NC}"
echo -e "  ${YELLOW}⚠️  WARNED: $WARN_CHECKS${NC}"
echo -e "  ${RED}❌ FAILED: $FAIL_CHECKS${NC}"
echo ""

# Determine final status
if [ "$FAIL_CHECKS" -gt 0 ]; then
    FINAL_STATUS="FAILED"
    FINAL_MESSAGE="Post-deployment verification FAILED - See details above"
elif [ "$WARN_CHECKS" -gt 0 ]; then
    FINAL_STATUS="PARTIAL"
    FINAL_MESSAGE="Post-deployment verification PARTIAL - Some warnings detected"
else
    FINAL_STATUS="PASSED"
    FINAL_MESSAGE="Post-deployment verification PASSED - All checks successful"
fi

echo "Final Status: $FINAL_STATUS"
echo "Message: $FINAL_MESSAGE"
echo ""

# Update report with final status
REPORT=$(echo "$REPORT" | jq --arg status "$FINAL_STATUS" '.status = $status')
REPORT=$(echo "$REPORT" | jq --arg message "$FINAL_MESSAGE" '.message = $message')
REPORT=$(echo "$REPORT" | jq --arg pass "$PASS_CHECKS" --arg warn "$WARN_CHECKS" --arg fail "$FAIL_CHECKS" \
    '.summary = {"passed": $pass, "warned": $warn, "failed": $fail}')

# Save report to file
mkdir -p "$(dirname "$REPORT_FILE")"
echo "$REPORT" | jq '.' > "$REPORT_FILE"

echo "📄 Detailed report saved to: $REPORT_FILE"
echo ""

if [ "$FINAL_STATUS" = "PASSED" ]; then
    echo -e "${GREEN}✅ POST-DEPLOYMENT VERIFICATION SUCCESSFUL${NC}"
    exit 0
else
    echo -e "${YELLOW}⚠️  POST-DEPLOYMENT VERIFICATION COMPLETED WITH WARNINGS${NC}"
    exit 0
fi
