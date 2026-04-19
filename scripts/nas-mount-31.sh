#!/bin/bash
# @file        scripts/nas-mount-31.sh
# @module      operations
# @description nas mount 31 — on-prem code-server
# @owner       platform
# @status      active
# File:    nas-mount-31.sh
# Owner:   Platform Engineering
# Purpose: NAS mount automation and validation for ${DEPLOY_HOST}
# Status:  ACTIVE
# Usage:   ./nas-mount-31.sh [mount|validate|backup|troubleshoot|all] [--dry-run]

set -e

# Bootstrap _common library (logging, utils, error-handler, config)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/init.sh" || { echo "FATAL: Cannot source _common/init.sh"; exit 1; }

LOG_DIR="/var/log"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="${LOG_DIR}/nas-mount-${TIMESTAMP}.log"
DRY_RUN=false
ACTION="${1:-all}"

# NAS Configuration — use env vars with production defaults
NAS_PRIMARY="${NAS_PRIMARY:-192.168.168.10}"
NAS_SECONDARY="${NAS_SECONDARY:-192.168.168.11}"
NAS_ARCHIVE="${NAS_ARCHIVE:-192.168.168.12}"

# Mount Points
MOUNTS=(
  "models:${NAS_PRIMARY}:/export/models:/mnt/models:nfs4"
  "data:${NAS_PRIMARY}:/export/data:/mnt/data:nfs4"
  "backups:${NAS_SECONDARY}:/export/backups:/mnt/backups:nfs3"
  "archive:${NAS_ARCHIVE}:/export/archive:/mnt/archive:nfs4"
)

mkdir -p "$LOG_DIR"

# Phase 1: Pre-mount validation
validate_prerequisites() {
  log_info "=== Pre-Mount Validation ==="
  
  local failed=0
  
  # Check NFS client
  if dpkg -l | grep -q nfs-common; then
    log_success "NFS client installed"
  else
    log_warning "NFS client not installed, installing..."
    if [[ $DRY_RUN == false ]]; then
      sudo apt update && sudo apt install -y nfs-common
    fi
  fi
  
  # Check network connectivity
  for nas in "$NAS_PRIMARY" "$NAS_SECONDARY" "$NAS_ARCHIVE"; do
    if ping -c 1 -W 2 "$nas" &> /dev/null; then
      log_success "NAS $nas reachable"
    else
      log_error "NAS $nas unreachable"
      failed=$((failed + 1))
    fi
  done
  
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
BACKUP_DEST="${NAS_SECONDARY:-192.168.168.11}:/export/backups/models"

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
BACKUP_DEST="${NAS_SECONDARY:-192.168.168.11}:/export/backups/models"

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
