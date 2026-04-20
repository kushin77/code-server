#!/usr/bin/env bash
# @file        scripts/ops/docker-storage-hygiene.sh
# @module      ops/storage-management
# @description Safely detect and remove orphaned Docker objects and stale artifacts

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPO_ROOT="${SCRIPT_DIR}"
REPORT_FILE="${REPO_ROOT}/artifacts/triage/docker-storage-hygiene-report.log"
METRICS_FILE="${REPO_ROOT}/artifacts/metrics/docker-storage-metrics.json"

mkdir -p "$(dirname "$REPORT_FILE")" "$(dirname "$METRICS_FILE")"

# Cleanup modes
DRY_RUN="${DRY_RUN:-1}"
APPLY_CLEANUP="${APPLY_CLEANUP:-0}"
VERBOSE="${VERBOSE:-0}"

# Retention policy (in days)
IMAGE_RETENTION_DAYS="${IMAGE_RETENTION_DAYS:-7}"
CONTAINER_RETENTION_DAYS="${CONTAINER_RETENTION_DAYS:-3}"
VOLUME_RETENTION_DAYS="${VOLUME_RETENTION_DAYS:-7}"
LOG_RETENTION_DAYS="${LOG_RETENTION_DAYS:-30}"
BUILD_CACHE_RETENTION_DAYS="${BUILD_CACHE_RETENTION_DAYS:-14}"

# Protected assets (never delete)
PROTECTED_CONTAINERS="${PROTECTED_CONTAINERS:-code-server,caddy,oauth2-proxy,postgres,redis,prometheus,grafana}"
PROTECTED_IMAGES="${PROTECTED_IMAGES:-code-server,caddy,oauth2-proxy,postgres,redis,prometheus,grafana,ubuntu,alpine}"
PROTECTED_VOLUMES="${PROTECTED_VOLUMES:-postgres-data,redis-data}"

# Metrics
TOTAL_IMAGES_SCANNED=0
ORPHANED_IMAGES_FOUND=0
ORPHANED_CONTAINERS_FOUND=0
ORPHANED_VOLUMES_FOUND=0
SPACE_RECLAIMED_MB=0

log_action() {
    local msg="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $msg" | tee -a "$REPORT_FILE"
}

is_protected() {
    local name="$1"
    local protected_list="$2"
    
    IFS=',' read -ra protected_array <<< "$protected_list"
    for protected in "${protected_array[@]}"; do
        if [[ "$name" == "$protected" ]] || [[ "$name" == *"$protected"* ]]; then
            return 0
        fi
    done
    return 1
}

cleanup_images() {
    log_action "Scanning for orphaned/stale Docker images..."
    
    local cutoff_date=$(date -d "$IMAGE_RETENTION_DAYS days ago" +%s 2>/dev/null || echo "0")
    
    docker images --format "table {{.ID}}\t{{.Repository}}\t{{.Tag}}\t{{.CreatedAt}}\t{{.Size}}" | tail -n +2 | while read -r image_id repo tag created_at size; do
        ((TOTAL_IMAGES_SCANNED++))
        
        # Skip protected images
        if is_protected "$repo" "$PROTECTED_IMAGES"; then
            if [ "$VERBOSE" -eq 1 ]; then
                log_action "  [PROTECTED] $repo:$tag (ID: ${image_id:0:12})"
            fi
            return 0
        fi
        
        # Check if image is dangling (untagged)
        if [[ "$repo" == "<none>" ]]; then
            log_action "  [ORPHANED] Dangling image: ${image_id:0:12} ($size)"
            ((ORPHANED_IMAGES_FOUND++))
            
            # Extract size in MB
            local size_mb=$(echo "$size" | grep -oE '[0-9]+' | head -1)
            if [[ ! -z "$size_mb" ]]; then
                ((SPACE_RECLAIMED_MB += size_mb))
            fi
            
            if [ "$APPLY_CLEANUP" -eq 1 ]; then
                log_action "    → DELETING: $image_id"
                docker rmi -f "$image_id" >> /dev/null 2>&1 || log_action "    → DELETE FAILED: $image_id"
            elif [ "$DRY_RUN" -eq 1 ]; then
                log_action "    → [DRY-RUN] Would delete: $image_id"
            fi
        fi
    done
}

cleanup_containers() {
    log_action "Scanning for exited/unhealthy containers..."
    
    docker ps -a --format "table {{.ID}}\t{{.Names}}\t{{.Status}}\t{{.CreatedAt}}" | tail -n +2 | while read -r container_id name status created_at; do
        # Skip protected containers
        if is_protected "$name" "$PROTECTED_CONTAINERS"; then
            if [ "$VERBOSE" -eq 1 ]; then
                log_action "  [PROTECTED] $name (ID: ${container_id:0:12})"
            fi
            return 0
        fi
        
        # Check if exited or unhealthy
        if [[ "$status" == "Exited"* ]] || [[ "$status" == "Unhealthy"* ]]; then
            log_action "  [ORPHANED] Container: $name (${container_id:0:12}) - Status: $status"
            ((ORPHANED_CONTAINERS_FOUND++))
            
            if [ "$APPLY_CLEANUP" -eq 1 ]; then
                log_action "    → DELETING: $name"
                docker rm -f "$container_id" >> /dev/null 2>&1 || log_action "    → DELETE FAILED: $container_id"
            elif [ "$DRY_RUN" -eq 1 ]; then
                log_action "    → [DRY-RUN] Would delete: $name"
            fi
        fi
    done
}

