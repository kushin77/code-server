#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# scripts/nas-mount-31.sh — NAS mount for ${DEPLOY_HOST}
# NAS: 192.168.168.56:/export  (primary storage)
# Usage: sudo ./scripts/nas-mount-31.sh [mount|umount|status|test|dirs]
# ═══════════════════════════════════════════════════════════════════════════════
set -euo pipefail

NAS_HOST="192.168.168.56"
NAS_EXPORT="/export"
MOUNT_POINT="/mnt/nas-56"
NFS_OPTS="vers=4.1,rw,hard,intr,timeo=30,retrans=3,rsize=1048576,wsize=1048576"

# Sub-directories provisioned on the NAS
NAS_DIRS=(
    "ollama"          # Ollama model cache (large files, ~10-40GB)
    "code-server"     # Developer workspace (NFS-backed home dir)
    "grafana"         # Grafana persistent data
    "prometheus"      # Prometheus TSDB (30d retention)
    "backups/postgres" # Postgres pg_dump backups
)

# ─────────────────────────────────────────────────────────────────────────────

log()  { echo "[nas-mount] $*"; }
ok()   { echo "[nas-mount] OK: $*"; }
warn() { echo "[nas-mount] WARN: $*" >&2; }
die()  { echo "[nas-mount] FATAL: $*" >&2; exit 1; }

require_root() {
    [[ $EUID -eq 0 ]] || die "This script must be run as root (sudo)"
}

check_nfs_client() {
    if ! dpkg -l | grep -q nfs-common 2>/dev/null; then
        log "Installing nfs-common..."
        apt-get update -qq && apt-get install -y -qq nfs-common
    fi
    ok "nfs-common present"
}

ping_nas() {
    if ping -c 2 -W 2 "$NAS_HOST" &>/dev/null; then
        ok "NAS $NAS_HOST reachable"
    else
        die "NAS $NAS_HOST unreachable — check network"
    fi
}

mount_nas() {
    require_root
    check_nfs_client
    ping_nas

    mkdir -p "$MOUNT_POINT"

    if mountpoint -q "$MOUNT_POINT"; then
        ok "Already mounted at $MOUNT_POINT"
        return 0
    fi

    log "Mounting ${NAS_HOST}:${NAS_EXPORT} → ${MOUNT_POINT}..."
    mount -t nfs4 -o "$NFS_OPTS" "${NAS_HOST}:${NAS_EXPORT}" "$MOUNT_POINT"
    ok "Mounted ${MOUNT_POINT}"

    # Persist via fstab (idempotent)
    local fstab_entry="${NAS_HOST}:${NAS_EXPORT} ${MOUNT_POINT} nfs4 ${NFS_OPTS},_netdev 0 0"
    if ! grep -qF "$MOUNT_POINT" /etc/fstab; then
        echo "$fstab_entry" >> /etc/fstab
        ok "Added to /etc/fstab"
    else
        ok "Already in /etc/fstab"
    fi

    provision_dirs
}

provision_dirs() {
    log "Provisioning NAS sub-directories..."
    for dir in "${NAS_DIRS[@]}"; do
        mkdir -p "${MOUNT_POINT}/${dir}"
        ok "  ${MOUNT_POINT}/${dir}"
    done

    # Ensure akushnir user owns service directories
    chown -R akushnir:akushnir \
        "${MOUNT_POINT}/ollama" \
        "${MOUNT_POINT}/code-server" \
        "${MOUNT_POINT}/grafana" \
        "${MOUNT_POINT}/prometheus" \
        "${MOUNT_POINT}/backups" 2>/dev/null || true
}

umount_nas() {
    require_root
    if mountpoint -q "$MOUNT_POINT"; then
        umount "$MOUNT_POINT"
        ok "Unmounted $MOUNT_POINT"
    else
        warn "$MOUNT_POINT not mounted"
    fi
}

