#!/bin/bash
# Infrastructure IP Configuration Variables
# Central source of truth for all infrastructure IPs
# Source this file: source scripts/_common/ip-config.sh
# All scripts should use these variables instead of hardcoding IPs

# ═══════════════════════════════════════════════════════════════════════
# INFRASTRUCTURE HOSTS
# ═══════════════════════════════════════════════════════════════════════

# Primary production host
export PRIMARY_HOST_IP="${PRIMARY_HOST_IP:-192.168.168.31}"
export PRIMARY_HOST_NAME="code-server-primary"
export PRIMARY_SSH_USER="${PRIMARY_SSH_USER:-akushnir}"
export PRIMARY_SSH_PORT="${PRIMARY_SSH_PORT:-22}"

# Replica/standby host (for HA)
export REPLICA_HOST_IP="${REPLICA_HOST_IP:-192.168.168.42}"
export REPLICA_HOST_NAME="code-server-replica"
export REPLICA_SSH_USER="${REPLICA_SSH_USER:-akushnir}"
export REPLICA_SSH_PORT="${REPLICA_SSH_PORT:-22}"

# Virtual IP for transparent failover (VRRP/Keepalived)
export VIRTUAL_IP="${VIRTUAL_IP:-192.168.168.40}"
export VIRTUAL_IP_HOSTNAME="${VIRTUAL_IP_HOSTNAME:-code-server.internal}"

# Load balancer (HAProxy/Nginx)
export LOAD_BALANCER_IP="${LOAD_BALANCER_IP:-192.168.168.40}"
export LOAD_BALANCER_NAME="code-server-lb"

# NAS/Storage (for backup and shared volumes)
export STORAGE_IP="${STORAGE_IP:-192.168.168.56}"
export STORAGE_NAS_EXPORT="${STORAGE_NAS_EXPORT:-/export/backups}"
export STORAGE_NFS_VERSION="${STORAGE_NFS_VERSION:-4}"

# ═══════════════════════════════════════════════════════════════════════
# NETWORK CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════

# Network subnet
export NETWORK_SUBNET="${NETWORK_SUBNET:-192.168.168.0/24}"
export NETWORK_GATEWAY="${NETWORK_GATEWAY:-192.168.168.1}"
export NETWORK_VLAN="${NETWORK_VLAN:-100}"
export NETWORK_MTU="${NETWORK_MTU:-1500}"

# ═══════════════════════════════════════════════════════════════════════
# DNS CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════

# Local DNS (CoreDNS)
export DNS_SERVER_IP="${DNS_SERVER_IP:-192.168.168.31}"
export DNS_PORT="${DNS_PORT:-53}"

# Primary domain
export APEX_DOMAIN="${APEX_DOMAIN:-example.com}"
export PRIMARY_DOMAIN="${PRIMARY_DOMAIN:-code-server.example.com}"
export REPLICA_DOMAIN="${REPLICA_DOMAIN:-replica.code-server.example.com}"

# ═══════════════════════════════════════════════════════════════════════
# SERVICE PORTS
# ═══════════════════════════════════════════════════════════════════════

# Code-server
export CODESERVER_PORT="${CODESERVER_PORT:-8080}"
export CODESERVER_TLS_PORT="${CODESERVER_TLS_PORT:-8443}"

# Caddy reverse proxy
export CADDY_HTTP_PORT="${CADDY_HTTP_PORT:-80}"
export CADDY_HTTPS_PORT="${CADDY_HTTPS_PORT:-443}"

# OAuth2-proxy
export OAUTH2_PORT="${OAUTH2_PORT:-4180}"
export OAUTH2_PORT_LOKI="${OAUTH2_PORT_LOKI:-4181}"

# Prometheus
export PROMETHEUS_PORT="${PROMETHEUS_PORT:-9090}"

# Grafana
export GRAFANA_PORT="${GRAFANA_PORT:-3000}"

# AlertManager
export ALERTMANAGER_PORT="${ALERTMANAGER_PORT:-9093}"

# Jaeger
export JAEGER_PORT="${JAEGER_PORT:-16686}"

# Kong API Gateway
export KONG_PORT="${KONG_PORT:-8000}"
export KONG_ADMIN_PORT="${KONG_ADMIN_PORT:-8001}"

# PostgreSQL
export POSTGRES_PORT="${POSTGRES_PORT:-5432}"

# Redis
export REDIS_PORT="${REDIS_PORT:-6379}"

# Loki
export LOKI_PORT="${LOKI_PORT:-3100}"

# OLLAMA
export OLLAMA_PORT="${OLLAMA_PORT:-11434}"

