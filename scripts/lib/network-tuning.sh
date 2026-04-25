#!/usr/bin/env bash
# @file        scripts/lib/network-tuning.sh
# @module      lib/network
# @description Network stack optimization for high-performance systems
# @governance  GOV-002: Immutable, version-controlled, idempotent infrastructure
# Issue #1536: Networking, DNS & Performance — Network Tuning

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${REPO_ROOT}/scripts/_common/logging.sh"

# ── Configuration ─────────────────────────────────────────────────────────────

# Network interface (primary)
NETWORK_IFACE="${NETWORK_IFACE:-eth0}"

# Performance targets
TARGET_TCP_WINDOW_SIZE="${TARGET_TCP_WINDOW_SIZE:-65535}"     # Max TCP window (64KB)
TARGET_SOCKET_BUFFER="${TARGET_SOCKET_BUFFER:-134217728}"    # 128MB per socket
TARGET_NETDEV_BACKLOG="${TARGET_NETDEV_BACKLOG:-5000}"       # Device backlog
TARGET_TCP_MAX_CONNECTIONS="${TARGET_TCP_MAX_CONNECTIONS:-100000}"  # Max connections

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
pass() { printf "${GREEN}✔${NC} %s\n" "$*"; }
fail() { printf "${RED}✖${NC} %s\n" "$*" >&2; }
warn() { printf "${YELLOW}⚠${NC} %s\n" "$*" >&2; }

# ── TCP Window Scaling ────────────────────────────────────────────────────────

# Enable TCP window scaling (for high-latency/high-bandwidth links)
enable_tcp_window_scaling() {
  local current
  current=$(sysctl -n net.ipv4.tcp_window_scaling 2>/dev/null || echo "0")

  if [ "${current}" != "1" ]; then
    sysctl -w net.ipv4.tcp_window_scaling=1 || return 1
    pass "TCP window scaling enabled"
  else
    pass "TCP window scaling already enabled"
  fi
  return 0
}

# ── TCP Buffers ───────────────────────────────────────────────────────────────

# Optimize TCP send/receive buffers (for high throughput)
optimize_tcp_buffers() {
  local rmem_default rmem_max wmem_default wmem_max
  
  # Read buffer defaults
  sysctl -w net.ipv4.tcp_rmem="4096 87380 ${TARGET_SOCKET_BUFFER}" || return 1
  pass "TCP read buffer optimized: 4KB min, 87KB default, ${TARGET_SOCKET_BUFFER}B max"

  # Write buffer defaults
  sysctl -w net.ipv4.tcp_wmem="4096 65536 ${TARGET_SOCKET_BUFFER}" || return 1
  pass "TCP write buffer optimized: 4KB min, 64KB default, ${TARGET_SOCKET_BUFFER}B max"

  # Socket buffer limits
  sysctl -w net.core.rmem_max="${TARGET_SOCKET_BUFFER}" || return 1
  sysctl -w net.core.wmem_max="${TARGET_SOCKET_BUFFER}" || return 1
  pass "Socket buffer maximums set to ${TARGET_SOCKET_BUFFER}B"

  return 0
}

# ── Connection Handling ───────────────────────────────────────────────────────

# Optimize TCP connection backlog (for accept queue)
optimize_tcp_backlog() {
  # Listen backlog (queue of incoming connections waiting to be accepted)
  sysctl -w net.ipv4.tcp_max_syn_backlog=5000 || return 1
  sysctl -w net.ipv4.somaxconn=5000 || return 1
  pass "TCP listen backlog optimized to 5000"

  # Network device backlog
  sysctl -w net.core.netdev_max_backlog="${TARGET_NETDEV_BACKLOG}" || return 1
  pass "Network device backlog set to ${TARGET_NETDEV_BACKLOG}"

  return 0
}

# ── Connection Reuse ─────────────────────────────────────────────────────────

# Enable TCP connection reuse (for high-frequency clients)
enable_tcp_reuse() {
  # Allow reusing ports in TIME_WAIT state
  sysctl -w net.ipv4.tcp_tw_reuse=1 || return 1
  pass "TCP TIME_WAIT reuse enabled (for client connections)"

  # Recycle TIME_WAIT connections (faster reuse, but less safe)
  # WARNING: Disable if behind NAT
  # sysctl -w net.ipv4.tcp_tw_recycle=1 || return 1

  # Maximum TIME_WAIT timeout (default 60s, reduce to 30s)
  sysctl -w net.ipv4.tcp_fin_timeout=30 || return 1
  pass "TCP FIN timeout reduced to 30s"

  return 0
}

