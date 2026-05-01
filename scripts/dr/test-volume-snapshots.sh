#!/bin/bash
###############################################################################
# Phase 5 Week 3: Disaster Recovery Testing - Volume Snapshots
#
# Tests volume snapshot creation and recovery procedures
#
# Usage:
#   bash scripts/dr/test-volume-snapshots.sh create
#   bash scripts/dr/test-volume-snapshots.sh verify
#   bash scripts/dr/test-volume-snapshots.sh restore
###############################################################################

set -euo pipefail

# Source canonical bootstrap
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

# Error handling traps
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Cleanup on exit..."; cleanup_on_exit || true' EXIT

# Configuration
DOCKER_COMPOSE_FILE="$PROJECT_ROOT/docker-compose.yml"
SNAPSHOT_DIR="$PROJECT_ROOT/artifacts/volume-snapshots"
DOCKER_VOLUME_PREFIX="code-server"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

cleanup_on_exit() {
    log_info "Cleanup complete"
}

# Get Docker volumes used by containers
get_docker_volumes() {
    log_info "Discovering Docker volumes..."
    
    docker volume ls --filter "label=com.docker.compose.project" -q || true
}

# Create volume snapshot
create_snapshot() {
    log_info "Creating volume snapshots..."
    mkdir -p "$SNAPSHOT_DIR"
    
    local volumes=($(get_docker_volumes))
    local snapshot_count=0
    
    for volume in "${volumes[@]}"; do
        log_info "Snapshotting volume: $volume"
        
        # Get volume mount point
        local mount_point=$(docker volume inspect "$volume" --format '{{.Mountpoint}}')
        
        if [ -z "$mount_point" ]; then
            log_warning "Could not determine mount point for $volume"
            continue
        fi
        
        # Create snapshot tarball
        local snapshot_file="$SNAPSHOT_DIR/snapshot-${volume}-$(date +%Y%m%d-%H%M%S).tar.gz"
        
        if sudo tar -czf "$snapshot_file" -C "$(dirname $mount_point)" "$(basename $mount_point)" 2>/dev/null; then
            local size=$(du -h "$snapshot_file" | cut -f1)
            log_success "  Snapshot created: $snapshot_file ($size)"
            snapshot_count+=1
        else
            log_warning "  Failed to create snapshot for $volume"
        fi
    done
    
    log_success "Total snapshots created: $snapshot_count"
}

# Verify snapshot integrity
verify_snapshots() {
    log_info "Verifying volume snapshot integrity..."
    
    if [ ! -d "$SNAPSHOT_DIR" ]; then
        log_error "Snapshot directory not found: $SNAPSHOT_DIR"
        return 1
    fi
    
    local snapshot_count=0
    local valid_count=0
    
    while IFS= read -r snapshot; do
        snapshot_count+=1
        
        log_info "Verifying: $(basename $snapshot)"
        
        if tar -tzf "$snapshot" > /dev/null 2>&1; then
            log_success "  ✅ Snapshot integrity verified"
            valid_count+=1
        else
            log_error "  ❌ Snapshot is corrupted"
        fi
    done < <(find "$SNAPSHOT_DIR" -name "snapshot-*.tar.gz" -type f)
    
    log_success "Verification complete: $valid_count/$snapshot_count snapshots valid"
    
    if [ $valid_count -eq $snapshot_count ] && [ $snapshot_count -gt 0 ]; then
        return 0
    else
        return 1
    fi
}

