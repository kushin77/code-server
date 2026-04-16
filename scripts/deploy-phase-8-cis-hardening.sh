#!/bin/bash
# DEPRECATED: Use canonical entrypoint from scripts/README.md instead (EOL: 2026-07-14)
# See: DEPRECATED-SCRIPTS.md
# scripts/deploy-phase-8-cis-hardening.sh
# =========================================
# CIS Ubuntu 22.04 LTS Security Hardening
# Implements CIS Benchmark Level 2 controls for production
#
# Usage:
#   sudo bash scripts/deploy-phase-8-cis-hardening.sh [--dry-run]
#
# Prerequisites:
#   - Ubuntu 22.04 LTS
#   - sudo access
#   - systemd

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
fi

# Logging
log_info() { echo "[INFO] $*"; }
log_ok()  { echo "  ✓ $*"; }
log_warn(){ echo "  ⚠ $*"; }
log_err() { echo "  ✗ $*" >&2; }

dry() {
    if [[ "${DRY_RUN}" == "true" ]]; then
        echo "[DRY-RUN] $*"
        return 0
    fi
    "$@"
}

log_info "═══════════════════════════════════════════════════════════════"
log_info "CIS Ubuntu 22.04 LTS Security Hardening (Level 2)"
log_info "═══════════════════════════════════════════════════════════════"

# ─── 1.1 Filesystem Configuration ─────────────────────────────────────────

log_info "1.1: Filesystem hardening"

# 1.1.1 - Mount /tmp with nodev,nosuid,noexec
if mountpoint -q /tmp; then
    log_info "1.1.1: Securing /tmp mount options"
    dry mount -o remount,nodev,nosuid,noexec /tmp && log_ok "/tmp hardened (nodev,nosuid,noexec)" || log_warn "/tmp remount failed"
fi

# 1.1.2 - Mount /var with nodev
if mountpoint -q /var; then
    log_info "1.1.2: Securing /var mount options"
    dry mount -o remount,nodev /var && log_ok "/var hardened (nodev)" || log_warn "/var remount failed"
fi

# 1.1.3 - Mount /var/tmp with nodev,nosuid,noexec
if mountpoint -q /var/tmp; then
    log_info "1.1.3: Securing /var/tmp mount options"
    dry mount -o remount,nodev,nosuid,noexec /var/tmp && log_ok "/var/tmp hardened" || log_warn "/var/tmp remount failed"
fi

# 1.1.4 - Mount /var/log with nodev,nosuid,noexec
if mountpoint -q /var/log; then
    log_info "1.1.4: Securing /var/log mount options"
    dry mount -o remount,nodev,nosuid,noexec /var/log && log_ok "/var/log hardened" || log_warn "/var/log remount failed"
fi

# 1.1.5 - Mount /var/log/audit with nodev,nosuid,noexec
if mountpoint -q /var/log/audit; then
    log_info "1.1.5: Securing /var/log/audit mount options"
    dry mount -o remount,nodev,nosuid,noexec /var/log/audit && log_ok "/var/log/audit hardened" || log_warn "/var/log/audit remount failed"
fi

# 1.1.6 - Mount /home with nodev
if mountpoint -q /home; then
    log_info "1.1.6: Securing /home mount options"
    dry mount -o remount,nodev /home && log_ok "/home hardened (nodev)" || log_warn "/home remount failed"
fi

# ─── 2.1 Services: Disable unnecessary services ────────────────────────────

log_info "2.1: Disable unnecessary services"

UNNECESSARY_SERVICES=(
    "avahi-daemon"
    "isc-dhcp-server"
    "isc-dhcp-server6"
    "slapd"
    "nfs-server"
    "bind9"
    "vsftpd"
    "apache2"
    "dovecot"
    "snmpd"
    "rsync"
    "nis"
)

for service in "${UNNECESSARY_SERVICES[@]}"; do
    if systemctl is-enabled "${service}" 2>/dev/null | grep -q "enabled"; then
        log_info "Disabling ${service}..."
        dry systemctl --now disable "${service}" && log_ok "${service} disabled" || log_warn "${service} disable failed (may not be installed)"
    fi
done

# ─── 3.1 Network Parameters: Disable IPv6 (if not needed) ──────────────────

log_info "3.1: Network hardening (IPv4)"

# Enable SYN cookies
log_info "3.1.1: Enable SYN cookies"
dry sysctl -w net.ipv4.tcp_syncookies=1 && log_ok "SYN cookies enabled" || log_warn "SYN cookies failed"

