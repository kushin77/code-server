# Input Variables for 192.168.168.31 Deployment

# ============================================================================
# SSH ACCESS & CONNECTIVITY
# ============================================================================

variable "deploy_host" {
  description = "IP address or hostname of target deployment host"
  type        = string
  default     = "192.168.168.31"
}

variable "deploy_user" {
  description = "SSH user account for deployment operations"
  type        = string
  default     = "akushnir"
  validation {
    condition     = length(var.deploy_user) > 0
    error_message = "SSH user must be specified."
  }
}

variable "deploy_ssh_key_path" {
  description = "Path to SSH private key for authentication (e.g., ~/.ssh/akushnir-31)"
  type        = string
  sensitive   = true
}

variable "bastion_host" {
  description = "(Optional) Bastion host for SSH proxy - DEPRECATED: Use direct SSH to .31 node instead"
  type        = string
  default     = null
}

variable "bastion_user" {
  description = "(Optional) Bastion SSH user"
  type        = string
  default     = null
  sensitive   = true
}

variable "bastion_ssh_key_path" {
  description = "(Optional) Bastion private key path"
  type        = string
  default     = null
  sensitive   = true
}

# ============================================================================
# NAS CONFIGURATION
# ============================================================================

variable "nas_primary_endpoint" {
  description = "NAS Primary IP address or hostname (e.g., 192.168.168.50)"
  type        = string
  validation {
    condition     = length(var.nas_primary_endpoint) > 0
    error_message = "NAS primary endpoint must be specified."
  }
}

variable "nas_primary_path" {
  description = "NAS Primary export path (e.g., /export/primary for NFS, target IQN for iSCSI)"
  type        = string
  validation {
    condition     = length(var.nas_primary_path) > 0
    error_message = "NAS primary path must be specified."
  }
}

variable "nas_primary_mount_point" {
  description = "Local mount point for NAS primary"
  type        = string
  default     = "/mnt/nas-primary"
}

variable "nas_backup_endpoint" {
  description = "NAS Backup IP address or hostname (e.g., 192.168.168.51)"
  type        = string
  validation {
    condition     = length(var.nas_backup_endpoint) > 0
    error_message = "NAS backup endpoint must be specified."
  }
}

variable "nas_backup_path" {
  description = "NAS Backup export path"
  type        = string
  validation {
    condition     = length(var.nas_backup_path) > 0
    error_message = "NAS backup path must be specified."
  }
}

variable "nas_backup_mount_point" {
  description = "Local mount point for NAS backup"
  type        = string
  default     = "/mnt/nas-backup"
}

variable "nas_protocol" {
  description = "NAS mount protocol: nfs4, nfs3, or iscsi"
  type        = string
  default     = "nfs4"
  validation {
    condition     = contains(["nfs4", "nfs3", "iscsi"], var.nas_protocol)
    error_message = "NAS protocol must be one of: nfs4, nfs3, iscsi."
  }
}

variable "nas_mount_options" {
  description = "NAS mount options (NFS-specific)"
  type        = string
  default     = "rw,hard,intr,timeo=600,retrans=2,_netdev"
}

# ============================================================================
# STORAGE ALLOCATION
# ============================================================================

variable "storage_ollama" {
  description = "Storage allocation for Ollama models (GB)"
  type        = number
  default     = 2000
  validation {
    condition     = var.storage_ollama > 0
    error_message = "Ollama storage must be positive."
  }
}

variable "storage_codeserver" {
  description = "Storage allocation for Code-Server data (GB)"
  type        = number
  default     = 500
  validation {
    condition     = var.storage_codeserver > 0
    error_message = "Code-Server storage must be positive."
  }
}

variable "storage_workspace" {
  description = "Storage allocation for user workspaces (GB)"
  type        = number
  default     = 1000
  validation {
    condition     = var.storage_workspace > 0
    error_message = "Workspace storage must be positive."
  }
}

# ============================================================================
# GPU CONFIGURATION
# ============================================================================

variable "gpu_count" {
  description = "Number of GPUs to configure (should match host hardware)"
  type        = number
  default     = 2
  validation {
    condition     = var.gpu_count > 0 && var.gpu_count <= 8
    error_message = "GPU count must be between 1 and 8."
  }
}

variable "gpu_model" {
  description = "GPU model name for documentation (e.g., A100, H100, RTX4090)"
  type        = string
  default     = "A100"
}

variable "cuda_version" {
  description = "CUDA Toolkit version to install (e.g., 12.4, 12.2)"
  type        = string
  default     = "12.4"
}

variable "cudnn_version" {
  description = "cuDNN version to install (e.g., 9.0, 8.9)"
  type        = string
  default     = "9.0"
}

variable "nvidia_driver_version" {
  description = "NVIDIA driver version (leave empty for latest compatible)"
  type        = string
  default     = ""
}

# ============================================================================
# DOCKER CONFIGURATION
# ============================================================================

variable "docker_version" {
  description = "Docker version to verify/install (leave empty for any version)"
  type        = string
  default     = ""
}

variable "docker_compose_version" {
  description = "Docker Compose version (v2 plugin or v1 standalone)"
  type        = string
  default     = "v2"
  validation {
    condition     = contains(["v1", "v2", "plugin"], var.docker_compose_version)
    error_message = "Docker Compose version must be v1, v2, or plugin."
  }
}

# ============================================================================
# OLLAMA CONFIGURATION
# ============================================================================

variable "ollama_models" {
  description = "List of Ollama models to document in deployment"
  type        = list(string)
  default     = ["llama2:70b-chat", "codegemma:latest", "mistral:latest"]
}

variable "ollama_num_gpu" {
  description = "Number of GPUs for Ollama (typically all available)"
  type        = number
  default     = 2
}

variable "ollama_keep_alive" {
  description = "How long to keep Ollama models in memory after use"
  type        = string
  default     = "24h"
}

# ============================================================================
# NETWORK & SECURITY
# ============================================================================

variable "domain_name" {
  description = "FQDN or local domain name for Code-Server (e.g., code-server-31.local)"
  type        = string
  default     = "code-server-31.local"
}

variable "tls_enabled" {
  description = "Enable TLS/HTTPS (recommended)"
  type        = bool
  default     = true
}

variable "allowed_ssh_ips" {
  description = "List of IPs allowed to SSH (empty = any)"
  type        = list(string)
  default     = []
}

# ============================================================================
# DEPLOYMENT BEHAVIOR
# ============================================================================

variable "skip_gpu_setup" {
  description = "Skip GPU driver/CUDA installation (if already done)"
  type        = bool
  default     = false
}

variable "skip_docker_setup" {
  description = "Skip Docker installation (if already present)"
  type        = bool
  default     = false
}

variable "skip_nas_mount" {
  description = "Skip NAS mount configuration (if already mounted)"
  type        = bool
  default     = false
}

variable "validation_timeout" {
  description = "Timeout for validation checks (seconds)"
  type        = number
  default     = 300
}

# ============================================================================
# DEPLOYMENT TAGS & METADATA
# ============================================================================

variable "deployment_name" {
  description = "Deployment identifier for resource naming"
  type        = string
  default     = "code-server-31"
}

variable "environment" {
  description = "Deployment environment (production, staging, development)"
  type        = string
  default     = "production"
  validation {
    condition     = contains(["production", "staging", "development"], var.environment)
    error_message = "Environment must be one of: production, staging, development."
  }
}

variable "tags" {
  description = "Common tags to apply to resources"
  type        = map(string)
  default = {
    Project     = "code-server-enterprise"
    Component   = "infrastructure"
    ManagedBy   = "Terraform"
    CreatedDate = "2026-04-13"
  }
}
