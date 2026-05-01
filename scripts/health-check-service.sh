#!/bin/bash

#############################################################################
# Health Check Service for HAProxy Load Balancer
#
# Purpose: Continuous monitoring of critical services with automatic
#          status file generation for HAProxy routing decisions
#
# Features:
#   - Monitors PostgreSQL, Redis, Vault on both hosts
#   - Detects failures within 5 seconds
#   - Generates status files for HAProxy read
#   - Logs state changes automatically
#############################################################################

set -e

readonly HEALTH_CHECK_DIR="/var/lib/haproxy/health"
readonly PRIMARY_HOST="192.168.168.31"
readonly REPLICA_HOST="192.168.168.42"
readonly CHECK_INTERVAL=5
readonly TIMEOUT=3
readonly LOG_FILE="/var/log/health-check-service.log"

# Trap error and exit handlers
trap 'echo "[ERROR] Health check failed at line $LINENO"; exit 1' ERR
trap 'echo "[INFO] Health check service stopping"; exit 0' EXIT

mkdir -p "$HEALTH_CHECK_DIR"

check_service() {
  local host="$1"
  local port="$2"
  local service_name="$3"
  
  local health_file="${HEALTH_CHECK_DIR}/${host}_${service_name}.status"
  local prev_status=""
  
  [[ -f "$health_file" ]] && prev_status=$(cat "$health_file")
  
  if timeout "$TIMEOUT" bash -c "echo >/dev/tcp/$host/$port" 2>/dev/null; then
    echo "up" > "$health_file"
    [[ "$prev_status" == "down" ]] && echo "[$(date +'%T')] $service_name@$host: RECOVERED" | tee -a "$LOG_FILE"
  else
    echo "down" > "$health_file"
    [[ "$prev_status" == "up" ]] && echo "[$(date +'%T')] $service_name@$host: FAILED" | tee -a "$LOG_FILE"
  fi
}

# Continuous health monitoring
while true; do
  check_service "$PRIMARY_HOST" 5432 postgres
  check_service "$PRIMARY_HOST" 6379 redis
  check_service "$PRIMARY_HOST" 8200 vault
  
  check_service "$REPLICA_HOST" 5432 postgres
  check_service "$REPLICA_HOST" 6379 redis
  check_service "$REPLICA_HOST" 8200 vault
  
  sleep "$CHECK_INTERVAL"
done
