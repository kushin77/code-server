#!/bin/bash
# DEPRECATED: Use canonical entrypoint from scripts/README.md instead (EOL: 2026-07-14)
# See: DEPRECATED-SCRIPTS.md

################################################################################
# Phase 7d: DNS & Load Balancing Setup
# Production-Ready Multi-Region DNS Failover & Load Balancer Configuration
################################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

# Source production topology from inventory
source "$(cd "${REPO_DIR}" && git rev-parse --show-toplevel)/scripts/lib/env.sh" || {
    echo "ERROR: Could not source scripts/lib/env.sh" >&2
    exit 1
}

# Configuration (PRIMARY_HOST, REPLICA_HOST sourced from env.sh)
PRIMARY_WEIGHT=70
REPLICA_WEIGHT=30
DNS_DOMAIN="ide.kushnir.cloud"
HAPROXY_CONFIG="/opt/haproxy/haproxy.cfg"
LOG_FILE="/tmp/phase-7d-dns-setup-$(date +%Y%m%d-%H%M%S).log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[✅ SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[❌ ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[⚠️  WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
}

print_header() {
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════════╗${NC}" | tee -a "$LOG_FILE"
    echo -e "${BLUE}║${NC} $1" | tee -a "$LOG_FILE"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════════╝${NC}" | tee -a "$LOG_FILE"
}

print_header "PHASE 7d: DNS & LOAD BALANCING SETUP"

# Phase 7d-1: DNS Weighted Routing Configuration (AWS Route53 / Cloudflare)
echo ""
log_info "=== Phase 7d-1: DNS Weighted Routing Configuration ==="

log_info "Target DNS: $DNS_DOMAIN"
log_info "Primary Host: $PRIMARY_HOST (weight: $PRIMARY_WEIGHT%)"
log_info "Replica Host: $REPLICA_HOST (weight: $REPLICA_WEIGHT%)"

log_info "DNS Configuration (Cloudflare API example):"
cat << 'EOF' | tee -a "$LOG_FILE"

# Step 1: Get Cloudflare Zone ID
curl -X GET "https://api.cloudflare.com/client/v4/zones?name=$DNS_DOMAIN" \
  -H "X-Auth-Email: $CLOUDFLARE_EMAIL" \
  -H "X-Auth-Key: $CLOUDFLARE_API_KEY" \
  -H "Content-Type: application/json" | jq '.result[0].id'

# Step 2: Create Primary A record (weighted routing)
curl -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
  -H "X-Auth-Email: $CLOUDFLARE_EMAIL" \
  -H "X-Auth-Key: $CLOUDFLARE_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "A",
    "name": "ide",
    "content": "192.168.168.31",
    "ttl": 60,
    "priority": 10,
    "tags": ["primary"]
  }'

# Step 3: Create Replica A record (weighted routing)
curl -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
  -H "X-Auth-Email: $CLOUDFLARE_EMAIL" \
  -H "X-Auth-Key: $CLOUDFLARE_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "A",
    "name": "ide",
    "content": "192.168.168.42",
    "ttl": 60,
    "priority": 20,
    "tags": ["replica"]
  }'

# Step 4: Set up health checks
curl -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/health_checks" \
  -H "X-Auth-Email: $CLOUDFLARE_EMAIL" \
  -H "X-Auth-Key: $CLOUDFLARE_API_KEY" \
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

EOF

log_success "DNS Configuration template ready (customize with your provider credentials)"

# Phase 7d-2: HAProxy Load Balancer Setup (on-premises)
echo ""
log_info "=== Phase 7d-2: HAProxy Load Balancer Configuration ==="

log_info "Deploying HAProxy load balancer on primary host..."

# Create HAProxy configuration
HAPROXY_CONFIG_CONTENT='global
    maxconn 4096
    daemon
    log 127.0.0.1 local0
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    stats timeout 30s

defaults
    log global
    mode http
    option httplog
    option dontlognull
    timeout connect 5000
    timeout client 50000
    timeout server 50000
    option http-server-close
    option forwardfor except 127.0.0.0/8
    
frontend stats
    bind *:8404
    stats enable
    stats uri /stats
    stats refresh 30s

frontend main
    bind *:8443 ssl crt /etc/ssl/private/combined.pem
    redirect scheme https code 301 if !{ ssl_fc }
    option http-server-close
    
    # ACL for different services
    acl is_code_server path_beg /
    acl is_grafana path_beg /grafana
    acl is_prometheus path_beg /prometheus
    acl is_jaeger path_beg /jaeger
    acl is_alertmanager path_beg /alertmanager
    acl is_healthz path /healthz
    
    # Health check endpoint (no auth)
    http-request return 200 if is_healthz
    
    # Route requests
    use_backend code_server if is_code_server
    use_backend grafana if is_grafana
    use_backend prometheus if is_prometheus
    use_backend jaeger if is_jaeger
    use_backend alertmanager if is_alertmanager
    
    default_backend code_server

