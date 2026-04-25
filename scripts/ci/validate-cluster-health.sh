#!/bin/bash
# @file scripts/ci/validate-cluster-health.sh
# @description Comprehensive cluster health validation script
# @governance GOV-002: Environment-driven configuration, immutable, idempotent
# @usage: bash scripts/ci/validate-cluster-health.sh

set -euo pipefail

##============================================================================
## Color codes for output
##============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

##============================================================================
## Configuration (Environment-driven)
##============================================================================
PRIMARY_HOST="${PRIMARY_HOST:-192.168.168.31}"
REPLICA_HOST="${REPLICA_HOST:-192.168.168.42}"
NAS_HOST="${NAS_HOST:-192.168.168.56}"
SSH_USER="${SSH_USER:-akushnir}"
APEX_DOMAIN="${APEX_DOMAIN:-kushnir.cloud}"
VERBOSE="${VERBOSE:-false}"

##============================================================================
## Logging functions
##============================================================================
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" >&2
}

log_ok() {
    echo -e "${GREEN}[OK]${NC}   $*" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC}  $*" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_section() {
    echo -e "\n${BLUE}════ $* ════${NC}" >&2
}

##============================================================================
## Validation functions
##============================================================================

check_ssh_connectivity() {
    local host=$1
    local label=$2
    
    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$SSH_USER@$host" "echo 'SSH OK'" &>/dev/null; then
        log_ok "SSH connectivity to $label ($host): WORKING"
        return 0
    else
        log_error "SSH connectivity to $label ($host): FAILED"
        return 1
    fi
}

check_docker_status() {
    local host=$1
    local label=$2
    
    if ssh -o ConnectTimeout=5 "$SSH_USER@$host" "command -v docker" &>/dev/null; then
        log_ok "Docker on $label ($host): INSTALLED"
        return 0
    else
        log_warn "Docker on $label ($host): NOT INSTALLED"
        return 1
    fi
}

check_docker_services() {
    local host=$1
    local label=$2
    
    local service_count=$(ssh -o ConnectTimeout=5 "$SSH_USER@$host" "docker ps --no-trunc --no-header 2>/dev/null | wc -l" 2>/dev/null)
    
    if [ "$service_count" -gt 0 ]; then
        log_ok "Docker services on $label ($host): $service_count running"
        
        if [ "$VERBOSE" = "true" ]; then
            ssh "$SSH_USER@$host" "docker ps --format 'table {{.Names}}\t{{.Status}}' 2>/dev/null" | sed 's/^/  /' >&2
        fi
        
        return 0
    else
        log_warn "Docker services on $label ($host): NONE RUNNING"
        return 1
    fi
}

check_nfs_mounts() {
    local host=$1
    local label=$2
    
    local mount_count=$(ssh -o ConnectTimeout=5 "$SSH_USER@$host" "mount | grep -c nfs || echo 0" 2>/dev/null)
    
    if [ "$mount_count" -gt 0 ]; then
        log_ok "NFS mounts on $label ($host): $mount_count mounted"
        
        if [ "$VERBOSE" = "true" ]; then
            ssh "$SSH_USER@$host" "mount | grep nfs" | sed 's/^/  /' >&2
        fi
        
        return 0
    else
        log_warn "NFS mounts on $label ($host): NONE"
        return 1
    fi
}

check_kubernetes_readiness() {
    local host=$1
    local label=$2
    
    if ssh "$SSH_USER@$host" "which k3s &>/dev/null" 2>/dev/null; then
        log_ok "Kubernetes on $label ($host): k3s binary installed"
        return 0
    else
        log_info "Kubernetes on $label ($host): NOT YET INSTALLED (expected pre-provisioning)"
        return 0
    fi
}

check_disk_space() {
    local host=$1
    local label=$2
    
    local disk_usage=$(ssh "$SSH_USER@$host" "df -h / | tail -1 | awk '{print \$5}' | sed 's/%//' 2>/dev/null")
    
    if [ -n "$disk_usage" ]; then
        if [ "$disk_usage" -lt 80 ]; then
            log_ok "Disk usage on $label ($host): $disk_usage%"
            return 0
        elif [ "$disk_usage" -lt 90 ]; then
            log_warn "Disk usage on $label ($host): $disk_usage% (approaching limit)"
            return 0
        else
            log_error "Disk usage on $label ($host): $disk_usage% (CRITICAL)"
            return 1
        fi
    else
        log_warn "Disk usage on $label ($host): Could not determine"
        return 1
    fi
}

