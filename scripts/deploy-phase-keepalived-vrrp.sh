#!/usr/bin/env bash
# scripts/deploy-phase-keepalived-vrrp.sh
# P2 #365: Deploy VRRP/Keepalived for automatic failover
# 
# Implements transparent failover between primary (192.168.168.31) and replica (192.168.168.42)
# Virtual IP: 192.168.168.30 (routes to active primary)
# 
# Usage: 
#   SSH to primary:    ssh akushnir@192.168.168.31
#   Deploy keepalived: bash scripts/deploy-phase-keepalived-vrrp.sh
#   Or via docker:     docker-compose up -d keepalived

set -euo pipefail

# Source inventory variables
source .env.inventory

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

# Load colors
source "$SCRIPT_DIR/_colors.sh" 2>/dev/null || {
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    NC='\033[0m'
}

echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}PHASE 11: KEEPALIVED VRRP DEPLOYMENT${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo ""

# Determine if this is primary or replica
CURRENT_IP=$(hostname -I | awk '{print $1}')
if [[ "$CURRENT_IP" == "$DEPLOY_HOST" ]]; then
    KEEPALIVED_ROLE="MASTER"
    KEEPALIVED_PRIORITY=100
    echo -e "${GREEN}? Detected PRIMARY host (${CURRENT_IP})${NC}"
    echo "  VRRP role: MASTER"
    echo "  Priority: 100"
elif [[ "$CURRENT_IP" == "$REPLICA_HOST" ]]; then
    KEEPALIVED_ROLE="BACKUP"
    KEEPALIVED_PRIORITY=50
    echo -e "${GREEN}? Detected REPLICA host (${CURRENT_IP})${NC}"
    echo "  VRRP role: BACKUP"
    echo "  Priority: 50"
else
    echo -e "${RED}✗ ERROR: Could not determine primary/replica role${NC}"
    echo "  Current IP: $CURRENT_IP"
    echo "  Expected: $DEPLOY_HOST (primary) or $REPLICA_HOST (replica)"
    exit 1
fi

echo ""
echo "? Deploying Keepalived VRRP configuration..."
echo "  Virtual IP: ${VIRTUAL_IP}"
echo "  Primary: ${DEPLOY_HOST}"
echo "  Replica: ${REPLICA_HOST}"
echo "  Failover timeout: 3 seconds"
echo ""

# Create keepalived configuration
mkdir -p config/keepalived

cat > config/keepalived/keepalived.conf << KEEPALIVED_CONF
# Keepalived Configuration - VRRP for High Availability
# P2 #365: Transparent failover between primary and replica
# 
# Architecture:
#   Primary (${DEPLOY_HOST}):  VRRP MASTER, priority 100
#   Replica (${REPLICA_HOST}): VRRP BACKUP, priority 50
#   Virtual IP (${VIRTUAL_IP}): Routes to active master
#
# Failover mechanism:
#   - Primary sends VRRP advertisements every 1 second
#   - Replica waits max 3 seconds (VRRP_INTERVAL * 3)
#   - If primary fails, replica becomes master in <3 seconds
#   - Application traffic automatically routed to replica
#   - Primary recovers and resumes master role (no flapping due to PREEMPT_DELAY)

global_defs {
   router_id code-server-ha
   script_user root
   enable_script_security
}

# Track primary service - if critical service fails, demote priority
vrrp_script check_primary_service {
    script "/usr/local/bin/check-primary-health.sh"
    interval 5
    weight -50
    fall 2
    rise 2
    timeout 3
}

# Track replica readiness
vrrp_script check_replica_ready {
    script "/usr/local/bin/check-replica-ready.sh"
    interval 5
    weight 20
    fall 3
    rise 2
    timeout 3
}

# VRRP Instance - Handles virtual IP failover
vrrp_instance code_server_ha {
    # Role configuration
    state ${KEEPALIVED_ROLE}
    interface eth0
    virtual_router_id 51
    priority ${KEEPALIVED_PRIORITY}

    # Virtual IP configuration
    virtual_ipaddress {
        ${VIRTUAL_IP}/24 dev eth0 label eth0:vip
    }

    # VRRP protocol settings
    version 3
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass ${VRRP_AUTH_PASS:-kushnir2024}
    }

    # Failover behavior
    preempt on
    preempt_delay 60
    notify_master "/usr/local/bin/notify-vrrp-master.sh"
    notify_backup "/usr/local/bin/notify-vrrp-backup.sh"
    notify_fault "/usr/local/bin/notify-vrrp-fault.sh"
    
    # Health checks
    track_script {
        check_primary_service
    }
}

