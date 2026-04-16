#!/bin/bash
# scripts/hardening/apply-cis-hardening.sh
# CIS Ubuntu Benchmark Hardening Script
# Run on production host (192.168.168.31) as root or with sudo
# 
# Prerequisites:
# - Ubuntu 22.04 LTS
# - Root/sudo access
# - Internet connectivity
#
# Usage: bash apply-cis-hardening.sh

set -euo pipefail

LOG_FILE="/tmp/cis-hardening-$(date +%Y%m%d-%H%M%S).log"
ROLLBACK_FILE="/tmp/cis-hardening-rollback-$(date +%Y%m%d-%H%M%S).sh"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

error() {
    echo "[ERROR] $*" | tee -a "$LOG_FILE"
    exit 1
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root"
    fi
}

# =============================================================================
# 1. FAIL2BAN — Automated IP Banning
# =============================================================================

setup_fail2ban() {
    log "Installing fail2ban..."
    
    apt-get update && apt-get install -y fail2ban 2>&1 | tee -a "$LOG_FILE"
    
    # Create custom jails configuration
    cat > /etc/fail2ban/jail.d/cis-hardening.conf << 'EOF'
[sshd]
enabled  = true
port     = 22
maxretry = 3
bantime  = 3600
findtime = 600
destemail = security@kushnir.cloud
sender   = root@kushnir.cloud

# Caddy API rate limiting (OAuth brute-force)
[caddy-oauth-api]
enabled  = true
port     = 4180
filter   = caddy-oauth-api
logpath  = /var/log/caddy/access.log
maxretry = 10
bantime  = 1800
findtime = 300
EOF

    # Create filter for Caddy OAuth
    cat > /etc/fail2ban/filter.d/caddy-oauth-api.conf << 'EOF'
[Definition]
failregex = ^<HOST>.*"POST /oauth2/auth" 401
            ^<HOST>.*"POST /oauth2/token" 401
            ^<HOST>.*401.*oauth
ignoreregex =
EOF

    # Enable and start
    systemctl enable fail2ban
    systemctl restart fail2ban
    
    # Add rollback
    echo "systemctl stop fail2ban && apt-get remove -y fail2ban" >> "$ROLLBACK_FILE"
    
    log "✓ fail2ban configured and started"
}

# =============================================================================
# 2. UNATTENDED-UPGRADES — Automatic Security Patching
# =============================================================================

setup_unattended_upgrades() {
    log "Installing unattended-upgrades..."
    
    apt-get install -y unattended-upgrades apt-listchanges 2>&1 | tee -a "$LOG_FILE"
    
    # Configure security-only updates
    cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
};

Unattended-Upgrade::Package-Blacklist {
};

Unattended-Upgrade::DevRelease "false";
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-New-Unused-Dependencies "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Automatic-Reboot-WithUsers "false";
Unattended-Upgrade::Automatic-Reboot-Time "02:00";
Unattended-Upgrade::Mail "security@kushnir.cloud";
Unattended-Upgrade::MailReport "on-change";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-New-Unused-Dependencies "true";
Unattended-Upgrade::SyslogEnable "true";
Unattended-Upgrade::SyslogFacility "daemon";
Unattended-Upgrade::Mail "security@kushnir.cloud";
EOF

    # Enable automatic updates
    cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

    log "✓ Unattended-upgrades configured"
}

# =============================================================================
# 3. AUDITD — Privileged Operation Audit Log
# =============================================================================