# Disable IP forwarding (unless needed)
log_info "3.1.2: Disable IP forwarding"
dry sysctl -w net.ipv4.ip_forward=0 && log_ok "IP forwarding disabled" || log_warn "IP forwarding disable failed"

# Disable ICMP redirect
log_info "3.1.3: Disable ICMP redirect"
dry sysctl -w net.ipv4.conf.all.send_redirects=0 && \
dry sysctl -w net.ipv4.conf.default.send_redirects=0 && \
log_ok "ICMP redirects disabled" || log_warn "ICMP redirect disable failed"

# Disable source packet routing
log_info "3.1.4: Disable source packet routing"
dry sysctl -w net.ipv4.conf.all.accept_source_route=0 && \
dry sysctl -w net.ipv4.conf.default.accept_source_route=0 && \
log_ok "Source packet routing disabled" || log_warn "Source routing disable failed"

# Enable bad error message protection
log_info "3.1.5: Enable bad error message protection"
dry sysctl -w net.ipv4.icmp_ignore_bogus_error_responses=1 && log_ok "Bad error protection enabled" || log_warn "Bad error protection failed"

# ─── 5.1 Access, Authentication, Authorization: SSH Hardening ──────────────

log_info "5.1: SSH Hardening"

if [[ -f /etc/ssh/sshd_config ]]; then
    # Backup original sshd_config
    if [[ "${DRY_RUN}" == "false" ]]; then
        cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak.$(date +%Y%m%d-%H%M%S)
    fi

    # Apply hardened SSH config
    SSH_HARDENING=(
        "PermitRootLogin no"
        "StrictModes yes"
        "MaxAuthTries 3"
        "MaxSessions 10"
        "PubkeyAuthentication yes"
        "PermitEmptyPasswords no"
        "PasswordAuthentication no"
        "PermitUserEnvironment no"
        "Compression no"
        "ClientAliveInterval 300"
        "ClientAliveCountMax 2"
        "UsePAM yes"
        "AllowAgentForwarding no"
        "AllowTcpForwarding no"
        "PermitTunnel no"
        "X11Forwarding no"
    )

    for setting in "${SSH_HARDENING[@]}"; do
        key="${setting%% *}"
        if ! grep -q "^${key}" /etc/ssh/sshd_config; then
            log_info "Adding SSH: ${setting}"
            if [[ "${DRY_RUN}" == "false" ]]; then
                echo "${setting}" >> /etc/ssh/sshd_config
            fi
        fi
    done

    if [[ "${DRY_RUN}" == "false" ]]; then
        sshd -t && systemctl reload ssh && log_ok "SSH hardened and reloaded" || log_err "SSH config error"
    else
        echo "[DRY-RUN] Would apply SSH hardening settings"
    fi
fi

# ─── 5.2.1 Configure auditd ───────────────────────────────────────────────

log_info "5.2.1: Install and configure auditd"

if ! command -v auditd &>/dev/null; then
    log_info "Installing auditd..."
    dry apt-get update && apt-get install -y auditd audispd-plugins
    log_ok "auditd installed"
fi

# Enable auditd
dry systemctl --now enable auditd && log_ok "auditd enabled" || log_warn "auditd enable failed"

# Add audit rules for critical operations
if [[ "${DRY_RUN}" == "false" ]]; then
    cat >> /etc/audit/rules.d/cis.rules 2>/dev/null <<'AUDIT' || true
-w /sbin/insmod -p x -k modules
-w /sbin/rmmod -p x -k modules
-w /sbin/modprobe -p x -k modules
-a always,exit -F arch=b64 -S adjtimex -S settimeofday -k time-change
-a always,exit -F arch=b32 -S adjtimex -S settimeofday -S stime -k time-change
-w /etc/localtime -p wa -k time-change
-a always,exit -F arch=b64 -S sethostname -S setdomainname -k network_modifications
-a always,exit -F arch=b32 -S sethostname -S setdomainname -k network_modifications
-w /etc/issue -p wa -k system_locale
-w /etc/sudoers -p wa -k scope
-w /var/log/wtmp -p wa -k logins
-w /var/log/btmp -p wa -k logins
-w /var/log/faillog -p wa -k logins
-w /var/log/lastlog -p wa -k logins
AUDIT
    auditctl -R /etc/audit/rules.d/cis.rules && log_ok "Audit rules loaded" || log_warn "Audit rules load failed"
fi

# ─── 5.2.4 Configure rsyslog ──────────────────────────────────────────────

log_info "5.2.4: Configure logging"

