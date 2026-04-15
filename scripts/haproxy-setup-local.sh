#!/bin/bash

################################################################################
# HAProxy Local Setup Script
# Standalone deployment for HAProxy load balancer (no nested SSH)
# Run directly on primary host: bash scripts/haproxy-setup-local.sh
################################################################################

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}HAProxy Load Balancer Setup (Local Execution)${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"

# Configuration
PRIMARY_WEIGHT=70
REPLICA_WEIGHT=30
REPLICA_HOST="192.168.168.42"

# HAProxy configuration content
HAPROXY_CONFIG='global
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
    server primary 127.0.0.1:8080 check inter 5s fall 3 rise 2 weight '"$PRIMARY_WEIGHT"'
    server replica '"$REPLICA_HOST"':8080 check inter 5s fall 3 rise 2 weight '"$REPLICA_WEIGHT"'

backend grafana
    balance roundrobin
    option httpchk GET /api/health HTTP/1.1\r\nHost:\ localhost
    server primary 127.0.0.1:3000 check inter 5s fall 3 rise 2 weight '"$PRIMARY_WEIGHT"'
    server replica '"$REPLICA_HOST"':3000 check inter 5s fall 3 rise 2 weight '"$REPLICA_WEIGHT"'

backend prometheus
    balance roundrobin
    option httpchk GET /-/healthy HTTP/1.1\r\nHost:\ localhost
    server primary 127.0.0.1:9090 check inter 5s fall 3 rise 2 weight '"$PRIMARY_WEIGHT"'
    server replica '"$REPLICA_HOST"':9090 check inter 5s fall 3 rise 2 weight '"$REPLICA_WEIGHT"'

backend jaeger
    balance roundrobin
    option httpchk GET / HTTP/1.1\r\nHost:\ localhost
    server primary 127.0.0.1:16686 check inter 5s fall 3 rise 2 weight '"$PRIMARY_WEIGHT"'
    server replica '"$REPLICA_HOST"':16686 check inter 5s fall 3 rise 2 weight '"$REPLICA_WEIGHT"'

backend alertmanager
    balance roundrobin
    option httpchk GET /-/healthy HTTP/1.1\r\nHost:\ localhost
    server primary 127.0.0.1:9093 check inter 5s fall 3 rise 2 weight '"$PRIMARY_WEIGHT"'
    server replica '"$REPLICA_HOST"':9093 check inter 5s fall 3 rise 2 weight '"$REPLICA_WEIGHT"'
'

# Create HAProxy config file locally
echo -e "${BLUE}[1/4] Creating HAProxy configuration file...${NC}"
mkdir -p config/haproxy
cat > config/haproxy/haproxy.cfg << 'EOFCFG'
$HAPROXY_CONFIG
EOFCFG
echo -e "${GREEN}✓ HAProxy config created${NC}"

# Check for existing HAProxy container
echo -e "${BLUE}[2/4] Checking for existing HAProxy container...${NC}"
if docker ps --all --format '{{.Names}}' | grep -q '^haproxy-lb$'; then
    echo -e "${BLUE}Removing existing HAProxy container...${NC}"
    docker stop haproxy-lb 2>/dev/null || true
    docker rm haproxy-lb 2>/dev/null || true
fi
echo -e "${GREEN}✓ Old containers cleaned${NC}"

# Deploy HAProxy container with docker-compose
echo -e "${BLUE}[3/4] Deploying HAProxy container...${NC}"
cat > docker-compose.haproxy.yml << 'EOFYML'
version: '3.8'
services:
  haproxy:
    image: haproxy:2.8-alpine
    container_name: haproxy-lb
    restart: always
    ports:
      - "8443:8443"
      - "8404:8404"
    volumes:
      - ./config/haproxy/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro
    networks:
      - enterprise
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8404/stats || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 3
      start_period: 10s

networks:
  enterprise:
    external: true
EOFYML

docker-compose -f docker-compose.haproxy.yml up -d
echo -e "${GREEN}✓ HAProxy container deployed${NC}"

# Verify deployment
echo -e "${BLUE}[4/4] Verifying HAProxy deployment...${NC}"
sleep 3

if docker ps --format '{{.Names}}' | grep -q '^haproxy-lb$'; then
    echo -e "${GREEN}✓ HAProxy container is running${NC}"
    
    # Test health check
    if curl -s -f http://localhost:8404/stats > /dev/null 2>&1; then
        echo -e "${GREEN}✓ HAProxy stats endpoint responding${NC}"
    else
        echo -e "${RED}⚠ HAProxy health check not yet passing (may take a moment)${NC}"
    fi
else
    echo -e "${RED}✗ HAProxy container failed to start${NC}"
    docker-compose -f docker-compose.haproxy.yml logs
    exit 1
fi

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✅ HAProxy Load Balancer Setup Complete${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""
echo "Access points:"
echo "  • Stats Dashboard: http://localhost:8404/stats"
echo "  • Health Check: http://localhost:8404/healthz"
echo ""
echo "Load distribution:"
echo "  • Primary (192.168.168.31): $PRIMARY_WEIGHT%"
echo "  • Replica ($REPLICA_HOST): $REPLICA_WEIGHT%"
echo ""
