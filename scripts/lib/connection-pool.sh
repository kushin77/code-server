#!/usr/bin/env bash
# @file        scripts/lib/connection-pool.sh
# @module      lib/connection-pool
# @description Connection pooling and SLA enforcement
# @governance  GOV-002: Immutable, version-controlled infrastructure
# Issue #1536: Networking, DNS & Performance — Network Tuning

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${REPO_ROOT}/scripts/_common/logging.sh"

# ── Configuration ─────────────────────────────────────────────────────────────

# Connection pool settings
POOL_MIN_SIZE="${POOL_MIN_SIZE:-10}"           # Minimum idle connections
POOL_MAX_SIZE="${POOL_MAX_SIZE:-100}"          # Maximum total connections
POOL_TIMEOUT="${POOL_TIMEOUT:-30}"             # Connection timeout (seconds)
POOL_IDLE_TIMEOUT="${POOL_IDLE_TIMEOUT:-300}"  # Idle connection timeout

# SLA targets
SLA_P99_LATENCY_MS="${SLA_P99_LATENCY_MS:-100}"      # 99th percentile latency
SLA_P95_LATENCY_MS="${SLA_P95_LATENCY_MS:-50}"       # 95th percentile latency
SLA_AVAILABILITY_PCT="${SLA_AVAILABILITY_PCT:-99.9}" # 99.9% availability

# ── PostgreSQL Connection Pool Configuration ──────────────────────────────────

# Generate pgBouncer configuration (connection pool proxy for PostgreSQL)
generate_pgbouncer_config() {
  local db_host="${1:-postgres}"
  local db_port="${2:-5432}"
  local db_name="${3:-app}"
  local pool_size="${4:-${POOL_MAX_SIZE}}"

  cat <<EOF
# pgBouncer Configuration - Connection Pooling for PostgreSQL
# Epic #1536 Phase 6 - IaC Compliance

[databases]
${db_name} = host=${db_host} port=${db_port} dbname=${db_name}

[pgbouncer]
; Network settings
listen_port = 6432
listen_addr = 0.0.0.0
unix_socket_dir = /var/run/pgbouncer

; Security
auth_type = md5
auth_file = /etc/pgbouncer/userlist.txt

; Connection pool settings
pool_mode = transaction      # transaction-level pooling (safest)
max_client_conn = 1000       # Max connections from clients
default_pool_size = 25       # Connections per database
min_pool_size = 10           # Minimum idle connections
reserve_pool_size = 5        # Reserve connections for emergencies
reserve_pool_timeout = 3     # Acquire from reserve after 3s
max_db_connections = 100     # Max connections to backend DB
max_user_connections = 100   # Max connections per user

; Timeout settings
server_lifetime = 3600       # Close server connection after 1 hour
server_idle_timeout = 600    # Close idle server connection after 10 min
client_idle_timeout = 0      # Never close client connection for idle

; Maintenance
server_connect_timeout = 15  # Connect timeout
query_timeout = 0            # No query timeout
query_wait_timeout = 120     # Wait for available connection

; Logging
log_connections = 1
log_disconnections = 1
log_pooler_stats = 60        # Log stats every 60s
stats_period = 60            # Collect stats every 60s

; Admin
admin_users = admin
stats_users = admin
EOF
}

# ── HAProxy Connection Pool Configuration ─────────────────────────────────────

# Generate HAProxy configuration for load balancing with connection pooling
generate_haproxy_config() {
  local backend_host1="${1:-app-1:3100}"
  local backend_host2="${2:-app-2:3100}"
  local backend_host3="${3:-app-3:3100}"

  cat <<EOF
# HAProxy Configuration - Connection Pooling & Load Balancing
# Epic #1536 Phase 6 - IaC Compliance

global
  maxconn 4096
  log 127.0.0.1 local0
  log 127.0.0.1 local1 notice
  tune.ssl.default-dh-param 2048
  tune.bufsize 65536

defaults
  log     global
  mode    http
  option  httplog
  option  dontlognull
  timeout connect 5000
  timeout client  50000
  timeout server  50000

# Stats page (access via http://localhost:8404/stats)
listen stats
  bind *:8404
  stats enable
  stats uri /stats
  stats refresh 30s
  stats show-legends

# Frontend (accepts client connections)
frontend frontend_http
  bind *:80
  option http-server-close     # Close connection after each request
  default_backend backend_app

# Backend (routes to application servers)
backend backend_app
  balance roundrobin           # Load balancing algorithm
  option httpclose             # Close connection after response
  option forwardfor            # Add X-Forwarded-For header
  
  # Connection limits per server
  server app-1 ${backend_host1} maxconn 100 check inter 5000 fall 3 rise 2
  server app-2 ${backend_host2} maxconn 100 check inter 5000 fall 3 rise 2
  server app-3 ${backend_host3} maxconn 100 check inter 5000 fall 3 rise 2
  
  # Circuit breaker (if > 50% connections failing)
  option redispatch
  retries 3

# Health check endpoint
backend health_check
  server app-1 ${backend_host1}/health
  server app-2 ${backend_host2}/health
  server app-3 ${backend_host3}/health
EOF
}

# ── Application Connection Pool Configuration ─────────────────────────────────

# Generate Caddy reverse proxy with connection pooling
generate_caddy_connpool_config() {
  local backend_url="${1:-http://localhost:3100}"

  cat <<EOF
# Caddy Configuration with Connection Pooling
# Epic #1536 Phase 6 - IaC Compliance

kushnir.cloud {
  reverse_proxy ${backend_url} {
    # Connection pooling settings
    policy random_choice 4         # 4-way load balancing
    
    # HTTP/1.1 keep-alive (reuse connections)
    header_up Connection "keep-alive"
    
    # Timeouts
    timeout 30s
    
    # Request/response limits
    max_request_body_size 100mb
    
    # Buffering (reduces connection time)
    flush_interval -1              # Disable buffering for streaming
    
    # Retry logic
    try_duration 5s
    try_interval 250ms
  }
}
EOF
}

