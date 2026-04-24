#!/usr/bin/env bash
# @file        scripts/ops/check-caddy-port-binding.sh
# @module      ops/monitoring
# @description Monitor Caddy port 80/443 binding state across all replicas, detect phantom binding
#
# Purpose:
#   - Verify Caddy is actually bound to ports 80/443 (not phantom kernel state)
#   - Detect if port binding is by Caddy process or orphaned kernel binding
#   - Alert on degraded cluster state (e.g., Replica 2 phantom binding)
#   - Provide evidence for maintenance decision
#
# Usage:
#   bash scripts/ops/check-caddy-port-binding.sh [--replicas R31,R42] [--alert] [--json]
#
# Example:
#   bash scripts/ops/check-caddy-port-binding.sh
#   bash scripts/ops/check-caddy-port-binding.sh --json | jq .replicas
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/../_common/init.sh"

# ============================================================================
# CONFIG
# ============================================================================

DEFAULT_REPLICAS="192.168.168.31,192.168.168.42"
REPLICAS="$DEFAULT_REPLICAS"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_rsa_onprem}"
SSH_USER="${SSH_USER:-akushnir}"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Alert flag
ALERT_MODE=0
JSON_MODE=0

# ============================================================================
# PARSE ARGS
# ============================================================================

while [[ $# -gt 0 ]]; do
  case "$1" in
    --alert) ALERT_MODE=1; shift ;;
    --json) JSON_MODE=1; shift ;;
    --replicas) REPLICAS="$2"; shift 2 ;;
    --help|-h)
      cat <<EOF
Usage: bash scripts/ops/check-caddy-port-binding.sh [--replicas R31,R42] [--alert] [--json]

Options:
  --replicas  Comma-separated list of replica hosts to check (default: $DEFAULT_REPLICAS)
  --alert     Exit 2 when degraded replicas are detected
  --json      Emit machine-readable JSON output
EOF
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# ============================================================================
# FUNCTIONS
# ============================================================================

# Check port binding on a single replica via SSH
check_replica_port_binding() {
  local replica_host="$1"
  local port="$2"
  
  local port_status
  local process_name
  local process_pid
  
  # Query netstat via SSH
  local netstat_output
  netstat_output=$(ssh -i "$SSH_KEY" -o ConnectTimeout=5 -o StrictHostKeyChecking=no \
    "$SSH_USER@$replica_host" "netstat -tlnp 2>/dev/null | grep :$port | head -1" 2>/dev/null || echo "")
  
  if [[ -z "$netstat_output" ]]; then
    # Port not bound
    port_status="unbound"
    process_name="none"
    process_pid="0"
  else
    # Extract process info from netstat output
    # Format: tcp 0 0 0.0.0.0:PORT 0.0.0.0:* LISTEN PID/process_name
    process_info=$(echo "$netstat_output" | awk '{print $NF}')
    
    if [[ "$process_info" == "-" ]]; then
      # Phantom binding (no process)
      port_status="phantom"
      process_name="kernel-phantom"
      process_pid="N/A"
    else
      # Actual process binding
      process_pid=$(echo "$process_info" | cut -d'/' -f1)
      process_name=$(echo "$process_info" | cut -d'/' -f2)
      
      if [[ "$process_name" == "caddy" ]]; then
        port_status="healthy"
      else
        port_status="unexpected-process"
      fi
    fi
  fi
  
  echo "$port_status|$process_name|$process_pid"
}

# Check if Caddy container is actually running
check_caddy_container() {
  local replica_host="$1"
  
  local caddy_status
  caddy_status=$(ssh -i "$SSH_KEY" -o ConnectTimeout=5 -o StrictHostKeyChecking=no \
    "$SSH_USER@$replica_host" "docker ps --filter name=caddy --format '{{.Status}}' 2>/dev/null || echo ''" 2>/dev/null)
  
  if [[ -z "$caddy_status" ]]; then
    echo "error"
  elif [[ "$caddy_status" =~ "Up" ]]; then
    echo "running"
  elif [[ "$caddy_status" =~ "Created" ]]; then
    echo "created"
  else
    echo "stopped"
  fi
}

# ============================================================================
# MAIN
# ============================================================================

