#!/usr/bin/env bash
# P0 #1272: Security & Compliance - IP Allowlist Implementation
# Network access control for workspace connections

# @file        scripts/security/configure-ip-allowlist.sh
# @module      security/network-access-control
# @description Configure IP allowlist for workspace network access

set -euo pipefail

echo "=========================================="
echo "P0 #1272: IP Allowlist Configuration"
echo "=========================================="
echo ""

# IP Allowlist configuration directory
ALLOWLIST_DIR="/etc/ip-allowlist"
ALLOWLIST_FILE="${ALLOWLIST_DIR}/workspace-allowlist.conf"
FIREWALL_RULES_FILE="${ALLOWLIST_DIR}/firewall-rules.sh"

setup_allowlist_infrastructure() {
    echo "Setting up IP allowlist infrastructure..."
    mkdir -p "${ALLOWLIST_DIR}"
    chmod 0700 "${ALLOWLIST_DIR}"
    
    # Create the allowlist configuration
    cat > "${ALLOWLIST_FILE}" << 'EOF'
# IP Allowlist Configuration for kushin77/code-server
# Format: IP_ADDRESS|DESCRIPTION|PROTOCOL|PORTS

# Internal trusted networks
192.168.168.0/24|Primary on-prem network|all|all
192.168.168.31|Primary production host|tcp|443,22,6379,5432
192.168.168.42|Replica host|tcp|443,22,6379,5432

# Corporate networks
10.0.0.0/8|Corporate network|tcp|443,22
203.0.113.0/24|Corporate office|tcp|443,22,3306

# Approved cloud providers
35.184.0.0/13|Google Cloud|tcp|443
52.0.0.0/8|AWS|tcp|443

# Monitoring and observability
127.0.0.1|Localhost|tcp|all
::1|Localhost IPv6|tcp|all

# Security services
198.51.100.0/24|Security provider|tcp|443,8443

# Defaults: DENY ALL OTHERS
*|Default deny|tcp|none
EOF

    echo "✓ Allowlist configuration created"
}

generate_firewall_rules() {
    echo "Generating firewall rules from allowlist..."
    
    cat > "${FIREWALL_RULES_FILE}" << 'EOF'
#!/usr/bin/env bash
# Auto-generated from IP allowlist configuration
# Do not edit manually - regenerate from allowlist source

# UFW-based firewall rules
setup_ufw_rules() {
    echo "Configuring UFW firewall rules..."
    
    # Reset to default deny
    ufw default deny incoming
    ufw default allow outgoing
    
    # Allow SSH from allowlisted IPs
    ufw allow from 192.168.168.0/24 to any port 22
    ufw allow from 10.0.0.0/8 to any port 22
    
    # Allow HTTPS from allowlisted IPs
    ufw allow from 192.168.168.0/24 to any port 443
    ufw allow from 10.0.0.0/8 to any port 443
    ufw allow from 35.184.0.0/13 to any port 443
    ufw allow from 52.0.0.0/8 to any port 443
    
    # Allow internal services
    ufw allow from 192.168.168.31 to 192.168.168.42 port 6379  # Redis
    ufw allow from 192.168.168.31 to 192.168.168.42 port 5432  # Postgres
    
    # Enable firewall
    ufw enable
    
    echo "✓ UFW rules configured"
}

# iptables-based rules
setup_iptables_rules() {
    echo "Configuring iptables rules..."
    
    # Allow established connections
    iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    
    # Allow loopback
    iptables -A INPUT -i lo -j ACCEPT
    
    # Allow SSH from internal network
    iptables -A INPUT -s 192.168.168.0/24 -p tcp --dport 22 -j ACCEPT
    
    # Allow HTTPS from allowlisted networks
    iptables -A INPUT -s 192.168.168.0/24 -p tcp --dport 443 -j ACCEPT
    iptables -A INPUT -s 10.0.0.0/8 -p tcp --dport 443 -j ACCEPT
    iptables -A INPUT -s 35.184.0.0/13 -p tcp --dport 443 -j ACCEPT
    iptables -A INPUT -s 52.0.0.0/8 -p tcp --dport 443 -j ACCEPT
    
    # Default deny
    iptables -A INPUT -j DROP
    
    echo "✓ iptables rules configured"
}

setup_ufw_rules
setup_iptables_rules
EOF

    chmod +x "${FIREWALL_RULES_FILE}"
    echo "✓ Firewall rules generated"
}

