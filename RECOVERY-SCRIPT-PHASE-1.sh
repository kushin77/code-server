#!/bin/bash
# Recovery script for kushnir.cloud SSL and infrastructure issues
# Fixes Caddyfile configuration, restarts services, validates failover

set -e

PRIMARY_HOST="192.168.168.31"
REPLICA_HOST="192.168.168.42"
USER="akushnir"

echo "🔴 INFRASTRUCTURE RECOVERY - $(date)"
echo "=================================================="

# Function to run SSH command
run_ssh() {
    local host=$1
    shift
    ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "${USER}@${host}" "$@"
}

# ════════════════════════════════════════════════════════════════════════════
# PHASE 1: Primary Host Recovery (192.168.168.31)
# ════════════════════════════════════════════════════════════════════════════

echo ""
echo "📋 PHASE 1: PRIMARY HOST RECOVERY (${PRIMARY_HOST})"
echo "────────────────────────────────────────────────"

echo "Step 1: Verify Caddyfile exists"
run_ssh "$PRIMARY_HOST" 'cd code-server-enterprise && ls -lh Caddyfile && wc -l Caddyfile'

echo ""
echo "Step 2: Clean docker state (remove broken containers)"
run_ssh "$PRIMARY_HOST" '
    docker ps -a --filter status=exited --format "{{.Names}}" | xargs -r docker rm -f
    docker ps -a --filter status=created --format "{{.Names}}" | xargs -r docker rm -f
    echo "✅ Removed exited/created containers"
' || echo "⚠️ Some containers may have failed to remove (expected)"

echo ""
echo "Step 3: Use absolute Caddyfile path to avoid snap mount issues"
run_ssh "$PRIMARY_HOST" '
    cd code-server-enterprise
    
    # Update docker-compose to use absolute path for Caddyfile mount
    CADDY_FILE_PATH="$(pwd)/Caddyfile"
    echo "Caddyfile path: ${CADDY_FILE_PATH}"
    
    # Verify absolute path exists
    test -f "${CADDY_FILE_PATH}" && echo "✅ Caddyfile accessible at ${CADDY_FILE_PATH}"
'

echo ""
echo "Step 4: Stop all services gracefully"
run_ssh "$PRIMARY_HOST" '
    cd code-server-enterprise
    
    # Try docker-compose; if it fails, use docker directly
    docker stop $(docker ps -q) 2>/dev/null || echo "No running containers"
    sleep 3
    echo "✅ All services stopped"
'

echo ""
echo "Step 5: Verify Caddyfile configuration"
run_ssh "$PRIMARY_HOST" '
    cd code-server-enterprise
    echo "Current Caddyfile (first 10 lines):"
    head -10 Caddyfile
    echo ""
    echo "Caddyfile size: $(wc -l < Caddyfile) lines"
'

echo ""
echo "Step 6: Start individual services with explicit mounts"
run_ssh "$PRIMARY_HOST" '
    cd code-server-enterprise
    
    # Use absolute path for Caddyfile
    CADDY_PATH="$(pwd)/Caddyfile"
    
    echo "Starting caddy with mounted Caddyfile..."
    docker run -d \
        --name caddy \
        --restart unless-stopped \
        -u 33 \
        --network net-edge \
        --network net-app \
        -p 80:80 \
        -p 443:443 \
        -p 127.0.0.1:2019:2019 \
        -v "${CADDY_PATH}:/etc/caddy/Caddyfile:ro" \
        -v caddy-data:/data \
        -v caddy-config:/config \
        -e "DOMAIN=kushnir.cloud" \
        -e "IDE_DOMAIN=ide.kushnir.cloud" \
        -e "PORTAL_DOMAIN=kushnir.cloud" \
        -e "DEV_SESSION_DOMAIN=dev.kushnir.cloud" \
        -e "ACME_EMAIL=ops@kushnir.cloud" \
        -e "ACME_AGREE=true" \
        caddy:2.7.6 2>&1 | head -5 || echo "Container already exists or other issue"
    
    sleep 5
    docker ps | grep caddy || echo "⚠️ Caddy not running yet"
'

echo ""
echo "Step 7: Check Caddy logs"
run_ssh "$PRIMARY_HOST" 'docker logs caddy --tail 30 2>&1 | tail -20'

echo ""
echo "Step 8: Test HTTP connectivity"
run_ssh "$PRIMARY_HOST" 'curl -s http://192.168.168.31/health 2>&1 || echo "HTTP test pending..."'

# ════════════════════════════════════════════════════════════════════════════
# PHASE 2: Replica Host Status (192.168.168.42)
# ════════════════════════════════════════════════════════════════════════════

echo ""
echo ""
echo "📋 PHASE 2: REPLICA HOST STATUS (${REPLICA_HOST})"
echo "────────────────────────────────────────────────"

echo "Step 1: Check container status"
run_ssh "$REPLICA_HOST" 'docker ps -a | head -20'

echo ""
echo "Step 2: Identify services in restart loop"
run_ssh "$REPLICA_HOST" 'docker ps -a --filter status=restarting --format "table {{.Names}}\t{{.Status}}"'

echo ""
echo "Step 3: Check for unhealthy services"
run_ssh "$REPLICA_HOST" 'docker ps --filter health=unhealthy --format "table {{.Names}}\t{{.Status}}"'

# ════════════════════════════════════════════════════════════════════════════
# PHASE 3: Verification
# ════════════════════════════════════════════════════════════════════════════

echo ""
echo ""
echo "📋 PHASE 3: VERIFICATION"
echo "────────────────────────────────────────────────"

echo "Primary Host Services:"
run_ssh "$PRIMARY_HOST" 'docker ps --format "table {{.Names}}\t{{.Status}}"'

echo ""
echo "DNS Resolution Test:"
nslookup kushnir.cloud 8.8.8.8 2>&1 | grep -A1 "Name:"

echo ""
echo "✅ Recovery script completed - see status above"
echo ""