REPLICA_ARRAY=(${REPLICAS//,/ })
HEALTHY_COUNT=0
DEGRADED_COUNT=0
FAILED_COUNT=0

declare -A REPLICA_RESULTS

for replica in "${REPLICA_ARRAY[@]}"; do
  replica_host=$(echo "$replica" | xargs) # Trim whitespace
  
  # Get binding status for port 80
  port80_result=$(check_replica_port_binding "$replica_host" "80" || echo "error|error|0")
  port80_status=$(echo "$port80_result" | cut -d'|' -f1)
  port80_process=$(echo "$port80_result" | cut -d'|' -f2)
  port80_pid=$(echo "$port80_result" | cut -d'|' -f3)
  
  # Get Caddy container status
  caddy_container=$(check_caddy_container "$replica_host" || echo "error")
  
  # Determine overall replica health
  if [[ "$port80_status" == "healthy" && "$caddy_container" == "running" ]]; then
    replica_health="healthy"
    HEALTHY_COUNT=$((HEALTHY_COUNT + 1))
  elif [[ "$port80_status" == "phantom" ]]; then
    replica_health="degraded-phantom-binding"
    DEGRADED_COUNT=$((DEGRADED_COUNT + 1))
  elif [[ "$port80_status" == "unbound" ]]; then
    replica_health="degraded-port-unbound"
    DEGRADED_COUNT=$((DEGRADED_COUNT + 1))
  else
    replica_health="error"
    FAILED_COUNT=$((FAILED_COUNT + 1))
  fi
  
  # Store results
  REPLICA_RESULTS[$replica_host]="$replica_health|$port80_status|$port80_process|$port80_pid|$caddy_container"
done

# ============================================================================
# OUTPUT
# ============================================================================

if [[ $JSON_MODE -eq 1 ]]; then
  # JSON output
  cat <<EOF
{
  "timestamp": "$TIMESTAMP",
  "cluster_health": {
    "healthy": $HEALTHY_COUNT,
    "degraded": $DEGRADED_COUNT,
    "failed": $FAILED_COUNT,
    "total": ${#REPLICA_ARRAY[@]}
  },
  "replicas": {
EOF
  
  first=1
  for replica_host in "${!REPLICA_RESULTS[@]}"; do
    if [[ $first -eq 0 ]]; then echo ","; fi
    first=0
    
    IFS='|' read -r health port80_status port80_process port80_pid caddy_container <<< "${REPLICA_RESULTS[$replica_host]}"
    
    cat <<EOF
    "$replica_host": {
      "health": "$health",
      "port_80": {
        "status": "$port80_status",
        "process": "$port80_process",
        "pid": "$port80_pid"
      },
      "caddy_container": "$caddy_container"
    }
EOF
  done
  
  cat <<EOF

  }
}
EOF
else
  # Human-readable output
  echo ""
  log_section "CADDY PORT BINDING HEALTH CHECK"
  echo "Timestamp: $TIMESTAMP"
  echo ""
  
  for replica_host in "${!REPLICA_RESULTS[@]}"; do
    IFS='|' read -r health port80_status port80_process port80_pid caddy_container <<< "${REPLICA_RESULTS[$replica_host]}"
    
    case "$health" in
      healthy)
        echo -e "${GREEN}✓${NC} $replica_host"
        ;;
      degraded-phantom-binding)
        echo -e "${YELLOW}⚠${NC} $replica_host — Port 80 phantom binding (no process)"
        ;;
      degraded-port-unbound)
        echo -e "${YELLOW}⚠${NC} $replica_host — Port 80 unbound (Caddy internal-only)"
        ;;
      error)
        echo -e "${RED}❌${NC} $replica_host — Error communicating with replica"
        ;;
    esac
    
    echo "    Port 80 Status: $port80_status"
    echo "    Process: $port80_process (PID: $port80_pid)"
    echo "    Caddy Container: $caddy_container"
    echo ""
  done
  
  # Summary
  log_section "SUMMARY"
  echo "Healthy: $HEALTHY_COUNT / ${#REPLICA_ARRAY[@]}"
  echo "Degraded: $DEGRADED_COUNT / ${#REPLICA_ARRAY[@]}"
  echo "Failed: $FAILED_COUNT / ${#REPLICA_ARRAY[@]}"
  
  if [[ $HEALTHY_COUNT -eq ${#REPLICA_ARRAY[@]} ]]; then
    log_success "All replicas operational, full external routing available"
    exit 0
  elif [[ $DEGRADED_COUNT -gt 0 ]]; then
    log_warn "Degraded cluster state, external routing limited to healthy replicas"
    if [[ $ALERT_MODE -eq 1 ]]; then
      exit 2
    else
      exit 0
    fi
  else
    log_error "Cluster error state, routing may be unavailable"
    exit 1
  fi
fi
