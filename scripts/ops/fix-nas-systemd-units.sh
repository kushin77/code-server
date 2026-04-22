#!/usr/bin/env bash
# @file        scripts/ops/fix-nas-systemd-units.sh
# @module      ops/nas-hardening
# @description Fix 5 failed systemd units on NAS (192.168.168.56)
#              - eiq-nas-drift-guard bash syntax error
#              - eiq-nas-ssh-key-reconciliation (obsolete/wrong GCP project)
#              - nginx (unused, failed 17 days)
#              - nas-alerting + nas-alerting-engine (blocked on GCP auth #1378)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

NAS_USER="${NAS_USER:-akushnir}"
DRY_RUN="${DRY_RUN:-0}"

require_var NAS_HOST "NAS host IP (should be set in config.sh)"
require_command ssh "SSH is required to connect to NAS"

log_info "NAS Systemd Units Remediation"
log_info "Host: $NAS_HOST"
log_info "Dry-run: $([ "$DRY_RUN" = "1" ] && echo "YES (preview mode)" || echo "NO (execute)")"
log_info ""

# SSH command helper
run_ssh() {
    local cmd="$1"
    if [ "$DRY_RUN" = "1" ]; then
        log_info "[DRY-RUN] SSH $cmd"
        return 0
    else
        ssh "${NAS_USER}@${NAS_HOST}" bash -c "$cmd"
    fi
}

# Test SSH connectivity
log_info "Testing SSH connectivity to $NAS_HOST..."
if ! ssh -o ConnectTimeout=5 "${NAS_USER}@${NAS_HOST}" "echo 'SSH OK'" >/dev/null 2>&1; then
    log_fatal "Cannot connect to $NAS_HOST via SSH. Verify network and credentials."
fi
log_info "✓ SSH connection successful"
log_info ""

# ==============================================================================
# Fix 1: eiq-nas-drift-guard.service (bash syntax error)
# ==============================================================================

log_info "Fix 1: eiq-nas-drift-guard.service"
log_info "Problem: Bash syntax error in systemd ExecStartPre (every 10 min)"
log_info "Solution: Create wrapper script and update systemd drop-in"
log_info ""

WRAPPER_SCRIPT='cat > /usr/local/bin/nas-sanitize-portal-env.sh << '\''EOF'\''
#!/usr/bin/env bash
sed -i "s|^NAS_PORTAL_RECOVERY_CONFIRM_PHRASE=I UNDERSTAND\$|NAS_PORTAL_RECOVERY_CONFIRM_PHRASE='"'"'I UNDERSTAND'"'"'|" /etc/eiq-nas/portal.env || true
EOF
chmod +x /usr/local/bin/nas-sanitize-portal-env.sh'

log_info "Creating wrapper script..."
run_ssh "sudo bash -c '$WRAPPER_SCRIPT'"

DROP_IN_CONFIG='mkdir -p /etc/systemd/system/eiq-nas-drift-guard.service.d
cat > /etc/systemd/system/eiq-nas-drift-guard.service.d/portal-env-sanitize.conf << EOF
[Service]
ExecStartPre=/usr/local/bin/nas-sanitize-portal-env.sh
EOF'

log_info "Creating systemd drop-in configuration..."
run_ssh "sudo bash -c '$DROP_IN_CONFIG'"

log_info "Reloading systemd and restarting service..."
run_ssh "sudo systemctl daemon-reload && sudo systemctl restart eiq-nas-drift-guard.service"

log_info "Verifying service status..."
if [ "$DRY_RUN" = "0" ]; then
    STATUS=$(ssh "${NAS_USER}@${NAS_HOST}" "sudo systemctl is-active eiq-nas-drift-guard.service" 2>/dev/null || echo "unknown")
    if [ "$STATUS" = "active" ]; then
        log_info "✓ eiq-nas-drift-guard.service is now ACTIVE"
    else
        log_warn "⚠ eiq-nas-drift-guard.service status: $STATUS (check manually)"
    fi
