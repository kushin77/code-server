#!/bin/bash
# Phase 14: VPN Readiness Verification Script
# Purpose: Quick check that user is ready to execute validation suite
# Usage: bash /scripts/phase-14-vpn-readiness-check.sh

set -u

DOMAIN="ide.kushnir.cloud"
PROD_HOST="192.168.168.31"
COLOR_GREEN='\033[0;32m'
COLOR_RED='\033[0;31m'
COLOR_YELLOW='\033[1;33m'
COLOR_BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${COLOR_BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${COLOR_BLUE}║  Phase 14: VPN Readiness Verification                  ║${NC}"
echo -e "${COLOR_BLUE}║  Purpose: Confirm VPN is ready for validation suite   ║${NC}"
echo -e "${COLOR_BLUE}╚════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Timestamp: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo ""

PASS_COUNT=0
FAIL_COUNT=0

# Check 1: Ping production host
echo -e "${COLOR_BLUE}[1] VPN Connectivity Check${NC}"
if ping -c 1 -W 3 "$PROD_HOST" &>/dev/null; then
    echo -e "${COLOR_GREEN}✅ Can reach $PROD_HOST${NC}"
    ((PASS_COUNT++))
else
    echo -e "${COLOR_RED}❌ Cannot reach $PROD_HOST - VPN may not be connected${NC}"
    ((FAIL_COUNT++))
fi
echo ""

# Check 2: DNS Server Configuration
echo -e "${COLOR_BLUE}[2] VPN DNS Configuration Check${NC}"
if grep -q "nameserver" /etc/resolv.conf 2>/dev/null; then
    DNS_COUNT=$(grep "nameserver" /etc/resolv.conf | wc -l)
    echo -e "${COLOR_GREEN}✅ Found $DNS_COUNT nameserver(s) configured${NC}"
    grep "nameserver" /etc/resolv.conf | head -3 | sed 's/^/   /'
    ((PASS_COUNT++))
else
    echo -e "${COLOR_YELLOW}⚠️  No nameservers found - DNS may be misconfigured${NC}"
    ((FAIL_COUNT++))
fi
echo ""

# Check 3: DNS Resolution Test
echo -e "${COLOR_BLUE}[3] DNS Resolution Test${NC}"
if command -v dig &>/dev/null; then
    RESOLVED_IP=$(dig +short "$DOMAIN" A 2>/dev/null | head -1)
    if [ -n "$RESOLVED_IP" ]; then
        if [ "$RESOLVED_IP" = "$PROD_HOST" ]; then
            echo -e "${COLOR_GREEN}✅ DNS resolves $DOMAIN → $RESOLVED_IP${NC}"
            ((PASS_COUNT++))
        else
            echo -e "${COLOR_YELLOW}⚠️  DNS resolves $DOMAIN → $RESOLVED_IP (expected $PROD_HOST)${NC}"
            ((FAIL_COUNT++))
        fi
    else
        echo -e "${COLOR_RED}❌ DNS cannot resolve $DOMAIN${NC}"
        ((FAIL_COUNT++))
    fi
else
    echo -e "${COLOR_YELLOW}⚠️  dig not available - skipping DNS test${NC}"
fi
echo ""

# Check 4: HTTPS Connectivity (pre-check)
echo -e "${COLOR_BLUE}[4] HTTPS Endpoint Reachability${NC}"
if command -v curl &>/dev/null; then
    if timeout 5 curl -s -k -I "https://$DOMAIN/" &>/dev/null; then
        echo -e "${COLOR_GREEN}✅ HTTPS endpoint reachable${NC}"
        ((PASS_COUNT++))
    else
        echo -e "${COLOR_YELLOW}⚠️  HTTPS endpoint not responding (may be normal, proxy warming up)${NC}"
    fi
else
    echo -e "${COLOR_YELLOW}⚠️  curl not available - skipping HTTPS test${NC}"
fi
echo ""

# Check 5: Required Tools
echo -e "${COLOR_BLUE}[5] Required Tools Check${NC}"
TOOLS_FOUND=0
for tool in dig curl openssl timeout; do
    if command -v "$tool" &>/dev/null; then
        echo -e "${COLOR_GREEN}✅ $tool${NC}"
        ((TOOLS_FOUND++))
    else
        echo -e "${COLOR_YELLOW}⚠️  $tool not found${NC}"
    fi
done
if [ $TOOLS_FOUND -ge 3 ]; then
    ((PASS_COUNT++))
else
    ((FAIL_COUNT++))
fi
echo ""

# Summary
echo -e "${COLOR_BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${COLOR_BLUE}VERIFICATION SUMMARY${NC}"
echo -e "${COLOR_BLUE}═══════════════════════════════════════════════════════${NC}"
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"
echo ""

if [ $FAIL_COUNT -eq 0 ]; then
    echo -e "${COLOR_GREEN}✅ VPN IS READY - You can proceed with validation suite${NC}"
    echo ""
    echo "Next step: Execute validation suite"
    echo "Command: bash /scripts/phase-14-vpn-validation-runner.sh"
    echo ""
    exit 0
elif [ $FAIL_COUNT -eq 1 ] && grep -q "endpoint not responding" <<< "$(ping -c 1 -W 3 "$PROD_HOST" 2>&1 || true)"; then
    echo -e "${COLOR_YELLOW}⚠️  VPN CONNECTION WEAK - Verify connection and retry${NC}"
    echo ""
    echo "Troubleshooting steps:"
    echo "1. Verify VPN client is connected: \`ip link | grep tun\`"
    echo "2. Check routing: \`ip route | grep tun\`"
    echo "3. Test DNS: \`nslookup $DOMAIN\`"
    echo ""
    exit 1
else
    echo -e "${COLOR_RED}❌ VPN NOT READY - Address issues before proceeding${NC}"
    echo ""
    echo "Common issues:"
    echo "1. Not connected to production VPN"
    echo "2. DNS not configured for VPN"
    echo "3. Firewall blocking production host"
    echo ""
    echo "Fix and retry: bash /scripts/phase-14-vpn-readiness-check.sh"
    echo ""
    exit 1
fi