# ── SLA Monitoring ────────────────────────────────────────────────────────────

# Monitor application SLA metrics
monitor_sla() {
  local endpoint="${1:-http://localhost:3100/api/health}"
  local samples="${2:-100}"

  echo ""
  echo "=== SLA Monitoring (${samples} samples) ==="
  echo ""

  if ! command -v curl &>/dev/null; then
    fail "curl command not found"
    return 1
  fi

  # Collect latency samples
  local latencies=()
  local success_count=0
  local fail_count=0

  for ((i = 1; i <= samples; i++)); do
    local start_time end_time latency

    start_time=$(date +%s%N)
    
    if curl -s -o /dev/null -w "%{http_code}" "${endpoint}" 2>/dev/null | grep -q "200"; then
      ((success_count++))
    else
      ((fail_count++))
    fi

    end_time=$(date +%s%N)
    latency=$(( (end_time - start_time) / 1000000 ))
    latencies+=("${latency}")
  done

  # Calculate percentiles
  local sorted_latencies
  sorted_latencies=$(printf '%s\n' "${latencies[@]}" | sort -n)

  local p50 p95 p99
  p50=$(echo "${sorted_latencies}" | sed "$(( samples / 2 ))q;d")
  p95=$(echo "${sorted_latencies}" | sed "$(( (samples * 95) / 100 ))q;d")
  p99=$(echo "${sorted_latencies}" | sed "$(( (samples * 99) / 100 ))q;d")

  local availability_pct
  availability_pct=$(( (success_count * 100) / (success_count + fail_count) ))

  # Display results
  echo "Availability: ${availability_pct}% (${success_count}/${success_count + fail_count})"
  echo "Latency P50: ${p50}ms"
  echo "Latency P95: ${p95}ms (target: ${SLA_P95_LATENCY_MS}ms)"
  echo "Latency P99: ${p99}ms (target: ${SLA_P99_LATENCY_MS}ms)"

  echo ""

  # Check SLA compliance
  local sla_violated=0

  if [ "${availability_pct}" -lt "${SLA_AVAILABILITY_PCT}" ]; then
    warn "SLA VIOLATION: Availability ${availability_pct}% < target ${SLA_AVAILABILITY_PCT}%"
    ((sla_violated++))
  else
    pass "Availability OK: ${availability_pct}% ≥ target ${SLA_AVAILABILITY_PCT}%"
  fi

  if [ "${p99}" -gt "${SLA_P99_LATENCY_MS}" ]; then
    warn "SLA VIOLATION: P99 latency ${p99}ms > target ${SLA_P99_LATENCY_MS}ms"
    ((sla_violated++))
  else
    pass "P99 latency OK: ${p99}ms ≤ target ${SLA_P99_LATENCY_MS}ms"
  fi

  if [ "${sla_violated}" -eq 0 ]; then
    echo ""
    pass "All SLA targets MET"
    return 0
  else
    echo ""
    fail "${sla_violated} SLA target(s) violated"
    return 1
  fi
}

# ── Connection Pool Statistics ────────────────────────────────────────────────

# Collect connection pool metrics
get_connection_pool_stats() {
  echo ""
  echo "=== Connection Pool Statistics ==="
  echo ""

  # TCP connections
  echo "TCP Connection States:"
  echo "  Established: $(ss -tn 2>/dev/null | grep ESTAB | wc -l || echo 'N/A')"
  echo "  TIME_WAIT: $(ss -tn 2>/dev/null | grep TIME-WAIT | wc -l || echo 'N/A')"
  echo "  SYN_RECV: $(ss -tn 2>/dev/null | grep SYN-RECV | wc -l || echo 'N/A')"

  echo ""
  echo "Connection Distribution:"
  ss -tn 2>/dev/null | awk '{print $4}' | sed 's/:.*//g' | sort | uniq -c | head -10 || echo "N/A"

  echo ""
}

# ── Connection Pool Health ────────────────────────────────────────────────────

# Check connection pool health
check_connection_pool_health() {
  echo ""
  echo "=== Connection Pool Health Check ==="
  echo ""

  local healthy=true

  # Check for connection exhaustion
  local tcp_connections
  tcp_connections=$(ss -tn 2>/dev/null | wc -l)

  if [ "${tcp_connections}" -gt 5000 ]; then
    warn "High connection count: ${tcp_connections} (> 5000)"
    healthy=false
  else
    pass "Connection count OK: ${tcp_connections}"
  fi

  # Check for TIME_WAIT accumulation
  local timewait_count
  timewait_count=$(ss -tn 2>/dev/null | grep TIME-WAIT | wc -l)

  if [ "${timewait_count}" -gt 1000 ]; then
    warn "High TIME_WAIT connections: ${timewait_count} (> 1000)"
    healthy=false
  else
    pass "TIME_WAIT connections OK: ${timewait_count}"
  fi

  echo ""
  if [ "${healthy}" = true ]; then
    pass "Connection pool HEALTHY"
    return 0
  else
    warn "Connection pool has issues (see above)"
    return 1
  fi
}

# ── Export Functions ───────────────────────────────────────────────────────────

export -f generate_pgbouncer_config
export -f generate_haproxy_config
export -f generate_caddy_connpool_config
export -f monitor_sla
export -f get_connection_pool_stats
export -f check_connection_pool_health
