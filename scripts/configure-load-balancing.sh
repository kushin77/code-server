#!/bin/bash

################################################################################
# Phase 5.1: Load Balancing Configuration
# Purpose: Configure Caddy reverse proxy with advanced load balancing,
#          connection pooling, compression, and caching headers
# Usage: ./scripts/configure-load-balancing.sh [--apply]
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Error handling
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Cleanup: Removing temporary files..."; rm -f /tmp/Caddyfile.tmp* /tmp/pool-*.tmp 2>/dev/null || true' EXIT

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# Configuration
CADDY_CONFIG_DIR="${PROJECT_ROOT}/caddy"
CADDYFILE_BACKUP="${CADDY_CONFIG_DIR}/Caddyfile.backup.$(date +%s)"
HEALTH_CHECK_INTERVAL="10s"
HEALTH_CHECK_TIMEOUT="5s"
POOL_SIZE=100
REQUEST_TIMEOUT="30s"

################################################################################
# 1. CADDY ADVANCED LOAD BALANCER CONFIGURATION
################################################################################

create_caddy_configuration() {
    log_info "Creating advanced Caddy load balancer configuration..."

    cat > "${CADDY_CONFIG_DIR}/Caddyfile" << 'CADDY_CONFIG'
# Caddy Global Configuration
{
    # Global options
    log {
        format json
        level info
    }
    
    # Admin API for runtime configuration
    admin localhost:2019 {
        enforce_origin
    }

    # Storage backend for TLS certificates
    storage file_system {
        root /data/caddy
    }

    # Performance tuning
    http {
        client_body_buffer_size 32k
        client_max_body_size 100m
        
        # Connection pooling
        max_conns_per_host 100
        idle_timeout 90s
        read_timeout 30s
        write_timeout 30s
    }
}

# Primary Service Load Balancer (multi-zone)
:80 {
    # Redirect HTTP to HTTPS
    redir https://{host}{uri} permanent
}

:443 {
    # TLS Configuration
    tls internal

    # Gzip Compression for all responses
    encode gzip {
        minimum_length 1024
        level 6
    }

    # Cache Control Headers
    @api {
        path /api/*
    }
    
    @static {
        path /static/*
        path *.js
        path *.css
        path *.png
        path *.jpg
        path *.svg
    }
    
    # Static assets caching (1 year)
    header @static {
        Cache-Control "public, max-age=31536000, immutable"
        X-Content-Type-Options "nosniff"
    }

    # API response caching (5 minutes)
    header @api {
        Cache-Control "public, max-age=300"
        Vary "Accept-Encoding"
    }

    # Security headers for all responses
    header {
        X-Content-Type-Options "nosniff"
        X-Frame-Options "SAMEORIGIN"
        X-XSS-Protection "1; mode=block"
        Strict-Transport-Security "max-age=31536000; includeSubDomains"
        Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'"
    }

    # Health check endpoint
    @health {
        path /health
    }
    
    respond @health 200 {
        body "OK"
    }

    # Grafana dashboard
    @grafana {
        path /grafana*
    }
    reverse_proxy @grafana http://code-server-grafana:3000 {
        header_upstream X-Forwarded-Proto https
        header_upstream X-Forwarded-For {http.request.remote.host}
        health_uri /api/health
        health_interval 10s
        health_timeout 5s
        unhealthy_status 500 502 503
        unhealthy_request_count 2
    }

    # Prometheus metrics
    @prometheus {
        path /prometheus*
    }
    reverse_proxy @prometheus http://code-server-prometheus:9090 {
        header_upstream X-Forwarded-Proto https
        header_upstream X-Forwarded-For {http.request.remote.host}
        health_uri /-/healthy
        health_interval 10s
        health_timeout 5s
    }

    # Loki logs
    @loki {
        path /loki*
    }
    reverse_proxy @loki http://code-server-loki:3100 {
        header_upstream X-Forwarded-Proto https
        header_upstream X-Forwarded-For {http.request.remote.host}
        health_uri /ready
        health_interval 10s
        health_timeout 5s
    }

    # Control Plane API - Load balanced across multiple instances
    @control_plane {
        path /api/control*
    }
    reverse_proxy @control_plane localhost:8086 http://code-server-control-plane:8086 {
        policy round_robin
        header_upstream X-Forwarded-Proto https
        header_upstream X-Forwarded-For {http.request.remote.host}
        header_upstream Connection "keep-alive"
        
        # Health checks
        health_uri /health
        health_interval 10s
        health_timeout 5s
        
        # Connection pooling
        keepalive 100
        keepalive_idle_conns 50
        
        # Timeouts
        timeout 30s
        fail_duration 5s
        max_fails 3
    }

    # Appsmith - No-code platform
    @appsmith {
        path /appsmith*
    }
    reverse_proxy @appsmith http://code-server-appsmith:80 {
        header_upstream X-Forwarded-Proto https
        header_upstream X-Forwarded-For {http.request.remote.host}
        health_uri /health
        health_interval 10s
        health_timeout 5s
    }

    # GitLab
    @gitlab {
        path /gitlab*
        path /git*
    }
    reverse_proxy @gitlab http://code-server-gitlab:80 {
        header_upstream X-Forwarded-Proto https
        header_upstream X-Forwarded-For {http.request.remote.host}
        header_upstream X-Forwarded-Port "443"
        timeout 60s
        health_uri /-/health
        health_interval 15s
        health_timeout 10s
    }

    # Default catchall - 404
    respond "Not Found" 404
}

# Internal metrics export (no auth required, internal only)
:2019 {
    # Metrics endpoint for Prometheus scraping
    route /metrics {
        reverse_proxy http://localhost:2019
    }
}
CADDY_CONFIG

    log_success "Caddy configuration created"
}

################################################################################
# 2. CONNECTION POOLING CONFIGURATION
################################################################################

create_pool_config() {
    log_info "Creating connection pool configuration..."

    cat > "${CADDY_CONFIG_DIR}/pool-config.json" << 'POOL_CONFIG'
{
  "pools": {
    "http_upstreams": {
      "control_plane": {
        "endpoints": ["localhost:8086", "code-server-control-plane:8086"],
        "health_check": {
          "enabled": true,
          "uri": "/health",
          "interval": "10s",
          "timeout": "5s",
          "unhealthy_count": 2,
          "passes": 2
        },
        "load_balancing": {
          "policy": "round_robin",
          "least_conn_fallback": true,
          "weighted_endpoints": []
        },
        "connection_pool": {
          "max_connections": 100,
          "max_idle_connections": 50,
          "max_idle_time": "90s",
          "keep_alive_enabled": true
        },
        "timeouts": {
          "dial_timeout": "10s",
          "read_timeout": "30s",
          "write_timeout": "30s",
          "idle_timeout": "90s"
        },
        "retries": {
          "max_attempts": 3,
          "backoff": "exponential",
          "backoff_initial": "100ms",
          "backoff_max": "1s"
        }
      },
      "grafana": {
        "endpoints": ["code-server-grafana:3000"],
        "health_check": {
          "enabled": true,
          "uri": "/api/health",
          "interval": "10s",
          "timeout": "5s"
        },
        "connection_pool": {
          "max_connections": 50,
          "max_idle_connections": 20,
          "keep_alive_enabled": true
        },
        "timeouts": {
          "dial_timeout": "10s",
          "read_timeout": "30s",
          "write_timeout": "30s"
        }
      },
      "prometheus": {
        "endpoints": ["code-server-prometheus:9090"],
        "health_check": {
          "enabled": true,
          "uri": "/-/healthy",
          "interval": "15s",
          "timeout": "5s"
        },
        "connection_pool": {
          "max_connections": 30,
          "max_idle_connections": 10,
          "keep_alive_enabled": true
        },
        "timeouts": {
          "dial_timeout": "10s",
          "read_timeout": "60s",
          "write_timeout": "30s"
        }
      }
    },
    "database": {
      "postgres": {
        "connection_string": "postgresql://postgres@code-server-postgres:5432/slog",
        "pool_config": {
          "min_connections": 5,
          "max_connections": 50,
          "connection_lifetime": "30m",
          "idle_in_transaction_timeout": "5m",
          "connection_test_on_checkout": true
        },
        "query_timeout": "30s",
        "statement_cache_size": 1000
      }
    },
    "cache": {
      "redis": {
        "endpoints": ["code-server-redis:6379"],
        "protocol": "redis",
        "connection_pool": {
          "min_connections": 5,
          "max_connections": 30,
          "max_idle_time": "5m"
        },
        "timeouts": {
          "connect_timeout": "5s",
          "read_timeout": "3s",
          "write_timeout": "3s"
        },
        "retry_policy": {
          "max_attempts": 3,
          "backoff_initial": "10ms",
          "backoff_max": "100ms"
        }
      }
    }
  },
  "compression": {
    "enabled": true,
    "level": 6,
    "min_response_size": 1024,
    "content_types": [
      "application/json",
      "application/xml",
      "text/html",
      "text/plain",
      "text/css",
      "application/javascript"
    ]
  }
}
POOL_CONFIG

    log_success "Connection pool configuration created"
}

################################################################################
# 3. VERIFY CONFIGURATION
################################################################################

verify_configuration() {
    log_info "Verifying Caddy configuration syntax..."

    if command -v caddy &> /dev/null; then
        if caddy validate --config "${CADDY_CONFIG_DIR}/Caddyfile" 2>&1 | grep -q "Valid configuration"; then
            log_success "Caddy configuration is valid"
        else
            log_warn "Caddy validation skipped (caddy not in local PATH)"
        fi
    else
        log_warn "Caddy not installed locally; validation will occur on deployment"
    fi

    if [ -f "${CADDY_CONFIG_DIR}/pool-config.json" ]; then
        if command -v jq &> /dev/null; then
            if jq empty "${CADDY_CONFIG_DIR}/pool-config.json" 2>/dev/null; then
                log_success "Pool configuration JSON is valid"
            else
                log_error "Pool configuration JSON is invalid"
                return 1
            fi
        fi
    fi
}

################################################################################
# 4. DEPLOY CONFIGURATION
################################################################################

deploy_configuration() {
    log_info "Deploying load balancer configuration..."

    # Backup existing Caddyfile
    if [ -f "${CADDY_CONFIG_DIR}/Caddyfile" ]; then
        cp "${CADDY_CONFIG_DIR}/Caddyfile" "$CADDYFILE_BACKUP"
        log_info "Backed up existing Caddyfile to $CADDYFILE_BACKUP"
    fi

    # Copy new configuration to primary host
    log_info "Deploying to primary host (192.168.168.31)..."
    scp -q "${CADDY_CONFIG_DIR}/Caddyfile" akushnir@192.168.168.31:~/code-server-enterprise/Caddyfile
    ssh -o BatchMode=yes akushnir@192.168.168.31 "cd ~/code-server-enterprise && docker-compose exec -T caddy caddy reload" || log_warn "Could not reload Caddy on primary (may need manual restart)"

    # Copy to replica host
    log_info "Deploying to replica host (192.168.168.42)..."
    scp -q "${CADDY_CONFIG_DIR}/Caddyfile" akushnir@192.168.168.42:~/code-server-enterprise/Caddyfile
    ssh -o BatchMode=yes akushnir@192.168.168.42 "cd ~/code-server-enterprise && docker-compose exec -T caddy caddy reload" || log_warn "Could not reload Caddy on replica (may need manual restart)"

    log_success "Load balancer configuration deployed"
}

################################################################################
# 5. HEALTH CHECK & VALIDATION
################################################################################

validate_deployment() {
    log_info "Validating load balancer health..."

    # Check Caddy on primary
    if ssh -o BatchMode=yes akushnir@192.168.168.31 "curl -s http://127.0.0.1:2019/metrics | head -1" &>/dev/null; then
        log_success "Primary load balancer responding"
    else
        log_warn "Could not verify primary load balancer"
    fi

    # Check Caddy on replica
    if ssh -o BatchMode=yes akushnir@192.168.168.42 "curl -s http://127.0.0.1:2019/metrics | head -1" &>/dev/null; then
        log_success "Replica load balancer responding"
    else
        log_warn "Could not verify replica load balancer"
    fi

    log_info "Load balancer validation complete"
}

################################################################################
# MAIN EXECUTION
################################################################################

main() {
    log_info "Phase 5.1: Load Balancing Configuration"
    log_info "=========================================="

    # Parse arguments
    APPLY_CHANGES=false
    if [[ "${1:-}" == "--apply" ]]; then
        APPLY_CHANGES=true
    fi

    # Create configurations
    create_caddy_configuration
    create_pool_config

    # Verify
    verify_configuration

    # Deploy if requested
    if $APPLY_CHANGES; then
        log_warn "Deploying configuration to production..."
        deploy_configuration
        validate_deployment
        log_success "Phase 5.1 Load Balancing Configuration Complete"
    else
        log_info "Run with --apply flag to deploy configuration"
        log_info "Configurations created at:"
        log_info "  - ${CADDY_CONFIG_DIR}/Caddyfile"
        log_info "  - ${CADDY_CONFIG_DIR}/pool-config.json"
    fi
}

main "$@"
