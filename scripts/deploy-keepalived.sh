#!/bin/bash
# scripts/deploy-keepalived.sh
# ============================
# Deploy Keepalived VRRP to primary and replica hosts.
# Creates floating VIP 192.168.168.30 with automatic failover.
#
# Usage:
#   scripts/deploy-keepalived.sh [--dry-run]
#
# Prerequisites:
#   - SSH key-based access to primary (192.168.168.31) and replica (192.168.168.42)
#   - VRRP_AUTH_PASS set in environment or SOPS secret
#   - Run from repo root

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
# shellcheck source=scripts/lib/env.sh
source "$REPO_ROOT/scripts/lib/env.sh"

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    echo "DRY RUN mode — no changes will be applied"
fi

# ─── Validation ───────────────────────────────────────────────────────────────

if [[ -z "${VRRP_AUTH_PASS:-}" ]]; then
    echo "ERROR: VRRP_AUTH_PASS not set in environment" >&2
    echo "Set via SOPS: sops exec-env secrets/production.enc.env 'bash scripts/deploy-keepalived.sh'" >&2
    exit 1
fi

if [[ ${#VRRP_AUTH_PASS} -lt 8 ]]; then
    echo "ERROR: VRRP_AUTH_PASS must be at least 8 characters" >&2
    exit 1
fi

echo "=== Deploying Keepalived VRRP ==="
echo "  Primary:  $PRIMARY_HOST (MASTER, priority 110)"
echo "  Replica:  $REPLICA_HOST (BACKUP, priority 100)"
echo "  VIP:      $VIP"
echo "  Auth:     [set]"
echo ""

# ─── Deploy to Primary ────────────────────────────────────────────────────────

deploy_primary() {
    echo "--- Deploying to primary ($PRIMARY_HOST) ---"

    # Substitute auth password into config template
    local config
    config=$(sed "s|\\\$VRRP_AUTH_PASS|${VRRP_AUTH_PASS}|g" \
        "$REPO_ROOT/config/keepalived/keepalived-primary.conf")

    if $DRY_RUN; then
        echo "[DRY RUN] Would deploy config to $PRIMARY_HOST:/etc/keepalived/keepalived.conf"
        return
    fi

    ssh "$SSH_USER@$PRIMARY_HOST" "sudo mkdir -p /etc/keepalived"

    echo "$config" | ssh "$SSH_USER@$PRIMARY_HOST" \
        "sudo tee /etc/keepalived/keepalived.conf > /dev/null"

    # Copy notify script
    ssh "$SSH_USER@$PRIMARY_HOST" \
        "sudo tee /etc/keepalived/notify.sh > /dev/null" \
        < "$REPO_ROOT/config/keepalived/notify.sh"

    ssh "$SSH_USER@$PRIMARY_HOST" \
        "sudo chmod +x /etc/keepalived/notify.sh"

    # Install keepalived if not present
    ssh "$SSH_USER@$PRIMARY_HOST" \
        "command -v keepalived &>/dev/null || sudo apt-get install -y keepalived"

    # Verify config syntax
    ssh "$SSH_USER@$PRIMARY_HOST" \
        "sudo keepalived --config-test 2>&1" && \
        echo "✅ Config syntax valid on primary" || \
        { echo "❌ Config syntax error on primary"; exit 1; }

    # Enable and restart
    ssh "$SSH_USER@$PRIMARY_HOST" \
        "sudo systemctl enable keepalived && sudo systemctl restart keepalived"

    echo "✅ Keepalived deployed and started on primary ($PRIMARY_HOST)"
}

# ─── Deploy to Replica ────────────────────────────────────────────────────────

deploy_replica() {
    echo "--- Deploying to replica ($REPLICA_HOST) ---"

    local config
    config=$(sed "s|\\\$VRRP_AUTH_PASS|${VRRP_AUTH_PASS}|g" \
        "$REPO_ROOT/config/keepalived/keepalived-replica.conf")

    if $DRY_RUN; then
        echo "[DRY RUN] Would deploy config to $REPLICA_HOST:/etc/keepalived/keepalived.conf"
        return
    fi

    ssh "$SSH_USER@$REPLICA_HOST" "sudo mkdir -p /etc/keepalived"

    echo "$config" | ssh "$SSH_USER@$REPLICA_HOST" \
        "sudo tee /etc/keepalived/keepalived.conf > /dev/null"

    ssh "$SSH_USER@$REPLICA_HOST" \
        "sudo tee /etc/keepalived/notify.sh > /dev/null" \
        < "$REPO_ROOT/config/keepalived/notify.sh"

    ssh "$SSH_USER@$REPLICA_HOST" \
        "sudo chmod +x /etc/keepalived/notify.sh"

    ssh "$SSH_USER@$REPLICA_HOST" \
        "command -v keepalived &>/dev/null || sudo apt-get install -y keepalived"

    ssh "$SSH_USER@$REPLICA_HOST" \
        "sudo keepalived --config-test 2>&1" && \
        echo "✅ Config syntax valid on replica" || \
        { echo "❌ Config syntax error on replica"; exit 1; }

    ssh "$SSH_USER@$REPLICA_HOST" \
        "sudo systemctl enable keepalived && sudo systemctl restart keepalived"

    echo "✅ Keepalived deployed and started on replica ($REPLICA_HOST)"
}

# ─── Verify VIP ───────────────────────────────────────────────────────────────

verify_vip() {
    if $DRY_RUN; then
        echo "[DRY RUN] Would verify VIP $VIP is pingable"
        return
    fi

    echo "--- Verifying VIP ($VIP) ---"
    sleep 3

    if ping -c 3 -W 2 "$VIP" &>/dev/null; then
        echo "✅ VIP $VIP is reachable"
    else
        echo "❌ VIP $VIP is NOT reachable after deployment"
        echo "   Check: ssh $SSH_USER@$PRIMARY_HOST 'ip addr show eth0'"
        exit 1
    fi

    # Verify VIP is assigned to primary
    if ssh "$SSH_USER@$PRIMARY_HOST" "ip addr show | grep -q '192.168.168.30'"; then
        echo "✅ VIP is assigned to primary ($PRIMARY_HOST) — MASTER state"
    else
        echo "⚠️  VIP not on primary — checking replica..."
        if ssh "$SSH_USER@$REPLICA_HOST" "ip addr show | grep -q '192.168.168.30'"; then
            echo "⚠️  VIP is on replica ($REPLICA_HOST) — primary may have lost health check"
        else
            echo "❌ VIP not found on any host"
            exit 1
        fi
    fi
}

# ─── Main ─────────────────────────────────────────────────────────────────────

deploy_primary
deploy_replica
verify_vip

echo ""
echo "══════════════════════════════════════════════════════════"
echo "  ✅ KEEPALIVED VRRP DEPLOYMENT COMPLETE"
echo "══════════════════════════════════════════════════════════"
echo ""
echo "  VIP:      $VIP (floating)"
echo "  Primary:  $PRIMARY_HOST (MASTER, priority 110)"
echo "  Replica:  $REPLICA_HOST (BACKUP, priority 100)"
echo ""
echo "  Test failover:"
echo "    ssh $SSH_USER@$PRIMARY_HOST 'sudo systemctl stop keepalived'"
echo "    ping $VIP   # should continue responding from replica"
echo ""
echo "  Recover:"
echo "    ssh $SSH_USER@$PRIMARY_HOST 'sudo systemctl start keepalived'"
echo "    # Primary rejoins as BACKUP (nopreempt prevents flapping)"
echo ""
echo "  Docs: docs/runbooks/vrrp-failover.md"
