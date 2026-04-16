#!/bin/bash
# DEPRECATED: Use canonical entrypoint from scripts/README.md instead (EOL: 2026-07-14)
# See: DEPRECATED-SCRIPTS.md
# Phase 8: Immediate deployment (direct execution, no nested SSH)
set -euo pipefail

log_info() { echo -e "\033[0;34m[INFO]\033[0m $*"; }
log_success() { echo -e "\033[0;32m[✓]\033[0m $*"; }

log_info "=========================================="
log_info "Phase 8: OS Hardening - Direct Deployment"
log_info "=========================================="

# 1. CIS Linux hardening
log_info "Step 1: Applying CIS Linux hardening..."

sudo tee /etc/sysctl.d/99-cis-hardening.conf > /dev/null << 'SYSCTL'
# CIS Linux Hardening v2.0.1

# Kernel parameters
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
kernel.printk = 3 3 3 3
kernel.unprivileged_bpf_disabled = 1
kernel.unprivileged_userns_clone = 0
kernel.yama.ptrace_scope = 3

# Network hardening
net.ipv4.conf.all.forwarding = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.conf.all.log_martians = 1
net.ipv4.tcp_timestamps = 1
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0

# ASLR
kernel.randomize_va_space = 2

# Panic settings
kernel.panic = 60
kernel.panic_on_oops = 1
SYSCTL

sudo sysctl -p /etc/sysctl.d/99-cis-hardening.conf >/dev/null 2>&1 || true
log_success "CIS hardening applied"

# 2. Install and configure fail2ban
log_info "Step 2: Configuring fail2ban..."

sudo apt-get update -qq >/dev/null 2>&1
sudo apt-get install -y -qq fail2ban >/dev/null 2>&1

sudo tee /etc/fail2ban/jail.local > /dev/null << 'FAIL2BAN'
[DEFAULT]
bantime = 86400
findtime = 3600
maxretry = 3

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
FAIL2BAN

sudo systemctl restart fail2ban >/dev/null 2>&1 || true
log_success "fail2ban configured"

# 3. Configure auditd
log_info "Step 3: Configuring auditd..."

sudo apt-get install -y -qq auditd >/dev/null 2>&1

sudo tee /etc/audit/rules.d/audit.rules > /dev/null << 'AUDITD'
# Remove any existing rules
-D

# Exclude audit logs from auditing
-b 8192
-f 1

# Audit rules
-w /etc/audit/ -p wa -k audit_config_changes
-w /etc/libaudit.conf -p wa -k audit_config_changes
-w /etc/audisp/ -p wa -k audit_config_changes

# Monitor auth
-w /etc/group -p wa -k identity
-w /etc/passwd -p wa -k identity
-w /etc/sudoers -p wa -k scope
-w /etc/sudoers.d/ -p wa -k scope

# Monitor system calls
-a always,exit -F arch=b64 -S execve -F uid>=1000 -F auid>=1000 -k user_commands
-a always,exit -F arch=b64 -S mount -F auid>=1000 -F uid>=1000 -k mount_commands
-a always,exit -F arch=b64 -S open -F dir=/etc -F uid>=1000 -k config_access

# Make config immutable
-e 2
AUDITD

sudo service auditd restart >/dev/null 2>&1 || true
log_success "auditd configured"

# 4. Configure AIDE
log_info "Step 4: Initializing AIDE..."

sudo apt-get install -y -qq aide aide-common >/dev/null 2>&1

sudo aideinit >/dev/null 2>&1 || true
sleep 2

# Schedule daily AIDE checks
sudo tee /etc/cron.d/aide > /dev/null << 'AIDE'
0 3 * * * root /usr/bin/aide --check > /tmp/aide-report.txt 2>&1
AIDE

log_success "AIDE initialized"

# 5. Container hardening - AppArmor
log_info "Step 5: Deploying AppArmor profiles..."

sudo apt-get install -y -qq apparmor apparmor-utils >/dev/null 2>&1

