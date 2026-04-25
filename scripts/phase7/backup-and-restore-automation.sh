#!/bin/bash
# Phase 7: Full Backup/Restore Automation with NAS/S3 Integration
# Purpose: Idempotent backup and restore orchestration for all application data
# Governance: GOV-002 compliant (@governance tag required)
# Date: April 25, 2026

set -euo pipefail

# ============================================================================
# CONFIGURATION (all env-driven, no hardcoding)
# ============================================================================

readonly BACKUP_MODE="${BACKUP_MODE:-}"  # 'backup' or 'restore'
readonly DRY_RUN="${DRY_RUN:-false}"
readonly VERBOSE="${VERBOSE:-false}"

# Infrastructure hosts
readonly PRIMARY_HOST="${PRIMARY_HOST:-192.168.168.31}"
readonly REPLICA_HOST="${REPLICA_HOST:-192.168.168.42}"
readonly NAS_HOST="${NAS_HOST:-192.168.168.56}"
readonly APEX_DOMAIN="${APEX_DOMAIN:-kushnir.cloud}"
readonly SSH_USER="${SSH_USER:-akushnir}"

# NAS paths
readonly NAS_BACKUP_PATH="${NAS_BACKUP_PATH:-/nas/cold/paperclip-backups}"
readonly NAS_MOUNT_POINT="${NAS_MOUNT_POINT:-/mnt/nas-backup}"

# S3 configuration (optional)
readonly S3_ENABLED="${S3_ENABLED:-false}"
readonly S3_BUCKET="${S3_BUCKET:-}"
readonly S3_REGION="${S3_REGION:-us-east-1}"
readonly AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-}"
readonly AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-}"

# Backup retention
readonly BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"
readonly BACKUP_COMPRESSION="${BACKUP_COMPRESSION:-true}"

# Backup timestamp
readonly BACKUP_TIMESTAMP=$(date +%Y%m%d_%H%M%S)
readonly BACKUP_DIR="backup_${BACKUP_TIMESTAMP}"

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] [BACKUP] $*" >&2
}

log_verbose() {
  [[ "$VERBOSE" == "true" ]] && echo "[$(date +'%Y-%m-%d %H:%M:%S')] [BACKUP-VERBOSE] $*" >&2 || true
}

error() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2
  exit 1
}

warn() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] [WARNING] $*" >&2
}

dry_run_cmd() {
  if [[ "$DRY_RUN" == "true" ]]; then
    log "DRY_RUN: $*"
    return 0
  else
    "$@"
  fi
}

# SSH wrapper with timeout
remote_cmd() {
  local host="$1"
  shift
  ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new "${SSH_USER}@${host}" "$@"
}

# ============================================================================
# PREFLIGHT CHECKS
# ============================================================================

preflight_checks() {
  log "Running preflight checks..."
  
  # Check required tools
  local required_tools=("ssh" "rsync" "tar")
  [[ "$S3_ENABLED" == "true" ]] && required_tools+=("aws")
  
  for tool in "${required_tools[@]}"; do
    if ! command -v "$tool" &> /dev/null; then
      error "Required tool not found: $tool"
    fi
  done
  
  # Check SSH connectivity to hosts
  for host in "$PRIMARY_HOST" "$REPLICA_HOST"; do
    if ! remote_cmd "$host" "echo OK" &> /dev/null; then
      error "Cannot reach $host via SSH"
    fi
    log_verbose "✓ SSH connectivity to $host verified"
  done
  
  # Check NAS connectivity
  if ! ping -c 1 -W 2 "$NAS_HOST" &> /dev/null; then
    warn "NAS host $NAS_HOST is not reachable (optional - S3 backup may work)"
  else
    log_verbose "✓ NAS host $NAS_HOST is reachable"
  fi
  
  # Verify backup directory exists locally
  if [[ ! -d "$(pwd)" ]]; then
    error "Current working directory is not accessible"
  fi
  
  log "✓ Preflight checks passed"
}

# ============================================================================
# BACKUP FUNCTIONS
# ============================================================================

backup_postgres_database() {
  local host="$1"
  local db_name="${2:-code_server_db}"
  
  log "Backing up PostgreSQL database: $db_name from $host"
  
  # Get PostgreSQL container name
  local pg_container
  pg_container=$(remote_cmd "$host" "docker ps --format '{{.Names}}' | grep postgres | head -1") || true
  
  if [[ -z "$pg_container" ]]; then
    warn "PostgreSQL container not found on $host (skipping)"
    return 0
  fi
  
  log_verbose "PostgreSQL container: $pg_container"
  
  # Create backup directory
  mkdir -p "${BACKUP_DIR}/postgres"
  
  # Dump database with pg_dump inside container
  local dump_file="${BACKUP_DIR}/postgres/${db_name}_${BACKUP_TIMESTAMP}.sql"
  
  dry_run_cmd remote_cmd "$host" \
    "docker exec $pg_container pg_dump -U postgres $db_name" > "$dump_file" || {
    warn "Failed to dump PostgreSQL database from $host"
    return 1
  }
  
  # Compress if enabled
  if [[ "$BACKUP_COMPRESSION" == "true" ]]; then
    dry_run_cmd gzip "$dump_file"
    dump_file="${dump_file}.gz"
  fi
  
  log "✓ PostgreSQL backup saved: $dump_file"
}