# ── TCP Keepalive ────────────────────────────────────────────────────────────

# Configure TCP keepalive (detects dead connections)
configure_tcp_keepalive() {
  # Time before first probe (seconds)
  sysctl -w net.ipv4.tcp_keepalive_time=300 || return 1
  # Interval between probes (seconds)
  sysctl -w net.ipv4.tcp_keepalive_intvl=30 || return 1
  # Number of probes before giving up
  sysctl -w net.ipv4.tcp_keepalive_probes=5 || return 1
  pass "TCP keepalive: 300s initial, 30s interval, 5 probes"

  return 0
}

# ── TCP Congestion Control ────────────────────────────────────────────────────

# Set TCP congestion control algorithm (for LAN vs WAN)
set_tcp_congestion_control() {
  local algorithm="${1:-bbr}"  # Default to BBR (best for WAN)

  # Available algorithms: reno, cubic, bbr, dctcp
  if [ "${algorithm}" = "bbr" ]; then
    sysctl -w net.core.default_qdisc=fq || return 1
    sysctl -w net.ipv4.tcp_congestion_control=bbr || return 1
    pass "TCP congestion control: BBR (high-bandwidth networks)"
  elif [ "${algorithm}" = "cubic" ]; then
    sysctl -w net.ipv4.tcp_congestion_control=cubic || return 1
    pass "TCP congestion control: CUBIC (balanced)"
  elif [ "${algorithm}" = "reno" ]; then
    sysctl -w net.ipv4.tcp_congestion_control=reno || return 1
    pass "TCP congestion control: RENO (legacy)"
  else
    fail "Unknown congestion control algorithm: ${algorithm}"
    return 1
  fi

  return 0
}

# ── Network Interface Tuning ──────────────────────────────────────────────────

# Optimize MTU for jumbo frames (if supported)
optimize_mtu() {
  local mtu="${1:-9000}"  # Default to jumbo frames (9KB)
  
  ip link show "${NETWORK_IFACE}" >/dev/null 2>&1 || {
    fail "Interface ${NETWORK_IFACE} not found"
    return 1
  }

  ip link set dev "${NETWORK_IFACE}" mtu "${mtu}" || return 1
  pass "MTU set to ${mtu} bytes (jumbo frames)"

  return 0
}

# ── System Resource Limits ────────────────────────────────────────────────────

# Increase maximum open file descriptors (per process)
increase_ulimits() {
  # Check current limits
  local soft_limit hard_limit
  soft_limit=$(ulimit -Sn 2>/dev/null || echo "1024")
  hard_limit=$(ulimit -Hn 2>/dev/null || echo "65535")

  if [ "${soft_limit}" -lt 65535 ]; then
    ulimit -Sn 65535 || return 1
    pass "Soft limit for open files increased to 65535"
  else
    pass "Open file limit already at ${soft_limit}"
  fi

  # Persist limits in /etc/security/limits.conf
  if [ -w /etc/security/limits.conf ]; then
    {
      echo "* soft nofile 65535"
      echo "* hard nofile 65535"
    } >> /etc/security/limits.conf 2>/dev/null || true
  fi

  return 0
}

# ── Connection Pool Analysis ──────────────────────────────────────────────────

# Check current network connection states
analyze_connections() {
  echo ""
  echo "=== Network Connection Analysis ==="
  echo ""

  # Establish rate
  echo "Listening ports:"
  ss -tlnp 2>/dev/null | awk 'NR>1 {print $4}' | sort | uniq -c

  echo ""
  echo "Connection states:"
  ss -s 2>/dev/null | grep -E "TCP|UDP" || netstat -sn | grep -E "Tcp|Udp"

  echo ""
  echo "Active connections:"
  echo "  Established: $(ss -tn 2>/dev/null | grep ESTAB | wc -l)"
  echo "  TIME_WAIT: $(ss -tn 2>/dev/null | grep TIME-WAIT | wc -l)"
  echo "  Close_WAIT: $(ss -tn 2>/dev/null | grep CLOSE-WAIT | wc -l)"

  return 0
}

# ── Latency Measurement ──────────────────────────────────────────────────────

