#!/bin/bash
# @file scripts/ha/check-caddy-health.sh
# @description Keepalived health check script — verifies Caddy is running and responsive
# @usage Called by keepalived every 3 seconds; exit 0 = healthy, exit 1 = unhealthy

set -eu

trap 'exit 1' ERR
trap 'true' EXIT

# Verify Caddy container is running
if ! docker ps --format '{{.Names}}' | grep -q '^code-server-caddy$'; then
  exit 1
fi

# Test Caddy health endpoint via loopback (works in container network)
if ! wget -q --timeout=2 -O - http://127.0.0.1/health 2>/dev/null | grep -q OK; then
  exit 1
fi

exit 0
