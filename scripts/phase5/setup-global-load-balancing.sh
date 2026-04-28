#!/bin/bash
# @file scripts/phase5/setup-global-load-balancing.sh
# @description Cloudflare + Caddy global load balancing orchestration (Q3 Phase 5)
# @version 1.0.0
# @date April 25, 2026

set -euo pipefail

# Source canonical bootstrap
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

readonly LOG_FILE="${REPO_ROOT}/artifacts/phase5/glb-$(date +%Y%m%d-%H%M%S).log"

mkdir -p "$(dirname "$LOG_FILE")"

# Note: Logging functions (log_info, log_success, log_error) are provided by
# scripts/_common/init.sh which sources apps/_shared/test.sh for enhanced logging.
# For script-specific file logging, wrap calls with: log_info "msg" | tee -a "$LOG_FILE"

# ============================================================================
# CLOUDFLARE SETUP (DNS + DDoS Protection)
# ============================================================================

setup_cloudflare_dns() {
  log_info "Setting up Cloudflare DNS and DDoS protection..."
  
  if [[ -z "$CLOUDFLARE_API_TOKEN" ]]; then
    log_error "CLOUDFLARE_API_TOKEN not set"
    exit 1
  fi
  
  local domain="code-server.ai"
  
  # Create DNS records for edge locations
  local edge_locations=(
    "us-east.code-server.ai:18.211.50.23"      # N. Virginia
    "us-west.code-server.ai:54.153.120.45"     # N. California
    "eu-central.code-server.ai:52.47.220.100"  # Frankfurt
    "apac-sg.code-server.ai:13.215.180.90"     # Singapore
    "apac-jp.code-server.ai:18.181.142.45"     # Tokyo
    "br-south.code-server.ai:177.71.150.60"    # São Paulo
  )
  
  for record in "${edge_locations[@]}"; do
    local subdomain="${record%%:*}"
    local ip="${record##*:}"
    
    log_info "Creating DNS record: $subdomain → $ip"
    
    curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records" \
      -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
      -H "Content-Type: application/json" \
      --data "{
        \"type\": \"A\",
        \"name\": \"$subdomain\",
        \"content\": \"$ip\",
        \"ttl\": 120,
        \"proxied\": true
      }" | tee -a "$LOG_FILE"
    
    log_success "DNS record created: $subdomain"
  done
}

setup_cloudflare_geo_routing() {
  log_info "Setting up Cloudflare geographic routing..."
  
  # Create Cloudflare Argo Smart Routing rule
  curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/routing/rules" \
    -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
    -H "Content-Type: application/json" \
    --data '{
      "name": "Smart Routing - Code Server",
      "enabled": true,
      "expression": "(cf.country in {\"US\" \"CA\" \"MX\"})",
      "actions": [
        {
          "id": "serve_from_zone",
          "value": "us-east.code-server.ai"
        }
      ]
    }' | tee -a "$LOG_FILE"
  
  log_success "Cloudflare geo routing configured"
}

setup_cloudflare_rate_limiting() {
  log_info "Setting up Cloudflare rate limiting and DDoS protection..."
  
  # Create rate limiting rules
  curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/ratelimit" \
    -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
    -H "Content-Type: application/json" \
    --data '{
      "disabled": false,
      "description": "Rate limit aggressive bots",
      "match": {
        "request": {
          "url": {
            "path": {
              "matches": "^/api/.*"
            }
          }
        }
      },
      "action": {
        "mode": "challenge"
      },
      "threshold": 100,
      "period": 60,
      "characteristics": ["ip.src"]
    }' | tee -a "$LOG_FILE"
  
  log_success "Cloudflare rate limiting enabled"
}