# Measure end-to-end latency to target
measure_latency() {
  local target="${1}"
  local iterations="${2:-10}"

  if [ -z "${target}" ]; then
    fail "Target IP/hostname required"
    return 1
  fi

  if ! command -v ping &>/dev/null; then
    fail "ping command not found"
    return 1
  fi

  echo ""
  echo "=== Latency to ${target} ==="

  # Ping with summary
  ping -c "${iterations}" "${target}" 2>&1 | tail -4

  return 0
}

# ── TCP Performance Analysis ──────────────────────────────────────────────────

# Show current TCP performance parameters
show_tcp_settings() {
  echo ""
  echo "=== TCP Network Settings ==="
  echo ""

  echo "Window Scaling:"
  sysctl -n net.ipv4.tcp_window_scaling 2>/dev/null || echo "N/A"

  echo ""
  echo "TCP Buffers:"
  echo "  Read: $(sysctl -n net.ipv4.tcp_rmem 2>/dev/null | tr '\t' ' ' || echo 'N/A')"
  echo "  Write: $(sysctl -n net.ipv4.tcp_wmem 2>/dev/null | tr '\t' ' ' || echo 'N/A')"

  echo ""
  echo "Socket Limits:"
  echo "  Max read: $(sysctl -n net.core.rmem_max 2>/dev/null || echo 'N/A') bytes"
  echo "  Max write: $(sysctl -n net.core.wmem_max 2>/dev/null || echo 'N/A') bytes"

  echo ""
  echo "Connection Handling:"
  echo "  Backlog: $(sysctl -n net.ipv4.tcp_max_syn_backlog 2>/dev/null || echo 'N/A')"
  echo "  Max connections: $(sysctl -n net.ipv4.tcp_max_connections 2>/dev/null || echo 'N/A')"

  echo ""
  echo "Congestion Control:"
  sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "N/A"

  echo ""
}

# ── Full Network Tuning ───────────────────────────────────────────────────────

# Apply all network optimizations
apply_network_tuning() {
  echo ""
  echo "=== Applying Network Performance Tuning ==="
  echo ""

  local failed=0

  # Run all tuning steps
  enable_tcp_window_scaling || ((failed++))
  optimize_tcp_buffers || ((failed++))
  optimize_tcp_backlog || ((failed++))
  enable_tcp_reuse || ((failed++))
  configure_tcp_keepalive || ((failed++))
  set_tcp_congestion_control bbr || ((failed++))
  
  # Network interface tuning (may fail if not supported)
  optimize_mtu 9000 || true
  
  # Increase limits
  increase_ulimits || ((failed++))

  echo ""
  if [ ${failed} -eq 0 ]; then
    pass "All network tuning applied successfully"
    return 0
  else
    warn "Network tuning partially applied (${failed} steps failed)"
    return 1
  fi
}

# ── Persistence to /etc/sysctl.d/ ─────────────────────────────────────────────

# Write tuning parameters to persistent sysctl configuration
persist_network_tuning() {
  local config_file="/etc/sysctl.d/99-network-performance.conf"

  if [ ! -w "$(dirname "${config_file}")" ]; then
    fail "Cannot write to /etc/sysctl.d/ (requires root)"
    return 1
  fi

  cat > "${config_file}" <<'EOF'
# Network Performance Tuning
# Epic #1536 Phase 6
# Source: scripts/lib/network-tuning.sh

# ── TCP Window Scaling
net.ipv4.tcp_window_scaling = 1

# ── TCP Buffers (128MB max)
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728

# ── Connection Backlog
net.ipv4.tcp_max_syn_backlog = 5000
net.ipv4.somaxconn = 5000
net.core.netdev_max_backlog = 5000

# ── Connection Reuse
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30

# ── TCP Keepalive
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5

# ── TCP Congestion Control (BBR)
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq
EOF

  pass "Persistent configuration saved to ${config_file}"
  return 0
}

# ── Export Functions ───────────────────────────────────────────────────────────

export -f enable_tcp_window_scaling
export -f optimize_tcp_buffers
export -f optimize_tcp_backlog
export -f enable_tcp_reuse
export -f configure_tcp_keepalive
export -f set_tcp_congestion_control
export -f optimize_mtu
export -f increase_ulimits
export -f analyze_connections
export -f measure_latency
export -f show_tcp_settings
export -f apply_network_tuning
export -f persist_network_tuning
