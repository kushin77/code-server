# @file terraform/modules/storage/variables.tf
# @description Storage, volumes, and backup configuration

variable "nas_host" {
  description = "NAS/storage host IP/hostname"
  type        = string
  default     = ""
}

variable "storage_mount_path" {
  description = "Local mount path for NAS storage"
  type        = string
  default     = "/mnt/nas"
}

variable "postgres_volume_size_gb" {
  description = "PostgreSQL data volume size (GB)"
  type        = number
  default     = 100
}

variable "backup_retention_days" {
  description = "Backup retention period (days)"
  type        = number
  default     = 30
}

variable "enable_backups" {
  description = "Enable automated backups"
  type        = bool
  default     = true
}

variable "tags" {
  type    = map(string)
  default = {}
}