# Restore from snapshot
restore_snapshot() {
    local snapshot_file="${1:-}"
    
    if [ -z "$snapshot_file" ]; then
        # Use latest snapshot
        snapshot_file=$(find "$SNAPSHOT_DIR" -name "snapshot-*.tar.gz" -type f -printf '%T@ %p\n' | sort -rn | head -1 | cut -d' ' -f2-)
    fi
    
    if [ -z "$snapshot_file" ] || [ ! -f "$snapshot_file" ]; then
        log_error "Snapshot file not found"
        return 1
    fi
    
    log_warning "Restoring from snapshot: $(basename $snapshot_file)"
    log_warning "This will overwrite existing volume data"
    
    # Parse volume name from snapshot filename
    local volume_name=$(basename "$snapshot_file" | sed -E 's/snapshot-(.+)-[0-9]{8}-[0-9]{6}\.tar\.gz/\1/')
    
    log_info "Target volume: $volume_name"
    
    # Restore snapshot
    if sudo tar -xzf "$snapshot_file" -C "/var/lib/docker/volumes" 2>/dev/null; then
        log_success "Volume restored successfully"
    else
        log_error "Volume restore failed"
        return 1
    fi
}

# Calculate volume snapshot metrics
calculate_metrics() {
    log_info "Calculating volume snapshot metrics..."
    
    if [ ! -d "$SNAPSHOT_DIR" ]; then
        log_error "Snapshot directory not found"
        return 1
    fi
    
    log_info "Snapshot Statistics:"
    
    local total_size=$(du -sh "$SNAPSHOT_DIR" | cut -f1)
    echo "  Total Snapshot Size: $total_size"
    
    local oldest_snapshot=$(find "$SNAPSHOT_DIR" -name "snapshot-*.tar.gz" -type f -printf '%T+ %p\n' | sort | head -1 | cut -d' ' -f2-)
    if [ -n "$oldest_snapshot" ]; then
        local oldest_time=$(stat -c %y "$oldest_snapshot" | cut -d' ' -f1-2)
        echo "  Oldest Snapshot: $oldest_time"
    fi
    
    local newest_snapshot=$(find "$SNAPSHOT_DIR" -name "snapshot-*.tar.gz" -type f -printf '%T+ %p\n' | sort -r | head -1 | cut -d' ' -f2-)
    if [ -n "$newest_snapshot" ]; then
        local newest_time=$(stat -c %y "$newest_snapshot" | cut -d' ' -f1-2)
        echo "  Newest Snapshot: $newest_time"
    fi
    
    local snapshot_count=$(find "$SNAPSHOT_DIR" -name "snapshot-*.tar.gz" -type f | wc -l)
    echo "  Total Snapshots: $snapshot_count"
}

# List snapshots
list_snapshots() {
    log_info "Available volume snapshots:"
    
    if [ ! -d "$SNAPSHOT_DIR" ]; then
        log_warning "No snapshots directory found"
        return 0
    fi
    
    local count=0
    while IFS= read -r snapshot; do
        local size=$(du -h "$snapshot" | cut -f1)
        local timestamp=$(stat -c %y "$snapshot" | cut -d' ' -f1-2)
        echo "  [$((++count))] $(basename $snapshot) - $size - $timestamp"
    done < <(find "$SNAPSHOT_DIR" -name "snapshot-*.tar.gz" -type f -printf '%T@ %p\n' | sort -rn | cut -d' ' -f2-)
    
    if [ $count -eq 0 ]; then
        log_warning "No snapshot files found"
    else
        log_success "Total snapshots: $count"
    fi
}

# Main execution
main() {
    local scenario="${1:-help}"
    
    log_info "Phase 5 Week 3: Disaster Recovery - Volume Snapshots"
    
    case "$scenario" in
        create)
            create_snapshot
            ;;
        verify)
            verify_snapshots
            ;;
        restore)
            restore_snapshot "${2:-}"
            ;;
        metrics)
            calculate_metrics
            ;;
        list)
            list_snapshots
            ;;
        *)
            log_error "Invalid scenario: $scenario"
            echo "Usage:"
            echo "  $0 create            - Create volume snapshots"
            echo "  $0 verify            - Verify snapshot integrity"
            echo "  $0 restore [file]    - Restore from snapshot"
            echo "  $0 metrics           - Show snapshot metrics"
            echo "  $0 list              - List available snapshots"
            exit 1
            ;;
    esac
}

main "$@"