backup_docker_volumes() {
  local host="$1"
  
  log "Backing up Docker volumes from $host"
  
  # Get list of volumes
  local volumes
  volumes=$(remote_cmd "$host" "docker volume ls --format '{{.Name}}'" 2>/dev/null) || true
  
  if [[ -z "$volumes" ]]; then
    log_verbose "No Docker volumes found on $host"
    return 0
  fi
  
  mkdir -p "${BACKUP_DIR}/volumes"
  
  while read -r volume; do
    [[ -z "$volume" ]] && continue
    
    log_verbose "Backing up volume: $volume"
    
    # Create tar of volume using docker
    local tar_file="${BACKUP_DIR}/volumes/${volume}_${BACKUP_TIMESTAMP}.tar"
    
    dry_run_cmd remote_cmd "$host" \
      "docker run --rm -v ${volume}:/data:ro alpine tar czf - -C /data . | cat > /tmp/vol_backup.tar" || {
      warn "Failed to backup volume $volume from $host"
      continue
    }
    
    # Copy from remote to local
    dry_run_cmd scp -o ConnectTimeout=10 \
      "${SSH_USER}@${host}:/tmp/vol_backup.tar" "$tar_file" || {
      warn "Failed to copy volume backup from $host"
      continue
    }
    
    log_verbose "✓ Volume $volume backed up"
  done <<< "$volumes"
  
  log "✓ Docker volumes backup completed"
}

backup_application_config() {
  local host="$1"
  
  log "Backing up application configuration from $host"
  
  mkdir -p "${BACKUP_DIR}/config"
  
  # List of important config paths
  local config_paths=(
    "/etc/caddyfile"
    "/etc/kushnir.cloud"
    "/root/.kube/config"
    "/opt/code-server-enterprise/config"
  )
  
  for config_path in "${config_paths[@]}"; do
    # Check if path exists on remote
    if remote_cmd "$host" "[[ -e $config_path ]]" 2>/dev/null; then
      local local_path="${BACKUP_DIR}/config/$(echo $config_path | tr '/' '_')"
      log_verbose "Backing up: $config_path"
      
      dry_run_cmd scp -r -o ConnectTimeout=10 \
        "${SSH_USER}@${host}:${config_path}" "$local_path" 2>/dev/null || {
        log_verbose "Config path not found: $config_path (non-critical)"
      }
    fi
  done
  
  log "✓ Application configuration backup completed"
}

backup_state_directory() {
  local host="$1"
  
  log "Backing up state directory from $host"
  
  mkdir -p "${BACKUP_DIR}/state"
  
  dry_run_cmd rsync -avz -e "ssh -o ConnectTimeout=10" \
    "${SSH_USER}@${host}:/var/lib/code-server/state/" \
    "${BACKUP_DIR}/state/" || {
    warn "Failed to backup state directory from $host"
  }
  
  log "✓ State directory backup completed"
}

backup_helm_configurations() {
  local host="$1"
  
  log "Backing up Helm configurations from $host"
  
  mkdir -p "${BACKUP_DIR}/helm"
  
  # Backup Helm charts if k3s is running
  if remote_cmd "$host" "command -v helm &> /dev/null" 2>/dev/null; then
    dry_run_cmd remote_cmd "$host" \
      "helm list --all-namespaces -o json" > "${BACKUP_DIR}/helm/releases.json" || {
      log_verbose "Failed to export Helm releases"
    }
    
    # Backup kubeconfig
    dry_run_cmd scp -o ConnectTimeout=10 \
      "${SSH_USER}@${host}:~/.kube/config" "${BACKUP_DIR}/helm/kubeconfig" 2>/dev/null || {
      log_verbose "kubeconfig not available"
    }
  else
    log_verbose "Helm/kubectl not available on $host"
  fi
  
  log "✓ Helm configuration backup completed"
}