check_memory_availability() {
    local host=$1
    local label=$2
    
    local mem_available=$(ssh "$SSH_USER@$host" "free -h | grep Mem | awk '{print \$7}' 2>/dev/null")
    
    if [ -n "$mem_available" ]; then
        log_ok "Memory available on $label ($host): $mem_available"
        return 0
    else
        log_warn "Memory available on $label ($host): Could not determine"
        return 1
    fi
}

check_network_connectivity() {
    local source=$1
    local target=$2
    local label=$3
    
    if ssh "$SSH_USER@$source" "ping -c 1 -W 2 $target &>/dev/null" 2>/dev/null; then
        log_ok "Network $label ($source → $target): REACHABLE"
        return 0
    else
        log_error "Network $label ($source → $target): UNREACHABLE"
        return 1
    fi
}

##============================================================================
## Main validation flow
##============================================================================

main() {
    local failed_checks=0
    local total_checks=0
    
    log_section "Cluster Health Validation"
    log_info "Primary Host: $PRIMARY_HOST"
    log_info "Replica Host: $REPLICA_HOST"
    log_info "NAS Host: $NAS_HOST"
    
    # Primary Node Checks
    log_section "Primary Node ($PRIMARY_HOST)"
    
    check_ssh_connectivity "$PRIMARY_HOST" "Primary" || ((failed_checks++))
    ((total_checks++))
    
    check_docker_status "$PRIMARY_HOST" "Primary" || ((failed_checks++))
    ((total_checks++))
    
    check_docker_services "$PRIMARY_HOST" "Primary" || ((failed_checks++))
    ((total_checks++))
    
    check_nfs_mounts "$PRIMARY_HOST" "Primary" || ((failed_checks++))
    ((total_checks++))
    
    check_kubernetes_readiness "$PRIMARY_HOST" "Primary"
    ((total_checks++))
    
    check_disk_space "$PRIMARY_HOST" "Primary" || ((failed_checks++))
    ((total_checks++))
    
    check_memory_availability "$PRIMARY_HOST" "Primary"
    ((total_checks++))
    
    # Replica Node Checks
    log_section "Replica Node ($REPLICA_HOST)"
    
    check_ssh_connectivity "$REPLICA_HOST" "Replica" || ((failed_checks++))
    ((total_checks++))
    
    check_docker_status "$REPLICA_HOST" "Replica" || ((failed_checks++))
    ((total_checks++))
    
    check_docker_services "$REPLICA_HOST" "Replica" || ((failed_checks++))
    ((total_checks++))
    
    check_nfs_mounts "$REPLICA_HOST" "Replica" || ((failed_checks++))
    ((total_checks++))
    
    check_kubernetes_readiness "$REPLICA_HOST" "Replica"
    ((total_checks++))
    
    check_disk_space "$REPLICA_HOST" "Replica" || ((failed_checks++))
    ((total_checks++))
    
    check_memory_availability "$REPLICA_HOST" "Replica"
    ((total_checks++))
    
    # Network Connectivity
    log_section "Network Connectivity"
    
    check_network_connectivity "$PRIMARY_HOST" "$REPLICA_HOST" "Primary→Replica"
    ((total_checks++))
    
    check_network_connectivity "$REPLICA_HOST" "$PRIMARY_HOST" "Replica→Primary"
    ((total_checks++))
    
    check_network_connectivity "$PRIMARY_HOST" "$NAS_HOST" "Primary→NAS"
    ((total_checks++))
    
    check_network_connectivity "$REPLICA_HOST" "$NAS_HOST" "Replica→NAS"
    ((total_checks++))
    
    # Summary
    log_section "Validation Summary"
    local passed=$((total_checks - failed_checks))
    
    if [ $failed_checks -eq 0 ]; then
        log_ok "All $total_checks checks PASSED ✓"
        echo -e "\n${GREEN}════ CLUSTER HEALTH: GOOD ════${NC}\n" >&2
        return 0
    else
        log_warn "$passed/$total_checks checks passed, $failed_checks failed"
        echo -e "\n${YELLOW}════ CLUSTER HEALTH: DEGRADED ════${NC}\n" >&2
        return 1
    fi
}

##============================================================================
## Script entry point
##============================================================================

if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    main "$@"
fi
