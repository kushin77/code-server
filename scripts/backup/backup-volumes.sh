#!/bin/bash
#
# @file backup-volumes.sh
# @module backup
# @description Docker volumes automated backup script with tar archival
# @author Operations Team
# @version 1.0
#

set -euo pipefail

# ============================================================================
# ERROR HANDLING
# ============================================================================

trap 'log_error "Volume backup failed at line $LINENO"; cleanup; exit 1' ERR
trap 'cleanup' EXIT

cleanup() {
  log_info "Performing cleanup..."
  # Remove any running backup containers
  docker ps -q -f "ancestor=alpine:latest" | xargs -r docker rm -f 2>/dev/null || true
  rm -f /tmp/volume_backup_*.tmp 2>/dev/null || true
}

# ============================================================================
# CONFIGURATION
# ============================================================================

BACKUP_DIR="${BACKUP_DIR:-/backups/daily/volumes}"
NAS_BACKUP="${NAS_BACKUP:-/mnt/nas-backup/volumes}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"
LOG_FILE="/var/log/code-server-backup-volumes.log"
DOCKER_COMPOSE_FILE="${DOCKER_COMPOSE_FILE:-/home/akushnir/code-server/docker-compose.yml}"

# Volumes to backup (from docker-compose.yml)
VOLUMES=(
  "caddy_data"
  "caddy_config"
  "prometheus_data"
  "grafana_data"
  "loki_data"
  "alertmanager_data"
  "qdrant_data"
  "redis_data"
  "redpanda_data"
  "ollama_models"
  "tempo_data"
  "postgres_data"
  "appsmith_data"
)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

log_info() {
  echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] [INFO]${NC} $*" | tee -a "$LOG_FILE"
}

log_error() {
  echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR]${NC} $*" | tee -a "$LOG_FILE"
}

log_success() {
  echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] [SUCCESS]${NC} $*" | tee -a "$LOG_FILE"
}

log_warning() {
  echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] [WARNING]${NC} $*" | tee -a "$LOG_FILE"
}

# ============================================================================
# MAIN BACKUP LOGIC
# ============================================================================

# Create backup directories
mkdir -p "$BACKUP_DIR" "$NAS_BACKUP"

# Generate backup timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

log_info "Starting Docker volumes backup: $TIMESTAMP"
log_info "Backup directory: $BACKUP_DIR"

# Verify docker is running
log_info "Verifying Docker daemon is accessible..."
if ! docker ps >/dev/null 2>&1; then
  log_error "Cannot access Docker daemon"
  exit 1
fi
log_success "Docker verified"

# Track backup statistics
TOTAL_SIZE=0
BACKUP_COUNT=0
FAILED_COUNT=0

# Backup each volume
for VOLUME in "${VOLUMES[@]}"; do
  log_info "Processing volume: $VOLUME"
  
  # Check if volume exists
  if ! docker volume inspect "$VOLUME" >/dev/null 2>&1; then
    log_warning "Volume not found (skipping): $VOLUME"
    continue
  fi
  
  BACKUP_NAME="${VOLUME}_${TIMESTAMP}.tar.gz"
  BACKUP_PATH="${BACKUP_DIR}/${BACKUP_NAME}"
  
  # Create backup using Docker container
  log_info "  Creating tar.gz backup: $BACKUP_NAME"
  
  if docker run --rm \
    -v "${VOLUME}:/volume_data" \
    -v "${BACKUP_DIR}:/backups" \
    alpine:latest \
    tar -czf "/backups/${BACKUP_NAME}" -C /volume_data . \
    2>&1 | tee -a "$LOG_FILE"; then
    
    # Get backup file size
    if [ -f "$BACKUP_PATH" ]; then
      BACKUP_SIZE=$(du -h "$BACKUP_PATH" | cut -f1)
      log_success "  Backed up: $VOLUME ($BACKUP_SIZE)"
      
      # Copy to NAS
      if [ -d "$NAS_BACKUP" ]; then
        if cp "$BACKUP_PATH" "$NAS_BACKUP/" 2>&1; then
          log_info "  Copied to NAS: $BACKUP_NAME"
        else
          log_warning "  Failed to copy to NAS (continuing)"
        fi
      fi
      
      # Add to statistics
      VOLUME_SIZE=$(stat -f%z "$BACKUP_PATH" 2>/dev/null || stat -c%s "$BACKUP_PATH" 2>/dev/null || echo 0)
      TOTAL_SIZE=$((TOTAL_SIZE + VOLUME_SIZE))
      BACKUP_COUNT+=1
    else
      log_error "  Backup file not created: $BACKUP_NAME"
      FAILED_COUNT+=1
    fi
  else
    log_error "  Failed to backup volume: $VOLUME"
    FAILED_COUNT+=1
  fi