cleanup_volumes() {
    log_action "Scanning for orphaned volumes..."
    
    docker volume ls --format "table {{.Name}}\t{{.Driver}}\t{{.Mountpoint}}" | tail -n +2 | while read -r volume_name driver mountpoint; do
        # Skip protected volumes
        if is_protected "$volume_name" "$PROTECTED_VOLUMES"; then
            if [ "$VERBOSE" -eq 1 ]; then
                log_action "  [PROTECTED] $volume_name"
            fi
            return 0
        fi
        
        # Check if volume is in use by any container
        local in_use=$(docker ps -a --format '{{.Mounts}}' | grep -c "$volume_name" 2>/dev/null || echo "0")
        
        if [ "$in_use" -eq 0 ]; then
            log_action "  [ORPHANED] Volume: $volume_name (driver: $driver)"
            ((ORPHANED_VOLUMES_FOUND++))
            
            if [ "$APPLY_CLEANUP" -eq 1 ]; then
                log_action "    → DELETING: $volume_name"
                docker volume rm "$volume_name" >> /dev/null 2>&1 || log_action "    → DELETE FAILED: $volume_name"
            elif [ "$DRY_RUN" -eq 1 ]; then
                log_action "    → [DRY-RUN] Would delete: $volume_name"
            fi
        fi
    done
}

cleanup_build_cache() {
    log_action "Scanning for unused build cache..."
    
    # Prune unused build cache
    if [ "$APPLY_CLEANUP" -eq 1 ]; then
        log_action "Running docker buildx prune..."
        docker buildx du > /dev/null 2>&1 || true
        docker buildx prune -af --keep-state >> /dev/null 2>&1 || log_action "Build cache prune failed or not available"
    elif [ "$DRY_RUN" -eq 1 ]; then
        log_action "[DRY-RUN] Would prune unused build cache"
    fi
}

cleanup_logs() {
    log_action "Scanning for stale container logs..."
    
    # Note: Docker logs are typically managed by Docker daemon
    # This is informational - actual log rotation is config-based
    log_action "  Container logs: Managed by Docker daemon (log rotation config in daemon.json)"
}

generate_report() {
    log_action ""
    log_action "=========================================="
    log_action "Docker Storage Hygiene Report"
    log_action "=========================================="
    log_action "Retention Policy:"
    log_action "  Images:         $IMAGE_RETENTION_DAYS days"
    log_action "  Containers:     $CONTAINER_RETENTION_DAYS days"
    log_action "  Volumes:        $VOLUME_RETENTION_DAYS days"
    log_action "  Logs:           $LOG_RETENTION_DAYS days"
    log_action "  Build cache:    $BUILD_CACHE_RETENTION_DAYS days"
    log_action ""
    log_action "Scan Results:"
    log_action "  Total images scanned:     $TOTAL_IMAGES_SCANNED"
    log_action "  Orphaned images found:    $ORPHANED_IMAGES_FOUND"
    log_action "  Orphaned containers:      $ORPHANED_CONTAINERS_FOUND"
    log_action "  Orphaned volumes:         $ORPHANED_VOLUMES_FOUND"
    log_action ""
    log_action "Space Metrics:"
    log_action "  Estimated space reclaimed: ${SPACE_RECLAIMED_MB}MB"
    log_action ""
    log_action "Mode: $([ "$APPLY_CLEANUP" -eq 1 ] && echo 'APPLY' || echo 'DRY-RUN')"
    log_action "Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}

save_metrics() {
    cat > "$METRICS_FILE" <<EOF
{
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "retention_policy": {
    "image_days": $IMAGE_RETENTION_DAYS,
    "container_days": $CONTAINER_RETENTION_DAYS,
    "volume_days": $VOLUME_RETENTION_DAYS,
    "log_days": $LOG_RETENTION_DAYS,
    "build_cache_days": $BUILD_CACHE_RETENTION_DAYS
  },
  "scan_results": {
    "total_images_scanned": $TOTAL_IMAGES_SCANNED,
    "orphaned_images": $ORPHANED_IMAGES_FOUND,
    "orphaned_containers": $ORPHANED_CONTAINERS_FOUND,
    "orphaned_volumes": $ORPHANED_VOLUMES_FOUND
  },
  "storage_metrics": {
    "space_reclaimed_mb": $SPACE_RECLAIMED_MB
  },
  "mode": "$([ "$APPLY_CLEANUP" -eq 1 ] && echo 'apply' || echo 'dry-run')"
}
EOF
    log_action "Metrics saved to: $METRICS_FILE"
}

main() {
    log_action "Docker Storage Hygiene Automation Starting"
    log_action "Mode: $([ "$APPLY_CLEANUP" -eq 1 ] && echo 'APPLY CLEANUP' || echo 'DRY-RUN')"
    log_action ""
    
    # Check docker availability
    if ! command -v docker &> /dev/null; then
        log_action "ERROR: Docker not found. Exiting."
        exit 1
    fi
    
    # Run cleanup jobs
    cleanup_images
    cleanup_containers
    cleanup_volumes
    cleanup_build_cache
    cleanup_logs
    
    # Generate reports
    generate_report
    save_metrics
    
    log_action ""
    log_action "Cleanup complete. Report saved to: $REPORT_FILE"
}

main "$@"
