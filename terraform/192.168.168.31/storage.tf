# Storage Configuration: Docker Volumes, NAS Mounts, Storage Topology

# ============================================================================
# NAS MOUNT CONFIGURATION
# ============================================================================

resource "null_resource" "nfs_mount_primary" {
  depends_on = [null_resource.prepare_mount_directories]

  count = var.skip_nas_mount ? 0 : 1

  provisioner "remote-exec" {
    type = "ssh"

    inline = [
      "set -e",
      "echo '=== Configuring NAS Primary Mount (${var.nas_protocol}) ==='",
      
      # Install NFS client if needed
      "if [ '${var.nas_protocol}' = 'nfs4' ] || [ '${var.nas_protocol}' = 'nfs3' ]; then",
      "  if ! command -v mount.nfs &>/dev/null; then",
      "    if command -v apt-get &>/dev/null; then",
      "      sudo apt-get install -y nfs-common 2>&1 | tail -2",
      "    elif command -v yum &>/dev/null; then",
      "      sudo yum install -y nfs-utils 2>&1 | tail -2",
      "    fi",
      "  fi",
      "fi",
      
      # Install iSCSI initiator if needed
      "if [ '${var.nas_protocol}' = 'iscsi' ]; then",
      "  if ! command -v iscsiadm &>/dev/null; then",
      "    if command -v apt-get &>/dev/null; then",
      "      sudo apt-get install -y open-iscsi 2>&1 | tail -2",
      "    elif command -v yum &>/dev/null; then",
      "      sudo yum install -y iscsi-initiator-utils 2>&1 | tail -2",
      "    fi",
      "  fi",
      "fi",
      
      # Create systemd mount unit for NAS primary
      "sudo tee /etc/systemd/system/mnt-nas\\x2dprimary.mount > /dev/null << 'MOUNT_EOF'",
      "[Unit]",
      "Description=NAS Primary Mount",
      "After=network-online.target",
      "Wants=network-online.target",
      "",
      "[Mount]",
      "What=${var.nas_primary_endpoint}:${var.nas_primary_path}",
      "Where=${var.nas_primary_mount_point}",
      "Type=${var.nas_protocol}",
      "Options=${var.nas_mount_options}",
      "TimeoutSec=120",
      "",
      "[Install]",
      "WantedBy=multi-user.target",
      "MOUNT_EOF",
      
      # Enable and mount
      "sudo systemctl enable mnt-nas\\x2dprimary.mount",
      "sudo systemctl start mnt-nas\\x2dprimary.mount || echo 'Warning: Mount may require credentials or network connectivity'",
      "sleep 2",
      
      # Verify mount
      "if mount | grep -q '${var.nas_primary_mount_point}'; then",
      "  echo '✓ NAS primary mounted at ${var.nas_primary_mount_point}'",
      "  df -h '${var.nas_primary_mount_point}'",
      "else",
      "  echo 'ℹ NAS mount pending - verify network connectivity and NAS credentials'",
      "  echo 'Mount status: '$(systemctl status mnt-nas\\x2dprimary.mount 2>&1 | head -4)",
      "fi",
    ]

    connection {
      type        = "ssh"
      host        = var.deploy_host
      user        = var.deploy_user
      private_key = file(pathexpand(var.deploy_ssh_key_path))
      timeout     = "15m"
    }

    on_failure = continue
  }
}