KEEPALIVED_CONF

echo -e "${GREEN}✓ Created keepalived.conf${NC}"
echo ""

# Create health check scripts
mkdir -p scripts/keepalived

cat > scripts/keepalived/check-primary-health.sh << 'HEALTH_SCRIPT'
#!/usr/bin/env bash
# Check primary service health - demote if critical service fails
set -euo pipefail

# Check essential services on primary
checks_passed=0
checks_total=5

# 1. Check Docker daemon
if docker ps &>/dev/null; then
    ((checks_passed++))
else
    echo "FAIL: Docker daemon not responding" >&2
fi
((checks_total++)) || true

# 2. Check code-server container
if docker-compose ps code-server 2>/dev/null | grep -q "Up"; then
    ((checks_passed++))
else
    echo "FAIL: code-server container not running" >&2
fi
((checks_total++)) || true

# 3. Check PostgreSQL
if docker-compose exec -T postgres pg_isready &>/dev/null; then
    ((checks_passed++))
else
    echo "FAIL: PostgreSQL not responding" >&2
fi
((checks_total++)) || true

# 4. Check HTTP endpoint
if curl -sf http://localhost:8080/healthz &>/dev/null; then
    ((checks_passed++))
else
    echo "FAIL: code-server HTTP endpoint not responding" >&2
fi
((checks_total++)) || true

# 5. Check Prometheus
if curl -sf http://localhost:9090/-/healthy &>/dev/null; then
    ((checks_passed++))
else
    echo "FAIL: Prometheus not responding" >&2
fi
((checks_total++)) || true

# Require 4+ checks to pass (80%)
if [[ $checks_passed -lt 4 ]]; then
    echo "ALERT: Primary services degraded ($checks_passed/$checks_total)" >&2
    exit 1
fi

exit 0
HEALTH_SCRIPT

chmod +x scripts/keepalived/check-primary-health.sh

cat > scripts/keepalived/check-replica-ready.sh << 'REPLICA_SCRIPT'
#!/usr/bin/env bash
# Check replica readiness - can it take over?
set -euo pipefail

# Check critical replica services
checks_passed=0
checks_total=3

# 1. Check PostgreSQL replication lag
REPLICATION_LAG=$(docker-compose exec -T postgres \
    psql -U postgres -t -c \
    "SELECT EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp()));" 2>/dev/null || echo "999")

if (( $(echo "$REPLICATION_LAG < 30" | bc -l) )); then
    ((checks_passed++))
else
    echo "FAIL: Replication lag > 30s: ${REPLICATION_LAG}s" >&2
fi
((checks_total++)) || true

# 2. Check Redis availability
if redis-cli -h localhost ping &>/dev/null | grep -q PONG; then
    ((checks_passed++))
else
    echo "FAIL: Redis not responding" >&2
fi
((checks_total++)) || true

# 3. Check disk space (>20% free)
FREE_SPACE=$(df /data | awk 'NR==2 {print $4/$2}' | awk '{printf "%.0f\n", $1*100}')
if [[ $FREE_SPACE -gt 20 ]]; then
    ((checks_passed++))
else
    echo "FAIL: Disk space critically low: ${FREE_SPACE}%" >&2
fi
((checks_total++)) || true

if [[ $checks_passed -lt 2 ]]; then
    echo "ALERT: Replica not ready ($checks_passed/$checks_total)" >&2
    exit 1
fi

exit 0
REPLICA_SCRIPT

chmod +x scripts/keepalived/check-replica-ready.sh

# Create notification scripts
cat > scripts/keepalived/notify-vrrp-master.sh << 'MASTER_NOTIFY'
#!/usr/bin/env bash
# Callback when transitioning to VRRP MASTER
set -euo pipefail

