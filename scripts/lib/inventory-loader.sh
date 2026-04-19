#!/usr/bin/env bash
################################################################################
# inventory-loader.sh
# 
# Loads production topology from environments/production/hosts.yml
# Provides functions to query inventory without hardcoding IPs
#
# Usage:
#   source scripts/lib/inventory-loader.sh
#   inventory_load_production
#   get_host_ip primary      # → 192.168.168.31
#   get_host_fqdn primary    # → primary.prod.internal
#   get_vip_ip              # → 192.168.168.30
#   list_all_hosts          # → primary replica
#
################################################################################

set -euo pipefail

# =============================================================================
# ENVIRONMENT
# =============================================================================

INVENTORY_FILE="${PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/environments/production/hosts.yml"
INVENTORY_LOADED=false
declare -gA INVENTORY_CACHE

# =============================================================================
# MAIN FUNCTIONS
# =============================================================================

# Load production inventory from YAML file
inventory_load_production() {
    if [[ "$INVENTORY_LOADED" == "true" ]]; then
        return 0  # Already loaded
    fi

    if [[ ! -f "$INVENTORY_FILE" ]]; then
        >&2 echo "ERROR: Inventory file not found: $INVENTORY_FILE"
        return 1
    fi

    # Use Python to parse YAML (more reliable than yq)
    local python_script=$(cat <<'PYTHON_EOF'
import sys
import yaml

try:
    with open(sys.argv[1], 'r') as f:
        data = yaml.safe_load(f)
        
    # Export host information
    hosts = data.get('hosts', {})
    
    # Primary host
    if 'primary' in hosts:
        primary = hosts['primary']
        print(f"PRIMARY_IP={primary['ip']}")
        print(f"PRIMARY_FQDN={primary['fqdn']}")
        print(f"PRIMARY_SSH_USER={primary['ssh_user']}")
        print(f"PRIMARY_SSH_PORT={primary['ssh_port']}")
    
    # Replica host
    if 'replica' in hosts:
        replica = hosts['replica']
        print(f"REPLICA_IP={replica['ip']}")
        print(f"REPLICA_FQDN={replica['fqdn']}")
        print(f"REPLICA_SSH_USER={replica['ssh_user']}")
        print(f"REPLICA_SSH_PORT={replica['ssh_port']}")
    
    # VIP (virtual IP)
    if 'vip' in data:
        vip = data['vip']
        print(f"VIP_IP={vip['ip']}")
        print(f"VIP_FQDN={vip['fqdn']}")
        
    # Cluster info
    print(f"CLUSTER_NAME={data.get('cluster_name', 'code-server-enterprise')}")
    print(f"DOMAIN_INTERNAL={data.get('domain_internal', 'prod.internal')}")
    print(f"DOMAIN_EXTERNAL={data.get('domain_external', 'kushnir.cloud')}")
    
except Exception as e:
    print(f"ERROR parsing inventory: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF
    )

    # Execute Python to parse YAML
    if ! eval "python3" <<< "$python_script $INVENTORY_FILE" | while IFS= read -r line; do
        export "$line"
        INVENTORY_CACHE["${line%=*}"]="${line#*=}"
    done; then
        >&2 echo "ERROR: Failed to parse inventory file"
        return 1
    fi

    INVENTORY_LOADED=true
    return 0
}

# Get primary host IP
get_host_ip() {
    local host="${1:?Host name required (primary|replica)}"
    inventory_load_production
    
    case "$host" in
        primary) echo "$PRIMARY_IP" ;;
        replica) echo "$REPLICA_IP" ;;
        vip) echo "$VIP_IP" ;;
        *)
            >&2 echo "ERROR: Unknown host: $host"
            return 1
            ;;
    esac
}

# Get host FQDN
get_host_fqdn() {
    local host="${1:?Host name required (primary|replica)}"
    inventory_load_production
    
    case "$host" in
        primary) echo "$PRIMARY_FQDN" ;;
        replica) echo "$REPLICA_FQDN" ;;
        vip) echo "$VIP_FQDN" ;;
        *)
            >&2 echo "ERROR: Unknown host: $host"
            return 1
            ;;
    esac
}