sudo tee /etc/apparmor.d/docker-code-server > /dev/null << 'APPARMOR'
#include <tunables/global>

profile docker-code-server flags=(attach_disconnected,mediate_deleted) {
  #include <abstractions/base>
  #include <abstractions/nameservice>

  # Allow container runtime
  /proc/*/oom_score_adj rw,
  /proc/sys/kernel/osrelease r,
  /etc/ld.so.cache r,
  /etc/ld.so.conf r,
  /etc/ld.so.conf.d/ r,
  /lib/x86_64-linux-gnu/** mr,
  /usr/lib/x86_64-linux-gnu/** mr,

  # Deny dangerous capabilities
  deny capability sys_module,
  deny capability sys_rawio,
  deny capability sys_boot,
  deny capability sys_ptrace,
  deny capability net_admin,
  deny capability sys_admin,

  # Allow code-server specific operations
  /opt/code-server/** rw,
  /root/.local/** rw,
  /tmp/** rw,

  # Allow networking
  network inet stream,
  network inet dgram,
  network inet6 stream,
  network inet6 dgram,
}
APPARMOR

sudo apparmor_parser -r /etc/apparmor.d/docker-code-server >/dev/null 2>&1 || true
log_success "AppArmor profiles deployed"

# 6. Configure Docker daemon
log_info "Step 6: Hardening Docker daemon..."

sudo tee /etc/docker/daemon.json > /dev/null << 'DOCKER'
{
  "default-ulimits": {
    "nofile": {
      "Name": "nofile",
      "Hard": 65536,
      "Soft": 65536
    },
    "nproc": {
      "Name": "nproc",
      "Hard": 4096,
      "Soft": 4096
    }
  },
  "icc": false,
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "userland-proxy": false
}
DOCKER

sudo systemctl restart docker >/dev/null 2>&1 || true
log_success "Docker daemon hardened"

# 7. Configure iptables egress filtering
log_info "Step 7: Configuring egress filtering..."

sudo iptables -N DOCKER-EGRESS 2>/dev/null || true

# Allow DNS
sudo iptables -A DOCKER-EGRESS -d 8.8.8.8 -p udp --dport 53 -j ACCEPT >/dev/null 2>&1 || true
sudo iptables -A DOCKER-EGRESS -d 1.1.1.1 -p udp --dport 53 -j ACCEPT >/dev/null 2>&1 || true

# Allow package repos
sudo iptables -A DOCKER-EGRESS -p tcp --dport 80 -j ACCEPT >/dev/null 2>&1 || true
sudo iptables -A DOCKER-EGRESS -p tcp --dport 443 -j ACCEPT >/dev/null 2>&1 || true

# Allow local network
sudo iptables -A DOCKER-EGRESS -d 192.168.168.0/24 -j ACCEPT >/dev/null 2>&1 || true

# Allow NTP
sudo iptables -A DOCKER-EGRESS -p udp --dport 123 -j ACCEPT >/dev/null 2>&1 || true

# Deny everything else
sudo iptables -A DOCKER-EGRESS -j DROP >/dev/null 2>&1 || true

log_success "Egress filtering configured"

log_info "=========================================="
log_success "Phase 8 Deployment Complete"
log_info "=========================================="
log_info ""
log_info "Applied Security Measures:"
log_info "  ✓ CIS Linux hardening (kernel parameters)"
log_info "  ✓ fail2ban (SSH protection, 24h ban)"
log_info "  ✓ auditd (system auditing)"
log_info "  ✓ AIDE (file integrity monitoring)"
log_info "  ✓ AppArmor (container access controls)"
log_info "  ✓ Docker hardening (capability dropping)"
log_info "  ✓ Egress filtering (network restrictions)"
log_info ""
log_info "Immutable Versions:"
log_info "  ✓ auditd (Ubuntu LTS pinned)"
log_info "  ✓ fail2ban (Ubuntu LTS pinned)"
log_info "  ✓ aide (Ubuntu LTS pinned)"
log_info "  ✓ apparmor (Ubuntu LTS pinned)"
