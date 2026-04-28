#!/bin/bash

###############################################################################
# setup-caddy-health-failover.sh
###############################################################################
# P2 #2430: Caddy health-check based upstream failover
#
# Configures Caddy to:
# - Monitor both primary and replica health endpoints
# - Automatically failover on primary unavailability
# - Distribute load (optional active-active mode)
# - Log failover events for SLOG processing
#
# Usage:
#   ./scripts/phase7/setup-caddy-health-failover.sh \
#     --primary-host 192.168.168.31 \
#     --replica-host 192.168.168.42 \
#     --health-check-interval 30s
#
###############################################################################

set -euo pipefail

trap 'error "Script failed at line $LINENO"' ERR
trap 'log_info "Cleanup complete"; rm -f /tmp/caddy.*.tmp 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LOG_DIR="${REPO_ROOT}/logs/caddy-failover"

PRIMARY_HOST="${1:-${PRIMARY_HOST:?PRIMARY_HOST must be set}}"
REPLICA_HOST="${2:-${REPLICA_HOST:?REPLICA_HOST must be set}}"
HEALTH_CHECK_INTERVAL="${3:-${HEALTH_CHECK_INTERVAL:-30s}}"

#############################################################################
# Logging
#############################################################################

mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/caddy-failover-$(date +%Y%m%d-%H%M%S).log"

log_info() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] $*" | tee -a "${LOG_FILE}"; }
warn() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] [WARN] $*" | tee -a "${LOG_FILE}"; }
error() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] $*" | tee -a "${LOG_FILE}"; exit 1; }

log_info "========================================"
log_info "Caddy Health-Based Failover Setup (P2 #2430)"
log_info "========================================"

log_info "Configuring health-check failover:"
log_info "  Primary: http://${PRIMARY_HOST}:80/health"
log_info "  Replica: http://${REPLICA_HOST}:80/health"
log_info "  Interval: ${HEALTH_CHECK_INTERVAL}"
log_info ""

cat > /tmp/caddyfile-failover.txt << EOF
# Caddyfile - Health-based upstream failover pattern

# Health check policy
# Primary health endpoint returns 200 if all services ready
# Replica health endpoint returns 200 if all services ready

(health_check) {
    uri /health
    timeout 5s
    interval ${HEALTH_CHECK_INTERVAL}
    expected_code 200
    expected_body code-server-healthy
}

# Upstream policy: healthy backends only, with failover
(upstream_policy) {
    policy random_choose 2
    # Tries remaining upstreams on first failure
    try_duration 3s
    try_interval 100ms
}

# Reverse proxy with health checks
:80 {
    log {
        output file /var/log/caddy/access.log {
            roll_size 100mb
            roll_keep 5
        }
    }
    
    # Health check endpoint (non-proxied)
    handle /health {
        respond "code-server-healthy" 200
    }
    
    # API endpoints with health-aware routing
    handle /api* {
        reverse_proxy http://${PRIMARY_HOST}:8080 http://${REPLICA_HOST}:8080 {
            use_health_uri
            health_uri /health
            health_interval ${HEALTH_CHECK_INTERVAL}
            
            # Log failover events for SLOG
            on_error HTTP.0 "[ERROR] Primary API unavailable, failing over to replica"
        }
    }
    
    # OPA policy engine
    handle /api/opa* {
        reverse_proxy http://${PRIMARY_HOST}:8181 http://${REPLICA_HOST}:8181 {
            use_health_uri
            health_uri /health
            health_interval ${HEALTH_CHECK_INTERVAL}
        }
    }
    
    # Default route
    handle / {
        reverse_proxy http://${PRIMARY_HOST}:80 http://${REPLICA_HOST}:80 {
            use_health_uri
            health_uri /health
            health_interval ${HEALTH_CHECK_INTERVAL}
        }
    }
}

# HTTPS (if TLS cert available)
:443 {
    tls /etc/caddy/certificates/cert.pem /etc/caddy/certificates/key.pem
    
    handle /health {
        respond "code-server-healthy" 200
    }
    
    handle /api* {
        reverse_proxy https://${PRIMARY_HOST}:8443 https://${REPLICA_HOST}:8443 {
            use_health_uri
            health_uri /health
            health_interval ${HEALTH_CHECK_INTERVAL}
        }
    }
    
    handle / {
        reverse_proxy https://${PRIMARY_HOST}:443 https://${REPLICA_HOST}:443 {
            use_health_uri
            health_uri /health
            health_interval ${HEALTH_CHECK_INTERVAL}
        }
    }
}
EOF

log_info "Caddyfile pattern (HTTP health-based routing):"
cat /tmp/caddyfile-failover.txt | tee -a "${LOG_FILE}"

log_info ""
log_info "Implementation steps:"
log_info "  1. Update config/caddy/Caddyfile with health check directives"
log_info "  2. Add use_health_uri directive to reverse_proxy blocks"
log_info "  3. Configure health_uri and health_interval"
log_info "  4. Add logging for failover events (on_error)"
log_info "  5. Test: Kill primary, verify failover to replica"
log_info "  6. Test: Kill replica, verify primary continues"
log_info "  7. Test: Both down, verify graceful error response"
log_info ""

log_info "Verification:"
log_info "  - curl -v http://localhost/health (should be 200)"
log_info "  - curl -v http://localhost/api/status (should route to healthy upstream)"
log_info "  - docker logs caddy | grep 'failover\\|unavailable'"
log_info "  - Check SLOG logs for failover events"
log_info ""

log_info "✅ Caddy health failover skeleton complete"
log_info "Log: ${LOG_FILE}"