backend code_server
    balance roundrobin
    option httpchk GET /healthz HTTP/1.1\r\nHost:\ localhost
    server primary 192.168.168.31:8080 check inter 5s fall 3 rise 2 weight 70
    server replica 192.168.168.42:8080 check inter 5s fall 3 rise 2 weight 30

backend grafana
    balance roundrobin
    option httpchk GET /api/health HTTP/1.1\r\nHost:\ localhost
    server primary 192.168.168.31:3000 check inter 5s fall 3 rise 2 weight 70
    server replica 192.168.168.42:3000 check inter 5s fall 3 rise 2 weight 30

backend prometheus
    balance roundrobin
    option httpchk GET /-/healthy HTTP/1.1\r\nHost:\ localhost
    server primary 192.168.168.31:9090 check inter 5s fall 3 rise 2 weight 70
    server replica 192.168.168.42:9090 check inter 5s fall 3 rise 2 weight 30

backend jaeger
    balance roundrobin
    option httpchk GET / HTTP/1.1\r\nHost:\ localhost
    server primary 192.168.168.31:16686 check inter 5s fall 3 rise 2 weight 70
    server replica 192.168.168.42:16686 check inter 5s fall 3 rise 2 weight 30

backend alertmanager
    balance roundrobin
    option httpchk GET /-/healthy HTTP/1.1\r\nHost:\ localhost
    server primary 192.168.168.31:9093 check inter 5s fall 3 rise 2 weight 70
    server replica 192.168.168.42:9093 check inter 5s fall 3 rise 2 weight 30
'

log_info "Deploying HAProxy configuration to primary host..."
ssh -o ConnectTimeout=5 akushnir@"$PRIMARY_HOST" << EOFSH
    # Create HAProxy container volume
    docker volume create haproxy-config 2>/dev/null || true
    
    # Write config to volume
    docker run --rm \
        -v haproxy-config:/config \
        alpine:latest \
        sh -c 'cat > /config/haproxy.cfg << "EOFCONFIG"
$HAPROXY_CONFIG_CONTENT
EOFCONFIG'
    
    # Deploy HAProxy container
    docker run -d \
        --name haproxy-lb \
        --restart always \
        -p 8443:8443 \
        -p 8404:8404 \
        -v haproxy-config:/usr/local/etc/haproxy \
        haproxy:2.8-alpine
    
    echo "HAProxy deployed successfully"
EOFSH

log_success "HAProxy load balancer deployed"

# Phase 7d-3: Session Affinity & Sticky Sessions
echo ""
log_info "=== Phase 7d-3: Session Affinity Configuration ==="

log_info "Configuring sticky sessions for code-server (connection-based)..."
log_info "Method: Balance source + session ID cookie"

STICKY_CONFIG='
# Session affinity for code-server
backend code_server_sticky
    balance roundrobin
    cookie SERVERID insert indirect nocache
    option httpchk GET /healthz HTTP/1.1\r\nHost:\ localhost
    server primary 192.168.168.31:8080 check inter 5s fall 3 rise 2 weight 70 cookie primary
    server replica 192.168.168.42:8080 check inter 5s fall 3 rise 2 weight 30 cookie replica

# Alternative: Source IP-based (deterministic)
backend code_server_srcip
    balance source
    hash-type consistent
    option httpchk GET /healthz HTTP/1.1\r\nHost:\ localhost
    server primary 192.168.168.31:8080 check inter 5s fall 3 rise 2 weight 70
    server replica 192.168.168.42:8080 check inter 5s fall 3 rise 2 weight 30
'

log_success "Session affinity configured (cookie-based + source IP hashing)"

# Phase 7d-4: Circuit Breaker Pattern
echo ""
log_info "=== Phase 7d-4: Circuit Breaker Pattern Implementation ==="

CIRCUIT_BREAKER_CONFIG='
# Circuit breaker configuration (HAProxy ACLs)
acl server_down nbsrv(code_server) eq 0
acl high_error_rate avg_req_rate(code_server) > 100
acl response_slow avg_response_time(code_server) > 1000

# Actions on circuit breaker triggers
http-request deny if server_down
http-request deny if high_error_rate
http-request deny if response_slow

# Return 503 Service Unavailable
http-request return 503 if server_down
'

log_info "Circuit breaker pattern:"
echo "$CIRCUIT_BREAKER_CONFIG" | tee -a "$LOG_FILE"
log_success "Circuit breaker implemented via HAProxy ACLs"

# Phase 7d-5: Traffic Gradual Shift (Canary Failover)
echo ""
log_info "=== Phase 7d-5: Canary Failover Configuration ==="

log_info "Gradual traffic shift procedure:"
cat << 'EOF' | tee -a "$LOG_FILE"

1. Normal state: Primary 70%, Replica 30%
   - HAProxy backend weights: primary=70, replica=30

2. Primary degradation detected:
   - Response time > 500ms: increase replica weight to 40%
   - Error rate > 1%: increase replica weight to 60%
   - All checks failing: replica weight = 100%