resource "null_resource" "nfs_mount_backup" {
  depends_on = [null_resource.nfs_mount_primary]

  count = var.skip_nas_mount ? 0 : 1

  provisioner "remote-exec" {
    type = "ssh"

    inline = [
      "set -e",
      "echo '=== Configuring NAS Backup Mount (${var.nas_protocol}) ==='",
      
      # Create systemd mount unit for NAS backup
      "sudo tee /etc/systemd/system/mnt-nas\\x2dbackup.mount > /dev/null << 'MOUNT_EOF'",
      "[Unit]",
      "Description=NAS Backup Mount",
      "After=network-online.target",
      "Wants=network-online.target",
      "",
      "[Mount]",
      "What=${var.nas_backup_endpoint}:${var.nas_backup_path}",
      "Where=${var.nas_backup_mount_point}",
      "Type=${var.nas_protocol}",
      "Options=${var.nas_mount_options}",
      "TimeoutSec=120",
      "",
      "[Install]",
      "WantedBy=multi-user.target",
      "MOUNT_EOF",
      
      # Enable and mount
      "sudo systemctl enable mnt-nas\\x2dbackup.mount",
      "sudo systemctl start mnt-nas\\x2dbackup.mount || echo 'Warning: Mount may require credentials or network connectivity'",
      "sleep 2",
      
      # Verify mount
      "if mount | grep -q '${var.nas_backup_mount_point}'; then",
      "  echo '✓ NAS backup mounted at ${var.nas_backup_mount_point}'",
      "  df -h '${var.nas_backup_mount_point}'",
      "else",
      "  echo 'ℹ NAS backup mount pending - verify network connectivity'",
      "fi",
    ]

    connection {
      type        = "ssh"
      host        = var.deploy_host
      user        = var.deploy_user
      private_key = file(pathexpand(var.deploy_ssh_key_path))
      timeout     = "15m"
    }

    on_failure = continue
  }
}

# ============================================================================
# DOCKER VOLUME DECLARATIONS
# ============================================================================

# Note: These are documented values for the docker-compose.yml file
# Actual volume creation happens via docker-compose, not Terraform

locals {
  docker_volumes = {
    ollama_data = {
      mount_path   = "/mnt/nas-primary/models"
      host_path    = "${var.nas_primary_mount_point}/models"
      capacity     = "${var.storage_ollama}G"
      purpose      = "Ollama LLM models and cache"
    }
    
    codeserver_data = {
      mount_path   = "/home/coder/.local/share/code-server"
      host_path    = "${var.nas_primary_mount_point}/codeserver"
      capacity     = "${var.storage_codeserver}G"
      purpose      = "Code-Server extensions, settings, workspace metadata"
    }
    
    workspace_data = {
      mount_path   = "/home/coder/projects"
      host_path    = "${var.nas_primary_mount_point}/workspaces"
      capacity     = "${var.storage_workspace}G"
      purpose      = "User code projects and workspace data"
    }
    
    backup_cache = {
      mount_path   = "/mnt/nas-backup"
      host_path    = "${var.nas_backup_mount_point}"
      capacity     = "Dynamic"
      purpose      = "Incremental backup of primary NAS"
    }
  }
}

# ============================================================================
# STORAGE CAPACITY VALIDATION
# ============================================================================

resource "null_resource" "validate_storage_capacity" {
  depends_on = [null_resource.nfs_mount_primary, null_resource.nfs_mount_backup]

  count = var.skip_nas_mount ? 0 : 1

  provisioner "remote-exec" {
    type = "ssh"

    inline = [
      "echo '=== Storage Capacity Validation ==='",
      
      # Check primary NAS capacity
      "if [ -d '${var.nas_primary_mount_point}' ]; then",
      "  echo 'NAS Primary Space:'",
      "  df -h '${var.nas_primary_mount_point}' | tail -1",
      "  available=$(df '${var.nas_primary_mount_point}' | tail -1 | awk '{print $4}')",
      "  required=$(( ${var.storage_ollama} * 1024 + ${var.storage_codeserver} * 1024 + ${var.storage_workspace} * 1024 ))",
      "  if [ \"$available\" -gt \"$required\" ]; then",
      "    echo '✓ Sufficient capacity available'",
      "  else",
      "    echo '✗ WARNING: Insufficient capacity! Required > Available'",
      "  fi",
      "fi",
      
      # Create subdirectories for volumes
      "echo 'Creating volume directories...        ''",
      "mkdir -p '${var.nas_primary_mount_point}'/models",
      "mkdir -p '${var.nas_primary_mount_point}'/codeserver",
      "mkdir -p '${var.nas_primary_mount_point}'/workspaces",
      "mkdir -p '${var.nas_primary_mount_point}'/backups",
      "echo '✓ Volume directories created'",
    ]

    connection {
      type        = "ssh"
      host        = var.deploy_host
      user        = var.deploy_user
      private_key = file(pathexpand(var.deploy_ssh_key_path))
    }

    on_failure = continue
  }
}

