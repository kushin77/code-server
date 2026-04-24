#!/usr/bin/env bash
# @file        scripts/ops/execute-p1-1694-security-fix.sh
# @module      ops/security-remediation
# @description Execution wrapper for P1-1694 TLS recovery - Execute this script on Linux box with SSH access
# @owner       platform
# @status      active
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/scripts/_common/init.sh"
init_repo

################################################################################
# P1-1694 SECURITY REMEDIATION EXECUTION WRAPPER
# This script executes the TLS recovery remediation for Let's Encrypt rate limit
################################################################################

log_info "🔴 P1-1694 SECURITY REMEDIATION EXECUTION"
log_info "📋 Issue: DAST target unreachable due to Let's Encrypt rate limit"
log_info "🎯 Solution: Deploy self-signed certificate, automatic recovery April 25"
log_info ""
log_info "⚙️  Environment Check:"
log_info "   - SSH Access: Required (will verify below)"
log_info "   - openssl: Required (will verify below)"
log_info "   - Replicas: 192.168.168.31, 192.168.168.42"
log_info ""

################################################################################
# PRE-FLIGHT CHECKS
################################################################################

log_info "🧪 Running pre-flight checks..."

# Check SSH connectivity
if ! command -v ssh &> /dev/null; then
    log_fatal "❌ ssh command not found. Install openssh-client and try again."
fi

if ! command -v openssl &> /dev/null; then
    log_fatal "❌ openssl command not found. Install openssl and try again."
fi

if ! command -v scp &> /dev/null; then
    log_fatal "❌ scp command not found. Install openssh-client and try again."
fi

log_info "✅ All required binaries present (ssh, openssl, scp)"

# Test SSH connectivity to replicas
REPLICAS="${REPLICAS:-192.168.168.31,192.168.168.42}"
DEPLOY_USER="${DEPLOY_USER:-akushnir}"
IFS=',' read -ra replica_array <<< "$REPLICAS"

log_info "🔗 Testing SSH connectivity to replicas..."
for replica in "${replica_array[@]}"; do
    if ssh -o ConnectTimeout=5 "${DEPLOY_USER}@${replica}" "echo '✅ Connected to $replica'" 2>/dev/null; then
        log_info "   ✅ ${replica}: SSH accessible"
    else
        log_fatal "   ❌ ${replica}: SSH not accessible. Check credentials and network."
    fi
done

log_info ""
log_info "✅ All pre-flight checks passed"
log_info ""

################################################################################
# EXECUTE REMEDIATION
################################################################################

log_info "🚀 EXECUTING P1-1694 REMEDIATION SCRIPT"
log_info ""

# Execute the TLS recovery script with self-signed recovery mode
cd "${SCRIPT_DIR}"

if bash "${SCRIPT_DIR}/scripts/ops/p1-1694-tls-recovery.sh" --recovery-mode self-signed; then
    log_info ""
    log_info "✅ P1-1694 REMEDIATION COMPLETE"
    log_info ""
    log_info "📊 Status:"
    log_info "   - Self-signed certificate deployed to all replicas"
    log_info "   - DAST target should now be reachable: https://ide.kushnir.cloud/health"
    log_info "   - HTTPS connectivity restored"
    log_info ""
    log_info "📅 Automatic Recovery Schedule:"
    log_info "   - Let's Encrypt rate limit expires: April 25, 2026 11:29:47 UTC"
    log_info "   - Caddy will automatically attempt renewal at that time"
    log_info "   - Production certificate (Let's Encrypt) will be restored automatically"
    log_info "   - No further manual intervention required"
    log_info ""
    log_info "✅ Issue #1694 will be CLOSED on April 26 (post-renewal verification)"
    log_info ""
    exit 0
else
    log_error "❌ P1-1694 remediation script failed"
    log_error "Review script output above for details"
    log_error "If SSH connection issues, check:"
    log_error "  - SSH key authentication: ssh-keygen and authorized_keys configured"
    log_error "  - Network connectivity: ping 192.168.168.31 and 192.168.168.42"
    log_error "  - Firewall rules: Port 22 (SSH) must be open"
    exit 1
fi