# ═══════════════════════════════════════════════════════════════════════
# DEPLOYMENT TARGETS
# ═══════════════════════════════════════════════════════════════════════

# Default deployment target (primary or replica)
export DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET:-primary}"
export DEPLOYMENT_HOST="${DEPLOYMENT_HOST:-${PRIMARY_HOST_IP}}"
export DEPLOYMENT_USER="${DEPLOYMENT_USER:-${PRIMARY_SSH_USER}}"

# Remote Terraform Docker provider endpoint
export TERRAFORM_DOCKER_HOST="${TERRAFORM_DOCKER_HOST:-ssh://${DEPLOYMENT_USER}@${DEPLOYMENT_HOST}}"

# ═══════════════════════════════════════════════════════════════════════
# HELPER FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════

# Get host IP by name
get_host_ip() {
    local host_name=$1
    case "$host_name" in
        primary|p|31)
            echo "$PRIMARY_HOST_IP"
            ;;
        replica|r|42)
            echo "$REPLICA_HOST_IP"
            ;;
        lb|load-balancer|40)
            echo "$LOAD_BALANCER_IP"
            ;;
        storage|nas|56)
            echo "$STORAGE_IP"
            ;;
        vip|virtual)
            echo "$VIRTUAL_IP"
            ;;
        *)
            echo "ERROR: Unknown host: $host_name" >&2
            return 1
            ;;
    esac
}

# Get host name by IP
get_host_name() {
    local ip=$1
    case "$ip" in
        "$PRIMARY_HOST_IP")
            echo "$PRIMARY_HOST_NAME"
            ;;
        "$REPLICA_HOST_IP")
            echo "$REPLICA_HOST_NAME"
            ;;
        "$LOAD_BALANCER_IP")
            echo "$LOAD_BALANCER_NAME"
            ;;
        "$STORAGE_IP")
            echo "nas-56"
            ;;
        "$VIRTUAL_IP")
            echo "$VIRTUAL_IP_HOSTNAME"
            ;;
        *)
            echo "UNKNOWN"
            ;;
    esac
}

# SSH to host
ssh_to_host() {
    local target=$1
    shift  # Remove first argument
    local cmd="${@}"  # Remaining arguments
    
    local ip=$(get_host_ip "$target")
    [[ $? -eq 0 ]] || return 1
    
    local user="${DEPLOYMENT_USER}"
    [[ "$target" == "primary" || "$target" == "p" || "$target" == "31" ]] && user="${PRIMARY_SSH_USER}"
    [[ "$target" == "replica" || "$target" == "r" || "$target" == "42" ]] && user="${REPLICA_SSH_USER}"
    
    if [[ -z "$cmd" ]]; then
        ssh -u "$user" "$ip"
    else
        ssh "$user@$ip" "$cmd"
    fi
}

# Validate IP format
is_valid_ip() {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        return 0
    else
        return 1
    fi
}

# Validate all critical IPs are reachable
validate_hosts() {
    echo "Validating infrastructure hosts..."
    
    local hosts=("$PRIMARY_HOST_IP" "$REPLICA_HOST_IP" "$LOAD_BALANCER_IP" "$STORAGE_IP")
    local names=("Primary" "Replica" "Load Balancer" "Storage")
    
    for i in "${!hosts[@]}"; do
        local ip="${hosts[$i]}"
        local name="${names[$i]}"
        
        if ping -c 1 -W 2 "$ip" >/dev/null 2>&1; then
            echo "✅ $name ($ip): REACHABLE"
        else
            echo "❌ $name ($ip): UNREACHABLE"
            return 1
        fi
    done
    
    echo "All hosts validated successfully"
    return 0
}

# Export functions for subshells
export -f get_host_ip
export -f get_host_name
export -f ssh_to_host
export -f is_valid_ip
export -f validate_hosts

# ═══════════════════════════════════════════════════════════════════════
# INITIALIZATION
# ═══════════════════════════════════════════════════════════════════════

# Validate IP format on source
if ! is_valid_ip "$PRIMARY_HOST_IP"; then
    echo "ERROR: Invalid PRIMARY_HOST_IP format: $PRIMARY_HOST_IP" >&2
    return 1
fi

if ! is_valid_ip "$REPLICA_HOST_IP"; then
    echo "ERROR: Invalid REPLICA_HOST_IP format: $REPLICA_HOST_IP" >&2
    return 1
fi

# Source inventory environment if available
if [[ -f "${SCRIPT_DIR}/../inventory/.inventory.env" ]]; then
    source "${SCRIPT_DIR}/../inventory/.inventory.env"
fi
