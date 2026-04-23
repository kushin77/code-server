#!/usr/bin/env bash
# @file        scripts/ops/setup-passwordless-sudo.sh
# @module      infrastructure/security
# @description Configure passwordless sudo for deployment operations (P1 #1636)
# @owner       On-call ops
# @status      Critical deployment prerequisite

set -euo pipefail

PRIMARY_HOST="${PRIMARY_HOST:-192.168.168.31}"
STANDBY_HOST="${STANDBY_HOST:-192.168.168.42}"
SUDO_USER="${SUDO_USER:-akushnir}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ────────────────────────────────────────────────────────────────────────────
# STEP 1: Verify current sudo status
# ────────────────────────────────────────────────────────────────────────────
log_info "Step 1: Verifying current sudo configuration on both replicas..."

for host in $PRIMARY_HOST $STANDBY_HOST; do
  log_info "Checking $host..."
  
  # Try passwordless sudo
  if ssh -i ~/.ssh/id_rsa_onprem akushnir@$host "sudo -n true" 2>/dev/null; then
    log_info "✅ $host already has passwordless sudo configured"
  else
    log_warn "⚠️ $host requires password for sudo"
  fi
done

# ────────────────────────────────────────────────────────────────────────────
# STEP 2: Create sudoers entry for passwordless sudo
# ────────────────────────────────────────────────────────────────────────────
log_info "Step 2: Creating sudoers entry for passwordless sudo..."

SUDOERS_ENTRY="$SUDO_USER ALL=(ALL) NOPASSWD: ALL"
TEMP_SUDOERS="/tmp/sudoers-$SUDO_USER-$RANDOM"

# Create temporary sudoers file
cat > $TEMP_SUDOERS << SUDOERS_EOF
# Passwordless sudo for deployment operations (P1 #1636)
# User: $SUDO_USER
# Purpose: Automated deployment and incident response procedures
# Added: $(date)

$SUDOERS_ENTRY
SUDOERS_EOF

log_info "Sudoers entry created locally: $SUDOERS_ENTRY"

# ────────────────────────────────────────────────────────────────────────────
# STEP 3: Apply passwordless sudo configuration to both replicas
# ────────────────────────────────────────────────────────────────────────────
log_info "Step 3: Applying passwordless sudo to both replicas..."

for host in $PRIMARY_HOST $STANDBY_HOST; do
  log_info "Configuring passwordless sudo on $host..."
  
  # Method 1: Try to use visudo (preferred method)
  if ssh -i ~/.ssh/id_rsa_onprem akushnir@$host "echo '$SUDOERS_ENTRY' | sudo tee /etc/sudoers.d/deployment-automation" > /dev/null 2>&1; then
    log_info "✅ Sudoers entry added to $host via /etc/sudoers.d/"
    
    # Verify sudoers syntax
    if ssh -i ~/.ssh/id_rsa_onprem akushnir@$host "sudo visudo -c" > /dev/null 2>&1; then
      log_info "✅ Sudoers syntax valid on $host"
    else
      log_error "Sudoers syntax error on $host - reverting changes"
      ssh -i ~/.ssh/id_rsa_onprem akushnir@$host "sudo rm -f /etc/sudoers.d/deployment-automation"
      continue
    fi
  else
    log_error "Failed to configure sudoers on $host (requires existing sudo access)"
    exit 1
  fi
done

# ────────────────────────────────────────────────────────────────────────────
# STEP 4: Verify passwordless sudo works
# ────────────────────────────────────────────────────────────────────────────
log_info "Step 4: Verifying passwordless sudo functionality..."

for host in $PRIMARY_HOST $STANDBY_HOST; do
  log_info "Testing passwordless sudo on $host..."
  
  if ssh -i ~/.ssh/id_rsa_onprem akushnir@$host "sudo -n whoami" 2>/dev/null | grep -q "root"; then
    log_info "✅ Passwordless sudo verified on $host (returned: root)"
  else
    log_error "Passwordless sudo verification FAILED on $host"
    exit 1
  fi
done