setup_auditd() {
    log "Installing auditd..."
    
    apt-get install -y auditd audispd-plugins 2>&1 | tee -a "$LOG_FILE"
    
    # Create audit rules
    cat > /etc/audit/rules.d/cis-production.rules << 'EOF'
# Remove any existing rules
-D

# Buffer Size
-b 8192

# Failure handling (continue but don't log to syslog if audit queue is full)
-f 1

# ===== Log all sudo commands =====
-a always,exit -F arch=b64 -S execve -F path=/usr/bin/sudo -k sudo_commands
-a always,exit -F arch=b32 -S execve -F path=/usr/bin/sudo -k sudo_commands

# ===== Docker socket access =====
-w /var/run/docker.sock -p rwxa -k docker_socket

# ===== Docker/compose file changes =====
-w /home/akushnir/code-server-enterprise/ -p wa -k compose_files

# ===== SSH key changes =====
-w /home/akushnir/.ssh/ -p wa -k ssh_keys

# ===== System file changes =====
-w /etc/passwd -p wa -k user_account_changes
-w /etc/shadow -p wa -k user_account_changes
-w /etc/group -p wa -k group_changes
-w /etc/sudoers -p wa -k sudoers_changes
-w /etc/sudoers.d/ -p wa -k sudoers_changes

# ===== Kernel parameter changes =====
-w /etc/sysctl.conf -p wa -k sysctl_changes
-w /etc/sysctl.d/ -p wa -k sysctl_changes

# ===== Network configuration changes =====
-w /etc/network/ -p wa -k network_modifications
-w /etc/hostname -p wa -k hostname_changes

# ===== System calls for privilege escalation =====
-a always,exit -F arch=b64 -S setuid -S setgid -k privilege_escalation
-a always,exit -F arch=b32 -S setuid -S setgid -k privilege_escalation

# ===== Failed login attempts =====
-a always,exit -F arch=b64 -S open -F dir=/var/log -F success=0 -k failed_file_access
-a always,exit -F arch=b32 -S open -F dir=/var/log -F success=0 -k failed_file_access

# ===== Make rules immutable =====
-e 2
EOF

    # Load rules
    augenrules --load 2>&1 | tee -a "$LOG_FILE"
    
    # Enable auditd
    systemctl enable auditd
    systemctl restart auditd
    
    log "✓ auditd configured with CIS audit rules"
}

# =============================================================================
# 4. AIDE — File Integrity Monitoring
# =============================================================================

setup_aide() {
    log "Installing AIDE file integrity monitoring..."
    
    apt-get install -y aide aide-common 2>&1 | tee -a "$LOG_FILE"
    
    # Configure AIDE
    cat >> /etc/aide/aide.conf << 'EOF'

# ===== Docker binaries =====
/usr/bin/docker       CONTENT_EX
/usr/bin/docker-compose CONTENT_EX

# ===== SSH and sudo =====
/usr/sbin/sshd        CONTENT_EX
/usr/bin/sudo         CONTENT_EX

# ===== Critical compose files =====
/home/akushnir/code-server-enterprise/docker-compose.yml CONTENT_EX
/home/akushnir/code-server-enterprise/Caddyfile CONTENT_EX
/home/akushnir/code-server-enterprise/.env CONTENT_EX
EOF

    # Initialize database
    log "Initializing AIDE database (this may take several minutes)..."
    aideinit 2>&1 | tee -a "$LOG_FILE"
    
    # Create daily check cron job
    cat > /etc/cron.d/aide-daily-check << 'EOF'
0 3 * * * root /usr/bin/aide --check > /tmp/aide-check-$(date +\%Y\%m\%d).log 2>&1 && mail -s "AIDE Check: $(hostname)" -r aide@kushnir.cloud security@kushnir.cloud < /tmp/aide-check-$(date +\%Y\%m\%d).log || true
EOF

    log "✓ AIDE configured with daily check"
}

# =============================================================================
# 5. KERNEL SECURITY PARAMETERS (sysctl)
# =============================================================================

setup_kernel_hardening() {
    log "Configuring kernel security parameters..."
    
    cat > /etc/sysctl.d/99-cis-hardening.conf << 'EOF'
# ===== Address Space Layout Randomization (ASLR) =====
kernel.randomize_va_space = 2

# ===== SYN Cookie Protection =====
net.ipv4.tcp_syncookies = 1

# ===== Reverse Path Filtering (anti-spoofing) =====
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# ===== Disable ICMP redirects =====
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0

# ===== Disable IP source routing =====
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0

# ===== Log suspicious packets =====
net.ipv4.conf.all.log_martians = 1

# ===== IPv6 (disable if not used) =====
# Uncomment if not using IPv6:
# net.ipv6.conf.all.disable_ipv6 = 1
# net.ipv6.conf.default.disable_ipv6 = 1

# ===== Core dumps =====
fs.suid_dumpable = 0
kernel.core_pattern = |/bin/false

# ===== Kernel pointer exposure =====
kernel.kptr_restrict = 2

# ===== dmesg restrictions =====
kernel.dmesg_restrict = 1

# ===== Magic SysRq =====
kernel.sysrq = 0

# ===== Panic parameters =====
kernel.panic = 60
kernel.panic_on_oops = 1

# ===== Docker requirements =====
net.ipv4.ip_forward = 1
EOF

    sysctl --system 2>&1 | tee -a "$LOG_FILE"
    
    log "✓ Kernel security parameters applied"
}

