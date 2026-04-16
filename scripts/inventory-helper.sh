#!/bin/bash
# Infrastructure Inventory Helper Script
# Provides operational convenience for inventory queries and management
# Usage: scripts/inventory-helper.sh [command] [args]

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
INVENTORY_FILE="inventory/infrastructure.yaml"
INVENTORY_ENV="inventory/.inventory.env"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Check if inventory file exists
if [[ ! -f "$REPO_ROOT/$INVENTORY_FILE" ]]; then
    echo -e "${RED}ERROR: Inventory file not found: $INVENTORY_FILE${NC}"
    exit 1
fi

# Load inventory as YAML (requires yq or python)
load_inventory() {
    if command -v yq &> /dev/null; then
        yq eval '.' "$REPO_ROOT/$INVENTORY_FILE"
    elif command -v python3 &> /dev/null; then
        python3 << 'PYTHON'
import yaml
with open('$INVENTORY_FILE') as f:
    data = yaml.safe_load(f)
    print(yaml.dump(data, default_flow_style=False))
PYTHON
    else
        echo -e "${RED}ERROR: yq or python3 required to parse inventory${NC}"
        exit 1
    fi
}

# Command: List all hosts with their roles
cmd_list_hosts() {
    echo -e "${BLUE}=== Inventory Hosts ===${NC}"
    
    if command -v yq &> /dev/null; then
        yq eval '.hosts | keys[]' "$REPO_ROOT/$INVENTORY_FILE" | while read -r host; do
            ip=$(yq eval ".hosts.$host.ip_address" "$REPO_ROOT/$INVENTORY_FILE")
            roles=$(yq eval ".hosts.$host.roles | join(\", \")" "$REPO_ROOT/$INVENTORY_FILE")
            status=$(yq eval ".hosts.$host.status" "$REPO_ROOT/$INVENTORY_FILE")
            deployed=$(yq eval ".hosts.$host.deployed" "$REPO_ROOT/$INVENTORY_FILE")
            
            if [[ "$deployed" == "true" ]]; then
                color=$GREEN
            else
                color=$YELLOW
            fi
            
            printf "${color}%-15s${NC} %-20s %-10s %s\n" "$host" "$ip" "$status" "$roles"
        done
    else
        echo -e "${RED}ERROR: yq required for this command${NC}"
        exit 1
    fi
}

# Command: List all services with their ports
cmd_list_services() {
    echo -e "${BLUE}=== Inventory Services ===${NC}"
    
    if command -v yq &> /dev/null; then
        yq eval '.services | keys[]' "$REPO_ROOT/$INVENTORY_FILE" | while read -r service; do
            port=$(yq eval ".services.$service.port // \"N/A\"" "$REPO_ROOT/$INVENTORY_FILE")
            version=$(yq eval ".services.$service.version // \"N/A\"" "$REPO_ROOT/$INVENTORY_FILE")
            desc=$(yq eval ".services.$service.description // \"\"" "$REPO_ROOT/$INVENTORY_FILE")
            
            printf "%-20s %-8s %-10s %s\n" "$service" "$port" "$version" "$desc"
        done
    else
        echo -e "${RED}ERROR: yq required for this command${NC}"
        exit 1
    fi
}

# Command: List all IP addresses
cmd_list_ips() {
    echo -e "${BLUE}=== Inventory IP Addresses ===${NC}"
    
    if command -v yq &> /dev/null; then
        yq eval '.hosts | keys[]' "$REPO_ROOT/$INVENTORY_FILE" | while read -r host; do
            ip=$(yq eval ".hosts.$host.ip_address" "$REPO_ROOT/$INVENTORY_FILE")
            hostname=$(yq eval ".hosts.$host.hostname" "$REPO_ROOT/$INVENTORY_FILE")
            printf "%-20s %-20s %s\n" "$host" "$ip" "$hostname"
        done
        
        echo ""
        echo -e "${BLUE}Virtual IPs:${NC}"
        vip=$(yq eval '.network.virtual_ip' "$REPO_ROOT/$INVENTORY_FILE")
        vip_hostname=$(yq eval '.network.virtual_ip_hostname' "$REPO_ROOT/$INVENTORY_FILE")
        printf "%-20s %-20s %s\n" "VIP" "$vip" "$vip_hostname"
    else
        echo -e "${RED}ERROR: yq required for this command${NC}"
        exit 1
    fi
}

# Command: Get specific host details
cmd_get_host() {
    local host=$1
    echo -e "${BLUE}=== Host: $host ===${NC}"
    
    if command -v yq &> /dev/null; then
        yq eval ".hosts.$host" "$REPO_ROOT/$INVENTORY_FILE"
    else
        echo -e "${RED}ERROR: yq required for this command${NC}"
        exit 1
    fi
}