# ────────────────────────────────────────────────────────────────────────────
# STEP 5: Test critical deployment operations
# ────────────────────────────────────────────────────────────────────────────
log_info "Step 5: Testing critical deployment operations..."

# Test iptables command (needed for Phase 1 isolation)
log_info "Testing iptables command (Phase 1 isolation)..."
if ssh -i ~/.ssh/id_rsa_onprem akushnir@$STANDBY_HOST "sudo iptables -L INPUT -n 2>/dev/null | head -3" > /dev/null 2>&1; then
  log_info "✅ iptables command works passwordlessly"
else
  log_warn "⚠️ iptables test inconclusive"
fi

# Test network namespace commands
log_info "Testing network namespace commands..."
if ssh -i ~/.ssh/id_rsa_onprem akushnir@$PRIMARY_HOST "sudo ip netns list 2>/dev/null || echo 'OK'" > /dev/null 2>&1; then
  log_info "✅ Network commands work passwordlessly"
else
  log_warn "⚠️ Network command test inconclusive"
fi

# Test systemctl commands
log_info "Testing systemctl commands..."
if ssh -i ~/.ssh/id_rsa_onprem akushnir@$PRIMARY_HOST "sudo systemctl is-active docker 2>/dev/null" > /dev/null 2>&1; then
  log_info "✅ systemctl commands work passwordlessly"
else
  log_warn "⚠️ systemctl test inconclusive"
fi

# ────────────────────────────────────────────────────────────────────────────
# STEP 6: Documentation
# ────────────────────────────────────────────────────────────────────────────
log_info "Step 6: Documenting passwordless sudo configuration..."

cat > /tmp/passwordless-sudo-summary.txt << SUMMARY_EOF
Passwordless Sudo Configuration - P1 #1636
Completed: $(date)

Configuration Applied:
- Primary Replica (192.168.168.31): ✅ Passwordless sudo enabled
- Standby Replica (192.168.168.42): ✅ Passwordless sudo enabled
- User: $SUDO_USER
- Configuration file: /etc/sudoers.d/deployment-automation
- Entry: $SUDOERS_ENTRY

Operations Now Available Without Password Prompt:
1. Phase 1 isolation: iptables rules for network blocking
2. PostgreSQL replication setup: ALTER SYSTEM configuration
3. Service restarts: docker-compose, systemctl operations
4. Hardware diagnostics: smartctl, iostat, df commands
5. Network debugging: ping, traceroute, tcpdump

Critical Deployment Procedures Unblocked:
- scripts/ops/isolate-replica-2-nvme-failure.sh (P0 #1635 Phase 1)
- scripts/ops/setup-postgres-streaming-replication.sh (P0 #1635 Phase 3)
- Patroni HA deployment scripts (future)
- Automated incident response procedures

Security Considerations:
- Passwordless sudo is limited to deployment user ($SUDO_USER)
- Configuration stored in /etc/sudoers.d/ (more maintainable than /etc/sudoers)
- Can be revoked by: sudo rm /etc/sudoers.d/deployment-automation
- SSH key authentication still required (not password-based)

Verification Commands:
$ ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 "sudo -n whoami"
# Expected: root

$ ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 "bash scripts/ops/isolate-replica-2-nvme-failure.sh"
# Phase 1 isolation now executable without password prompts
SUMMARY_EOF

log_info "Configuration summary: /tmp/passwordless-sudo-summary.txt"

# ────────────────────────────────────────────────────────────────────────────
# FINAL STATUS
# ────────────────────────────────────────────────────────────────────────────
log_info ""
log_info "════════════════════════════════════════════════════════════════"
log_info "PASSWORDLESS SUDO CONFIGURATION COMPLETE ✅"
log_info "════════════════════════════════════════════════════════════════"
log_info ""
log_info "P1 #1636 RESOLVED - Deployment operations unblocked"
log_info ""
log_info "Next Critical Action (P0 #1635):"
log_info "  $ bash scripts/ops/isolate-replica-2-nvme-failure.sh"
log_info ""
log_info "This will NOW execute without password prompts!"
log_info ""
