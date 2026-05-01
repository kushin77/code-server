#!/bin/bash
# Set up comprehensive audit logging for platform
# Enables auditd and configures rules for security monitoring

set -e
trap 'echo "❌ Setup failed"; exit 1' ERR

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Audit Logging Configuration                               ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
  echo "❌ This script must be run as root"
  exit 1
fi

# Install auditd
echo "Installing audit daemon..."
apt-get update >/dev/null
apt-get install -y auditd audispd-plugins >/dev/null
echo "✓ auditd installed"

# Create audit rules directory
mkdir -p /etc/audit/rules.d

echo "Configuring audit rules..."

# Backup existing rules
if [[ -f /etc/audit/rules.d/audit.rules ]]; then
  cp /etc/audit/rules.d/audit.rules /etc/audit/rules.d/audit.rules.backup
fi

# Create platform-specific audit rules
cat > /etc/audit/rules.d/platform.rules << 'AUDIT_EOF'
# Delete all rules
-D

# Buffer Size
-b 8192

# Failure Mode
-f 1

# Platform Security Audit Rules
# ==============================

# Monitor administrative commands (root)
-a always,exit -F arch=b64 -S execve -F uid=0 -k admin_commands
-a always,exit -F arch=b32 -S execve -F uid=0 -k admin_commands

# Monitor user commands (non-root)
-a always,exit -F arch=b64 -S execve -F uid>=1000 -k user_commands
-a always,exit -F arch=b32 -S execve -F uid>=1000 -k user_commands

# Monitor password changes
-w /etc/shadow -p wa -k password_changes
-w /etc/passwd -p wa -k user_changes
-w /etc/group -p wa -k group_changes
-w /etc/gshadow -p wa -k group_changes

# Monitor secrets
-w /var/secrets/ -p wa -k secrets_access
-w /var/backups/credentials/ -p wa -k credential_access
-w /var/backups/sealing-keys/ -p wa -k key_access

# Monitor system configuration
-w /etc/postgresql/ -p wa -k db_config_changes
-w /etc/docker/ -p wa -k container_config_changes
-w /etc/caddy/ -p wa -k gateway_config_changes
-w /etc/keepalived/ -p wa -k keepalived_config_changes

# Monitor application configuration
-w /home/akushnir/code-server-enterprise/ -p wa -k app_config_changes
-w /home/akushnir/code-server/ -p wa -k platform_config_changes

# Monitor Docker daemon
-w /var/lib/docker/ -p wa -k docker_changes
-w /var/run/docker.sock -p wa -k docker_socket

# Monitor network configuration
-w /etc/hosts -p wa -k network_config
-w /etc/hostname -p wa -k network_config
-w /etc/sysctl.conf -p wa -k network_config

# Monitor log files
-w /var/log/ -p wa -k log_changes
-w /var/log/audit/ -p wa -k audit_log_changes

# Monitor SSH access
-w /etc/ssh/sshd_config -p wa -k sshd_config
-w /var/log/auth.log -p wa -k authentication

# Monitor sudo usage
-w /etc/sudoers -p wa -k sudoers_changes
-w /etc/sudoers.d/ -p wa -k sudoers_changes

# File integrity monitoring
-w /usr/local/bin/ -p wa -k binary_changes
-w /usr/bin/ -p wa -k binary_changes

# Make rules immutable (prevents tampering)
-e 2
AUDIT_EOF

echo "✓ Audit rules configured"

# Load and enable rules
echo -n "Enabling audit rules... "
augenrules --load >/dev/null 2>&1 || auditctl -R /etc/audit/rules.d/ >/dev/null 2>&1
echo "✓"

# Enable and start auditd service
echo -n "Starting auditd service... "
systemctl enable auditd >/dev/null 2>&1
systemctl restart auditd >/dev/null 2>&1
echo "✓"

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Audit Logging Configuration Complete                      ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Display audit status
echo "Audit Status:"
auditctl -l | head -20 || echo "  (audit rules will display here)"

echo ""
echo "Audit Configuration:"
echo "  Rules directory: /etc/audit/rules.d/platform.rules"
echo "  Log directory: /var/log/audit/"
echo "  Status check: systemctl status auditd"
echo "  View logs: ausearch -k admin_commands (example)"
echo ""

# Display sample log viewing commands
cat > /tmp/audit-commands.sh << 'COMMANDS_EOF'
#!/bin/bash
# Common audit log viewing commands

echo "Sample audit log viewing commands:"
echo ""
echo "View password changes:"
echo "  ausearch -k password_changes"
echo ""
echo "View admin commands:"
echo "  ausearch -k admin_commands"
echo ""
echo "View config file changes:"
echo "  ausearch -k db_config_changes"
echo ""
echo "View SSH access:"
echo "  ausearch -k authentication"
echo ""
echo "View recent events:"
echo "  ausearch --start recent"
echo ""
COMMANDS_EOF

chmod +x /tmp/audit-commands.sh
bash /tmp/audit-commands.sh

echo "✅ Audit logging is now active"
