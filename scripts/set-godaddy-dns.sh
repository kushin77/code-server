#!/usr/bin/env bash
# set-godaddy-dns.sh
# Sets GoDaddy DNS A record for kushnir.cloud → public IP
# Mimics eiq-org pattern from nuke-redeploy-orchestrator.sh
# Requires: GODADDY_KEY and GODADDY_SECRET env vars
#           (fetch via scripts/fetch-gsm-secrets.sh)
# Usage: ./set-godaddy-dns.sh [--ip 173.77.179.148] [--domain kushnir.cloud]
set -euo pipefail

readonly GODADDY_API="https://api.godaddy.com/v1"
DOMAIN="${GODADDY_DOMAIN:-kushnir.cloud}"
PUBLIC_IP="${PUBLIC_IP:-}"

# Parse args
while [[ $# -gt 0 ]]; do
    case "$1" in
        --ip) PUBLIC_IP="$2"; shift 2 ;;
        --domain) DOMAIN="$2"; shift 2 ;;
        *) echo "Unknown arg: $1" >&2; exit 1 ;;
    esac
done

# Auto-detect public IP if not provided
if [[ -z "$PUBLIC_IP" ]]; then
    PUBLIC_IP=$(curl -sf https://api.ipify.org) || {
        echo "ERROR: Could not determine public IP. Pass --ip <ip>" >&2
        exit 1
    }
    echo "Detected public IP: ${PUBLIC_IP}" >&2
fi

# Validate credentials
if [[ -z "${GODADDY_KEY:-}" || -z "${GODADDY_SECRET:-}" ]]; then
    echo "ERROR: GODADDY_KEY and GODADDY_SECRET must be set." >&2
    echo "Run: source scripts/fetch-gsm-secrets.sh" >&2
    exit 1
fi

readonly AUTH="sso-key ${GODADDY_KEY}:${GODADDY_SECRET}"

echo "Querying current DNS for ${DOMAIN}..." >&2
current=$(curl -sf \
    -H "Authorization: ${AUTH}" \
    "${GODADDY_API}/domains/${DOMAIN}/records/A/%40" 2>/dev/null || echo "[]")
echo "Current A records: ${current}" >&2

echo "Setting A record: ${DOMAIN} → ${PUBLIC_IP} (TTL 600)..." >&2
curl -sf -X PUT \
    -H "Authorization: ${AUTH}" \
    -H "Content-Type: application/json" \
    -d "[{\"data\":\"${PUBLIC_IP}\",\"ttl\":600}]" \
    "${GODADDY_API}/domains/${DOMAIN}/records/A/%40" || {
    echo "ERROR: GoDaddy API call failed." >&2
    exit 1
}

echo "DNS A record set successfully: ${DOMAIN} → ${PUBLIC_IP}" >&2

# Verify
sleep 2
verified=$(curl -sf \
    -H "Authorization: ${AUTH}" \
    "${GODADDY_API}/domains/${DOMAIN}/records/A/%40" | grep -o "\"data\":\"[^\"]*\"" | head -1)
echo "Verified: ${verified}" >&2