status_nas() {
    echo "=== NAS Mount Status ==="
    echo "Host         : $NAS_HOST"
    echo "Export       : $NAS_EXPORT"
    echo "Mount point  : $MOUNT_POINT"

    if mountpoint -q "$MOUNT_POINT"; then
        echo "Status       : MOUNTED"
        df -h "$MOUNT_POINT"
        echo ""
        echo "=== Sub-directories ==="
        for dir in "${NAS_DIRS[@]}"; do
            if [[ -d "${MOUNT_POINT}/${dir}" ]]; then
                local size
                size=$(du -sh "${MOUNT_POINT}/${dir}" 2>/dev/null | cut -f1)
                echo "  ${dir}: ${size}"
            else
                echo "  ${dir}: MISSING"
            fi
        done
    else
        echo "Status       : NOT MOUNTED"
        return 1
    fi
}

test_nas() {
    log "Testing NAS read/write throughput..."
    if ! mountpoint -q "$MOUNT_POINT"; then
        die "NAS not mounted — run: sudo $0 mount"
    fi

    local test_file="${MOUNT_POINT}/.write-test-$$"

    # Write test
    echo "Write (256MB):"
    dd if=/dev/urandom of="$test_file" bs=1M count=256 conv=fsync 2>&1 | tail -1

    # Read test
    echo "Read (256MB):"
    dd if="$test_file" of=/dev/null bs=1M 2>&1 | tail -1

    rm -f "$test_file"
    ok "NAS throughput test complete"
}

# ─────────────────────────────────────────────────────────────────────────────

case "${1:-status}" in
    mount)   mount_nas ;;
    umount)  umount_nas ;;
    status)  status_nas ;;
    test)    test_nas ;;
    dirs)    provision_dirs ;;
    *)
        echo "Usage: sudo $0 [mount|umount|status|test|dirs]"
        echo "  mount   — mount NAS and provision directories"
        echo "  umount  — unmount NAS"
        echo "  status  — show mount status and usage"
        echo "  test    — throughput benchmark"
        echo "  dirs    — provision sub-directories only"
        exit 1
        ;;
esac

  # Check NFS services
  if rpcinfo -p "$NAS_PRIMARY" 2>/dev/null | grep -q nfs; then
    log_success "NFS service active on primary NAS"
  else
    log_error "NFS service not responding on primary NAS"
    failed=$((failed + 1))
  fi
  
  # Check mount directories exist
  for mount_spec in "${MOUNTS[@]}"; do
    IFS=':' read -r name nas path mount_point proto <<< "$mount_spec"
    if [[ ! -d $mount_point ]]; then
      log_warning "Creating mount directory: $mount_point"
      if [[ $DRY_RUN == false ]]; then
        sudo mkdir -p "$mount_point"
      fi
    fi
  done
  
  if [[ $failed -eq 0 ]]; then
    log_success "All prerequisites validated"
    return 0
  else
    log_error "Prerequisites validation failed"
    return 1
  fi
}

# Phase 2: Mount NAS exports
mount_nas_storage() {
  log_info "=== NAS Mount Configuration ==="
  
  for mount_spec in "${MOUNTS[@]}"; do
    IFS=':' read -r name nas path mount_point proto <<< "$mount_spec"
    
    log_info "Mounting $name ($proto): $nas:$path → $mount_point"
    
    # Check if already mounted
    if mountpoint -q "$mount_point"; then
      log_warning "$mount_point already mounted"
      continue
    fi
    
    # Prepare mount options
    local mount_opts
    if [[ $proto == "nfs4" ]]; then
      mount_opts="rw,sync,hard,intr,rsize=131072,wsize=131072,timeo=600,retrans=2"
    else
      mount_opts="rw,sync,hard,intr,rsize=262144,wsize=262144,timeo=600,retrans=2,vers=3"
    fi
    
    # Mount
    if [[ $DRY_RUN == false ]]; then
      if sudo mount -t "$proto" -o "$mount_opts" "$nas:$path" "$mount_point"; then
        log_success "Mounted $mount_point"
      else
        log_error "Failed to mount $mount_point"
        return 1
      fi
    else
      log_warning "[DRY-RUN] Would mount: mount -t $proto -o $mount_opts $nas:$path $mount_point"
    fi
  done
}

