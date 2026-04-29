#!/bin/bash
# Volume snapshot backup script
# Creates tar.gz snapshots of Docker volumes on both hosts

set -e
trap 'echo "❌ Volume snapshot failed at line $LINENO"; exit 1' ERR

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RETENTION_DAYS="${RETENTION_DAYS:-14}"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║        Docker Volume Snapshots - $TIMESTAMP                ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Function to snapshot volumes on a host
snapshot_host() {
  local HOST=$1
  local HOST_LABEL=$2
  
  echo "Snapshotting volumes on $HOST_LABEL ($HOST)..."
  echo "─────────────────────────────────────────────"
  
  ssh -o BatchMode=yes akushnir@$HOST << SNAPSHOT_EOF
    set -e
    
    BACKUP_DIR="/backups/volumes"
    mkdir -p "\$BACKUP_DIR"
    
    # Get list of volumes to backup
    VOLUMES=\$(docker volume ls --format "{{.Name}}" | grep -E "postgres|redis|qdrant|caddy|redpanda" || echo "")
    
    if [[ -z "\$VOLUMES" ]]; then
      echo "  ⚠️  No volumes found matching backup pattern"
      exit 0
    fi
    
    SNAPSHOT_COUNT=0
    
    for VOLUME in \$VOLUMES; do
      SNAPSHOT_NAME="\${VOLUME}_${TIMESTAMP}.tar.gz"
      SNAPSHOT_PATH="\$BACKUP_DIR/\$VOLUME/\$SNAPSHOT_NAME"
      
      mkdir -p "\$BACKUP_DIR/\$VOLUME"
      
      echo "  Snapshotting \$VOLUME..."
      
      # Create snapshot
      docker run --rm \
        -v "\$VOLUME:/data" \
        -v "\$BACKUP_DIR/\$VOLUME:/backup" \
        alpine tar czf /backup/"\$SNAPSHOT_NAME" -C /data . 2>/dev/null || {
        echo "    ⚠️  Failed to snapshot \$VOLUME"
        continue
      }
      
      # Verify snapshot
      if [[ -f "\$SNAPSHOT_PATH" ]]; then
        SIZE=\$(du -h "\$SNAPSHOT_PATH" | cut -f1)
        echo "    ✓ \$VOLUME: \$SIZE"
        ((SNAPSHOT_COUNT++))
      fi
    done
    
    echo "  Created \$SNAPSHOT_COUNT snapshots on \$HOSTNAME"
SNAPSHOT_EOF
  
  echo "✅ Snapshots created on $HOST_LABEL"
  echo ""
}

# Snapshot both hosts
snapshot_host "192.168.168.31" "PRIMARY"
snapshot_host "192.168.168.42" "REPLICA"

# Cleanup old snapshots
echo "Cleaning up old snapshots (retention: $RETENTION_DAYS days)..."
echo "────────────────────────────────────────────────────────────"

cleanup_old_snapshots() {
  local HOST=$1
  local HOST_LABEL=$2
  
  ssh -o BatchMode=yes akushnir@$HOST << CLEANUP_EOF
    BACKUP_DIR="/backups/volumes"
    
    if [[ ! -d "\$BACKUP_DIR" ]]; then
      exit 0
    fi
    
    DELETED=0
    for FILE in \$(find "\$BACKUP_DIR" -name "*.tar.gz" -mtime +$RETENTION_DAYS 2>/dev/null); do
      rm -f "\$FILE"
      ((DELETED++))
    done
    
    if [[ \$DELETED -gt 0 ]]; then
      echo "  Deleted \$DELETED old snapshots on $HOST_LABEL"
    fi
CLEANUP_EOF
}

cleanup_old_snapshots "192.168.168.31" "PRIMARY"
cleanup_old_snapshots "192.168.168.42" "REPLICA"

echo "✅ Cleanup complete"

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║        Volume snapshots completed                          ║"
echo "╚════════════════════════════════════════════════════════════╝"
