#!/bin/bash
# scripts/lib/env.sh
# ==================
# SOURCE THIS AT THE TOP OF EVERY PRODUCTION SCRIPT
#
# Usage:
#   source "$(git rev-parse --show-toplevel)/scripts/lib/env.sh"
#   ssh "$SSH_USER@$PRIMARY_HOST" "docker-compose ps"
#
# Exports all production topology variables from environments/production/hosts.yml

set -e

# Find the repo root (handles running from any subdirectory)
REPO_ROOT="$(git rev-parse --show-toplevel)" || {
    echo "ERROR: Not in a git repository. Cannot source env.sh" >&2
    return 1
}

INVENTORY_FILE="$REPO_ROOT/environments/production/hosts.yml"

# Verify inventory file exists
if [ ! -f "$INVENTORY_FILE" ]; then
    echo "ERROR: Inventory file not found: $INVENTORY_FILE" >&2
    echo "Run this script from within the code-server repository" >&2
    return 1
fi

# Verify yq is installed
if ! command -v yq &> /dev/null; then
    echo "ERROR: yq is required but not installed. Install: sudo apt-get install yq" >&2
    return 1
fi

# ============================================================================
# EXTRACT TOPOLOGY FROM INVENTORY
# ============================================================================

# Physical host IPs
export PRIMARY_HOST=$(yq '.hosts.primary.ip' "$INVENTORY_FILE")
export REPLICA_HOST=$(yq '.hosts.replica.ip' "$INVENTORY_FILE")
export VIP=$(yq '.vip.ip' "$INVENTORY_FILE")

# Physical host FQDNs
export PRIMARY_FQDN=$(yq '.hosts.primary.fqdn' "$INVENTORY_FILE")
export REPLICA_FQDN=$(yq '.hosts.replica.fqdn' "$INVENTORY_FILE")
export VIP_FQDN=$(yq '.vip.fqdn' "$INVENTORY_FILE")

# SSH connection parameters
export SSH_USER=$(yq '.hosts.primary.ssh_user' "$INVENTORY_FILE")
export SSH_PORT=$(yq '.hosts.primary.ssh_port' "$INVENTORY_FILE")

# Network parameters
export PROD_SUBNET=$(yq '.networks.prod_subnet.cidr' "$INVENTORY_FILE")
export DOCKER_INTERNAL=$(yq '.networks.docker_internal.cidr' "$INVENTORY_FILE")

# Environment info
export ENV_DOMAIN_INTERNAL=$(yq '.domain_internal' "$INVENTORY_FILE")
export ENV_DOMAIN_EXTERNAL=$(yq '.domain_external' "$INVENTORY_FILE")
export ENV_NAME=$(yq '.environment' "$INVENTORY_FILE")

# Derived hostnames (can use for everything now, not raw IPs)
# Use these in all SSH commands, scripts, and configs
export DEPLOY_HOST="$PRIMARY_HOST"              # alias for backwards compatibility
export DEPLOY_USER="$SSH_USER"                  # alias for backwards compatibility
export STANDBY_HOST="$REPLICA_HOST"             # alias for backwards compatibility
export STANDBY_USER="$SSH_USER"                 # alias for backwards compatibility

# ============================================================================
# VALIDATION & DIAGNOSTICS
# ============================================================================

# Optional: Set DEBUG=1 to see all exported variables
if [ "${DEBUG:-0}" = "1" ]; then
    echo "[env.sh] Loaded topology from: $INVENTORY_FILE"
    echo "[env.sh] PRIMARY_HOST=$PRIMARY_HOST"
    echo "[env.sh] REPLICA_HOST=$REPLICA_HOST"
    echo "[env.sh] VIP=$VIP"
    echo "[env.sh] PRIMARY_FQDN=$PRIMARY_FQDN"
    echo "[env.sh] REPLICA_FQDN=$REPLICA_FQDN"
    echo "[env.sh] SSH_USER=$SSH_USER"
fi

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

# Get primary host SSH command
primary_ssh() {
    ssh -p "$SSH_PORT" "$SSH_USER@$PRIMARY_HOST" "$@"
}

# Get replica host SSH command
replica_ssh() {
    ssh -p "$SSH_PORT" "$SSH_USER@$REPLICA_HOST" "$@"
}

# Get primary host FQDN SSH command (resolves via DNS)
primary_fqdn_ssh() {
    ssh -p "$SSH_PORT" "$SSH_USER@$PRIMARY_FQDN" "$@"
}

# Get replica host FQDN SSH command (resolves via DNS)
replica_fqdn_ssh() {
    ssh -p "$SSH_PORT" "$SSH_USER@$REPLICA_FQDN" "$@"
}

# Export functions for use in scripts
export -f primary_ssh
export -f replica_ssh
export -f primary_fqdn_ssh
export -f replica_fqdn_ssh
