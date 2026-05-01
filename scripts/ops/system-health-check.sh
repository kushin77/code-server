#!/bin/bash
# System health check with comprehensive diagnostics
# Run this regularly to monitor platform state

set -e
trap 'echo "❌ Health check encountered error at line $LINENO"; exit 1' ERR

PRIMARY="192.168.168.31"
REPLICA="192.168.168.42"
VIP="192.168.168.30"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║     ElevatedIQ System Health Check - $(date +%Y-%m-%d\ %H:%M:%S)       ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Function to check host health
check_host_health() {
  local HOST=$1
  local LABEL=$2
  
  echo "┌──────────────────────────────────────────────────────────┐"
  echo "│ $LABEL ($HOST)"
  echo "└──────────────────────────────────────────────────────────┘"
  
  ssh -o BatchMode=yes -o ConnectTimeout=5 akushnir@$HOST << 'HEALTH_EOF' 2>/dev/null || {
    echo "  ❌ HOST UNREACHABLE"
    return 1
  }
    # CPU Usage
    CPU=$(top -bn1 | grep "Cpu(s)" | awk '{print 100 - $8}' | cut -d'.' -f1)
    if [[ $CPU -gt 80 ]]; then
      echo "  ⚠️  HIGH CPU: $CPU%"
    elif [[ $CPU -gt 50 ]]; then
      echo "  ℹ️  Moderate CPU: $CPU%"
    else
      echo "  ✅ CPU: $CPU%"
    fi
    
    # Memory Usage
    MEM=$(free | grep Mem | awk '{printf "%.0f", ($3/$2)*100}')
    if [[ $MEM -gt 90 ]]; then
      echo "  🚨 CRITICAL MEMORY: $MEM%"
    elif [[ $MEM -gt 80 ]]; then
      echo "  ⚠️  HIGH MEMORY: $MEM%"
    else
      echo "  ✅ Memory: $MEM%"
    fi
    
    # Disk Usage
    DISK=$(df / | tail -1 | awk '{print $5}' | cut -d'%' -f1)
    if [[ $DISK -gt 95 ]]; then
      echo "  🚨 CRITICAL DISK: $DISK%"
    elif [[ $DISK -gt 90 ]]; then
      echo "  ⚠️  HIGH DISK: $DISK%"
    else
      echo "  ✅ Disk: $DISK%"
    fi
    
    # Container Status
    RUNNING=$(docker ps --format '{{.State}}' | grep "running" | wc -l || echo "0")
    TOTAL=$(docker ps --all --format '{{.State}}' | wc -l || echo "0")
    echo "  📦 Containers: $RUNNING/$TOTAL"
    
    # Check specific critical containers
    for CONTAINER in postgres redis caddy keepalived; do
      if docker ps -a --format '{{.Names}}' | grep -q "code-server-$CONTAINER"; then
        STATUS=$(docker ps --format '{{.Status}}' --filter "name=code-server-$CONTAINER" | cut -d' ' -f1)
        if [[ "$STATUS" == "Up" ]]; then
          echo "    ✅ $CONTAINER"
        else
          echo "    ❌ $CONTAINER (not running)"
        fi
      fi
    done
    
    # Network connectivity
    if ping -c 1 -W 1 8.8.8.8 >/dev/null 2>&1; then
      echo "  🌐 Internet: ✅"
    else
      echo "  🌐 Internet: ⚠️  No connectivity"
    fi
HEALTH_EOF
  echo ""
  return 0
}

# Check both hosts
check_host_health "$PRIMARY" "PRIMARY HOST"
check_host_health "$REPLICA" "REPLICA HOST"

# VRRP Status
echo "┌──────────────────────────────────────────────────────────┐"
echo "│ VRRP / High Availability Status"
echo "└──────────────────────────────────────────────────────────┘"

ssh -o BatchMode=yes akushnir@$PRIMARY << 'VRRP_EOF' 2>/dev/null || echo "⚠️  VRRP check failed"
  STATUS=$(docker exec code-server-keepalived cat /tmp/vrrp_state.txt 2>/dev/null || echo "UNKNOWN")
  echo "  VRRP State: $STATUS"
  
  # Check transitions in last hour
  TRANSITIONS=$(docker exec code-server-keepalived grep -c "Transition" /var/log/keepalived.log 2>/dev/null || echo "0")
  echo "  Transitions (1h): $TRANSITIONS"
VRRP_EOF

# Virtual IP Status
echo ""
if ping -c 1 -W 2 $VIP >/dev/null 2>&1; then
  echo "  ✅ Virtual IP: $VIP responding"
else
  echo "  ❌ Virtual IP: $VIP NOT responding"
fi

echo ""
echo "┌──────────────────────────────────────────────────────────┐"
echo "│ Critical Services"
echo "└──────────────────────────────────────────────────────────┘"

# Database status
if ssh -o BatchMode=yes akushnir@$PRIMARY "docker exec code-server-postgres pg_isready -U postgres" >/dev/null 2>&1; then
  echo "  ✅ PostgreSQL: Ready"
else
  echo "  ❌ PostgreSQL: NOT ready"
fi

# Redis status
if ssh -o BatchMode=yes akushnir@$PRIMARY "docker exec code-server-redis redis-cli ping >/dev/null 2>&1" ; then
  echo "  ✅ Redis: Ready"
else
  echo "  ❌ Redis: NOT ready"
fi

# API endpoint
echo -n "  "
if curl -fsSI http://localhost/health >/dev/null 2>&1; then
  echo "✅ API Gateway: Responding"
else
  echo "❌ API Gateway: NOT responding"
fi

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Health check completed at $(date +%Y-%m-%d\ %H:%M:%S)                   ║"
echo "╚════════════════════════════════════════════════════════════╝"
}
