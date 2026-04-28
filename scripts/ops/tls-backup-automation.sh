#!/bin/bash
# @file tls-backup-automation.sh
# @module infrastructure
# @description Automated TLS certificate backup and recovery for production safety
# @governance GOV-002 - TLS certificates must be backed up and recoverable
# @idempotent YES - Safe to run continuously
set -euo pipefail

# Source canonical bootstrap
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

# =============================================================================
# ERROR HANDLING & CLEANUP
# =============================================================================
trap 'log_error "Script failed at line $LINENO (exit code: $?)"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

readonly CADDY_DATA_DIR="./caddy_data"
readonly BACKUP_DIR="./state/backups/tls"
readonly LOG_FILE="./artifacts/tls-backup-$(date +%s).log"
readonly ENCRYPTION_KEY="${TLS_ENCRYPTION_KEY:-}"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

warn() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $*" | tee -a "$LOG_FILE"
}

error() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" | tee -a "$LOG_FILE"
}

# Initialize backup directory
init_backup_dir() {
  mkdir -p "$BACKUP_DIR"
  mkdir -p "${BACKUP_DIR}/certificates"
  mkdir -p "${BACKUP_DIR}/keys"
  mkdir -p "${BACKUP_DIR}/archives"
  log "Backup directory initialized: $BACKUP_DIR"
}

# Create encrypted backup of TLS certificates
backup_tls_certificates() {
  log "Starting TLS certificate backup..."
  
  if [[ ! -d "$CADDY_DATA_DIR" ]]; then
    warn "Caddy data directory not found: $CADDY_DATA_DIR"
    return 1
  fi
  
  local backup_timestamp=$(date +%s)
  local backup_file="${BACKUP_DIR}/archives/tls-backup-${backup_timestamp}.tar.gz"
  
  # Create backup
  log "Creating backup: $backup_file"
  tar czf "$backup_file" \
    --directory="$(dirname "$CADDY_DATA_DIR")" \
    "$(basename "$CADDY_DATA_DIR")"
  
  if [[ -n "$ENCRYPTION_KEY" ]]; then
    log "Encrypting backup..."
    openssl enc -aes-256-cbc -salt -in "$backup_file" \
      -out "${backup_file}.enc" \
      -k "$ENCRYPTION_KEY" 2>/dev/null
    rm "$backup_file"
    backup_file="${backup_file}.enc"
    log "Backup encrypted: $backup_file"
  fi
  
  # Calculate checksum
  local checksum=$(sha256sum "$backup_file" | cut -d' ' -f1)
  echo "$backup_timestamp:$checksum:$backup_file" >> "${BACKUP_DIR}/manifest.log"
  
  log "✅ Backup complete: $backup_file"
  log "Checksum: $checksum"
  
  # Keep only last 30 days of backups
  find "${BACKUP_DIR}/archives" -name "tls-backup-*.tar.gz*" -mtime +30 -delete
  log "Cleaned up backups older than 30 days"
}

# Verify TLS backup integrity
verify_tls_backup() {
  log "Verifying TLS backup integrity..."
  
  local latest_backup=$(ls -t "${BACKUP_DIR}/archives"/tls-backup-*.tar.gz* 2>/dev/null | head -1)
  
  if [[ -z "$latest_backup" ]]; then
    error "No TLS backup found"
    return 1
  fi
  
  log "Checking backup: $latest_backup"
  
  # Verify file integrity
  if [[ "$latest_backup" == *.enc ]]; then
    log "Backup is encrypted, verifying encryption..."
    if [[ -z "$ENCRYPTION_KEY" ]]; then
      warn "Cannot verify encrypted backup without ENCRYPTION_KEY"
      return 0
    fi
    
    # Try to decrypt and verify
    if openssl enc -aes-256-cbc -d -in "$latest_backup" \
      -k "$ENCRYPTION_KEY" 2>/dev/null | tar tzf - &>/dev/null; then
      log "✅ Encrypted backup verified successfully"
      return 0
    else
      error "❌ Failed to decrypt and verify backup"
      return 1
    fi
  else
    # Verify tar archive
    if tar tzf "$latest_backup" &>/dev/null; then
      log "✅ Backup verified successfully"
      return 0
    else
      error "❌ Backup verification failed"
      return 1
    fi
  fi
}

