#!/bin/bash
set -euo pipefail
# ── Enterprise backup/restore for coder-data volume ──────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKUP_DIR="$SCRIPT_DIR/../backups"
mkdir -p "$BACKUP_DIR"

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