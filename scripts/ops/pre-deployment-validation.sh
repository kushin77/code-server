#!/bin/bash
# pre-deployment-validation.sh
# Pre-Deployment Infrastructure Validation Script  
# Run T-7 days before deployment
# Part of: Deployment Validation Procedures

set -e

# Error handling
log_error() {
  echo "❌ ERROR: $1" >&2
}

trap 'log_error "Script failed at line $LINENO - check logs at /tmp/pre-deployment-validation.log"; exit 1' ERR
trap 'rm -f /tmp/pre-deployment-validation.tmp 2>/dev/null || true' EXIT

echo "=== Pre-Deployment Validation $(date) ===" | tee /tmp/pre-deployment-validation.log

PRIMARY="192.168.168.31"
REPLICA="192.168.168.42"
PASSED=0
FAILED=0

# Helper function for logging
check_result() {
  if [ $1 -eq 0 ]; then
    echo "✅ $2" | tee -a /tmp/pre-deployment-validation.log
    ((PASSED++))
  else
    echo "❌ $2" | tee -a /tmp/pre-deployment-validation.log
    ((FAILED++))
  fi
}

# === PRIMARY HOST CHECKS ===
echo "" | tee -a /tmp/pre-deployment-validation.log
echo "=== PRIMARY HOST ($PRIMARY) ===" | tee -a /tmp/pre-deployment-validation.log

ssh -o ConnectTimeout=5 -o BatchMode=yes akushnir@$PRIMARY "uptime" &>/dev/null
check_result $? "SSH connection to primary"

ssh -o ConnectTimeout=5 -o BatchMode=yes akushnir@$PRIMARY "docker ps -q | wc -l" &>/dev/null
check_result $? "Docker daemon running on primary"

DISK_CHECK=$(ssh -o ConnectTimeout=5 -o BatchMode=yes akushnir@$PRIMARY "df -h / | tail -1 | awk '{print \$4}' | sed 's/G//' | awk '{\$1=(\$1>50)?1:0}1'" 2>/dev/null || echo "0")
check_result $DISK_CHECK "Disk space > 50GB on primary"

# === REPLICA HOST CHECKS ===
echo "" | tee -a /tmp/pre-deployment-validation.log
echo "=== REPLICA HOST ($REPLICA) ===" | tee -a /tmp/pre-deployment-validation.log

ssh -o ConnectTimeout=5 -o BatchMode=yes akushnir@$REPLICA "uptime" &>/dev/null
check_result $? "SSH connection to replica"

ssh -o ConnectTimeout=5 -o BatchMode=yes akushnir@$REPLICA "docker ps -q | wc -l" &>/dev/null
check_result $? "Docker daemon running on replica"

# === DATABASE CHECKS ===
echo "" | tee -a /tmp/pre-deployment-validation.log
echo "=== DATABASE CONFIGURATION ===" | tee -a /tmp/pre-deployment-validation.log

# Check primary database exists
ssh -o ConnectTimeout=5 -o BatchMode=yes akushnir@$PRIMARY "docker exec code-server-postgres psql -U postgres -c 'SELECT 1' 2>/dev/null" &>/dev/null
check_result $? "PostgreSQL primary accessible"

# Check replica in recovery mode
RECOVERY_CHECK=$(ssh -o ConnectTimeout=5 -o BatchMode=yes akushnir@$REPLICA "docker exec code-server-postgres psql -U postgres -c 'SELECT pg_is_in_recovery();' 2>/dev/null | grep -i 't' | wc -l" || echo "0")
[ "$RECOVERY_CHECK" -eq 1 ]
check_result $? "PostgreSQL replica in recovery mode"

# Check standby.signal exists
ssh -o ConnectTimeout=5 -o BatchMode=yes akushnir@$REPLICA "docker exec code-server-postgres ls /var/lib/postgresql/data/standby.signal 2>/dev/null" &>/dev/null
check_result $? "standby.signal file present"

# === NETWORK CHECKS ===
echo "" | tee -a /tmp/pre-deployment-validation.log
echo "=== NETWORK CONNECTIVITY ===" | tee -a /tmp/pre-deployment-validation.log

# Check replication port open
ssh -o ConnectTimeout=5 -o BatchMode=yes akushnir@$PRIMARY "nc -zv -w 3 $REPLICA 5432 2>&1 | grep -q 'succeeded' && exit 0 || exit 1" &>/dev/null
check_result $? "Replication port 5432 open (primary→replica)"

# Check network latency
LATENCY=$(ssh -o ConnectTimeout=5 -o BatchMode=yes akushnir@$PRIMARY "ping -c 1 -W 2 $REPLICA 2>/dev/null | grep 'time=' | cut -d'=' -f2 | cut -d' ' -f1 | cut -d'.' -f1 || echo '999'" 2>/dev/null)
if [ "$LATENCY" -lt 10 ]; then
  check_result 0 "Network latency <10ms (actual: ${LATENCY}ms)"
else
  check_result 1 "Network latency <10ms (actual: ${LATENCY}ms)"
fi

# === SUMMARY ===
echo "" | tee -a /tmp/pre-deployment-validation.log
echo "=== VALIDATION SUMMARY ===" | tee -a /tmp/pre-deployment-validation.log
echo "Passed: $PASSED" | tee -a /tmp/pre-deployment-validation.log
echo "Failed: $FAILED" | tee -a /tmp/pre-deployment-validation.log

if [ $FAILED -eq 0 ]; then
  echo "✅ ALL CHECKS PASSED - READY FOR DEPLOYMENT" | tee -a /tmp/pre-deployment-validation.log
  exit 0
else
  echo "❌ SOME CHECKS FAILED - RESOLVE BEFORE DEPLOYMENT" | tee -a /tmp/pre-deployment-validation.log
  exit 1
fi