# Phase 3: Validate mounts
validate_mounts() {
  log_info "=== Mount Validation ==="
  
  local failed=0
  
  for mount_spec in "${MOUNTS[@]}"; do
    IFS=':' read -r name nas path mount_point proto <<< "$mount_spec"
    
    log_info "Validating $name at $mount_point..."
    
    # Check if mounted
    if mountpoint -q "$mount_point"; then
      log_success "$mount_point is mounted"
    else
      log_error "$mount_point not mounted"
      failed=$((failed + 1))
      continue
    fi
    
    # Check accessibility
    if timeout 5 ls "$mount_point" > /dev/null 2>&1; then
      log_success "$mount_point is accessible"
    else
      log_error "$mount_point is inaccessible (timeout)"
      failed=$((failed + 1))
      continue
    fi
    
    # Check read/write
    if [[ $DRY_RUN == false ]]; then
      TEST_FILE="$mount_point/.validation-$(date +%s%N)"
      if touch "$TEST_FILE" 2>/dev/null && rm "$TEST_FILE"; then
        log_success "$mount_point is readable/writable"
      else
        log_warning "$mount_point appears read-only or permission denied"
      fi
    fi
    
    # Display capacity
    capacity=$(df -h "$mount_point" | awk 'NR==2 {print $2}')
    used=$(df -h "$mount_point" | awk 'NR==2 {print $3}')
    available=$(df -h "$mount_point" | awk 'NR==2 {print $4}')
    percent=$(df -h "$mount_point" | awk 'NR==2 {print $5}')
    
    log_info "  Capacity: Total=$capacity, Used=$used, Available=$available ($percent)"
  done
  
  if [[ $failed -eq 0 ]]; then
    log_success "All mounts validated"
    return 0
  else
    log_error "$failed mount(s) have issues"
    return 1
  fi
}

# Phase 4: Setup backup automation
setup_backup_automation() {
  log_info "=== Backup Automation Setup ==="
  
  # Create backup scripts directory
  BACKUP_SCRIPTS="/usr/local/bin"
  
  log_info "Installing backup scripts to $BACKUP_SCRIPTS..."
  
  # Create hourly model backup script
  BACKUP_MODELS_SCRIPT="$BACKUP_SCRIPTS/backup-models.sh"
  
  cat > "$BACKUP_MODELS_SCRIPT" << 'BACKUP_SCRIPT'
#!/bin/bash
# Hourly backup of Ollama models

BACKUP_LOG="/var/log/nas-backup.log"
MODELS_SOURCE="/mnt/models"
BACKUP_DEST="192.168.168.11:/export/backups/models"

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $@" | tee -a "$BACKUP_LOG"
}

log "Starting hourly model backup..."

# Check source mount
if ! mountpoint -q "$MODELS_SOURCE"; then
  log "ERROR: $MODELS_SOURCE not mounted"
  exit 1
fi

# Perform rsync
rsync -avz --delete --timeout=300 "$MODELS_SOURCE/" "$BACKUP_DEST/" 2>&1 | \
  tail -5 >> "$BACKUP_LOG" || {
  log "ERROR: rsync failed"
  exit 1
}

log "Backup completed"
BACKUP_SCRIPT
  
  if [[ $DRY_RUN == false ]]; then
    sudo tee "$BACKUP_MODELS_SCRIPT" > /dev/null << 'BACKUP_SCRIPT'
#!/bin/bash
# Hourly backup of Ollama models

BACKUP_LOG="/var/log/nas-backup.log"
MODELS_SOURCE="/mnt/models"
BACKUP_DEST="192.168.168.11:/export/backups/models"

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $@" | tee -a "$BACKUP_LOG"
}

log "Starting hourly model backup..."

# Check source mount
if ! mountpoint -q "$MODELS_SOURCE"; then
  log "ERROR: $MODELS_SOURCE not mounted"
  exit 1
fi

# Perform rsync
rsync -avz --delete --timeout=300 "$MODELS_SOURCE/" "$BACKUP_DEST/" 2>&1 | \
  tail -5 >> "$BACKUP_LOG" || {
  log "ERROR: rsync failed"
  exit 1
}

log "Backup completed"
BACKUP_SCRIPT
    
    sudo chmod +x "$BACKUP_MODELS_SCRIPT"
    log_success "Backup script installed: $BACKUP_MODELS_SCRIPT"
  fi
  
  # Setup crontab
  log_info "Setting up backup cron schedule..."
  
  if [[ $DRY_RUN == false ]]; then
    # Add hourly backup
    (crontab -l 2>/dev/null | grep -v "backup-models.sh"; echo "0 * * * * $BACKUP_MODELS_SCRIPT") | crontab -
    log_success "Backup scheduled hourly"
  else
    log_warning "[DRY-RUN] Would schedule: 0 * * * * $BACKUP_MODELS_SCRIPT"
  fi
}

