#!/usr/bin/env bash
################################################################################
# File:          scripts/_common/docker.sh
# Owner:         Platform Engineering
# Purpose:       Centralized Docker/Compose operations on the remote host.
#                Eliminates inline docker ps + docker exec + docker compose
#                patterns duplicated across 50+ scripts.
# Compatibility: bash 4.0+
# Dependencies:  _common/config.sh, _common/logging.sh, _common/ssh.sh
# Source:        Loaded automatically by _common/init.sh — do NOT source directly
# Last Updated:  April 14, 2026
################################################################################

[[ -n "${_COMMON_DOCKER_LOADED:-}" ]] && return 0
readonly _COMMON_DOCKER_LOADED=1

# ─────────────────────────────────────────────────────────────────────────────
# CONTAINER STATE
# ─────────────────────────────────────────────────────────────────────────────

# Get container status string (e.g. "Up 2 hours (healthy)")
# Usage: docker_status code-server
docker_status() {
    local name="$1"
    ssh_exec "docker ps -a --filter name='^/${name}$' --format '{{.Status}}'" 2>/dev/null || echo "not found"
}

# Returns 0 if container is running (any running state)
# Usage: docker_is_running code-server && echo "up"
docker_is_running() {
    local status
    status=$(docker_status "$1")
    [[ "$status" == Up* ]]
}

# Returns 0 if container is healthy (Docker healthcheck passed)
# Usage: docker_is_healthy prometheus || log_error "prometheus unhealthy"
docker_is_healthy() {
    local status
    status=$(docker_status "$1")
    [[ "$status" == *"(healthy)"* ]]
}

# Print a formatted status table for all enterprise containers
# Usage: docker_status_all
docker_status_all() {
    ssh_exec "docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' | \
              grep -E 'NAMES|${CONTAINER_CODE_SERVER}|${CONTAINER_CADDY}|${CONTAINER_OLLAMA}|${CONTAINER_POSTGRES}|${CONTAINER_REDIS}|${CONTAINER_PROMETHEUS}|${CONTAINER_GRAFANA}|${CONTAINER_ALERTMANAGER}'"
}

# ─────────────────────────────────────────────────────────────────────────────
# CONTAINER OPERATIONS
# ─────────────────────────────────────────────────────────────────────────────

# Start one or more containers (or all if none specified)
# Usage: docker_start code-server caddy
docker_start() {
    log_info "Starting containers: ${*:-all}"
    ssh_compose "up -d $*"
}

# Restart one or more containers
# Usage: docker_restart caddy
docker_restart() {
    log_info "Restarting containers: $*"
    ssh_exec "docker restart $*"
}

# Stop one or more containers
# Usage: docker_stop code-server
docker_stop() {
    log_info "Stopping containers: $*"
    ssh_exec "docker stop $* 2>/dev/null || true"
}

# Execute a command inside a running container
# Usage: docker_exec_in code-server "ls /home/coder"
docker_exec_in() {
    local container="$1"
    shift
    ssh_exec "docker exec $container $*"
}

# Tail logs from a container
# Usage: docker_logs code-server 50
docker_logs() {
    local container="$1"
    local lines="${2:-50}"
    ssh_exec "docker logs $container --tail $lines 2>&1"
}

# ─────────────────────────────────────────────────────────────────────────────
# HEALTH CHECKING
# ─────────────────────────────────────────────────────────────────────────────

# Wait for a container to become healthy, with timeout
# Usage: docker_wait_healthy prometheus 60
docker_wait_healthy() {
    local container="$1"
    local timeout="${2:-$HEALTH_CHECK_TIMEOUT}"
    local elapsed=0
    local interval=3

    log_info "Waiting for $container to become healthy (timeout: ${timeout}s)..."
    while (( elapsed < timeout )); do
        if docker_is_healthy "$container"; then
            log_success "$container is healthy"
            return 0
        fi
        if ! docker_is_running "$container"; then
            log_error "$container stopped unexpectedly"
            docker_logs "$container" 20
            return 1
        fi
        sleep "$interval"
        elapsed=$(( elapsed + interval ))
    done

    log_error "$container did not become healthy within ${timeout}s"
    docker_logs "$container" 30
    return 1
}

# Assert a container is healthy, fatal if not
# Usage: assert_container_healthy grafana
assert_container_healthy() {
    docker_wait_healthy "$1" "$HEALTH_CHECK_TIMEOUT" || log_fatal "$1 failed health check"
}

# ─────────────────────────────────────────────────────────────────────────────
# HTTP ENDPOINT CHECKS
# ─────────────────────────────────────────────────────────────────────────────

# Assert an HTTP endpoint returns the expected status code
# Usage: assert_http_ok http://192.168.168.31:8080/ 200
assert_http_ok() {
    local url="$1"
    local expected="${2:-200}"
    local actual
    actual=$(ssh_exec "curl -sk -o /dev/null -w '%{http_code}' '$url'" 2>/dev/null || echo "000")
    if [[ "$actual" != "$expected" ]]; then
        log_error "HTTP check failed: $url → got $actual, expected $expected"
        return 1
    fi
    log_debug "✓ HTTP $actual: $url"
}

# Run health checks on all enterprise services
# Usage: docker_healthcheck_all
docker_healthcheck_all() {
    local fail=0

    log_section "Enterprise Service Health Check"

    docker_is_running "$CONTAINER_CODE_SERVER" \
        && log_success "$CONTAINER_CODE_SERVER is running" \
        || { log_error "$CONTAINER_CODE_SERVER is NOT running"; fail=1; }

    docker_is_running "$CONTAINER_CADDY" \
        && log_success "$CONTAINER_CADDY is running" \
        || { log_error "$CONTAINER_CADDY is NOT running"; fail=1; }

    docker_is_running "$CONTAINER_OLLAMA" \
        && log_success "$CONTAINER_OLLAMA is running" \
        || { log_warn "$CONTAINER_OLLAMA is not running (non-critical)"; }

    docker_is_healthy "$CONTAINER_PROMETHEUS" \
        && log_success "$CONTAINER_PROMETHEUS is healthy" \
        || { log_warn "$CONTAINER_PROMETHEUS health unknown"; }

    docker_is_healthy "$CONTAINER_GRAFANA" \
        && log_success "$CONTAINER_GRAFANA is healthy" \
        || { log_warn "$CONTAINER_GRAFANA health unknown"; }

    return $fail
}