# ============================================================================
# BACKUP SCHEDULING (via Systemd timers)
# ============================================================================

 resource "null_resource" "configure_backup_timer" {
  depends_on = [null_resource.validate_storage_capacity]

  count = var.skip_nas_mount ? 0 : 1

  provisioner "remote-exec" {
    type = "ssh"

    inline = [
      "echo '=== Configuring Backup Automation ==='",
      
      # Create backup service script
      "sudo tee /usr/local/bin/nas-backup.sh > /dev/null << 'SCRIPT_EOF'",
      "#!/bin/bash",
      "source /etc/environment",
      "echo \"[$(date)] Starting NAS backup\"",
      "rsync -av --delete '${var.nas_primary_mount_point}/' '${var.nas_backup_mount_point}/' >> /var/log/nas-backup.log 2>&1",
      "echo \"[$(date)] Backup completed\" >> /var/log/nas-backup.log",
      "SCRIPT_EOF",
      
      "sudo chmod +x /usr/local/bin/nas-backup.sh",
      
      # Create systemd service for backup
      "sudo tee /etc/systemd/system/nas-backup.service > /dev/null << 'SERVICE_EOF'",
      "[Unit]",
      "Description=NAS Backup Service",
      "After=mnt-nas\\\\x2dprimary.mount mnt-nas\\\\x2dbackup.mount",
      "Requires=mnt-nas\\\\x2dprimary.mount mnt-nas\\\\x2dbackup.mount",
      "",
      "[Service]",
      "Type=oneshot",
      "ExecStart=/usr/local/bin/nas-backup.sh",
      "User=${var.deploy_user}",
      "StandardOutput=journal",
      "StandardError=journal",
      "SERVICE_EOF",
      
      # Create systemd timer for hourly backups
      "sudo tee /etc/systemd/system/nas-backup.timer > /dev/null << 'TIMER_EOF'",
      "[Unit]",
      "Description=NAS Backup Timer (Hourly)",
      "",
      "[Timer]",
      "OnBootSec=5min",
      "OnUnitActiveSec=1h",
      "Persistent=true",
      "",
      "[Install]",
      "WantedBy=timers.target",
      "TIMER_EOF",
      
      # Enable and start timer
      "sudo systemctl daemon-reload",
      "sudo systemctl enable nas-backup.timer",
      "sudo systemctl start nas-backup.timer || echo 'Timer start may require root'",
      "echo '✓ Backup timer configured (hourly backups)'",
    ]

    connection {
      type        = "ssh"
      host        = var.deploy_host
      user        = var.deploy_user
      private_key = file(pathexpand(var.deploy_ssh_key_path))
    }

    on_failure = continue
  }
}

# ============================================================================
# STORAGE OUTPUTS
# ============================================================================

output "storage_configuration" {
  description = "Storage configuration summary"
  value = {
    nas_primary       = var.nas_primary_mount_point
    nas_backup        = var.nas_backup_mount_point
    protocol          = var.nas_protocol
    total_allocation_gb = var.storage_ollama + var.storage_codeserver + var.storage_workspace
    volumes           = keys(local.docker_volumes)
  }
}

output "volume_mount_paths" {
  description = "Volume mount points for docker-compose.yml"
  value = {
    for name, config in local.docker_volumes :
    name => {
      container_path = config.mount_path
      host_path      = config.host_path
      capacity       = config.capacity
      purpose        = config.purpose
    }
  }
}

output "backup_schedule" {
  description = "Backup automation status"
  value       = "Hourly incremental backups configured via systemd timer (nas-backup.timer)"
}
