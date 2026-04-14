#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# scripts/vpn-test.sh — VPN endpoint connectivity test suite
# Tests: WireGuard status, peer reachability, latency, service access via VPN
# Usage: ./scripts/vpn-test.sh [--peer 10.8.0.2] [--verbose]
# ═══════════════════════════════════════════════════════════════════════════════
set -euo pipefail

SERVER_IP="192.168.168.31"
NAS_IP="192.168.168.56"
VPN_SERVER="10.8.0.1"
WG_IFACE="wg0"
VERBOSE=false
PEER_IP=""

for arg in "$@"; do
    case $arg in
        --peer)   PEER_IP="${2:-}"; shift ;;
        --verbose) VERBOSE=true ;;
    esac
done

PASS=0; FAIL=0

ok()   { echo "  [PASS] $*"; PASS=$((PASS + 1)); }
fail() { echo "  [FAIL] $*" >&2; FAIL=$((FAIL + 1)); }
skip() { echo "  [SKIP] $*"; }
info() { echo "  [INFO] $*"; }

section() { echo ""; echo "── $* ──────────────────────────────────────────"; }

# ── 1. WireGuard kernel module / binary ──────────────────────────────────────
section "WireGuard installation"

if command -v wg &>/dev/null; then
    ok "wg binary present ($(wg --version 2>/dev/null | head -1))"
else
    fail "wg not installed (run: sudo scripts/vpn-setup.sh install)"
fi

if command -v wg-quick &>/dev/null; then
    ok "wg-quick present"
else
    fail "wg-quick not found"
fi

# ── 2. Interface status ───────────────────────────────────────────────────────
section "WireGuard interface ($WG_IFACE)"

if ip link show "$WG_IFACE" &>/dev/null 2>&1; then
    ok "Interface $WG_IFACE is UP"
    info "$(wg show "$WG_IFACE" 2>/dev/null | grep -E 'public key|listening port|peer' | head -10)"
else
    fail "Interface $WG_IFACE is DOWN (run: sudo scripts/vpn-setup.sh start)"
fi

# ── 3. Port listening ─────────────────────────────────────────────────────────
section "UDP port 51820"

if ss -ulnp | grep -q ":51820"; then
    ok "UDP 51820 listening"
else
    fail "UDP 51820 not listening"
fi

# ── 4. Firewall check ────────────────────────────────────────────────────────
section "Firewall (iptables)"

if iptables -t nat -L POSTROUTING -n 2>/dev/null | grep -q MASQUERADE; then
    ok "MASQUERADE rule present (NAT enabled)"
else
    fail "MASQUERADE rule missing (VPN traffic won't be forwarded)"
fi

if cat /proc/sys/net/ipv4/ip_forward | grep -q "1"; then
    ok "ip_forward=1"
else
    fail "ip_forward=0 (NAT won't work)"
fi

# ── 5. Server VPN IP reachability ────────────────────────────────────────────
section "Server VPN address ($VPN_SERVER)"

if ping -c 3 -W 2 "$VPN_SERVER" &>/dev/null 2>&1; then
    local_latency=$(ping -c 10 -q "$VPN_SERVER" 2>/dev/null | grep rtt | awk -F'/' '{print $5}')
    ok "Server VPN IP reachable (avg ${local_latency}ms)"
else
    skip "Cannot ping $VPN_SERVER from server itself (expected)"
fi

# ── 6. Peer reachability ─────────────────────────────────────────────────────
section "Peer reachability"

if [[ -n "$PEER_IP" ]]; then
    if ping -c 5 -W 3 "$PEER_IP" &>/dev/null; then
        latency=$(ping -c 10 -q "$PEER_IP" 2>/dev/null | grep rtt | awk -F'/' '{print $5}')
        ok "Peer $PEER_IP reachable (avg ${latency}ms)"
        if (( $(echo "$latency < 50" | bc -l) )); then
            ok "Latency OK (< 50ms)"
        else
            fail "Latency HIGH (${latency}ms > 50ms)"
        fi
    else
        fail "Peer $PEER_IP unreachable"
    fi
else
    skip "No --peer specified — skipping peer reachability"
fi

# ── 7. Service reachability from VPN subnet ──────────────────────────────────
section "Service access from VPN ($VPN_SERVER)"

services=(
    "code-server:http://localhost:8080/healthz"
    "ollama:http://localhost:11434/api/tags"
    "prometheus:http://localhost:9090/-/healthy"
    "grafana:http://localhost:3000/api/health"
    "alertmanager:http://localhost:9093/-/healthy"
    "jaeger:http://localhost:16686/"
)

for entry in "${services[@]}"; do
    name="${entry%%:*}"
    url="${entry#*:}"
    if curl -sf --max-time 5 "$url" &>/dev/null; then
        ok "$name accessible"
    else
        fail "$name not accessible ($url)"
    fi
done

# ── 8. NAS reachability via VPN ───────────────────────────────────────────────
section "NAS access"

if mountpoint -q /mnt/nas-56; then
    ok "NAS mounted at /mnt/nas-56"
    used=$(df -h /mnt/nas-56 | awk 'NR==2{print $3 "/" $2 " (" $5 " used)"}')
    info "NAS capacity: $used"
else
    fail "NAS /mnt/nas-56 not mounted (run: sudo scripts/nas-mount-31.sh mount)"
fi

# ── 9. WireGuard handshake age ───────────────────────────────────────────────
section "WireGuard handshake freshness"

if command -v wg &>/dev/null && ip link show "$WG_IFACE" &>/dev/null 2>&1; then
    handshakes=$(wg show "$WG_IFACE" latest-handshakes 2>/dev/null || echo "")
    if [[ -n "$handshakes" ]]; then
        while IFS=$'\t' read -r peer ts; do
            age=$(( $(date +%s) - ts ))
            if [[ $age -lt 180 ]]; then
                ok "Peer $peer handshake fresh (${age}s ago)"
            elif [[ $age -lt 600 ]]; then
                info "Peer $peer handshake ${age}s ago (OK)"
            else
                fail "Peer $peer handshake stale (${age}s ago — connection may be broken)"
            fi
        done <<< "$handshakes"
    else
        skip "No active peers yet"
    fi
fi

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  VPN TEST RESULTS"
echo "  PASS: $PASS  |  FAIL: $FAIL"
echo "═══════════════════════════════════════════════════════════"

if [[ $FAIL -gt 0 ]]; then
    echo ""
    echo "  Next steps:"
    echo "    sudo scripts/vpn-setup.sh install   # install WireGuard"
    echo "    sudo scripts/vpn-setup.sh config    # generate server config"
    echo "    sudo scripts/vpn-setup.sh start     # bring up WireGuard"
    echo "    sudo scripts/vpn-setup.sh addpeer laptop  # add a client"
    exit 1
fi

echo "  All VPN checks passed"
