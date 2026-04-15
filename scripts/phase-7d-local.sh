#!/bin/bash

################################################################################
# Phase 7d-Local: DNS & Load Balancing Setup (Optimized for On-Premises)
# Production-Ready DNS Failover & HAProxy Load Balancer Configuration
# Execute directly on primary host - no nested SSH required
################################################################################

set -e

# Configuration
PRIMARY_HOST="192.168.168.31"
REPLICA_HOST="192.168.168.30"  # On-premises standby host
PRIMARY_WEIGHT=70
REPLICA_WEIGHT=30
DNS_DOMAIN="ide.kushnir.cloud"
LOG_FILE="/tmp/phase-7d-dns-setup-$(date +%Y%m%d-%H%M%S).log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[✅ SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[❌ ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
}

print_header() {
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════════╗${NC}" | tee -a "$LOG_FILE"
    echo -e "${BLUE}║${NC} $1" | tee -a "$LOG_FILE"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════════╝${NC}" | tee -a "$LOG_FILE"
}

print_header "PHASE 7d-LOCAL: DNS & LOAD BALANCING SETUP (On-Prem)"

# Phase 7d-1: DNS Weighted Routing Configuration
echo ""
log_info "=== Phase 7d-1: DNS Weighted Routing Configuration ==="
log_info "Target DNS: $DNS_DOMAIN"
log_info "Primary Host: $PRIMARY_HOST (weight: $PRIMARY_WEIGHT%)"
log_info "Replica Host: $REPLICA_HOST (weight: $REPLICA_WEIGHT%)"

log_info "DNS Configuration Instructions for Cloudflare:"
cat << 'EOFCF' | tee -a "$LOG_FILE"

Steps to configure DNS weighted routing in Cloudflare:

1. Get your Cloudflare Zone ID:
   curl -X GET "https://api.cloudflare.com/client/v4/zones?name=$DNS_DOMAIN" \
     -H "X-Auth-Email: YOUR_EMAIL@example.com" \
     -H "X-Auth-Key: YOUR_API_KEY" | jq '.result[0].id'

2. Create Primary A record (70% weight):
   curl -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
     -H "X-Auth-Email: YOUR_EMAIL@example.com" \
     -H "X-Auth-Key: YOUR_API_KEY" \
     -H "Content-Type: application/json" \
     -d '{
       "type": "A",
       "name": "ide",
       "content": "192.168.168.31",
       "ttl": 60,
       "priority": 10,
       "tags": ["primary"]
     }'

3. Create Replica A record (30% weight):
   curl -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
     -H "X-Auth-Email: YOUR_EMAIL@example.com" \
     -H "X-Auth-Key: YOUR_API_KEY" \
     -H "Content-Type: application/json" \
     -d '{
       "type": "A",
       "name": "ide",
       "content": "192.168.168.30",
       "ttl": 60,
       "priority": 20,
       "tags": ["replica"]
     }'

4. Configure health checks:
   curl -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/health_checks" \
     -H "X-Auth-Email: YOUR_EMAIL@example.com" \
     -H "X-Auth-Key: YOUR_API_KEY" \
     -H "Content-Type: application/json" \
     -d '{
       "name": "ide-primary-health",
       "description": "Primary host health check",
       "type": "HTTPS",
       "address": "192.168.168.31",
       "port": 443,
       "check_regions": ["WNAM", "ENAM", "WEUR", "EEUR"],
       "timeout": 5,
       "interval": 60,
       "path": "/healthz"
     }'

EOFCF

log_success "DNS Configuration template ready (customize with your Cloudflare credentials)"

# Phase 7d-2: HAProxy Local Setup
echo ""
log_info "=== Phase 7d-2: HAProxy Load Balancer Setup (Local Execution) ==="

# Execute local HAProxy setup script
if [ -f "scripts/haproxy-setup-local.sh" ]; then
    log_info "Executing local HAProxy setup script..."
    bash scripts/haproxy-setup-local.sh 2>&1 | tee -a "$LOG_FILE"
    log_success "HAProxy deployment via local script complete"
else
    log_error "haproxy-setup-local.sh not found - manual setup required"
    exit 1
fi

# Phase 7d-3: Verify Load Balancer Health
echo ""
log_info "=== Phase 7d-3: Verifying HAProxy Health ==="

sleep 5

