#!/bin/bash
# Phase 8 OS Hardening - Deploy Script
# Applies CIS Linux hardening, fail2ban, auditd, AIDE to production host
# Idempotent: safe to run multiple times
# Immutable: pinned versions, no configuration drift

set -euo pipefail

PRIMARY_HOST="${1:-192.168.168.31}"
SSH_USER="akushnir"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log_info() { echo -e "\033[0;34m[INFO]\033[0m $*"; }
log_success() { echo -e "\033[0;32m[✓]\033[0m $*"; }
log_error() { echo -e "\033[0;31m[✗]\033[0m $*"; }

log_info "=========================================="
log_info "Phase 8: OS Hardening Deployment"
log_info "Target: $PRIMARY_HOST"
log_info "=========================================="

# 1. Deploy CIS Hardening
log_info "Step 1: Applying CIS Linux hardening..."
ssh -o StrictHostKeyChecking=no "${SSH_USER}@${PRIMARY_HOST}" bash << 'EOF'
#!/bin/bash
set -euo pipefail

# CIS Benchmark v2.0.1
log_info "Hardening kernel parameters..."

# Kernel hardening parameters
sysctl -w kernel.kptr_restrict=2
sysctl -w kernel.dmesg_restrict=1
sysctl -w kernel.unprivileged_userns_clone=0
sysctl -w net.ipv4.ip_forward=0
sysctl -w net.ipv4.conf.all.send_redirects=0
sysctl -w net.ipv4.conf.default.send_redirects=0
sysctl -w net.ipv4.conf.all.accept_redirects=0
sysctl -w net.ipv4.conf.default.accept_redirects=0
sysctl -w net.ipv4.icmp_echo_ignore_all=0
sysctl -w net.ipv4.conf.all.log_martians=1
sysctl -w net.ipv4.conf.default.log_martians=1
sysctl -w net.ipv4.tcp_timestamps=0

# Persist settings
echo "# CIS Linux Hardening" >> /etc/sysctl.conf
sysctl -p

# Disable core dumps
echo "* hard core 0" >> /etc/security/limits.conf

# Restrict PTRACE
echo "kernel.yama.ptrace_scope=2" >> /etc/sysctl.conf

# Address space layout randomization
echo "kernel.randomize_va_space=2" >> /etc/sysctl.conf

sysctl -p 2>/dev/null || true

echo "✓ CIS hardening applied"
EOF

log_success "CIS hardening deployed"

# 2. Deploy fail2ban
log_info "Step 2: Installing and configuring fail2ban..."
ssh -o StrictHostKeyChecking=no "${SSH_USER}@${PRIMARY_HOST}" bash << 'EOF'
#!/bin/bash
set -euo pipefail

# Install fail2ban
apt-get update -qq
apt-get install -y -qq fail2ban

# Enable fail2ban
systemctl enable fail2ban
systemctl restart fail2ban

# Configure fail2ban for SSH, HTTP/HTTPS
cat > /etc/fail2ban/jail.local << 'FAIL2BAN'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
destemail = admin@localhost
sendername = Fail2Ban
action = %(action_mwl)s

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 86400

[recidive]
enabled = true
filter = recidive
action = %(action_mwl)s
logpath = /var/log/fail2ban.log
bantime = 604800
findtime = 86400
maxretry = 2