# Phase 5: Performance testing
test_nas_performance() {
  log_info "=== NAS Performance Testing ==="
  
  for mount_spec in "${MOUNTS[@]}"; do
    IFS=':' read -r name nas path mount_point proto <<< "$mount_spec"
    
    if ! mountpoint -q "$mount_point"; then
      log_warning "Skipping $name (not mounted)"
      continue
    fi
    
    log_info "Testing $name at $mount_point..."
    
    TEST_FILE="$mount_point/perf-test-$TIMESTAMP"
    TEST_SIZE_MB=50
    
    # Write test
    log_info "  Sequential write test ($TEST_SIZE_MB MB)..."
    if [[ $DRY_RUN == false ]]; then
      write_speed=$(dd if=/dev/zero of="$TEST_FILE" bs=1M count="$TEST_SIZE_MB" 2>&1 | \
        awk '/copied/ {gsub(/[^0-9.]/,""); print $1}')
      log_success "  Write speed: ${write_speed} MB/s"
      
      # Read test
      log_info "  Sequential read test..."
      read_speed=$(dd if="$TEST_FILE" of=/dev/null bs=1M 2>&1 | \
        awk '/copied/ {gsub(/[^0-9.]/,""); print $1}')
      log_success "  Read speed: ${read_speed} MB/s"
      
      # Cleanup
      rm -f "$TEST_FILE"
    else
      log_warning "[DRY-RUN] Would test write/read performance on $mount_point"
    fi
  done
  
  log_success "Performance testing complete"
}

# Phase 6: Troubleshooting
troubleshoot_nas_issues() {
  log_info "=== NAS Troubleshooting ==="
  
  log_info "System Information:"
  uname -a | tee -a "$LOG_FILE"
  
  log_info "NFS Client Version:"
  apt-cache policy nfs-common | tee -a "$LOG_FILE"
  
  log_info "NFS Mounts:"
  mount | grep -i nfs | tee -a "$LOG_FILE"
  
  log_info "NFS Statistics:"
  nfsstat 2>/dev/null | head -20 | tee -a "$LOG_FILE" || echo "(nfsstat not available)" | tee -a "$LOG_FILE"
  
  log_info "Network Connectivity:"
  for nas in "$NAS_PRIMARY" "$NAS_SECONDARY"; do
    echo "  Pinging $nas:" | tee -a "$LOG_FILE"
    ping -c 3 "$nas" 2>&1 | tail -1 | tee -a "$LOG_FILE"
  done
  
  log_info "RPC Services:"
  rpcinfo 2>/dev/null | tee -a "$LOG_FILE" || echo "(rpcinfo not available)" | tee -a "$LOG_FILE"
  
  log_success "Diagnostics collected in $LOG_FILE"
}

# Main execution
main() {
  log_info "NAS Mount Automation Script Started"
  log_info "Action: $ACTION, Dry-run: $DRY_RUN"
  
  case "$ACTION" in
    mount)
      validate_prerequisites && mount_nas_storage && validate_mounts
      ;;
    validate)
      validate_mounts
      ;;
    backup)
      setup_backup_automation
      ;;
    test)
      test_nas_performance
      ;;
    troubleshoot)
      troubleshoot_nas_issues
      ;;
    all)
      validate_prerequisites && log_success "Prerequisites passed"
      log_info ""
      mount_nas_storage && log_success "Mounts completed"
      log_info ""
      validate_mounts && log_success "Validation passed"
      log_info ""
      setup_backup_automation && log_success "Backup setup complete"
      log_info ""
      test_nas_performance && log_success "Performance tests complete"
      ;;
    *)
      log_error "Unknown action: $ACTION"
      echo "Usage: $0 [mount|validate|backup|test|troubleshoot|all] [--dry-run]"
      return 1
      ;;
  esac
  
  log_success "NAS mount script completed"
  log_info "Log file: $LOG_FILE"
}

# Parse dry-run flag
if [[ $2 == "--dry-run" ]]; then
  DRY_RUN=true
fi

main "$@"