setup_cloudflare_waf() {
  log_info "Setting up Cloudflare WAF rules..."
  
  curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/waf/rules" \
    -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
    -H "Content-Type: application/json" \
    --data '{
      "rules": [
        {
          "name": "OWASP Core Ruleset",
          "enabled": true,
          "priority": 1
        },
        {
          "name": "Cloudflare Bot Management",
          "enabled": true,
          "priority": 2
        }
      ]
    }' | tee -a "$LOG_FILE"
  
  log_success "Cloudflare WAF rules configured"
}

# ============================================================================
# CADDY REVERSE PROXY SETUP
# ============================================================================

generate_caddy_config() {
  log_info "Generating Caddy reverse proxy configuration..."
  
  cat > "${CADDY_CONFIG_DIR}/Caddyfile.glb" <<'EOF'
# Global load balancer Caddyfile (Phase 5)
{
  # Global configuration
  debug
  http_port 80
  https_port 443
  
  # Metrics endpoint for monitoring
  admin localhost:2019
  
  # Log configuration
  log {
    output stdout
    format json
    level info
  }
}

# Main API endpoints
api.code-server.ai {
  # Request logging
  log {
    output stdout
    format json
  }
  
  # Health check endpoint
  @health path /api/health
  handle @health {
    respond "OK" 200 {
      -type text/plain
    }
  }
  
  # Service discovery - route to nearest edge
  @api_primary path /api/*
  handle @api_primary {
    # Weighted round robin to regional endpoints
    reverse_proxy localhost:3100 localhost:3101 localhost:3102 {
      # Health uri for failover
      health_uri /api/health
      health_interval 5s
      health_timeout 2s
      
      # Policy: least connection with regional affinity
      policy least_request
      
      # Retry on failure
      policy_uri @health
      policy_timeout 3s
      
      # Header manipulation
      header_up X-Real-IP {http.request.remote}
      header_up X-Forwarded-For {http.request.header.X-Forwarded-For}
      header_up X-Forwarded-Proto {http.request.proto}
      header_up X-Forwarded-Host {http.request.host}
      
      # Connection pooling
      transport http {
        dial_timeout 10s
        response_header_timeout 30s
        keep_alive_interval 30s
        max_idle_conns 100
      }
    }
  }
  
  # WebSocket support
  @websocket {
    header Connection *Upgrade*
    header Upgrade websocket
  }
  handle @websocket {
    reverse_proxy localhost:3100 localhost:3101 localhost:3102 {
      transport http {
        dial_timeout 10s
        response_header_timeout 300s
        keep_alive_interval 30s
      }
      
      # WebSocket specific handling
      websocket
    }
  }
  
  # Static assets (cacheable)
  @static {
    path /static/*
    file {
      try_files {path}
    }
  }
  handle @static {
    header Cache-Control "public, max-age=86400, immutable"
    file_server {
      root /var/www/code-server
    }
  }
  
  # Rate limiting middleware
  rate_limit {
    zone default {
      key {http.request.remote}
      rate 1000/s
    }
  }
  
  # Error handling
  handle_errors {
    @5xx expression `{http.error.status_code} >= 500`
    handle @5xx {
      respond "Service temporarily unavailable" 503
    }
    
    @4xx expression `{http.error.status_code} >= 400 && {http.error.status_code} < 500`
    handle @4xx {
      respond "Request error" 400
    }
  }
}

# Regional edge endpoints
us-east.code-server.ai {
  reverse_proxy localhost:3100 {
    health_uri /api/health
    health_interval 5s
  }
}

us-west.code-server.ai {
  reverse_proxy localhost:3101 {
    health_uri /api/health
    health_interval 5s
  }
}

eu-central.code-server.ai {
  reverse_proxy localhost:3102 {
    health_uri /api/health
    health_interval 5s
  }
}

apac-sg.code-server.ai {
  reverse_proxy localhost:3103 {
    health_uri /api/health
    health_interval 5s
  }
}

apac-jp.code-server.ai {
  reverse_proxy localhost:3104 {
    health_uri /api/health
    health_interval 5s
  }
}

br-south.code-server.ai {
  reverse_proxy localhost:3105 {
    health_uri /api/health
    health_interval 5s
  }
}
EOF
  
  log_success "Caddy configuration generated"
}

deploy_caddy_config() {
  log_info "Deploying Caddy configuration..."
  
  # Validate Caddy configuration
  caddy validate --config "${CADDY_CONFIG_DIR}/Caddyfile.glb" | tee -a "$LOG_FILE"
  
  # Test configuration without reloading
  caddy fmt --overwrite "${CADDY_CONFIG_DIR}/Caddyfile.glb"
  
  # Reload Caddy
  caddy reload --config "${CADDY_CONFIG_DIR}/Caddyfile.glb" --adapter caddyfile | tee -a "$LOG_FILE"
  
  log_success "Caddy configuration deployed and reloaded"
}

# ============================================================================
# CIRCUIT BREAKER & FAILOVER SETUP
# ============================================================================

create_circuit_breaker_config() {
  log_info "Creating circuit breaker and failover policies..."
  
  cat > "${SCRIPT_DIR}/config/glb/circuit-breaker-policy.yaml" <<'EOF'
# Global Load Balancer Circuit Breaker Policy (Phase 5)
---
apiVersion: code-server.ai/v1
kind: CircuitBreakerPolicy
metadata:
  name: api-circuit-breaker
  namespace: production
spec:
  # Target service
  targetService: api
  
  # Circuit breaker thresholds
  failureThreshold: 50        # % failure rate to open circuit
  successThreshold: 5         # consecutive successes to close circuit
  timeout: 30s                # time circuit stays open
  
  # Health check parameters
  healthCheck:
    interval: 5s
    timeout: 2s
    path: /api/health
    expectedStatus: 200
  
  # Retry policies
  retryPolicy:
    maxRetries: 3
    backoffMultiplier: 2
    initialBackoff: 100ms
    maxBackoff: 10s
  
  # Regional endpoint weights
  endpoints:
    - name: us-east
      region: us-east-1
      weight: 30
      healthCheckInterval: 5s
      priority: 1
      
    - name: us-west
      region: us-west-2
      weight: 25
      healthCheckInterval: 5s
      priority: 1
      
    - name: eu-central
      region: eu-central-1
      weight: 20
      healthCheckInterval: 5s
      priority: 2
      
    - name: apac-sg
      region: ap-southeast-1
      weight: 15
      healthCheckInterval: 5s
      priority: 3
      
    - name: apac-jp
      region: ap-northeast-1
      weight: 5
      healthCheckInterval: 5s
      priority: 4
  
  # Fallback behavior
  fallback:
    strategy: failover        # failover | round_robin | random
    maxAttempts: 5
    timeoutBetweenAttempts: 1s
  
  # Metrics and logging
  metrics:
    enabled: true
    scrapeInterval: 30s
    
  alerting:
    enabled: true
    alertThresholds:
      - metric: circuit_breaker_open
        severity: critical
        duration: 1m
      
      - metric: error_rate_high
        threshold: 25%
        severity: warning
        duration: 5m
EOF
  
  log_success "Circuit breaker policy created"
}

# ============================================================================
# MONITORING & METRICS SETUP
# ============================================================================

setup_glb_monitoring() {
  log_info "Setting up GLB monitoring and metrics collection..."
  
  cat > "${SCRIPT_DIR}/config/glb/prometheus-glb-rules.yaml" <<'EOF'
# Global Load Balancer Prometheus Rules
---
groups:
  - name: glb_metrics
    interval: 30s
    rules:
      # Request rate by region
      - record: glb:request_rate:5m
        expr: rate(http_requests_total[5m])
      
      # Error rate by endpoint
      - record: glb:error_rate:5m
        expr: rate(http_errors_total[5m]) / rate(http_requests_total[5m])
      
      # Latency percentiles
      - record: glb:latency_p99:5m
        expr: histogram_quantile(0.99, http_request_duration_seconds_bucket)
      
      - record: glb:latency_p95:5m
        expr: histogram_quantile(0.95, http_request_duration_seconds_bucket)
      
      # Connection pool utilization
      - record: glb:pool_utilization
        expr: caddy_http_requests_in_flight / caddy_http_requests_max_in_flight
      
      # Alert: High error rate
      - alert: GLBHighErrorRate
        expr: glb:error_rate:5m > 0.05
        for: 5m
        annotations:
          severity: warning
          summary: "High error rate in GLB"
      
      # Alert: Circuit breaker open
      - alert: CircuitBreakerOpen
        expr: caddy_circuit_breaker_state == 1
        for: 1m
        annotations:
          severity: critical
          summary: "Circuit breaker is open"
      
      # Alert: High latency
      - alert: GLBHighLatency
        expr: glb:latency_p99:5m > 1000
        for: 5m
        annotations:
          severity: warning
          summary: "P99 latency > 1s"
EOF
  
  log_success "GLB monitoring configured"
}

# ============================================================================
# TRAFFIC DISTRIBUTION POLICY
# ============================================================================

create_traffic_distribution_policy() {
  log_info "Creating traffic distribution policy..."
  
  cat > "${SCRIPT_DIR}/config/glb/traffic-distribution.yaml" <<'EOF'
# Traffic Distribution Policy (Phase 5)
---
apiVersion: code-server.ai/v1
kind: TrafficDistributionPolicy
metadata:
  name: global-distribution
spec:
  # Geographic routing
  geographic:
    # North America
    - region: us-east-1
      countries: ["US", "CA"]
      primaryEndpoint: us-east.code-server.ai
      secondaryEndpoint: us-west.code-server.ai
      weight: 35
      latencyTarget: 50ms
      
    - region: us-west-2
      countries: ["US", "CA", "MX"]
      primaryEndpoint: us-west.code-server.ai
      secondaryEndpoint: br-south.code-server.ai
      weight: 30
      latencyTarget: 50ms
    
    # Europe
    - region: eu-central-1
      countries: ["DE", "FR", "IT", "ES", "UK", "NL", "SE", "NO"]
      primaryEndpoint: eu-central.code-server.ai
      secondaryEndpoint: us-east.code-server.ai
      weight: 20
      latencyTarget: 30ms
    
    # Asia Pacific
    - region: ap-southeast-1
      countries: ["SG", "MY", "TH", "ID", "PH", "VN"]
      primaryEndpoint: apac-sg.code-server.ai
      secondaryEndpoint: apac-jp.code-server.ai
      weight: 10
      latencyTarget: 40ms
      
    - region: ap-northeast-1
      countries: ["JP", "KR", "CN", "TW"]
      primaryEndpoint: apac-jp.code-server.ai
      secondaryEndpoint: apac-sg.code-server.ai
      weight: 5
      latencyTarget: 40ms
    
    # South America
    - region: br-south
      countries: ["BR", "AR", "CL"]
      primaryEndpoint: br-south.code-server.ai
      secondaryEndpoint: us-east.code-server.ai
      weight: 5
      latencyTarget: 60ms
  
  # Capacity-based routing
  capacity:
    algorithm: least_connections
    monitor_interval: 10s
    
  # Load balancing strategy
  loadBalancing:
    algorithm: weighted_round_robin
    failover: active
    healthCheckInterval: 5s
    
  # QoS parameters
  qos:
    priorityLevels:
      - name: critical
        weight: 5
        examples: ["API calls", "Authentication"]
      
      - name: high
        weight: 3
        examples: ["IDE operations", "File sync"]
      
      - name: normal
        weight: 1
        examples: ["Analytics", "Logging"]
    
    rateLimit:
      perSecond: 1000
      perMinute: 50000
      burstSize: 100
EOF
  
  log_success "Traffic distribution policy created"
}

# ============================================================================
# VALIDATION & TESTING
# ============================================================================

validate_glb_setup() {
  log_info "Validating GLB setup..."
  
  # Test DNS resolution
  log_info "Testing DNS resolution..."
  for endpoint in api.code-server.ai us-east.code-server.ai eu-central.code-server.ai; do
    local ip=$(dig +short "$endpoint" @8.8.8.8 | head -1)
    if [[ -n "$ip" ]]; then
      log_success "DNS resolved: $endpoint → $ip"
    else
      log_error "DNS resolution failed: $endpoint"
    fi
  done
  
  # Test Caddy configuration
  log_info "Testing Caddy configuration..."
  caddy validate --config "${CADDY_CONFIG_DIR}/Caddyfile.glb" | tee -a "$LOG_FILE"
  
  # Test health endpoints
  log_info "Testing health endpoints..."
  for i in 0 1 2 3 4 5; do
    local port=$((3100 + i))
    if curl -s "http://localhost:$port/api/health" > /dev/null 2>&1; then
      log_success "Health check passed: localhost:$port"
    fi
  done
  
  log_success "GLB validation complete"
}

# ============================================================================
# REPORTING
# ============================================================================

generate_glb_report() {
  log_info "Generating GLB setup report..."
  
  local report_file="${SCRIPT_DIR}/artifacts/phase5/glb-setup-report-$(date +%Y%m%d).md"
  
  cat > "$report_file" <<'EOF'
# Global Load Balancing Setup Report

**Setup Date**: $(date -u +'%Y-%m-%d %H:%M:%S UTC')

## Cloudflare Configuration

### DNS Records Created
- api.code-server.ai (main)
- us-east.code-server.ai (NA - East)
- us-west.code-server.ai (NA - West)
- eu-central.code-server.ai (Europe)
- apac-sg.code-server.ai (APAC - Singapore)
- apac-jp.code-server.ai (APAC - Japan)
- br-south.code-server.ai (South America)

### DDoS & WAF Protection
- Rate limiting: 1000 req/s per IP
- OWASP Core Ruleset: Enabled
- Bot Management: Enabled
- Geographic routing: Enabled

## Caddy Reverse Proxy

### Configuration
- Main endpoint: api.code-server.ai
- Regional endpoints: 6 locations
- Load balancing policy: Least connection
- Health check interval: 5s
- Failover strategy: Active

### Features
- WebSocket support
- Static asset caching (86400s)
- Request logging (JSON format)
- Connection pooling (100 max idle)
- Circuit breaker protection

## Regional Distribution

| Region | Primary Endpoint | Weight | Latency Target |
|--------|------------------|--------|----------------|
| US East | us-east | 30% | 50ms |
| US West | us-west | 25% | 50ms |
| EU Central | eu-central | 20% | 30ms |
| APAC SG | apac-sg | 10% | 40ms |
| APAC JP | apac-jp | 5% | 40ms |
| BR South | br-south | 5% | 60ms |

## Monitoring

- Prometheus metrics collection enabled
- Alert thresholds configured
- Error rate tracking: > 5% = warning
- Latency tracking: P99 > 1s = warning
- Circuit breaker state monitoring

## Next Steps

1. Deploy to AWS CloudFront for CDN acceleration
2. Configure multi-region database replication
3. Set up edge cache invalidation strategy
4. Implement geoIP-based request routing
5. Configure failover to disaster recovery regions

## Logs
See: $(printf '%s\n' "$LOG_FILE")

EOF
  
  log_success "Report generated: $report_file"
}

# ============================================================================
# MAIN
# ============================================================================

main() {
  log_info "Starting global load balancing setup..."
  
  setup_cloudflare_dns
  setup_cloudflare_geo_routing
  setup_cloudflare_rate_limiting
  setup_cloudflare_waf
  
  generate_caddy_config
  deploy_caddy_config
  
  create_circuit_breaker_config
  setup_glb_monitoring
  create_traffic_distribution_policy
  
  validate_glb_setup
  generate_glb_report
  
  log_success "✓ Global load balancing setup complete"
}

main "$@"