# Restore TLS certificates from backup
restore_tls_certificates() {
  local backup_file="${1:-}"
  
  if [[ -z "$backup_file" ]]; then
    backup_file=$(ls -t "${BACKUP_DIR}/archives"/tls-backup-*.tar.gz* 2>/dev/null | head -1)
  fi
  
  if [[ -z "$backup_file" ]]; then
    error "No backup file specified and no backup found"
    return 1
  fi
  
  log "Restoring TLS certificates from: $backup_file"
  
  # Create backup of current state before restore
  if [[ -d "$CADDY_DATA_DIR" ]]; then
    log "Creating pre-restore backup..."
    tar czf "${BACKUP_DIR}/archives/pre-restore-$(date +%s).tar.gz" "$CADDY_DATA_DIR"
  fi
  
  # Decrypt if necessary
  if [[ "$backup_file" == *.enc ]]; then
    if [[ -z "$ENCRYPTION_KEY" ]]; then
      error "Encrypted backup requires ENCRYPTION_KEY environment variable"
      return 1
    fi
    
    log "Decrypting backup..."
    local decrypted_file=$(mktemp)
    openssl enc -aes-256-cbc -d -in "$backup_file" \
      -out "$decrypted_file" \
      -k "$ENCRYPTION_KEY" 2>/dev/null || {
      error "Failed to decrypt backup"
      rm "$decrypted_file"
      return 1
    }
    backup_file="$decrypted_file"
  fi
  
  # Remove current certificates
  if [[ -d "$CADDY_DATA_DIR" ]]; then
    log "Removing current TLS certificates..."
    rm -rf "$CADDY_DATA_DIR"
  fi
  
  # Restore from backup
  log "Extracting backup..."
  tar xzf "$backup_file" -C "$(dirname "$CADDY_DATA_DIR")"
  
  if [[ -d "$CADDY_DATA_DIR" ]]; then
    log "✅ TLS certificates restored successfully"
    
    # Restart Caddy to reload certificates
    log "Restarting Caddy service..."
    docker compose restart caddy
    
    return 0
  else
    error "❌ Failed to restore TLS certificates"
    return 1
  fi
}

# Create daily scheduled backup
setup_backup_cron() {
  log "Setting up backup cron job..."
  
  local cron_cmd="0 2 * * * /bin/bash ${PWD}/scripts/ops/tls-backup-automation.sh backup"
  
  # Check if already scheduled
  if crontab -l 2>/dev/null | grep -q "tls-backup-automation.sh"; then
    log "Backup cron job already scheduled"
    return 0
  fi
  
  # Add to crontab
  (crontab -l 2>/dev/null; echo "$cron_cmd") | crontab -
  log "✅ Backup cron job scheduled (daily at 2:00 AM)"
}

# Generate recovery procedure documentation
create_recovery_docs() {
  log "Creating recovery procedure documentation..."
  
  cat > "${BACKUP_DIR}/RECOVERY-PROCEDURES.md" << 'RECOVERY_EOF'
# TLS Certificate Recovery Procedures

## Backup Status
- Location: ./state/backups/tls/
- Last Backup: (see manifest.log)
- Backup Retention: 30 days

## Quick Recovery (if Caddy is down)

### Step 1: List available backups
```bash
ls -la ./state/backups/tls/archives/
```

### Step 2: Restore from latest backup
```bash
export TLS_ENCRYPTION_KEY="your-encryption-key"
bash ./scripts/ops/tls-backup-automation.sh restore
```

### Step 3: Verify Caddy is running
```bash
docker compose ps caddy
```

## Manual Recovery (if scripts fail)

### Decrypt backup
```bash
openssl enc -aes-256-cbc -d -in tls-backup-xxxx.tar.gz.enc \
  -out tls-backup-xxxx.tar.gz \
  -k "your-encryption-key"
```

### Extract backup
```bash
tar xzf tls-backup-xxxx.tar.gz
```

### Restart Caddy
```bash
docker compose down caddy
docker compose up -d caddy
```

## Emergency: If all backups are lost

### Generate new certificates (will break HTTPS)
```bash
docker compose exec caddy caddy reload --config /etc/caddy/Caddyfile
```

### Or recover from Let's Encrypt
If using Let's Encrypt, certificates can be re-issued:
```bash
docker compose restart caddy
# Wait 5 minutes for certificate generation
docker compose ps caddy
```

## Backup Verification

Check backup integrity:
```bash
bash ./scripts/ops/tls-backup-automation.sh verify
```

RECOVERY_EOF

  log "✅ Recovery procedures documented"
}

main() {
  case "${1:-backup}" in
    backup)
      log "=========================================="
      log "TLS Certificate Backup"
      log "=========================================="
      init_backup_dir
      backup_tls_certificates
      ;;
    verify)
      log "=========================================="
      log "TLS Backup Verification"
      log "=========================================="
      init_backup_dir
      verify_tls_backup
      ;;
    restore)
      log "=========================================="
      log "TLS Certificate Restore"
      log "=========================================="
      init_backup_dir
      restore_tls_certificates "${2:-}"
      ;;
    setup-cron)
      log "=========================================="
      log "Setup Backup Cron"
      log "=========================================="
      setup_backup_cron
      ;;
    setup)
      log "=========================================="
      log "Complete TLS Backup Setup"
      log "=========================================="
      init_backup_dir
      backup_tls_certificates
      verify_tls_backup
      setup_backup_cron
      create_recovery_docs
      ;;
    *)
      echo "Usage: $0 {backup|verify|restore|setup-cron|setup}"
      exit 1
      ;;
  esac
}

main "$@"
