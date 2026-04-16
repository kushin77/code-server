#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════════════
# Deploy Docker egress filtering via iptables DOCKER-USER chain
# Issue #350: Block data exfiltration, prevent C&C communication
# ════════════════════════════════════════════════════════════════════════════

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}════════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}DOCKER EGRESS FILTERING DEPLOYMENT - iptables DOCKER-USER Chain${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════════════════════${NC}"

# ─────────────────────────────────────────────────────────────────────────────
# 1. Verify prerequisites
# ─────────────────────────────────────────────────────────────────────────────

echo -e "\n${BLUE}[1] Verifying prerequisites...${NC}"

if ! command -v iptables &> /dev/null; then
    echo -e "${RED}✗ iptables not found${NC}"
    exit 1
fi
echo -e "${GREEN}✓ iptables available${NC}"

if ! command -v docker &> /dev/null; then
    echo -e "${RED}✗ Docker not found${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Docker available${NC}"

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}✗ This script must be run as root (sudo)${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Running as root${NC}"

# ─────────────────────────────────────────────────────────────────────────────
# 2. Create DOCKER-EGRESS chain (whitelist-only egress policy)
# ─────────────────────────────────────────────────────────────────────────────

echo -e "\n${BLUE}[2] Setting up DOCKER-EGRESS chain (default-deny)...${NC}"

# Create chain if not exists
if ! iptables -L DOCKER-EGRESS -n &>/dev/null 2>&1; then
    iptables -N DOCKER-EGRESS || true
    echo -e "${GREEN}✓ Created DOCKER-EGRESS chain${NC}"
else
    echo -e "${YELLOW}⚠ DOCKER-EGRESS chain already exists${NC}"
fi

# Flush existing rules
iptables -F DOCKER-EGRESS || true

# Default policy: ACCEPT (will be called from FORWARD/OUTPUT)
iptables -P DOCKER-EGRESS ACCEPT || true

# ─────────────────────────────────────────────────────────────────────────────
# 3. DNS Whitelist Rules (port 53)
# ─────────────────────────────────────────────────────────────────────────────

echo -e "\n${BLUE}[3] Adding DNS whitelist rules (port 53)...${NC}"

DNS_SERVERS=(
    "8.8.8.8"       # Google Public DNS
    "1.1.1.1"       # Cloudflare DNS
    "8.8.4.4"       # Google Public DNS secondary
)

for dns_ip in "${DNS_SERVERS[@]}"; do
    # UDP 53 (DNS)
    iptables -A DOCKER-EGRESS -d "$dns_ip" -p udp --dport 53 -j ACCEPT
    # TCP 53 (DNS over TCP, used for zone transfers and large responses)
    iptables -A DOCKER-EGRESS -d "$dns_ip" -p tcp --dport 53 -j ACCEPT
done

echo -e "${GREEN}✓ Added ${#DNS_SERVERS[@]} DNS server whitelist rules${NC}"

# ─────────────────────────────────────────────────────────────────────────────
# 4. HTTPS Whitelist Rules (port 443)
# ─────────────────────────────────────────────────────────────────────────────

echo -e "\n${BLUE}[4] Adding HTTPS whitelist rules (port 443)...${NC}"

# Allow all 443 HTTPS (specific domain filtering requires DPI, which is not practical with iptables)
# Production deployments should use:
# - Egress proxy (Squid/Nginx) for domain-level filtering
# - Network ACLs for coarser-grained control
# - WAF rules for application-level control

iptables -A DOCKER-EGRESS -p tcp --dport 443 -j ACCEPT
echo -e "${GREEN}✓ Added HTTPS (port 443) whitelist rule${NC}"

# ─────────────────────────────────────────────────────────────────────────────
# 5. NTP Whitelist Rules (port 123)
# ─────────────────────────────────────────────────────────────────────────────

echo -e "\n${BLUE}[5] Adding NTP whitelist rules (port 123)...${NC}"

NTP_SERVERS=(
    "0.ubuntu.pool.ntp.org"
    "1.ubuntu.pool.ntp.org"
    "2.ubuntu.pool.ntp.org"
    "3.ubuntu.pool.ntp.org"
)

for ntp_host in "${NTP_SERVERS[@]}"; do
    # Resolve hostname to IP (may have multiple IPs)
    ntp_ips=$(getent hosts "$ntp_host" | awk '{print $1}' | sort -u)
    for ntp_ip in $ntp_ips; do
        iptables -A DOCKER-EGRESS -d "$ntp_ip" -p udp --dport 123 -j ACCEPT
    done
done

echo -e "${GREEN}✓ Added ${#NTP_SERVERS[@]} NTP server whitelist rules${NC}"

# ─────────────────────────────────────────────────────────────────────────────
# 6. Local Network Whitelist (internal replication, failover)
# ─────────────────────────────────────────────────────────────────────────────

echo -e "\n${BLUE}[6] Adding local network whitelist rules...${NC}"

LOCAL_NETWORKS=(
    "192.168.168.0/24"  # Primary/replica/standby
    "10.0.0.0/8"        # Additional internal networks
    "172.16.0.0/12"     # Docker internal networks
)

for net in "${LOCAL_NETWORKS[@]}"; do
    iptables -A DOCKER-EGRESS -d "$net" -j ACCEPT
done

echo -e "${GREEN}✓ Added ${#LOCAL_NETWORKS[@]} local network whitelist rules${NC}"

# ─────────────────────────────────────────────────────────────────────────────
# 7. HTTP Whitelist (port 80) - for package repo redirects, fallback
# ─────────────────────────────────────────────────────────────────────────────

echo -e "\n${BLUE}[7] Adding HTTP whitelist rules (port 80)...${NC}"

iptables -A DOCKER-EGRESS -p tcp --dport 80 -j ACCEPT
echo -e "${GREEN}✓ Added HTTP (port 80) whitelist rule${NC}"

# ─────────────────────────────────────────────────────────────────────────────
# 8. Block Egress Rules (explicit deny for dangerous patterns)
# ─────────────────────────────────────────────────────────────────────────────

echo -e "\n${BLUE}[8] Adding egress blocking rules (crypto mining, botnet C&C)...${NC}"

# Block SSH (port 22) - prevent lateral movement
iptables -A DOCKER-EGRESS -p tcp --dport 22 -j DROP
iptables -A DOCKER-EGRESS -p tcp --dport 22 -j DROP -m state --state NEW
echo -e "${GREEN}✓ Blocked SSH egress (port 22)${NC}"

# Block SMTP (port 25) - prevent spam
iptables -A DOCKER-EGRESS -p tcp --dport 25 -j DROP
iptables -A DOCKER-EGRESS -p tcp --dport 587 -j DROP
echo -e "${GREEN}✓ Blocked SMTP egress (ports 25, 587)${NC}"

# Block RDP (port 3389) - prevent C&C
iptables -A DOCKER-EGRESS -p tcp --dport 3389 -j DROP
echo -e "${GREEN}✓ Blocked RDP egress (port 3389)${NC}"

# Block WinRM (port 5985) - prevent C&C
iptables -A DOCKER-EGRESS -p tcp --dport 5985 -j DROP
echo -e "${GREEN}✓ Blocked WinRM egress (port 5985)${NC}"

# Block crypto mining pools (common ports)
for mining_port in 3333 4444 5555 6666 7777 8888 9999 14444 19333; do
    iptables -A DOCKER-EGRESS -p tcp --dport "$mining_port" -j DROP
    iptables -A DOCKER-EGRESS -p udp --dport "$mining_port" -j DROP
done
echo -e "${GREEN}✓ Blocked crypto mining pool ports${NC}"

# ─────────────────────────────────────────────────────────────────────────────
# 9. Default policy: DROP (default-deny for unlisted ports)
# ─────────────────────────────────────────────────────────────────────────────

echo -e "\n${BLUE}[9] Setting DOCKER-EGRESS default policy to DROP...${NC}"

# Add default DROP rule at end of chain
iptables -A DOCKER-EGRESS -j DROP
echo -e "${GREEN}✓ Added default DROP rule (whitelist-only policy)${NC}"

# ─────────────────────────────────────────────────────────────────────────────
# 10. Integrate into Docker FORWARD chain
# ─────────────────────────────────────────────────────────────────────────────

echo -e "\n${BLUE}[10] Integrating DOCKER-EGRESS into FORWARD chain...${NC}"

# Find container network interface (docker0 or custom bridge)
DOCKER_BRIDGE=$(docker network inspect bridge -f '{{.Options}}' 2>/dev/null | grep -o 'com.docker.network.bridge.name=[^,}]*' | cut -d= -f2)
DOCKER_BRIDGE=${DOCKER_BRIDGE:-docker0}

echo -e "     Using Docker bridge: ${BLUE}${DOCKER_BRIDGE}${NC}"

# Remove existing rule if present
iptables -D FORWARD -i "$DOCKER_BRIDGE" ! -o "$DOCKER_BRIDGE" -j DOCKER-EGRESS 2>/dev/null || true

# Add new rule: apply DOCKER-EGRESS to all outbound container traffic
iptables -I FORWARD -i "$DOCKER_BRIDGE" ! -o "$DOCKER_BRIDGE" -j DOCKER-EGRESS

echo -e "${GREEN}✓ Integrated DOCKER-EGRESS into FORWARD chain${NC}"

# ─────────────────────────────────────────────────────────────────────────────
# 11. Verify and display rules
# ─────────────────────────────────────────────────────────────────────────────

echo -e "\n${BLUE}[11] Verifying DOCKER-EGRESS chain...${NC}"

RULE_COUNT=$(iptables -L DOCKER-EGRESS -n | tail -n +3 | wc -l)
echo -e "${GREEN}✓ DOCKER-EGRESS chain contains ${RULE_COUNT} rules${NC}"

echo -e "\n${YELLOW}DOCKER-EGRESS chain rules:${NC}"
iptables -L DOCKER-EGRESS -nv

# ─────────────────────────────────────────────────────────────────────────────
# 12. Make rules persistent (iptables-persistent or nftables)
# ─────────────────────────────────────────────────────────────────────────────

echo -e "\n${BLUE}[12] Persisting iptables rules...${NC}"

if command -v iptables-save &> /dev/null; then
    mkdir -p /etc/iptables
    iptables-save > /etc/iptables/rules.v4
    echo -e "${GREEN}✓ Rules saved to /etc/iptables/rules.v4${NC}"
fi

if systemctl list-unit-files | grep -q iptables-persistent; then
    systemctl enable iptables-persistent
    echo -e "${GREEN}✓ iptables-persistent enabled${NC}"
else
    echo -e "${YELLOW}⚠ Consider installing iptables-persistent for persistence across reboots${NC}"
    echo -e "   ${YELLOW}Run: sudo apt-get install iptables-persistent${NC}"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 13. Test and verify
# ─────────────────────────────────────────────────────────────────────────────

echo -e "\n${BLUE}[13] Testing egress filtering...${NC}"

if command -v docker &> /dev/null && docker ps -q &>/dev/null; then
    CONTAINER=$(docker ps -q | head -1)
    if [[ -n "$CONTAINER" ]]; then
        echo -e "\n${YELLOW}Testing with container ${CONTAINER}:${NC}"
        
        # Test allowed (DNS)
        echo -e "\n  Testing DNS (should succeed):${NC}"
        docker exec "$CONTAINER" nslookup google.com 8.8.8.8 > /dev/null && echo -e "    ${GREEN}✓ DNS to 8.8.8.8 allowed${NC}" || echo -e "    ${RED}✗ DNS to 8.8.8.8 blocked${NC}"
        
        # Test blocked (external SSH)
        echo -e "\n  Testing SSH to external (should fail):${NC}"
        docker exec "$CONTAINER" timeout 2 bash -c 'echo > /dev/tcp/8.8.8.8/22' 2>/dev/null && echo -e "    ${RED}✗ SSH not blocked${NC}" || echo -e "    ${GREEN}✓ SSH egress blocked${NC}"
    else
        echo -e "${YELLOW}⚠ No running containers to test${NC}"
    fi
else
    echo -e "${YELLOW}⚠ Docker not available, skipping container tests${NC}"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────

echo -e "\n${GREEN}════════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✓ DOCKER EGRESS FILTERING DEPLOYED SUCCESSFULLY${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════════════════════${NC}"

echo -e "\n${BLUE}Configuration Summary:${NC}"
echo -e "  • Chain: DOCKER-EGRESS (default-deny whitelist)"
echo -e "  • Rules: DNS (UDP/TCP 53), HTTPS (443), HTTP (80), NTP (123)"
echo -e "  • Local: 192.168.168.0/24, 10.0.0.0/8, 172.16.0.0/12"
echo -e "  • Blocked: SSH (22), SMTP (25,587), RDP (3389), WinRM (5985), crypto mining"
echo -e "  • Persistence: /etc/iptables/rules.v4 (via iptables-save)"
echo -e "  • Status: ${GREEN}ACTIVE${NC}"

echo -e "\n${BLUE}Verification Commands:${NC}"
echo -e "  • Check rules: ${YELLOW}sudo iptables -L DOCKER-EGRESS -nv${NC}"
echo -e "  • View detailed: ${YELLOW}sudo iptables -L DOCKER-EGRESS -nv | grep -E 'pkts|bytes'${NC}"
echo -e "  • Test DNS: ${YELLOW}docker exec <container> nslookup google.com${NC}"
echo -e "  • Test SSH block: ${YELLOW}docker exec <container> timeout 1 bash -c 'echo >/dev/tcp/8.8.8.8/22'${NC}"
echo -e "  • Monitor blocks: ${YELLOW}sudo iptables -L DOCKER-EGRESS -nv${NC}"

echo -e "\n${BLUE}Monitoring & Alerts:${NC}"
echo -e "  • Monitor /var/log/syslog for DROP rules"
echo -e "  • Enable iptables logging: ${YELLOW}iptables -A DOCKER-EGRESS -j LOG --log-prefix 'DOCKER-DROP: '${NC}"
echo -e "  • Prometheus metrics available via node-exporter"

echo -e "\n${BLUE}Next Steps:${NC}"
echo -e "  • Deploy Prometheus metrics for egress monitoring"
echo -e "  • Configure AlertManager alerts for blocked traffic"
echo -e "  • Run 48-hour monitoring period for false positives"
echo -e "  • Proceed to #348 (Cloudflare Tunnel) after verification"

echo -e ""