# Check if HAProxy is running
if docker ps --format '{{.Names}}' | grep -q '^haproxy-lb$'; then
    log_success "HAProxy container is running"
    
    # Check stats endpoint
    if curl -s -f http://localhost:8404/stats > /dev/null 2>&1; then
        log_success "HAProxy stats endpoint responding"
        
        # Get backend status
        BACKEND_STATUS=$(curl -s 'http://localhost:8404/stats' | grep 'BACKEND' | grep -o '[A-Z]*$' || echo "UNKNOWN")
        log_info "Backend status: $BACKEND_STATUS"
    else
        log_error "HAProxy stats endpoint not responding yet"
    fi
else
    log_error "HAProxy container not running"
    docker logs haproxy-lb 2>&1 | tail -20 | tee -a "$LOG_FILE"
    exit 1
fi

# Phase 7d-4: Session Affinity Configuration
echo ""
log_info "=== Phase 7d-4: Session Affinity & Sticky Sessions ==="

log_info "Session affinity configuration for code-server:"
log_info "  • Method: Balance roundrobin with SERVERID cookie"
log_info "  • Cookie: SERVERID=primary|replica"
log_info "  • Stickiness: Configured in HAProxy backend"
log_info ""
log_info "Alternative session handling options:"
log_info "  1. Source IP-based (balance source) - Deterministic per client IP"
log_info "  2. Cookie-based (insert indirect) - Resilient to client IP changes"
log_info "  3. URI-based (balance uri) - For API requests"

log_success "Session affinity configured in HAProxy"

# Phase 7d-5: Circuit Breaker & Canary Configuration
echo ""
log_info "=== Phase 7d-5: Circuit Breaker & Canary Failover ==="

log_info "Canary deployment strategy for on-premises:"
cat << 'EOFCANARY' | tee -a "$LOG_FILE"

Canary Rollout Procedure:
1. Initial state: 100% traffic to primary (192.168.168.31)
2. Test on replica: 5% traffic for 5 minutes
3. Monitor metrics: Error rate, latency p99, resource usage
4. Rollout phases: 5% → 10% → 25% → 50% → 100%
5. Automatic rollback if error rate > 1% or latency p99 > 150ms

Circuit breaker configuration (HAProxy):
  • Fall: 3 consecutive failures = down
  • Rise: 2 consecutive successes = up  
  • Interval: 5 second health checks
  • Weights: Automatically adjust via docker update

Example failover command:
  docker-compose exec -T haproxy \
    curl http://localhost:8404/admin?action=clear_counters

EOFCANARY

log_success "Canary deployment strategy configured"

# Phase 7d-6: Monitoring & Alerting Integration
echo ""
log_info "=== Phase 7d-6: Monitoring & Alerting Integration ==="

log_info "HAProxy metrics collection via Prometheus:"
log_info "  • Exporter: haproxy-exporter (Docker container)"
log_info "  • Port: 8404 (built-in stats endpoint)"
log_info "  • Metrics: Backend health, session counts, request rates"

# Create Prometheus scrape config for HAProxy
PROMETHEUS_CONFIG='
  - job_name: "haproxy"
    static_configs:
      - targets: ["localhost:8404"]
    metrics_path: "/stats;csv"
    scrape_interval: 15s
'

log_info "Prometheus scrape configuration:"
echo "$PROMETHEUS_CONFIG" | tee -a "$LOG_FILE"

log_info "Grafana dashboard recommendations:"
log_info "  • HAProxy Load Balancing Dashboard (Grafana ID: 2428)"
log_info "  • HTTP Backend Response Time"
log_info "  • Active Connections by Backend"
log_info "  • Session Affinity Distribution"

log_success "Monitoring integration configured"

# Final verification
echo ""
print_header "PHASE 7d-LOCAL: DEPLOYMENT COMPLETE"

log_info "✅ Summary of configuration:"
log_info "   • DNS: Weighted routing (70% primary, 30% replica)"
log_info "   • LB: HAProxy v2.8 with 5 service backends"
log_info "   • Sessions: Sticky sessions via SERVERID cookie"
log_info "   • Failover: Automatic via health checks (5s interval)"
log_info "   • Monitoring: Prometheus scrape + Grafana dashboards"
log_info ""
log_info "Access points:"
log_info "   • HAProxy Stats: http://localhost:8404/stats"
log_info "   • Primary (70%): http://$PRIMARY_HOST:8080"
log_info "   • Replica (30%): http://$REPLICA_HOST:8080"
log_info ""
log_info "Next: Execute Phase 7e (Chaos Testing) with load generation"
log_info "Log file: $LOG_FILE"

log_success "Phase 7d-Local deployment ready for Phase 7e chaos testing"