# Command: SSH to a host
cmd_ssh_host() {
    local host=$1
    
    if command -v yq &> /dev/null; then
        ip=$(yq eval ".hosts.$host.ip_address" "$REPO_ROOT/$INVENTORY_FILE")
        user=$(yq eval ".hosts.$host.ssh_user" "$REPO_ROOT/$INVENTORY_FILE")
        port=$(yq eval ".hosts.$host.ssh_port // 22" "$REPO_ROOT/$INVENTORY_FILE")
        
        if [[ -z "$ip" ]]; then
            echo -e "${RED}ERROR: Host '$host' not found${NC}"
            exit 1
        fi
        
        echo -e "${GREEN}Connecting to $host ($ip)...${NC}"
        ssh -p "$port" "$user@$ip"
    else
        echo -e "${RED}ERROR: yq required for this command${NC}"
        exit 1
    fi
}

# Command: Export environment variables
cmd_export_env() {
    echo -e "${BLUE}=== Exporting Environment Variables ===${NC}"
    
    if [[ ! -f "$REPO_ROOT/$INVENTORY_ENV" ]]; then
        echo -e "${YELLOW}INFO: Creating inventory environment file...${NC}"
        # This will be generated by Terraform, for now just show how to source it
        echo "source $INVENTORY_ENV"
        return
    fi
    
    # Source and display the environment
    set +u  # Allow unset variables for sourcing
    # shellcheck source=/dev/null
    source "$REPO_ROOT/$INVENTORY_ENV"
    set -u
    
    echo "Environment variables loaded from $INVENTORY_ENV"
    echo ""
    echo "Key variables:"
    echo "  PRIMARY_HOST=$PRIMARY_HOST"
    echo "  REPLICA_HOST=$REPLICA_HOST"
    echo "  VIRTUAL_IP=$VIRTUAL_IP"
    echo "  STORAGE_IP=$STORAGE_IP"
}

# Command: Validate inventory format
cmd_validate() {
    echo -e "${BLUE}=== Validating Inventory Format ===${NC}"
    
    if command -v yq &> /dev/null; then
        if yq eval '.' "$REPO_ROOT/$INVENTORY_FILE" > /dev/null 2>&1; then
            echo -e "${GREEN}✓ YAML syntax valid${NC}"
        else
            echo -e "${RED}✗ YAML syntax invalid${NC}"
            exit 1
        fi
        
        # Check required sections
        for section in hosts network services metadata; do
            if yq eval ".$section" "$REPO_ROOT/$INVENTORY_FILE" > /dev/null 2>&1; then
                echo -e "${GREEN}✓ Section '$section' present${NC}"
            else
                echo -e "${RED}✗ Section '$section' missing${NC}"
                exit 1
            fi
        done
        
        # Check required hosts
        for host in primary replica storage; do
            if yq eval ".hosts.$host" "$REPO_ROOT/$INVENTORY_FILE" > /dev/null 2>&1; then
                echo -e "${GREEN}✓ Host '$host' configured${NC}"
            else
                echo -e "${RED}✗ Host '$host' missing${NC}"
                exit 1
            fi
        done
        
        echo -e "${GREEN}All validation checks passed!${NC}"
    else
        echo -e "${RED}ERROR: yq required for validation${NC}"
        exit 1
    fi
}

# Command: Show help
cmd_help() {
    cat << 'EOF'
Infrastructure Inventory Helper Script

USAGE:
    scripts/inventory-helper.sh [command] [args]

COMMANDS:
    list-hosts          List all hosts with roles and status
    list-services       List all services with ports and versions
    list-ips            List all IP addresses (hosts + VIP)
    get-host <name>     Get detailed information about a specific host
    ssh <name>          SSH to a specific host
    export-env          Export inventory as environment variables
    validate            Validate inventory YAML format
    help                Show this help message

EXAMPLES:
    # List all hosts
    scripts/inventory-helper.sh list-hosts
    
    # Get primary host details
    scripts/inventory-helper.sh get-host primary
    
    # SSH to replica
    scripts/inventory-helper.sh ssh replica
    
    # Load environment variables
    source <(scripts/inventory-helper.sh export-env)

DEPENDENCIES:
    - yq (YAML query tool): https://github.com/mikefarah/yq
      Install: brew install yq  (macOS) or apt install yq (Ubuntu)
    - bash 4.0+

INVENTORY FILE:
    inventory/infrastructure.yaml

EOF
}

# Main command dispatcher
main() {
    case "${1:-help}" in
        list-hosts)
            cmd_list_hosts
            ;;
        list-services)
            cmd_list_services
            ;;
        list-ips)
            cmd_list_ips
            ;;
        get-host)
            if [[ -z "${2:-}" ]]; then
                echo -e "${RED}ERROR: Host name required${NC}"
                exit 1
            fi
            cmd_get_host "$2"
            ;;
        ssh)
            if [[ -z "${2:-}" ]]; then
                echo -e "${RED}ERROR: Host name required${NC}"
                exit 1
            fi
            cmd_ssh_host "$2"
            ;;
        export-env)
            cmd_export_env
            ;;
        validate)
            cmd_validate
            ;;
        help|--help|-h)
            cmd_help
            ;;
        *)
            echo -e "${RED}ERROR: Unknown command: $1${NC}"
            cmd_help
            exit 1
            ;;
    esac
}

# Run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
