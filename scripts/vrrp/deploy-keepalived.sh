#!/bin/bash
################################################################################
# scripts/vrrp/deploy-keepalived.sh
# Deploy Keepalived VRRP configuration and start failover service
#
# Usage:
#   ./deploy-keepalived.sh primary|replica
#   
# Example:
#   ssh akushnir@192.168.168.31 "cd code-server && bash scripts/vrrp/deploy-keepalived.sh primary"
#   ssh akushnir@192.168.168.42 "cd code-server && bash scripts/vrrp/deploy-keepalived.sh replica"
#
# Managed by: P2 #365 (VRRP Virtual IP Failover)
################################################################################

set -euo pipefail

# Source logging and common functions
source scripts/_common/logging.sh

# Configuration
ROLE="${1:-primary}"  # primary|replica
VRRP_INTERFACE="${VRRP_INTERFACE:-eth0}"
VRRP_VIRTUAL_IP="${VRRP_VIRTUAL_IP:-192.168.168.30}"
VRRP_ROUTER_ID_NUM="${VRRP_ROUTER_ID_NUM:-51}"
VRRP_AUTH_SECRET="${VRRP_AUTH_SECRET:-SecretPassword123}"

KEEPALIVED_CONFIG_DIR="/etc/keepalived"
KEEPALIVED_SBIN_DIR="/usr/local/sbin"

log_info "🚀 Deploying Keepalived VRRP configuration for role: $ROLE"

# ─────────────────────────────────────────────────────────────────────────────
# Step 1: Install Keepalived package
# ─────────────────────────────────────────────────────────────────────────────

if ! command -v keepalived &> /dev/null; then
    log_info "📦 Installing Keepalived..."
    
    if command -v apt-get &> /dev/null; then
        sudo apt-get update
        sudo apt-get install -y keepalived
    elif command -v yum &> /dev/null; then
        sudo yum install -y keepalived
    else
        log_error "❌ Package manager not found (apt-get or yum required)"
        exit 1
    fi
    
    log_info "✅ Keepalived installed"
else
    log_info "✅ Keepalived already installed"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Step 2: Deploy notification and health check scripts
# ─────────────────────────────────────────────────────────────────────────────

log_info "📝 Deploying helper scripts..."

# Copy notify script
sudo bash -c "
    cat > $KEEPALIVED_SBIN_DIR/vrrp-notify.sh << 'EOF'
$(cat scripts/vrrp/vrrp-notify.sh)
EOF
"
sudo chmod +x "$KEEPALIVED_SBIN_DIR/vrrp-notify.sh"

# Copy health check script
sudo bash -c "
    cat > $KEEPALIVED_SBIN_DIR/check-services.sh << 'EOF'
$(cat scripts/vrrp/check-services.sh)
EOF
"
sudo chmod +x "$KEEPALIVED_SBIN_DIR/check-services.sh"

log_info "✅ Helper scripts deployed"

# ─────────────────────────────────────────────────────────────────────────────
# Step 3: Render configuration from template
# ─────────────────────────────────────────────────────────────────────────────

log_info "⚙️  Rendering Keepalived configuration for $ROLE..."

case "$ROLE" in
    primary)
        TEMPLATE_FILE="scripts/vrrp/keepalived-primary.conf.tpl"
        ;;
    replica)
        TEMPLATE_FILE="scripts/vrrp/keepalived-replica.conf.tpl"
        ;;
    *)
        log_error "❌ Invalid role: $ROLE (expected: primary|replica)"
        exit 1
        ;;
esac

# Render configuration using envsubst
RENDERED_CONFIG=$(VRRP_INTERFACE="$VRRP_INTERFACE" \
                  VRRP_VIRTUAL_IP="$VRRP_VIRTUAL_IP" \
                  VRRP_ROUTER_ID_NUM="$VRRP_ROUTER_ID_NUM" \
                  VRRP_AUTH_SECRET="$VRRP_AUTH_SECRET" \
                  envsubst < "$TEMPLATE_FILE")

# Write to temporary file for validation
TEMP_CONFIG="/tmp/keepalived-$ROLE.conf"
echo "$RENDERED_CONFIG" > "$TEMP_CONFIG"

# Validate configuration syntax
if ! keepalived -t -f "$TEMP_CONFIG" >/dev/null 2>&1; then
    log_error "❌ Keepalived configuration syntax error:"
    keepalived -t -f "$TEMP_CONFIG"
    exit 1
fi

log_info "✅ Configuration syntax valid"

# ─────────────────────────────────────────────────────────────────────────────
# Step 4: Deploy configuration to system
# ─────────────────────────────────────────────────────────────────────────────

log_info "📂 Deploying configuration to $KEEPALIVED_CONFIG_DIR..."

sudo bash -c "cat > $KEEPALIVED_CONFIG_DIR/keepalived.conf << 'EOF'
$RENDERED_CONFIG
EOF
"

log_info "✅ Configuration deployed"

# ─────────────────────────────────────────────────────────────────────────────
# Step 5: Enable and start Keepalived service
# ─────────────────────────────────────────────────────────────────────────────

log_info "🔄 Enabling and starting Keepalived service..."

sudo systemctl daemon-reload
sudo systemctl enable keepalived
sudo systemctl restart keepalived

# Wait for service to start
sleep 2

if sudo systemctl is-active --quiet keepalived; then
    log_info "✅ Keepalived service running"
else
    log_error "❌ Keepalived service failed to start"
    sudo systemctl status keepalived --no-pager
    exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# Step 6: Verify VRRP configuration
# ─────────────────────────────────────────────────────────────────────────────

log_info "🔍 Verifying VRRP state..."

# Check VRRP state
if sudo systemctl is-active --quiet keepalived; then
    VRRP_STATE=$(sudo journalctl -u keepalived -n 5 --no-pager | grep -i "state changed" | tail -1 || echo "unknown")
    log_info "VRRP Status: $VRRP_STATE"
fi

# Check if VIP is assigned (on primary only, initially)
if [[ "$ROLE" == "primary" ]]; then
    sleep 3  # Give VRRP time to acquire VIP
    
    if ip addr show "$VRRP_INTERFACE" | grep -q "$VRRP_VIRTUAL_IP"; then
        log_info "✅ Virtual IP $VRRP_VIRTUAL_IP is assigned to $VRRP_INTERFACE"
    else
        log_warn "⚠️  Virtual IP not yet assigned (may take up to 10s)"
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# Step 7: Setup log rotation
# ─────────────────────────────────────────────────────────────────────────────

log_info "📝 Setting up log rotation..."

sudo bash -c "cat > /etc/logrotate.d/vrrp << 'EOF'
/var/log/vrrp-*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0640 root root
}
EOF
"

log_info "✅ Log rotation configured"

# ─────────────────────────────────────────────────────────────────────────────
# Deployment complete
# ─────────────────────────────────────────────────────────────────────────────

log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "✅ KEEPALIVED DEPLOYMENT COMPLETE"
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info ""
log_info "Next steps:"
log_info "  1. Verify VIP on primary:  ip addr show $VRRP_INTERFACE | grep $VRRP_VIRTUAL_IP"
log_info "  2. Test failover:          sudo systemctl stop keepalived (on primary)"
log_info "  3. Check VIP moved:        ip addr show $VRRP_INTERFACE | grep $VRRP_VIRTUAL_IP (on replica)"
log_info "  4. Monitor logs:           sudo journalctl -u keepalived -f"
log_info ""

exit 0
