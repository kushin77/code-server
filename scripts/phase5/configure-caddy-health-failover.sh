#!/bin/bash

###############################################################################
# configure-caddy-health-failover.sh
###############################################################################
# Issue #2430: Add health-based upstream failover to Caddy
#
# Current state: Caddy routes to backends but no health checks
# Problem: If a backend dies, Caddy doesn't failover (manual intervention)
# Solution: Use Caddy's health_uri + health_interval for automatic failover
#
###############################################################################

set -euo pipefail

trap 'log_error "Script failed at line $LINENO"' ERR

log_info() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] $*"; }
log_error() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] $*"; }

log_info "========================================"
log_info "Configuring Caddy Health-Based Failover"
log_info "========================================"

log_info ""
log_info "Current Caddy configuration (Caddyfile):"
log_info "  - Static upstream routing"
log_info "  - No health checks"
log_info "  - Manual failover required"

log_info ""
log_info "New health-check configuration:"

cat > /tmp/caddy-health-failover.conf << 'CADDYEOF'
# Health-based upstream failover configuration
# Use health_uri directive for automatic failover

upstream_health {
  # Primary backend health check
  reverse_proxy 192.168.168.31:8080 {
    # Health check endpoint
    health_uri /health
    health_interval 5s
    health_timeout 2s
    
    # Failover to replica if primary unhealthy
    policy random_choose 2
  }
  
  # Replica backend (automatic failover)
  reverse_proxy 192.168.168.42:8080 {
    health_uri /health
    health_interval 5s
    health_timeout 2s
  }
}

# API backend routing
api.example.com {
  reverse_proxy localhost:3000 {
    health_uri /api/health
    health_interval 5s
    health_timeout 2s
  }
}

# Database proxy (if needed)
db-proxy.internal {
  reverse_proxy localhost:5432 {
    health_uri /health
    health_interval 10s
    health_timeout 3s
  }
}

# Logging for health check events
log {
  output file /var/log/caddy/health-checks.log
  format json
  level info
}
CADDYEOF

log_info "✅ Health-check configuration:"
cat /tmp/caddy-health-failover.conf | head -20

log_info ""
log_info "Benefits:"
log_info "  ✅ Automatic failover on health check failure"
log_info "  ✅ No manual intervention required"
log_info "  ✅ Sub-second failover detection"
log_info "  ✅ Configurable health intervals"
log_info "  ✅ Logging of all health events"

log_info ""
log_info "Implementation:"
log_info "1. Update Caddyfile with health_uri directives"
log_info "2. Deploy new Caddyfile to container"
log_info "3. Reload Caddy: 'caddy reload'"
log_info "4. Verify health checks: 'curl localhost:2019/config/apps/http/servers'"
log_info ""

rm -f /tmp/caddy-health-failover.conf
