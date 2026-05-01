#!/bin/bash
# PHASE 2B AUTOMATED HEALTH CHECK SCRIPT
# Purpose: Monitoring Lead can run hourly to verify all systems operational
# Usage: bash check-system-health.sh 
# Output: Color-coded results, easy to spot issues
# Created: April 30, 2026

set -e
trap 'echo "❌ Health check script failed at line $LINENO"; exit 1' ERR
trap 'echo "✓ Health check completed"; rm -f /tmp/health_check_*.tmp 2>/dev/null || true' EXIT

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Initialize counters
PASSED=0
FAILED=0
WARNING=0

# Function to print status
print_status() {
    local check_name=$1
    local result=$2
    local threshold=$3
    
    if [ "$result" = "PASS" ]; then
        echo -e "${GREEN}✓ PASS${NC} - $check_name"
        PASSED+=1
    elif [ "$result" = "WARN" ]; then
        echo -e "${YELLOW}⚠ WARN${NC} - $check_name $threshold"
        WARNING+=1
    else
        echo -e "${RED}✗ FAIL${NC} - $check_name $threshold"
        FAILED+=1
    fi
}

# Header
echo "=========================================="
echo "PHASE 2B SYSTEM HEALTH CHECK"
echo "Timestamp: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo "=========================================="
echo ""

# SECTION 1: CONTAINER STATUS
echo "📦 CONTAINER STATUS"
echo "==================="

# Count containers on PRIMARY
primary_containers=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no 192.168.168.31 'docker ps --format "{{.Status}}" | wc -l' 2>/dev/null || echo "0")
if [ "$primary_containers" -ge 87 ]; then
    print_status "PRIMARY containers (87+)" "PASS"
elif [ "$primary_containers" -ge 80 ]; then
    print_status "PRIMARY containers ($primary_containers/87)" "WARN" "Below optimal"
else
    print_status "PRIMARY containers ($primary_containers/87)" "FAIL" "Critical count"
fi

# Count containers on REPLICA
replica_containers=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no 192.168.168.42 'docker ps --format "{{.Status}}" | wc -l' 2>/dev/null || echo "0")
if [ "$replica_containers" -ge 88 ]; then
    print_status "REPLICA containers (88+)" "PASS"
elif [ "$replica_containers" -ge 80 ]; then
    print_status "REPLICA containers ($replica_containers/88)" "WARN" "Below optimal"
else
    print_status "REPLICA containers ($replica_containers/88)" "FAIL" "Critical count"
fi

# Check for exited containers
exited=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no 192.168.168.31 'docker ps -a | grep -i "exited\|dead" | wc -l' 2>/dev/null || echo "0")
if [ "$exited" -eq 0 ]; then
    print_status "No exited containers on PRIMARY" "PASS"
else
    print_status "PRIMARY has exited containers ($exited)" "FAIL"
fi

echo ""

# SECTION 2: DATABASE REPLICATION
echo "🗄️  DATABASE REPLICATION"
echo "======================="

# Check replication lag
repl_lag=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no 192.168.168.31 'docker exec gitlab_db psql -U postgres -c "SELECT EXTRACT(EPOCH FROM (NOW() - pg_last_xact_replay_timestamp()));" -t 2>/dev/null' || echo "999")
repl_lag_int=${repl_lag%.*}

if [ "$repl_lag_int" -lt 5 ]; then
    print_status "Replication lag ${repl_lag_int}s (target <5s)" "PASS"
elif [ "$repl_lag_int" -lt 30 ]; then
    print_status "Replication lag ${repl_lag_int}s (target <5s)" "WARN" "Slightly elevated"
else
    print_status "Replication lag ${repl_lag_int}s (target <5s)" "FAIL" "Critical delay"
fi

# Check replication slot
repl_slot=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no 192.168.168.31 'docker exec gitlab_db psql -U postgres -c "SELECT COUNT(*) FROM pg_replication_slots WHERE active = true;" -t 2>/dev/null || echo "0")
if [ "$repl_slot" -ge 1 ]; then
    print_status "Replication slot active" "PASS"
else
    print_status "Replication slot" "FAIL" "Not active"
fi

# Check connected replicas
connected=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no 192.168.168.31 'docker exec gitlab_db psql -U postgres -c "SELECT COUNT(*) FROM pg_stat_replication;" -t 2>/dev/null || echo "0")
if [ "$connected" -ge 1 ]; then
    print_status "Connected replicas ($connected)" "PASS"
else
    print_status "Connected replicas" "FAIL" "None connected"
fi

echo ""

# SECTION 3: RESOURCE USAGE
echo "💻 RESOURCE USAGE"
echo "================="

# CPU on PRIMARY
cpu_primary=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no 192.168.168.31 'top -bn1 | grep "Cpu(s)" | awk "{print int(\$2)}"' 2>/dev/null || echo "999")
if [ "$cpu_primary" -lt 40 ]; then
    print_status "PRIMARY CPU ${cpu_primary}% (target <40%)" "PASS"
elif [ "$cpu_primary" -lt 80 ]; then
    print_status "PRIMARY CPU ${cpu_primary}% (target <40%)" "WARN" "Elevated"
else
    print_status "PRIMARY CPU ${cpu_primary}% (target <40%)" "FAIL" "Critical"
fi

# Memory on PRIMARY
mem_primary=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no 192.168.168.31 'free | grep Mem | awk "{printf(\"%.0f\", \$3/\$2 * 100)}"' 2>/dev/null || echo "999")
if [ "$mem_primary" -lt 70 ]; then
    print_status "PRIMARY Memory ${mem_primary}% (target <70%)" "PASS"
