#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# scripts/vpn-setup.sh — WireGuard VPN server setup
# Server : 192.168.168.31 (on-prem)
# VPN net: 10.8.0.0/24
# Port   : 51820/udp
# Usage  : sudo ./scripts/vpn-setup.sh [install|genkey|addpeer|status|start|stop]
# ═══════════════════════════════════════════════════════════════════════════════
set -euo pipefail

SERVER_IP="192.168.168.31"
VPN_SUBNET="10.8.0.0/24"
SERVER_VPN_IP="10.8.0.1"
WG_IFACE="wg0"
WG_PORT="51820"
WG_CONF="/etc/wireguard/${WG_IFACE}.conf"
PEER_DIR="/etc/wireguard/peers"

log()  { echo "[vpn-setup] $*"; }
ok()   { echo "[vpn-setup] OK: $*"; }
die()  { echo "[vpn-setup] FATAL: $*" >&2; exit 1; }

require_root() {
    [[ $EUID -eq 0 ]] || die "Must be run as root (sudo)"
}

# ── Detect outbound interface ──────────────────────────────────────────────
get_wan_iface() {
    ip route get 8.8.8.8 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' | head -1
}

# ── Install WireGuard ──────────────────────────────────────────────────────
install_wg() {
    require_root
    if command -v wg &>/dev/null; then
        ok "WireGuard already installed ($(wg --version))"
        return 0
    fi
    log "Installing WireGuard..."
    apt-get update -qq
    apt-get install -y -qq wireguard wireguard-tools
    ok "WireGuard installed"
}

# ── Generate server keys ──────────────────────────────────────────────────
genkey_server() {
    require_root
    install_wg

    if [[ -f "/etc/wireguard/server_private.key" ]]; then
        log "Server keys already exist"
        return 0
    fi

    local priv pub
    priv=$(wg genkey)
    pub=$(echo "$priv" | wg pubkey)

    echo "$priv" > /etc/wireguard/server_private.key
    echo "$pub"  > /etc/wireguard/server_public.key
    chmod 600 /etc/wireguard/server_private.key

    ok "Server keys generated"
    echo "  Public key: $pub"
}

# ── Write server config ───────────────────────────────────────────────────
write_server_config() {
    require_root
    genkey_server

    local priv wan_iface
    priv=$(cat /etc/wireguard/server_private.key)
    wan_iface=$(get_wan_iface)

    log "Writing server config (iface: $wan_iface)..."
    mkdir -p "$(dirname "$WG_CONF")"
    cat > "$WG_CONF" <<CONFEOF
# WireGuard server — 192.168.168.31
# Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)
# MANAGED BY scripts/vpn-setup.sh — do not edit manually

[Interface]
Address    = ${SERVER_VPN_IP}/24
ListenPort = ${WG_PORT}
PrivateKey = ${priv}

# NAT: forward VPN traffic to internet
PostUp   = iptables -A FORWARD -i %i -j ACCEPT; iptables -t nat -A POSTROUTING -o ${wan_iface} -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -t nat -D POSTROUTING -o ${wan_iface} -j MASQUERADE

# Peers are appended by vpn-setup.sh addpeer
CONFEOF

    chmod 600 "$WG_CONF"
    ok "Server config written to $WG_CONF"

    # Enable IP forwarding
    echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-wg.conf
    sysctl -p /etc/sysctl.d/99-wg.conf &>/dev/null
    ok "IP forwarding enabled"
}

# ── Add peer ──────────────────────────────────────────────────────────────
add_peer() {
    require_root
    [[ -f "$WG_CONF" ]] || write_server_config

    local peer_name="${1:-peer1}"
    mkdir -p "$PEER_DIR"

    # Find next available IP in 10.8.0.x
    local last_used
    last_used=$(grep -oP '10\.8\.0\.\K[0-9]+' "$WG_CONF" 2>/dev/null | sort -n | tail -1 || echo "1")
    local next_ip="10.8.0.$((last_used + 1))"

    local peer_priv peer_pub psk
    peer_priv=$(wg genkey)
    peer_pub=$(echo "$peer_priv" | wg pubkey)
    psk=$(wg genpsk)

    local server_pub
    server_pub=$(cat /etc/wireguard/server_public.key)

    # Write peer client config
    local peer_conf="${PEER_DIR}/${peer_name}.conf"
    cat > "$peer_conf" <<PEEREOF
# WireGuard client config — ${peer_name}
# Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)
# Copy to client: /etc/wireguard/wg0.conf

[Interface]
PrivateKey = ${peer_priv}
Address    = ${next_ip}/24
DNS        = 1.1.1.1

[Peer]
PublicKey           = ${server_pub}
PresharedKey        = ${psk}
Endpoint            = ${SERVER_IP}:${WG_PORT}
AllowedIPs          = ${VPN_SUBNET}
PersistentKeepalive = 25
PEEREOF
    chmod 600 "$peer_conf"

    # Append peer to server config
    cat >> "$WG_CONF" <<APPENDEOF

# Peer: ${peer_name} (added $(date -u +%Y-%m-%dT%H:%M:%SZ))
[Peer]
PublicKey    = ${peer_pub}
PresharedKey = ${psk}
AllowedIPs   = ${next_ip}/32
APPENDEOF

    # Hot-add peer to running interface (no restart needed)
    if wg show "$WG_IFACE" &>/dev/null; then
        wg addconf "$WG_IFACE" <(tail -n +2 "$WG_CONF" | grep -A3 "Peer: ${peer_name}" || true)
    fi

    ok "Peer '${peer_name}' added — IP: ${next_ip}"
    echo "  Client config: ${peer_conf}"
    echo "  Distribute to peer securely (scp / GSM / secret manager)"
}

# ── Start / Stop / Status ─────────────────────────────────────────────────
start_vpn() {
    require_root
    [[ -f "$WG_CONF" ]] || write_server_config
    systemctl enable --now "wg-quick@${WG_IFACE}"
    ok "VPN started (wg-quick@${WG_IFACE})"
    wg show "$WG_IFACE"
}

stop_vpn() {
    require_root
    systemctl stop "wg-quick@${WG_IFACE}" 2>/dev/null || true
    ok "VPN stopped"
}

status_vpn() {
    if ip link show "$WG_IFACE" &>/dev/null; then
        wg show "$WG_IFACE"
        echo ""
        echo "VPN subnet: $VPN_SUBNET (server: $SERVER_VPN_IP)"
        echo "Peers:"
        ls "${PEER_DIR}"/*.conf 2>/dev/null | while read -r f; do
            local name; name=$(basename "$f" .conf)
            echo "  $name → $(grep -oP '10\.8\.0\.[0-9]+' "$f" | head -1)"
        done
    else
        echo "WireGuard interface $WG_IFACE is DOWN"
        return 1
    fi
}

# ─────────────────────────────────────────────────────────────────────────────

case "${1:-status}" in
    install)       install_wg ;;
    genkey)        genkey_server ;;
    config)        write_server_config ;;
    addpeer)       add_peer "${2:-peer1}" ;;
    start)         start_vpn ;;
    stop)          stop_vpn ;;
    status)        status_vpn ;;
    *)
        echo "Usage: sudo $0 [install|genkey|config|addpeer <name>|start|stop|status]"
        exit 1
        ;;
esac