done

# Generate backup metadata
{
  echo "Timestamp: $TIMESTAMP"
  echo "Hostname: $(hostname)"
  echo "Volumes Backed Up: $BACKUP_COUNT"
  echo "Volumes Failed: $FAILED_COUNT"
  echo "Total Size: $(numfmt --to=iec-i --suffix=B $TOTAL_SIZE 2>/dev/null || echo "$TOTAL_SIZE bytes")"
  echo "Format: tar.gz (Alpine Linux)"
  echo "Status: $([ $FAILED_COUNT -eq 0 ] && echo 'SUCCESS' || echo 'PARTIAL')"
  echo "Retention: $RETENTION_DAYS days"
} > "${BACKUP_DIR}/volumes_backup_${TIMESTAMP}.metadata"

# Cleanup old backups (retention policy)
log_info "Cleaning up backups older than $RETENTION_DAYS days..."
DELETED_COUNT=0
if [ -d "$BACKUP_DIR" ]; then
  DELETED_COUNT=$(find "$BACKUP_DIR" -name "*_*.tar.gz" -mtime +$RETENTION_DAYS -delete -print | wc -l)
fi
log_info "Deleted $DELETED_COUNT old backups from primary"

if [ -d "$NAS_BACKUP" ]; then
  NAS_DELETED=$(find "$NAS_BACKUP" -name "*_*.tar.gz" -mtime +$RETENTION_DAYS -delete -print | wc -l)
  log_info "Deleted $NAS_DELETED old backups from NAS"
fi

# Check disk space
log_info "Checking disk space..."
DISK_USAGE=$(df "$BACKUP_DIR" | tail -1 | awk '{print $5}' | sed 's/%//')
log_info "Backup disk usage: $DISK_USAGE%"

if [ "$DISK_USAGE" -gt 85 ]; then
  log_warning "Backup disk space above 85% - consider archiving or expansion"
elif [ "$DISK_USAGE" -gt 95 ]; then
  log_error "Backup disk space CRITICAL - above 95% - immediate action required"
fi

log_success "Docker volumes backup complete: $TIMESTAMP"

# Print summary
echo ""
echo "┌────────────────────────────────────────────┐"
echo "│ Volume Backup Summary                      │"
echo "├────────────────────────────────────────────┤"
echo "│ Timestamp:       $TIMESTAMP"
echo "│ Volumes Backed:  $BACKUP_COUNT"
echo "│ Failed:          $FAILED_COUNT"
echo "│ Total Size:      $(numfmt --to=iec-i --suffix=B $TOTAL_SIZE 2>/dev/null || echo "$TOTAL_SIZE bytes")"
echo "│ Location:        $BACKUP_DIR"
echo "│ Disk Usage:      $DISK_USAGE%"
echo "│ Status:          $([ $FAILED_COUNT -eq 0 ] && echo '✅ SUCCESS' || echo '⚠️  PARTIAL')"
echo "└────────────────────────────────────────────┘"
echo ""

# Exit with error if any backups failed
if [ $FAILED_COUNT -gt 0 ]; then
  exit 1
fi
