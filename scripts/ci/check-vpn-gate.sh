#!/usr/bin/env bash
# @file        scripts/ci/check-vpn-gate.sh
# @module      ci/security
# @description Enforce VPN-only E2E test execution gate.
#              E2E tests against production endpoints must originate from approved VPN context.
#              Exits 0 if VPN context verified, exits 1 (fail-fast) if not.
#
# Usage: bash scripts/ci/check-vpn-gate.sh [--warn-only]

set -euo pipefail

WARN_ONLY="${1:-}"
VPN_ALLOWED_CIDRS="${VPN_ALLOWED_CIDRS:-10.0.0.0/8 192.168.0.0/16 172.16.0.0/12}"
REQUIRE_VPN="${REQUIRE_VPN:-1}"

_log()  { echo "[vpn-gate] $*"; }
_warn() { echo "[vpn-gate] WARN: $*" >&2; }
_fail() {
  echo "[vpn-gate] BLOCKED: $*" >&2
  if [[ "$WARN_ONLY" == "--warn-only" ]]; then
    return 0
  fi
  return 1
}

# Detect current outbound IP
detect_local_ip() {
  if [[ -n "${VPN_LOCAL_IP:-}" ]]; then
    echo "$VPN_LOCAL_IP"
    return 0
  fi

  # Try to get routable IP
  if command -v ip >/dev/null 2>&1; then
    ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' | head -1
  elif command -v hostname >/dev/null 2>&1; then
    hostname -I 2>/dev/null | awk '{print $1}'
  elif command -v ifconfig >/dev/null 2>&1; then
    ifconfig 2>/dev/null | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | head -1
  else
    echo ""
  fi
}

# Check if IP is in any of the allowed CIDR ranges
ip_in_vpn_range() {
  local ip="$1"
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$ip" "$VPN_ALLOWED_CIDRS" << 'EOF'
import sys, ipaddress
ip = sys.argv[1]
cidrs = sys.argv[2].split()
try:
    addr = ipaddress.ip_address(ip)
    for cidr in cidrs:
        if addr in ipaddress.ip_network(cidr, strict=False):
            sys.exit(0)
    sys.exit(1)
except Exception:
    sys.exit(1)
EOF
  else
    # Simple string prefix check fallback
    local first_octet
    first_octet=$(echo "$ip" | cut -d. -f1)
    case "$first_octet" in
      10|192|172) return 0 ;;
      *) return 1 ;;
    esac
  fi
}

# ── Skip gate if not requiring VPN (non-production CI) ───────────────────────
if [[ "$REQUIRE_VPN" != "1" ]]; then
  _log "VPN gate disabled (REQUIRE_VPN!=1) — skipping"
  exit 0
fi

# ── Detect and validate ───────────────────────────────────────────────────────
local_ip=$(detect_local_ip)
_log "detected local IP: ${local_ip:-unknown}"

if [[ -z "$local_ip" ]]; then
  _fail "could not detect local IP — cannot verify VPN context" || exit 1
  exit 0
fi

if ip_in_vpn_range "$local_ip"; then
  _log "PASS: $local_ip is within allowed VPN range ($VPN_ALLOWED_CIDRS)"
  exit 0
else
  _fail "BLOCKED: $local_ip is NOT in VPN range ($VPN_ALLOWED_CIDRS). Connect to VPN before running production E2E tests." || exit 1
  exit 1
fi