create_backup_manifest() {
  log "Creating backup manifest..."
  
  local manifest="${BACKUP_DIR}/MANIFEST.json"
  
  cat > "$manifest" <<EOF
{
  "backup_timestamp": "$BACKUP_TIMESTAMP",
  "backup_version": "1.0",
  "source_primary": "$PRIMARY_HOST",
  "source_replica": "$REPLICA_HOST",
  "nas_destination": "$NAS_HOST",
  "s3_enabled": $S3_ENABLED,
  "compression": $BACKUP_COMPRESSION,
  "backup_components": [
    "postgresql",
    "docker_volumes",
    "application_config",
    "state_directory",
    "helm_configurations"
  ],
  "backup_retention_days": $BACKUP_RETENTION_DAYS,
  "created_at": "$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
}
EOF
  
  log "✓ Manifest created: $manifest"
}

upload_backup_to_nas() {
  log "Uploading backup to NAS: $NAS_HOST:$NAS_BACKUP_PATH"
  
  if ! ping -c 1 -W 2 "$NAS_HOST" &> /dev/null; then
    warn "NAS is unreachable - skipping NAS upload (S3 may still succeed)"
    return 1
  fi
  
  # Mount NAS if needed
  if [[ ! -d "$NAS_MOUNT_POINT" ]]; then
    mkdir -p "$NAS_MOUNT_POINT"
  fi
  
  # Try to mount via NFS or SMB
  if ! mountpoint -q "$NAS_MOUNT_POINT"; then
    log_verbose "Mounting NAS at $NAS_MOUNT_POINT"
    
    # Attempt NFS mount
    dry_run_cmd mount -t nfs -o soft,timeo=10 "$NAS_HOST:$NAS_BACKUP_PATH" "$NAS_MOUNT_POINT" 2>/dev/null || {
      log_verbose "NFS mount failed, skipping NAS backup"
      return 1
    }
  fi
  
  # Copy backup to mounted NAS
  local nas_dest="${NAS_MOUNT_POINT}/${BACKUP_DIR}"
  dry_run_cmd mkdir -p "$nas_dest"
  dry_run_cmd cp -r "${BACKUP_DIR}/"* "$nas_dest/" || {
    warn "Failed to copy backup to NAS"
    return 1
  }
  
  log "✓ Backup uploaded to NAS: $nas_dest"
  
  # Unmount
  dry_run_cmd umount "$NAS_MOUNT_POINT" 2>/dev/null || true
  
  return 0
}

upload_backup_to_s3() {
  [[ "$S3_ENABLED" != "true" ]] && return 0
  
  [[ -z "$S3_BUCKET" ]] && error "S3_BUCKET not set"
  [[ -z "$AWS_ACCESS_KEY_ID" ]] && error "AWS_ACCESS_KEY_ID not set"
  [[ -z "$AWS_SECRET_ACCESS_KEY" ]] && error "AWS_SECRET_ACCESS_KEY not set"
  
  log "Uploading backup to S3: s3://$S3_BUCKET"
  
  # Set AWS credentials
  export AWS_ACCESS_KEY_ID
  export AWS_SECRET_ACCESS_KEY
  export AWS_DEFAULT_REGION="$S3_REGION"
  
  # Upload backup directory
  dry_run_cmd aws s3 sync "${BACKUP_DIR}/" \
    "s3://${S3_BUCKET}/backups/${BACKUP_DIR}/" \
    --region "$S3_REGION" || {
    warn "Failed to upload backup to S3"
    return 1
  }
  
  log "✓ Backup uploaded to S3: s3://$S3_BUCKET/backups/$BACKUP_DIR"
}

execute_backup() {
  log "Starting backup sequence..."
  
  mkdir -p "$BACKUP_DIR"
  
  # Backup from Primary host
  backup_postgres_database "$PRIMARY_HOST"
  backup_docker_volumes "$PRIMARY_HOST"
  backup_application_config "$PRIMARY_HOST"
  backup_state_directory "$PRIMARY_HOST"
  backup_helm_configurations "$PRIMARY_HOST"
  
  # Create manifest
  create_backup_manifest
  
  # Upload to destinations
  upload_backup_to_nas || true
  upload_backup_to_s3 || true
  
  log "✓ Backup completed successfully"
  log "Backup location: $(pwd)/$BACKUP_DIR"
  
  # Print summary
  du -sh "$BACKUP_DIR"
}

# ============================================================================
# RESTORE FUNCTIONS
# ============================================================================