# =============================================================================
# 6. SSH HARDENING
# =============================================================================

setup_ssh_hardening() {
    log "Hardening SSH configuration..."
    
    mkdir -p /etc/ssh/sshd_config.d
    
    cat > /etc/ssh/sshd_config.d/99-cis-hardening.conf << 'EOF'
# ===== Root login =====
PermitRootLogin no

# ===== Password authentication =====
PasswordAuthentication no
ChallengeResponseAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes

# ===== Authorized users =====
AllowUsers akushnir

# ===== Authentication limits =====
MaxAuthTries 3
LoginGraceTime 30

# ===== Client keepalive =====
ClientAliveInterval 300
ClientAliveCountMax 2

# ===== X11 and tunneling =====
X11Forwarding no
AllowTcpForwarding no
AllowAgentForwarding no
AllowStreamLocalForwarding no

# ===== Empty passwords =====
PermitEmptyPasswords no

# ===== Banner and logging =====
Banner /etc/ssh/banner.txt
LogLevel VERBOSE
SyslogFacility AUTH

# ===== Cryptography (strong algorithms only) =====
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
HostKeyAlgorithms ecdsa-sha2-nistp256-cert-v01@openssh.com,ecdsa-sha2-nistp256

# ===== Other hardening =====
Compression no
GatewayPorts no
IgnoreUserKnownHosts yes
PermitUserEnvironment no
UsePAM yes
X11UseLocalhost yes
Subsystem sftp /usr/lib/openssh/sftp-server -f AUTHPRIV -l INFO
EOF

    # Create SSH banner
    cat > /etc/ssh/banner.txt << 'EOF'
╔════════════════════════════════════════════════════════════════╗
║                                                                ║
║  ⚠️  AUTHORIZED ACCESS ONLY  ⚠️                                 ║
║                                                                ║
║  All access is monitored and logged for security purposes.    ║
║  Unauthorized access attempts will be reported to law         ║
║  enforcement and may result in civil and criminal penalties.  ║
║                                                                ║
║  By accessing this system, you agree to comply with all       ║
║  applicable laws and organizational policies.                 ║
║                                                                ║
╚════════════════════════════════════════════════════════════════╝
EOF

    # Test SSH config before applying
    sshd -t 2>&1 | tee -a "$LOG_FILE" || error "SSH config validation failed"
    
    systemctl restart ssh
    
    log "✓ SSH hardening applied"
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    check_root
    
    log "Starting CIS Ubuntu Hardening..."
    log "Log file: $LOG_FILE"
    log "Rollback script: $ROLLBACK_FILE"
    
    # Execute hardening steps
    setup_fail2ban
    setup_unattended_upgrades
    setup_auditd
    setup_aide
    setup_kernel_hardening
    setup_ssh_hardening
    
    # Verify changes
    log ""
    log "=== HARDENING VERIFICATION ==="
    log "fail2ban status: $(systemctl is-active fail2ban)"
    log "auditd status: $(systemctl is-active auditd)"
    log "SSH hardening: $(sshd -T | grep -c 'permitrootlogin no')"
    log "AIDE database: $(test -f /var/lib/aide/aide.db && echo 'initialized' || echo 'pending')"
    log "Kernel params applied: $(sysctl kernel.randomize_va_space | grep -c '2')"
    log ""
    log "✅ CIS Ubuntu Hardening Complete!"
    log "Reboot recommended for full effect (especially kernel parameters)"
    log "Rollback script (if needed): bash $ROLLBACK_FILE"
}

main "$@"