HOSTNAME=$(hostname)
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
VIP=${VIRTUAL_IP:-192.168.168.30}

echo "[$TIMESTAMP] $HOSTNAME: VRRP transition to MASTER (VIP: $VIP)" | \
    logger -t keepalived -p local0.notice

# Alert monitoring system
curl -X POST http://alertmanager:9093/api/v1/alerts \
    -H "Content-Type: application/json" \
    -d "{
        \"alerts\": [{
            \"status\": \"firing\",
            \"labels\": {
                \"alertname\": \"VRRPMasterTransition\",
                \"instance\": \"$HOSTNAME\",
                \"severity\": \"info\",
                \"component\": \"keepalived\"
            },
            \"annotations\": {
                \"summary\": \"$HOSTNAME became VRRP MASTER\",
                \"description\": \"Virtual IP $VIP is now mastered by $HOSTNAME\"
            },
            \"startsAt\": \"$TIMESTAMP\"
        }]
    }" 2>/dev/null || true

MASTER_NOTIFY

chmod +x scripts/keepalived/notify-vrrp-master.sh

cat > scripts/keepalived/notify-vrrp-backup.sh << 'BACKUP_NOTIFY'
#!/usr/bin/env bash
# Callback when transitioning to VRRP BACKUP
set -euo pipefail

HOSTNAME=$(hostname)
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

echo "[$TIMESTAMP] $HOSTNAME: VRRP transition to BACKUP" | \
    logger -t keepalived -p local0.notice

BACKUP_NOTIFY

chmod +x scripts/keepalived/notify-vrrp-backup.sh

cat > scripts/keepalived/notify-vrrp-fault.sh << 'FAULT_NOTIFY'
#!/usr/bin/env bash
# Callback when VRRP enters FAULT state
set -euo pipefail

HOSTNAME=$(hostname)
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

echo "[$TIMESTAMP] $HOSTNAME: VRRP FAULT - triggering failover" | \
    logger -t keepalived -p local0.error

# Send CRITICAL alert
curl -X POST http://alertmanager:9093/api/v1/alerts \
    -H "Content-Type: application/json" \
    -d "{
        \"alerts\": [{
            \"status\": \"firing\",
            \"labels\": {
                \"alertname\": \"VRRPFault\",
                \"instance\": \"$HOSTNAME\",
                \"severity\": \"critical\",
                \"component\": \"keepalived\"
            },
            \"annotations\": {
                \"summary\": \"VRRP FAULT on $HOSTNAME\",
                \"description\": \"$HOSTNAME detected VRRP fault, failover triggered\"
            },
            \"startsAt\": \"$TIMESTAMP\"
        }]
    }" 2>/dev/null || true

FAULT_NOTIFY

chmod +x scripts/keepalived/notify-vrrp-fault.sh

echo -e "${GREEN}✓ Created health check and notification scripts${NC}"
echo ""

# Add keepalived to docker-compose if not present
if ! grep -q "keepalived:" docker-compose.yml; then
    echo -e "${YELLOW}? Note: Add keepalived service to docker-compose.yml${NC}"
    echo "  Service should run with --net=host for VRRP support"
fi

echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✓ PHASE 11 COMPLETE: Keepalived VRRP Configuration${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo ""
echo "NEXT STEPS:"
echo "1. Review keepalived configuration:      cat config/keepalived/keepalived.conf"
echo "2. Test health checks:                    bash scripts/keepalived/check-primary-health.sh"
echo "3. Deploy keepalived container:          docker-compose up -d keepalived"
echo "4. Verify VRRP status:                   ip addr show eth0:vip"
echo "5. Monitor failover:                     docker logs -f keepalived"
echo "6. Failover test:                        killall keepalived (on primary)"
echo ""
echo "VRRP DETAILS:"
echo "  Virtual IP:        ${VIRTUAL_IP}"
echo "  Primary (MASTER):  ${DEPLOY_HOST} (priority 100)"
echo "  Replica (BACKUP):  ${REPLICA_HOST} (priority 50)"
echo "  Failover time:     < 3 seconds"
echo "  Authentication:    VRRP password"
echo "  Monitoring:        AlertManager integration"
echo ""