restore_postgres_database() {
  local source_dir="$1"
  local target_host="$2"
  
  log "Restoring PostgreSQL database on $target_host from $source_dir"
  
  # Find latest SQL dump
  local sql_file
  sql_file=$(find "$source_dir/postgres" -name "*.sql*" -type f 2>/dev/null | sort -r | head -1) || {
    error "No PostgreSQL dump found in $source_dir/postgres"
  }
  
  log "Restoring from: $sql_file"
  
  # Get PostgreSQL container
  local pg_container
  pg_container=$(remote_cmd "$target_host" "docker ps --format '{{.Names}}' | grep postgres | head -1") || {
    error "PostgreSQL container not found on $target_host"
  }
  
  # Restore database
  if [[ "$sql_file" == *.gz ]]; then
    dry_run_cmd gunzip -c "$sql_file" | remote_cmd "$target_host" \
      "docker exec -i $pg_container psql -U postgres" || {
      error "Failed to restore PostgreSQL database"
    }
  else
    dry_run_cmd cat "$sql_file" | remote_cmd "$target_host" \
      "docker exec -i $pg_container psql -U postgres" || {
      error "Failed to restore PostgreSQL database"
    }
  fi
  
  log "✓ PostgreSQL database restored"
}

restore_docker_volumes() {
  local source_dir="$1"
  local target_host="$2"
  
  log "Restoring Docker volumes on $target_host from $source_dir"
  
  [[ ! -d "$source_dir/volumes" ]] && {
    log_verbose "No volume backups found"
    return 0
  }
  
  for tar_file in "$source_dir"/volumes/*.tar*; do
    [[ ! -e "$tar_file" ]] && continue
    
    local volume_name
    volume_name=$(basename "$tar_file" | sed 's/_[0-9]*\.tar.*//')
    
    log_verbose "Restoring volume: $volume_name"
    
    # Create volume if not exists
    remote_cmd "$target_host" "docker volume create $volume_name" 2>/dev/null || true
    
    # Extract volume data
    dry_run_cmd remote_cmd "$target_host" \
      "docker run --rm -v ${volume_name}:/data alpine tar xzf - -C /data" < "$tar_file" || {
      warn "Failed to restore volume $volume_name"
      continue
    }
  done
  
  log "✓ Docker volumes restored"
}

restore_application_config() {
  local source_dir="$1"
  local target_host="$2"
  
  log "Restoring application configuration on $target_host"
  
  [[ ! -d "$source_dir/config" ]] && {
    log_verbose "No configuration backups found"
    return 0
  }
  
  for config_file in "$source_dir"/config/*; do
    [[ ! -e "$config_file" ]] && continue
    
    local original_path
    original_path="/$(basename "$config_file" | tr '_' '/')"
    
    log_verbose "Restoring: $original_path"
    
    dry_run_cmd scp -r -o ConnectTimeout=10 \
      "$config_file" "${SSH_USER}@${target_host}:${original_path}" || {
      warn "Failed to restore config: $original_path"
    }
  done
  
  log "✓ Configuration restored"
}

execute_restore() {
  local backup_source="${1:-.}"
  
  [[ ! -d "$backup_source" ]] && error "Backup source not found: $backup_source"
  [[ ! -f "$backup_source/MANIFEST.json" ]] && error "No MANIFEST.json found in backup"
  
  log "Starting restore sequence from: $backup_source"
  
  # Validate manifest
  log_verbose "Backup manifest:"
  cat "$backup_source/MANIFEST.json" >&2
  
  log "Restoring to: $PRIMARY_HOST"
  
  # Restore components
  restore_postgres_database "$backup_source" "$PRIMARY_HOST"
  restore_docker_volumes "$backup_source" "$PRIMARY_HOST"
  restore_application_config "$backup_source" "$PRIMARY_HOST"
  
  log "✓ Restore completed successfully"
}

# ============================================================================
# CLEANUP & RETENTION
# ============================================================================

cleanup_old_backups() {
  log "Cleaning up backups older than $BACKUP_RETENTION_DAYS days..."
  
  # Local cleanup
  find . -maxdepth 1 -name "backup_*" -type d -mtime "+$BACKUP_RETENTION_DAYS" -exec rm -rf {} \; 2>/dev/null || true
  
  # NAS cleanup (if mounted)
  if [[ -d "$NAS_MOUNT_POINT" ]]; then
    find "$NAS_MOUNT_POINT" -maxdepth 1 -name "backup_*" -type d -mtime "+$BACKUP_RETENTION_DAYS" -exec rm -rf {} \; 2>/dev/null || true
  fi
  
  log "✓ Cleanup completed"
}

# ============================================================================
# MAIN
# ============================================================================

main() {
  log "Phase 7: Backup & Restore Automation v1.0"
  log "Mode: $BACKUP_MODE | DRY_RUN: $DRY_RUN | Compression: $BACKUP_COMPRESSION"
  
  preflight_checks
  
  case "$BACKUP_MODE" in
    backup)
      execute_backup
      cleanup_old_backups
      ;;
    restore)
      local restore_source="${1:-.}"
      execute_restore "$restore_source"
      ;;
    *)
      error "Usage: BACKUP_MODE=backup|restore [source_dir] $0"
      ;;
  esac
}

# Run main if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
