# @file terraform/modules/storage/main.tf
# @description Storage and backup configuration

output "storage_configuration" {
  description = "Storage configuration"
  value = {
    nas_host              = var.nas_host
    storage_mount_path    = var.storage_mount_path
    postgres_volume_gb    = var.postgres_volume_size_gb
    backup_enabled        = var.enable_backups
    backup_retention_days = var.backup_retention_days
  }
}

output "volume_mounts" {
  description = "Docker volume mount points"
  value = {
    postgres_data  = "${var.storage_mount_path}/postgresql/data"
    redis_data     = "${var.storage_mount_path}/redis/data"
    qdrant_storage = "${var.storage_mount_path}/qdrant/storage"
    ollama_models  = "${var.storage_mount_path}/ollama/models"
    grafana_data   = "${var.storage_mount_path}/grafana/data"
  }
}

output "backup_strategy" {
  description = "Backup strategy summary"
  value = var.enable_backups ? {
    postgres_backup_path = "${var.storage_mount_path}/backups/postgresql"
    retention_days       = var.backup_retention_days
    schedule             = "daily at 2am UTC"
  } : null
}
