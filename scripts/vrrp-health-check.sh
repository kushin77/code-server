#!/bin/bash
# VRRP Health Check Script
# P2 #365: Virtual IP Failover Implementation
# Purpose: Validate all critical services for VRRP failover decision
# Generated: April 15, 2026

set -euo pipefail

HOST="${1:-primary}"
THRESHOLD=3
ERRORS=0
LOG_FILE="/var/log/keepalived/health-check.log"

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

# Helper function for logging
log_error() {
    local msg="$1"
    echo "[$(date -Iseconds)] ❌ $msg" >> "$LOG_FILE"
    echo "❌ $msg"
    ((ERRORS++))
}

log_success() {
    local msg="$1"
    echo "[$(date -Iseconds)] ✅ $msg" >> "$LOG_FILE"
}

# Check 1: Code-server port 8080 responding
if timeout 2 bash -c "echo >/dev/tcp/127.0.0.1/8080" >/dev/null 2>&1; then
    log_success "Code-server port 8080 responding"
else
    log_error "Code-server port 8080 not responding"
fi

# Check 2: PostgreSQL responding
if ! timeout 3 psql -h 127.0.0.1 -U postgres -d postgres -c "SELECT 1" >/dev/null 2>&1; then
    log_error "PostgreSQL not responding"
else
    log_success "PostgreSQL responding"
fi

# Check 3: Redis responding
if redis-cli -h 127.0.0.1 ping 2>/dev/null | grep -q PONG; then
    log_success "Redis responding"
else
    log_error "Redis not responding"
fi

# Check 4: Caddy responding on HTTPS (ignore cert validation)
if timeout 3 curl -f -s -k https://127.0.0.1:8443/live >/dev/null 2>&1; then
    log_success "Caddy HTTPS responding"
else
    log_error "Caddy HTTPS port 8443 not responding"
fi

# Check 5: Prometheus responding
if timeout 3 curl -f -s http://127.0.0.1:9090/-/healthy >/dev/null 2>&1; then
    log_success "Prometheus responding"
else
    log_error "Prometheus not responding"
fi

# Check 6: Docker-compose services running
RUNNING_SERVICES=$(docker-compose ps --services --filter "status=running" 2>/dev/null | wc -l || echo 0)
EXPECTED_SERVICES=10  # Adjust based on your docker-compose.yml

if (( RUNNING_SERVICES >= EXPECTED_SERVICES )); then
    log_success "Docker services running ($RUNNING_SERVICES)"
else
    log_error "Insufficient Docker services running ($RUNNING_SERVICES < $EXPECTED_SERVICES)"
fi

# Check 7: Replication lag (replica only)
if [[ "$HOST" == "replica" ]]; then
    LAG=$(psql -h 127.0.0.1 -U postgres -d postgres -c \
        "SELECT EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp())) AS lag;" 2>/dev/null | \
        grep -oP '[0-9]+\.[0-9]+|[0-9]+' | head -1 || echo "999")
    
    # Alert if lag is significant (>60 seconds)
    if (( $(echo "$LAG > 60" | bc -l 2>/dev/null || echo 0) )); then
        log_error "Replication lag too high: ${LAG}s (>60s threshold)"
    else
        log_success "Replication lag acceptable: ${LAG}s"
    fi
else
    log_success "Primary host - skipping replication lag check"
fi

# Check 8: Network connectivity to other host
if [[ "$HOST" == "primary" ]]; then
    OTHER_HOST="192.168.168.42"
else
    OTHER_HOST="192.168.168.31"
fi

if timeout 2 ping -c 1 "$OTHER_HOST" >/dev/null 2>&1; then
    log_success "Network connectivity to $OTHER_HOST OK"
else
    log_error "Cannot reach $OTHER_HOST"
fi

# Determine exit code based on error count
if (( ERRORS >= THRESHOLD )); then
    echo "[$(date -Iseconds)] HEALTH CHECK FAILED: $ERRORS errors (threshold: $THRESHOLD)" >> "$LOG_FILE"
    exit 1  # Failure - trigger failover weight reduction
else
    echo "[$(date -Iseconds)] HEALTH CHECK PASSED: $ERRORS errors" >> "$LOG_FILE"
    exit 0  # Success - maintain VRRP state
fi
