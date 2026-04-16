#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════════════
# Cleanup Docker egress filtering rules (for rollback/uninstall)
# ════════════════════════════════════════════════════════════════════════════

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}Removing Docker egress filtering rules...${NC}"

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}✗ This script must be run as root${NC}"
    exit 1
fi

# Remove DOCKER-EGRESS chain from FORWARD
DOCKER_BRIDGE=$(docker network inspect bridge -f '{{.Options}}' 2>/dev/null | grep -o 'com.docker.network.bridge.name=[^,}]*' | cut -d= -f2)
DOCKER_BRIDGE=${DOCKER_BRIDGE:-docker0}

iptables -D FORWARD -i "$DOCKER_BRIDGE" ! -o "$DOCKER_BRIDGE" -j DOCKER-EGRESS 2>/dev/null || true

# Flush DOCKER-EGRESS chain
iptables -F DOCKER-EGRESS 2>/dev/null || true

# Remove DOCKER-EGRESS chain
iptables -X DOCKER-EGRESS 2>/dev/null || true

echo -e "${GREEN}✓ Egress filtering rules removed${NC}"
