#!/bin/bash
################################################################################
# File: backup.sh
# Owner: Data Management Team
# Purpose: Enterprise backup and restore for code-server persistent volumes
# Last Modified: April 14, 2026
# Compatibility: Ubuntu 22.04+, Bash 4.0+, Docker 20.10+
#
# Dependencies:
#   - docker (for volume backup/restore)
#   - tar (for compression)
#   - rsync (optional, for off-site replication)
#
# Related Files:
#   - scripts/disaster-recovery-p3.sh — Full DR procedures
#   - docker-compose.yml — Volume definitions
#   - RUNBOOKS.md — Operational procedures
#
# Usage:
#   ./backup.sh backup                    # Create snapshot of code-server data
#   ./backup.sh restore <backup.tar.gz>   # Restore from backup
#   ./backup.sh list                      # List available backups
#
# Examples:
#   ./backup.sh backup
#   ./backup.sh restore backups/coder-data-20260414-153000.tar.gz
#
# Recent Changes:
#   2026-04-14: Added error handling integration
#   2026-04-13: Initial creation with backup/restore functions
#
################################################################################
set -euo pipefail

# Bootstrap: single entrypoint loads config, logging, utils, error-handler, docker, ssh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/init.sh" || { echo "FATAL: Cannot source _common/init.sh"; exit 1; }

# Precondition assertions — fail fast before any side effects
assert_docker   # Docker must be running to backup volumes

BACKUP_DIR="$SCRIPT_DIR/../backups"
mkdir -p "$BACKUP_DIR" || log_fatal "Cannot create backup directory: $BACKUP_DIR"
require_command docker || log_fatal "docker not found in PATH"

COMMAND="${1:-backup}"

case "$COMMAND" in
  backup)
    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    OUTFILE="$BACKUP_DIR/coder-data-$TIMESTAMP.tar.gz"
    echo "[backup] Creating snapshot: $OUTFILE"
    docker run --rm \
      --volumes-from code-server \
      -v "$BACKUP_DIR:/backup" \
      alpine \
      sh -c "tar czf /backup/coder-data-$TIMESTAMP.tar.gz -C /home/coder . && echo done"
    echo "[backup] Success: $OUTFILE"
    ls -lh "$BACKUP_DIR"
    ;;
  restore)
    FILE="${2:-}"
    if [ -z "$FILE" ]; then
      echo "Usage: $0 restore <path-to-backup.tar.gz>" >&2
      exit 1
    fi
    if [ ! -f "$FILE" ]; then
      echo "Error: file not found: $FILE" >&2
      exit 1
    fi
    ABS_FILE="$(cd "$(dirname "$FILE")" && pwd)/$(basename "$FILE")"
    echo "[restore] Restoring from $ABS_FILE -- THIS WILL OVERWRITE /home/coder"
    read -rp "Continue? [y/N] " CONFIRM
    [ "$CONFIRM" = "y" ] || { echo "Aborted."; exit 0; }
    docker run --rm \
      --volumes-from code-server \
      -v "$ABS_FILE:/backup/restore.tar.gz:ro" \
      alpine \
      sh -c "cd /home/coder && tar xzf /backup/restore.tar.gz && echo done"
    echo "[restore] Complete. Restart code-server to apply."
    ;;
  list)
    ls -lh "$BACKUP_DIR"/*.tar.gz 2>/dev/null || echo "No backups found in $BACKUP_DIR"
    ;;
  *)
    echo "Usage: $0 {backup|restore <file>|list}" >&2
    exit 1
    ;;
esac