elif [ "$mem_primary" -lt 85 ]; then
    print_status "PRIMARY Memory ${mem_primary}% (target <70%)" "WARN" "Elevated"
else
    print_status "PRIMARY Memory ${mem_primary}% (target <70%)" "FAIL" "Critical"
fi

# Disk on PRIMARY
disk_primary=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no 192.168.168.31 'df /var/lib/docker | tail -1 | awk "{print int(\$5)}"' 2>/dev/null || echo "999")
if [ "$disk_primary" -lt 70 ]; then
    print_status "PRIMARY Disk ${disk_primary}% (target <70%)" "PASS"
elif [ "$disk_primary" -lt 85 ]; then
    print_status "PRIMARY Disk ${disk_primary}% (target <70%)" "WARN" "Elevated"
else
    print_status "PRIMARY Disk ${disk_primary}% (target <70%)" "FAIL" "Critical"
fi

echo ""

# SECTION 4: SERVICES AVAILABILITY
echo "🚀 SERVICES AVAILABILITY"
echo "======================="

# API endpoint
api_status=$(curl -s -o /dev/null -w "%{http_code}" http://192.168.168.31:8080/api/v4/user 2>/dev/null || echo "000")
if [ "$api_status" = "200" ]; then
    print_status "API endpoint (HTTP 200)" "PASS"
elif [ "$api_status" = "401" ]; then
    print_status "API endpoint (HTTP 401 - auth expected)" "PASS"
else
    print_status "API endpoint (HTTP $api_status)" "FAIL"
fi

# Web UI
web_status=$(curl -s -o /dev/null -w "%{http_code}" http://192.168.168.31  2>/dev/null || echo "000")
if [ "$web_status" = "200" ] || [ "$web_status" = "302" ]; then
    print_status "Web UI (HTTP $web_status)" "PASS"
else
    print_status "Web UI (HTTP $web_status)" "FAIL"
fi

# Database connection
db_status=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no 192.168.168.31 'docker exec gitlab_db psql -U postgres -c "SELECT 1;" 2>/dev/null' && echo "1" || echo "0")
if [ "$db_status" = "1" ]; then
    print_status "Database connection" "PASS"
else
    print_status "Database connection" "FAIL"
fi

# Redis connection
redis_status=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no 192.168.168.31 'docker exec gitlab_redis redis-cli PING 2>/dev/null' || echo "FAIL")
if [ "$redis_status" = "PONG" ]; then
    print_status "Redis connection" "PASS"
else
    print_status "Redis connection" "FAIL"
fi

echo ""

# SECTION 5: HA & VIP
echo "⚙️  HA & VIP STATUS"
echo "=================="

# VIP responsiveness
vip_status=$(ping -c 1 -W 1 192.168.168.50 > /dev/null 2>&1 && echo "1" || echo "0")
if [ "$vip_status" = "1" ]; then
    print_status "VIP 192.168.168.50 responsive" "PASS"
else
    print_status "VIP 192.168.168.50 responsive" "FAIL"
fi

# Keepalived on PRIMARY
keepalived_primary=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no 192.168.168.31 'docker exec gitlab_keepalived ps aux | grep -i keepalived | grep -v grep | wc -l' 2>/dev/null || echo "0")
if [ "$keepalived_primary" -gt 0 ]; then
    print_status "Keepalived on PRIMARY active" "PASS"
else
    print_status "Keepalived on PRIMARY" "FAIL" "Not running"
fi

# Keepalived on REPLICA
keepalived_replica=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no 192.168.168.42 'docker exec gitlab_keepalived ps aux | grep -i keepalived | grep -v grep | wc -l' 2>/dev/null || echo "0")
if [ "$keepalived_replica" -gt 0 ]; then
    print_status "Keepalived on REPLICA active" "PASS"
else
    print_status "Keepalived on REPLICA" "FAIL" "Not running"
fi

echo ""

# SECTION 6: MONITORING
echo "📊 MONITORING SYSTEMS"
echo "===================="

# Prometheus targets (example - adjust if monitoring infrastructure different)
prom_targets=$(curl -s http://localhost:9090/api/v1/targets 2>/dev/null | grep -c '"up": true' || echo "0")
if [ "$prom_targets" -ge 8 ]; then
    print_status "Prometheus targets ($prom_targets/8+ UP)" "PASS"
elif [ "$prom_targets" -ge 6 ]; then
    print_status "Prometheus targets ($prom_targets/8 UP)" "WARN" "Some down"
else
    print_status "Prometheus targets ($prom_targets/8 UP)" "FAIL" "Many down"
fi

# Grafana availability
grafana_status=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/api/health 2>/dev/null || echo "000")
if [ "$grafana_status" = "200" ]; then
    print_status "Grafana API responding" "PASS"
else
    print_status "Grafana API (HTTP $grafana_status)" "FAIL"
fi

echo ""

# SUMMARY
echo "=========================================="
echo "HEALTH CHECK SUMMARY"
echo "=========================================="
echo -e "${GREEN}Passed: $PASSED${NC}"
echo -e "${YELLOW}Warnings: $WARNING${NC}"
echo -e "${RED}Failed: $FAILED${NC}"
echo ""

# Overall status
if [ $FAILED -eq 0 ]; then
    if [ $WARNING -eq 0 ]; then
        echo -e "${GREEN}✓ ALL SYSTEMS GREEN${NC}"
        exit 0
    else
        echo -e "${YELLOW}⚠ SYSTEMS OPERATIONAL (WITH WARNINGS)${NC}"
        exit 0
    fi
else
    echo -e "${RED}✗ CRITICAL ISSUES DETECTED${NC}"
    exit 1
fi