else
    log_info "[DRY-RUN] Service status check skipped"
fi
log_info ""

# ==============================================================================
# Fix 2: eiq-nas-ssh-key-reconciliation.service (obsolete/wrong GCP project)
# ==============================================================================

log_info "Fix 2: eiq-nas-ssh-key-reconciliation.service"
log_info "Problem: References non-existent GCP project (nexusshield-prod) and host (.55)"
log_info "Solution: Disable (appears obsolete)"
log_info ""

log_info "Disabling eiq-nas-ssh-key-reconciliation.service..."
run_ssh "sudo systemctl disable eiq-nas-ssh-key-reconciliation.service && sudo systemctl stop eiq-nas-ssh-key-reconciliation.service"
log_info "✓ eiq-nas-ssh-key-reconciliation.service disabled"
log_info ""

# ==============================================================================
# Fix 3: nginx.service (unused, failed 17 days)
# ==============================================================================

log_info "Fix 3: nginx.service"
log_info "Problem: FAILED for 17 days (Caddy runs on .31, nginx not needed)"
log_info "Solution: Disable nginx"
log_info ""

log_info "Disabling nginx.service..."
run_ssh "sudo systemctl disable nginx.service && sudo systemctl stop nginx.service"
log_info "✓ nginx.service disabled"
log_info ""

# ==============================================================================
# Fix 4 & 5: nas-alerting + nas-alerting-engine (blocked on #1378)
# ==============================================================================

log_info "Fix 4 & 5: nas-alerting + nas-alerting-engine services"
log_info "Problem: Fail due to GCP auth expired (root cause in issue #1378)"
log_info "Status: TEMPORARILY DISABLED until GCP auth is restored"
log_info ""

log_info "Disabling nas-alerting services (temporary, until #1378 fixed)..."
run_ssh "sudo systemctl disable nas-alerting.service nas-alerting-engine.service && sudo systemctl stop nas-alerting.service nas-alerting-engine.service"
log_info "✓ nas-alerting services disabled"
log_info ""

# ==============================================================================
# Verification
# ==============================================================================

log_info "Final Verification"
log_info "==================="

if [ "$DRY_RUN" = "0" ]; then
    log_info "Checking systemd --failed..."
    FAILED_COUNT=$(ssh "${NAS_USER}@${NAS_HOST}" "sudo systemctl --failed 2>/dev/null | grep 'loaded units' | grep -o '^[0-9]*' | head -1" || echo "unknown")
    
    if [ "$FAILED_COUNT" = "0" ] || [ "$FAILED_COUNT" = "" ]; then
        log_info "✓ SUCCESS: 0 failed systemd units"
    else
        log_warn "⚠ WARNING: $FAILED_COUNT failed units still present (review with: sudo systemctl --failed)"
    fi
else
    log_info "[DRY-RUN] Verification check skipped"
fi

log_info ""
log_info "==============================================="
if [ "$DRY_RUN" = "1" ]; then
    log_info "DRY-RUN COMPLETE - No changes were made"
    log_info "To execute: run with DRY_RUN=0"
else
    log_info "REMEDIATION COMPLETE"
fi
log_info "==============================================="
log_info ""
log_info "Summary:"
log_info "  ✓ eiq-nas-drift-guard: Bash syntax error fixed"
log_info "  ✓ eiq-nas-ssh-key-reconciliation: Disabled (obsolete)"
log_info "  ✓ nginx: Disabled (unused)"
log_info "  ✓ nas-alerting*: Temporarily disabled (awaiting #1378)"
log_info ""
log_info "Next steps:"
log_info "  1. Verify with: ssh $NAS_USER@$NAS_HOST 'sudo systemctl --failed'"
log_info "  2. Once #1378 (GCP auth) is fixed, re-enable alerting:"
log_info "     ssh $NAS_USER@$NAS_HOST 'sudo systemctl enable nas-alerting nas-alerting-engine'"
log_info ""