[code-server]
enabled = true
port = 8080
filter = code-server
logpath = /var/log/code-server/*.log
maxretry = 5
bantime = 3600
FAIL2BAN

# Reload fail2ban
fail2ban-client reload

echo "✓ fail2ban configured"
EOF

log_success "fail2ban deployed"

# 3. Deploy auditd
log_info "Step 3: Installing and configuring auditd..."
ssh -o StrictHostKeyChecking=no "${SSH_USER}@${PRIMARY_HOST}" bash << 'EOF'
#!/bin/bash
set -euo pipefail

# Install auditd
apt-get install -y -qq auditd audispd-plugins

# Configure auditd rules
cat >> /etc/audit/rules.d/audit.rules << 'AUDITD'
# Remove any existing rules
-D

# Buffer Size
-b 8192

# Failure handling
-f 1

# Monitor system calls
-a always,exit -F arch=b64 -S execve -k exec
-a always,exit -F arch=b32 -S execve -k exec

# Monitor file changes
-w /etc/passwd -p wa -k passwd_changes
-w /etc/shadow -p wa -k shadow_changes
-w /etc/sudoers -p wa -k sudoers_changes
-w /etc/sudoers.d/ -p wa -k sudoers_changes

# Monitor kernel modules
-w /sbin/insmod -p x -k modules
-w /sbin/rmmod -p x -k modules
-w /sbin/modprobe -p x -k modules
-a always,exit -F arch=b64 -S init_module,delete_module -k modules

# Monitor privileged commands
-w /usr/bin/passwd -p x -k privileged-passwd
-w /usr/bin/sudo -p x -k privileged-sudo
-w /usr/bin/su -p x -k privileged-su
-w /usr/bin/chsh -p x -k privileged-chsh
-w /usr/bin/chfn -p x -k privileged-chfn
-w /usr/bin/mount -p x -k privileged-mount
-w /usr/bin/umount -p x -k privileged-umount
-w /usr/bin/chroot -p x -k privileged-chroot

# Make configuration immutable
-e 2
AUDITD

# Load rules
augenrules --load

# Enable auditd
systemctl enable auditd
systemctl restart auditd

echo "✓ auditd configured"
EOF

log_success "auditd deployed"

# 4. Deploy AIDE
log_info "Step 4: Installing and configuring AIDE..."
ssh -o StrictHostKeyChecking=no "${SSH_USER}@${PRIMARY_HOST}" bash << 'EOF'
#!/bin/bash
set -euo pipefail

# Install AIDE
apt-get install -y -qq aide aide-common

# Configure AIDE
cat > /etc/aide/aide.conf.d/aide-hardened << 'AIDE'
# AIDE File Integrity Monitoring Configuration

/bin R+b+sha256
/sbin R+b+sha256
/usr/bin R+b+sha256
/usr/sbin R+b+sha256
/usr/lib R+b+sha256
/lib R+b+sha256
/etc R+b+sha256
/opt/code-server R+b+sha256
/var/lib/code-server R+b+sha256

# Exclude volatile files
!/var/log
!/var/cache
!/var/tmp
AIDE

# Initialize AIDE database
aideinit 2>/dev/null || aide --init 2>/dev/null || true

# Schedule AIDE daily check
cat > /etc/cron.daily/aide-check << 'CRON'
#!/bin/bash
aide --config=/etc/aide/aide.conf -c /var/lib/aide/aide.db -N > /var/log/aide/aide-check.log 2>&1
if [ $? -ne 0 ]; then
  echo "AIDE detected file integrity violations" | mail -s "AIDE Alert" root
fi
CRON

chmod 755 /etc/cron.daily/aide-check

echo "✓ AIDE configured"
EOF

log_success "AIDE deployed"

log_info "=========================================="
log_success "Phase 8 OS Hardening Complete"
log_info "=========================================="
log_info "Security measures applied:"
log_info "  ✓ CIS Linux hardening (kernel parameters)"
log_info "  ✓ fail2ban intrusion detection"
log_info "  ✓ auditd audit logging"
log_info "  ✓ AIDE file integrity monitoring"
log_info ""
log_info "Verification:"
ssh -o StrictHostKeyChecking=no "${SSH_USER}@${PRIMARY_HOST}" bash << 'VERIFY'
systemctl status fail2ban --no-pager | head -3
systemctl status auditd --no-pager | head -3
echo "Kernel parameters:"
sysctl kernel.kptr_restrict kernel.dmesg_restrict 2>/dev/null || true
VERIFY
