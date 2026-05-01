#!/bin/bash
###############################################################################
# @file        scripts/ops/ssh-emergency-recovery.sh
# @module      ops/ssh-emergency-recovery
# @description Infrastructure automation script
# @governance  GOV-002: Deterministic, audited, immutable infrastructure
# @author      Autonomous Infrastructure
# @date        2026-04-25
###############################################################################

set -euo pipefail

# =============================================================================
# ERROR HANDLING & CLEANUP
# =============================================================================
trap 'log_error "Script failed at line $LINENO (exit code: $?)"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source canonical configuration (SSOT)
source "${SCRIPT_DIR}/../_common/init.sh"
###############################################################################
# SSH Service Emergency Recovery - ${REPLICA_HOST}
# Usage: bash /tmp/ssh-emergency-recovery.sh [--dry-run]
# 
# This script fixes the SSH daemon on Replica 2 which is resetting connections
# during key exchange. Requires host console, IPMI, or direct shell access.
#
# Date: April 25, 2026
# Related: #1645 (SSH connectivity), Epic #1616 (cluster parity)

set -e

DRY_RUN="${1:-}"
HOSTNAME=$(hostname -f 2>/dev/null || hostname)
SCRIPT_NAME="SSH Service Recovery"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
  echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
  echo ""
  echo -e "${GREEN}━━━ STEP: $1 ━━━${NC}"
  echo ""
}

exec_dry_run() {
  local cmd="$1"
  local desc="$2"
  
  if [ "$DRY_RUN" = "--dry-run" ]; then
    log_info "[DRY-RUN] Would execute: $desc"
    echo "    Command: $cmd"
  else
    log_info "Executing: $desc"
    eval "$cmd"
  fi
}

# Validate environment
log_step "Pre-flight Checks"

if [ "$(whoami)" != "root" ]; then
  log_error "This script must run as root (use: sudo bash ssh-emergency-recovery.sh)"
  exit 1
fi

log_info "Running on: $HOSTNAME"
log_info "User: $(whoami)"
log_info "Dry-run mode: ${DRY_RUN:-disabled}"

# Step 1: Diagnostic information
log_step "Collecting Diagnostic Information"

log_info "SSH service status:"
systemctl status ssh || log_warn "SSH service not found"

log_info "SSH host key files:"
ls -lh /etc/ssh/ssh_host_* 2>/dev/null || log_warn "No SSH host keys found"

log_info "SSH daemon processes:"
ps aux | grep -E '\[sshd\]|/usr/sbin/sshd' | grep -v grep || log_warn "No sshd processes found"

log_info "Port 22 listeners:"
netstat -tlnp 2>/dev/null | grep :22 || log_warn "netstat not available"

# Step 2: Try graceful restart first
log_step "Attempting Graceful SSH Service Restart"

exec_dry_run "systemctl restart ssh" "Restart SSH service"

if [ "$DRY_RUN" != "--dry-run" ]; then
  sleep 2
  if systemctl is-active --quiet ssh; then
    log_info "SSH service restarted successfully"
  else
    log_warn "SSH service not active after restart attempt"
  fi
fi

# Step 3: If restart failed, regenerate host keys
log_step "Regenerating SSH Host Keys"

exec_dry_run "ssh-keygen -A" "Generate missing/corrupted SSH host keys"

if [ "$DRY_RUN" != "--dry-run" ]; then
  log_info "Verifying SSH host keys:"
  ls -lh /etc/ssh/ssh_host_* | grep -E 'key$|key.pub$' | wc -l | xargs -I {} log_info "Found {} SSH host key files"
fi

# Step 4: Restart SSH after key regeneration
log_step "Restarting SSH After Key Regeneration"

exec_dry_run "systemctl restart ssh" "Restart SSH service with new keys"

if [ "$DRY_RUN" != "--dry-run" ]; then
  sleep 2
  if systemctl is-active --quiet ssh; then
    log_info "SSH service restarted successfully"
  else
    log_error "SSH service failed to start - attempting full reinstall"
    
    log_step "Full SSH Daemon Reinstall (Emergency)"
    exec_dry_run "apt-get update && apt-get install --reinstall openssh-server -y" "Reinstall openssh-server package"
    exec_dry_run "systemctl restart ssh" "Start SSH after reinstall"
  fi
fi

# Step 5: Verify SSH is working
log_step "Verification"

if [ "$DRY_RUN" != "--dry-run" ]; then
  log_info "SSH service status:"
  systemctl status ssh --no-pager || log_error "SSH service not healthy"
  
  log_info "SSH listening on port 22:"
  netstat -tlnp 2>/dev/null | grep :22 || log_warn "Port 22 not found in netstat"
  
  log_info "Attempting local SSH test:"
  if ssh -o ConnectTimeout=3 -o BatchMode=yes localhost 'echo SSH_LOCAL_TEST' 2>/dev/null; then
    log_info "Local SSH connection successful"
  else
    log_warn "Local SSH test failed - service may need more time to stabilize"
  fi
fi

# Step 6: Post-recovery actions
log_step "Post-Recovery Steps"

if [ "$DRY_RUN" != "--dry-run" ]; then
  log_info "SSH host key fingerprints (share with team):"
  ssh-keygen -l -f /etc/ssh/ssh_host_ed25519_key.pub 2>/dev/null || log_warn "Could not generate host key fingerprint"
  
  log_info "Enabling SSH service to start on boot:"
  systemctl enable ssh || log_warn "Could not enable SSH on boot"
fi

# Summary
log_step "Recovery Summary"

if [ "$DRY_RUN" = "--dry-run" ]; then
  log_info "Dry-run complete. Would have executed the above steps."
  log_info "To apply changes, run: sudo bash ssh-emergency-recovery.sh"
else
  log_info "SSH service recovery complete"
  log_info "Testing connectivity from other hosts with: ssh akushnir@$(hostname -I | awk '{print $1}')"
  
  if systemctl is-active --quiet ssh; then
    log_info "Status: SSH service is ACTIVE ✓"
  else
    log_error "Status: SSH service is NOT ACTIVE ✗"
  fi
fi

echo ""
log_info "For full recovery guide, see: SSH-REPAIR-GUIDE-APRIL-25-2026.md"