if ! command -v rsyslog &>/dev/null; then
    log_info "Installing rsyslog..."
    dry apt-get install -y rsyslog
fi

dry systemctl --now enable rsyslog && log_ok "rsyslog enabled" || log_warn "rsyslog enable failed"

# ─── 5.3 Access, Authentication, Authorization: PAM ────────────────────────

log_info "5.3: PAM hardening"

if [[ -f /etc/security/pwquality.conf ]]; then
    log_info "Configuring password quality requirements"
    dry install -D -m 0644 /dev/null /etc/security/pwquality.conf.d/cis.conf
    if [[ "${DRY_RUN}" == "false" ]]; then
        cat > /etc/security/pwquality.conf.d/cis.conf <<'PAM'
minlen = 14
dcredit = -1
ucredit = -1
ocredit = -1
lcredit = -1
difok = 3
maxrepeat = 3
usercheck = 1
enforce_for_root
PAM
        log_ok "PAM password quality configured"
    fi
fi

# ─── 6.1 System Accounting with auditd ────────────────────────────────────

log_info "6.1: File Integrity Monitoring (AIDE)"

if ! command -v aide &>/dev/null; then
    log_info "Installing AIDE..."
    dry apt-get install -y aide aide-common
    if [[ "${DRY_RUN}" == "false" ]]; then
        aideinit  # Initialize AIDE database
        mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db
        log_ok "AIDE initialized"
    fi
fi

# ─── 6.2 System Maintenance: unattended-upgrades ───────────────────────────

log_info "6.2: Automatic security updates (unattended-upgrades)"

if ! command -v unattended-upgrade &>/dev/null; then
    log_info "Installing unattended-upgrades..."
    dry apt-get install -y unattended-upgrades
fi

dry systemctl --now enable unattended-upgrades && log_ok "unattended-upgrades enabled" || log_warn "unattended-upgrades enable failed"

# Configure APT auto-updates
if [[ "${DRY_RUN}" == "false" ]]; then
    cat > /etc/apt/apt.conf.d/50unattended-upgrades <<'APT'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};
Unattended-Upgrade::Mail "root";
Unattended-Upgrade::MailOnlyOnError "true";
Unattended-Upgrade::SyslogLogging "true";
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "02:00";
APT
    log_ok "Unattended-upgrades configuration deployed"
fi

# ─── 6.3 System Maintenance: fail2ban ──────────────────────────────────────

log_info "6.3: Install fail2ban (intrusion prevention)"

if ! command -v fail2ban-server &>/dev/null; then
    log_info "Installing fail2ban..."
    dry apt-get install -y fail2ban
fi

dry systemctl --now enable fail2ban && log_ok "fail2ban enabled" || log_warn "fail2ban enable failed"

# Configure fail2ban for SSH
if [[ "${DRY_RUN}" == "false" ]]; then
    cat > /etc/fail2ban/jail.local <<'FAIL2BAN'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
destemail = root@localhost
sendername = fail2ban
action = %(action_mwl)s

[sshd]
enabled = true
port = ssh
logpath = /var/log/auth.log
maxretry = 3
bantime = 7200
FAIL2BAN
    systemctl restart fail2ban && log_ok "fail2ban SSH protection configured" || log_warn "fail2ban config failed"
fi

# ─── Persist sysctl settings ──────────────────────────────────────────────

log_info "Persisting kernel parameters"

if [[ "${DRY_RUN}" == "false" ]]; then
    cat > /etc/sysctl.d/99-cis-hardening.conf <<'SYSCTL'
# CIS Ubuntu 22.04 LTS Hardening - Kernel parameters
net.ipv4.tcp_syncookies = 1
net.ipv4.ip_forward = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.icmp_ignore_bogus_error_responses = 1
kernel.dmesg_restrict = 1
kernel.printk = 3 3 3 3
kernel.unprivileged_bpf_disabled = 1
kernel.unprivileged_userns_clone = 0
net.core.bpf_jit_harden = 2
SYSCTL
    sysctl -p /etc/sysctl.d/99-cis-hardening.conf && log_ok "Kernel parameters persisted" || log_warn "sysctl persist failed"
fi

log_info "═══════════════════════════════════════════════════════════════"
log_ok "CIS Ubuntu 22.04 LTS hardening complete"
log_info "═══════════════════════════════════════════════════════════════"
log_info ""
log_warn "Manual verification required:"
log_warn "  - Review SSH configuration: sshd -T"
log_warn "  - Review audit rules: auditctl -l"
log_warn "  - Check firewall: ufw status"
log_warn "  - Monitor fail2ban: fail2ban-client status"