# Get SSH user for host
get_ssh_user() {
    local host="${1:?Host name required (primary|replica)}"
    inventory_load_production
    
    case "$host" in
        primary) echo "$PRIMARY_SSH_USER" ;;
        replica) echo "$REPLICA_SSH_USER" ;;
        *)
            >&2 echo "ERROR: Unknown host: $host"
            return 1
            ;;
    esac
}

# Get SSH port for host
get_ssh_port() {
    local host="${1:?Host name required (primary|replica)}"
    inventory_load_production
    
    case "$host" in
        primary) echo "$PRIMARY_SSH_PORT" ;;
        replica) echo "$REPLICA_SSH_PORT" ;;
        *)
            >&2 echo "ERROR: Unknown host: $host"
            return 1
            ;;
    esac
}

# Get VIP (virtual IP)
get_vip_ip() {
    inventory_load_production
    echo "$VIP_IP"
}

# Get VIP FQDN
get_vip_fqdn() {
    inventory_load_production
    echo "$VIP_FQDN"
}

# Get cluster name
get_cluster_name() {
    inventory_load_production
    echo "$CLUSTER_NAME"
}

# Get internal domain
get_domain_internal() {
    inventory_load_production
    echo "$DOMAIN_INTERNAL"
}

# Get external domain
get_domain_external() {
    inventory_load_production
    echo "$DOMAIN_EXTERNAL"
}

# List all host names
list_all_hosts() {
    inventory_load_production
    echo "primary replica"
}

# Export variables for use in scripts
export_inventory_vars() {
    inventory_load_production
    
    export PRIMARY_IP PRIMARY_FQDN PRIMARY_SSH_USER PRIMARY_SSH_PORT
    export REPLICA_IP REPLICA_FQDN REPLICA_SSH_USER REPLICA_SSH_PORT
    export VIP_IP VIP_FQDN
    export CLUSTER_NAME DOMAIN_INTERNAL DOMAIN_EXTERNAL
}

# Build SSH command for host
get_ssh_command() {
    local host="${1:?Host name required (primary|replica)}"
    
    local ip=$(get_host_ip "$host")
    local user=$(get_ssh_user "$host")
    local port=$(get_ssh_port "$host")
    
    echo "ssh -p $port ${user}@${ip}"
}

# Build SSH to host with command
ssh_to_host() {
    local host="${1:?Host name required}"
    local cmd="${2:?Command required}"
    
    local ssh_cmd=$(get_ssh_command "$host")
    eval "$ssh_cmd \"$cmd\""
}

# Validate inventory (check connectivity)
validate_inventory() {
    inventory_load_production
    
    local all_healthy=true
    
    echo "Validating inventory..."
    
    for host in primary replica; do
        local ip=$(get_host_ip "$host")
        local fqdn=$(get_host_fqdn "$host")
        
        if ping -c 1 -W 2 "$ip" >/dev/null 2>&1; then
            echo "✓ $host ($ip) reachable"
        else
            echo "✗ $host ($ip) NOT reachable"
            all_healthy=false
        fi
    done
    
    # Validate VIP
    local vip=$(get_vip_ip)
    if ping -c 1 -W 2 "$vip" >/dev/null 2>&1; then
        echo "✓ VIP ($vip) reachable"
    else
        echo "✗ VIP ($vip) NOT reachable"
        all_healthy=false
    fi
    
    if [[ "$all_healthy" == "true" ]]; then
        return 0
    else
        return 1
    fi
}

# =============================================================================
# EXPORTS
# =============================================================================

export -f inventory_load_production
export -f get_host_ip get_host_fqdn get_ssh_user get_ssh_port
export -f get_vip_ip get_vip_fqdn
export -f get_cluster_name get_domain_internal get_domain_external
export -f list_all_hosts get_ssh_command ssh_to_host
export -f export_inventory_vars validate_inventory