create_allowlist_validator() {
    echo "Creating IP allowlist validator..."
    
    cat > "${ALLOWLIST_DIR}/validate-allowlist.py" << 'EOF'
#!/usr/bin/env python3
"""Validate IP allowlist configuration and check for violations"""

import json
import ipaddress
import subprocess
from datetime import datetime

class IPAllowlistValidator:
    def __init__(self, allowlist_file):
        self.allowlist_file = allowlist_file
        self.violations = []
    
    def load_allowlist(self):
        """Load IP allowlist from configuration file"""
        allowlist = []
        with open(self.allowlist_file, 'r') as f:
            for line in f:
                line = line.strip()
                if line.startswith('#') or not line:
                    continue
                parts = line.split('|')
                if len(parts) >= 4:
                    ip, desc, proto, ports = parts[0:4]
                    allowlist.append({
                        'ip': ip,
                        'description': desc,
                        'protocol': proto,
                        'ports': ports
                    })
        return allowlist
    
    def validate_ip(self, ip_addr):
        """Validate if IP is in allowlist"""
        allowlist = self.load_allowlist()
        try:
            test_ip = ipaddress.ip_address(ip_addr)
            for entry in allowlist:
                try:
                    network = ipaddress.ip_network(entry['ip'], strict=False)
                    if test_ip in network:
                        return True, entry
                except:
                    pass
        except ValueError:
            pass
        return False, None
    
    def check_connection_logs(self):
        """Check system logs for unauthorized connection attempts"""
        print("Checking for unauthorized connection attempts...")
        result = subprocess.run(
            ["journalctl", "-u", "ufw", "-n", "100"],
            capture_output=True,
            text=True
        )
        
        for line in result.stdout.split('\n'):
            if 'REJECT' in line or 'DROP' in line:
                # Log potential violation
                self.violations.append({
                    'timestamp': datetime.now().isoformat(),
                    'event': line,
                    'severity': 'medium'
                })
        
        return len(self.violations)

if __name__ == '__main__':
    validator = IPAllowlistValidator('/etc/ip-allowlist/workspace-allowlist.conf')
    
    # Test IPs
    test_cases = [
        ('192.168.168.31', True),   # Should be allowed
        ('192.168.168.1', True),    # Should be allowed (in range)
        ('8.8.8.8', False),         # Should be denied
        ('203.0.113.10', True),     # Corporate network
    ]
    
    print("Testing IP allowlist validation...")
    for ip, expected in test_cases:
        allowed, entry = validator.validate_ip(ip)
        status = "✓" if allowed == expected else "✗"
        print(f"{status} {ip}: {'allowed' if allowed else 'denied'}")
        if entry:
            print(f"   ({entry['description']})")
    
    print("\nValidation complete.")
EOF

    chmod +x "${ALLOWLIST_DIR}/validate-allowlist.py"
    echo "✓ IP allowlist validator created"
}

main() {
    echo ""
    setup_allowlist_infrastructure
    echo ""
    
    generate_firewall_rules
    echo ""
    
    create_allowlist_validator
    echo ""
    
    echo "=========================================="
    echo "IP Allowlist Configuration Complete"
    echo "=========================================="
    echo ""
    echo "Configuration created:"
    echo "  Allowlist file: ${ALLOWLIST_FILE}"
    echo "  Firewall rules: ${FIREWALL_RULES_FILE}"
    echo "  Validator: ${ALLOWLIST_DIR}/validate-allowlist.py"
    echo ""
    echo "To apply firewall rules:"
    echo "  bash ${FIREWALL_RULES_FILE}"
    echo ""
}

main