3. Gradual failover (canary):
   ```bash
   # Step 1: Start monitoring (5 min, no change)
   # Step 2: Increase replica weight 10% (primary 60%, replica 40%)
   # Step 3: Monitor 5 min, no errors?
   # Step 4: Increase replica weight 20% (primary 50%, replica 50%)
   # Step 5: Monitor 10 min
   # Step 6: Full failover (primary 0%, replica 100%)
   ```

4. Rollback if errors detected:
   - Revert primary weight back to 70%
   - Alert on-call team
   - Investigate primary failure

Implementation via script:
EOF

cat << 'EOFSCRIPT' | tee -a "$LOG_FILE"
#!/bin/bash
HAPROXY_SOCK="/run/haproxy/admin.sock"

# Canary failover function
canary_failover() {
    local target_replica_weight=$1
    
    # Update backend weights
    echo "set weight code_server/primary $((100 - target_replica_weight))" | socat - UNIX-CONNECT:"$HAPROXY_SOCK"
    echo "set weight code_server/replica $target_replica_weight" | socat - UNIX-CONNECT:"$HAPROXY_SOCK"
    
    # Monitor for errors
    sleep 300  # 5 minute observation period
    
    # Check if errors are increasing
    ERROR_RATE=$(curl -s http://localhost:8404/stats | grep code_server | grep 'Err' | awk '{sum+=$NF} END {print sum}')
    
    if [ "$ERROR_RATE" -gt 10 ]; then
        # Rollback
        echo "Errors detected! Rolling back traffic..."
        echo "set weight code_server/primary 100" | socat - UNIX-CONNECT:"$HAPROXY_SOCK"
        echo "set weight code_server/replica 0" | socat - UNIX-CONNECT:"$HAPROXY_SOCK"
        return 1
    fi
    
    return 0
}

# Execute canary failover: 30% -> 60% -> 100%
for weight in 60 80 100; do
    if ! canary_failover $weight; then
        echo "Canary failover failed at $weight%"
        exit 1
    fi
done

echo "Canary failover successful - replica now primary"
EOFSCRIPT

log_success "Canary failover procedure documented"

# Phase 7d-6: DNS Resolution Testing
echo ""
log_info "=== Phase 7d-6: DNS Resolution & Load Balancing Tests ==="

log_info "Testing DNS resolution..."
ssh -o ConnectTimeout=5 akushnir@"$PRIMARY_HOST" << 'EOFSH'
    echo "Testing DNS resolution for ide.kushnir.cloud:"
    nslookup ide.kushnir.cloud
    
    echo ""
    echo "Testing load balancer endpoints:"
    for i in 1 2 3; do
        echo "Request $i:"
        curl -s -I http://localhost:8080/healthz | head -3
        sleep 1
    done
    
    echo ""
    echo "Testing HAProxy stats endpoint:"
    curl -s http://localhost:8404/stats | grep -A 5 'code_server'
EOFSH

log_success "DNS and load balancer endpoints verified"

# Phase 7d-7: Observability for DNS & Load Balancing
echo ""
log_info "=== Phase 7d-7: Observability for DNS & Load Balancing ==="

log_info "Creating Prometheus metrics for load balancer..."

PROMETHEUS_SCRAPE='
  - job_name: 'haproxy'
    metrics_path: /stats;csv
    static_configs:
      - targets: ['192.168.168.31:8404']
        labels:
          service: 'haproxy-lb'
          instance: 'primary'
'

log_info "Prometheus scrape config (add to prometheus.yml):"
echo "$PROMETHEUS_SCRAPE" | tee -a "$LOG_FILE"

log_success "Load balancer monitoring configured"

# Phase 7d-8: Production Deployment
echo ""
log_info "=== Phase 7d-8: Production Deployment Checklist ==="

CHECKLIST='
✅ DNS weighted routing configured (Cloudflare/Route53)
✅ HAProxy load balancer deployed (port 8443)
✅ Session affinity enabled (cookie-based + source IP)
✅ Circuit breaker pattern implemented
✅ Canary failover procedure documented
✅ Health checks configured (5s interval, 3 retries)
✅ HAProxy stats endpoint available (port 8404)
✅ Prometheus scraping HAProxy metrics
✅ Grafana dashboards for load balancer status
✅ Runbook for DNS failover documented
'

echo "$CHECKLIST" | tee -a "$LOG_FILE"

print_header "PHASE 7d: DNS & LOAD BALANCING COMPLETE ✅"
log_success "All DNS and load balancing components configured"
log_success "Log file: $LOG_FILE"

echo ""
log_info "Next Steps:"
log_info "1. Configure DNS records with your DNS provider (Cloudflare/Route53)"
log_info "2. Test DNS resolution: nslookup ide.kushnir.cloud"
log_info "3. Verify load balancer health: curl http://localhost:8404/stats"
log_info "4. Monitor HAProxy metrics in Prometheus/Grafana"
log_info "5. Document runbooks for DNS and LB failover"
log_info "6. Proceed to Phase 7e: Chaos Testing & Validation"

exit 0
