# Phase 6: Variables for Application Platform (code-server)

variable "namespace_code_server" {
  type        = string
  description = "Kubernetes namespace for code-server platform"
  default     = "code-server"
}

variable "environment" {
  type        = string
  description = "Environment name for labels"
  default     = "production"
}

variable "enable_code_server" {
  type        = bool
  description = "Enable code-server deployment"
  default     = true
}

variable "code_server_image" {
  type        = string
  description = "code-server container image repository"
  default     = "codercom/code-server"
}

variable "code_server_version" {
  type        = string
  description = "code-server container image version/tag"
  default     = "4.28.1"
  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+(-.+)?$", var.code_server_version))
    error_message = "code_server_version must be a valid semantic version (e.g., 4.28.1 or 4.28.1-ubuntu)"
  }
}

variable "code_server_replicas" {
  type        = number
  description = "Number of code-server replicas (StatefulSet)"
  default     = 2
  validation {
    condition     = var.code_server_replicas >= 1 && var.code_server_replicas <= 10
    error_message = "code_server_replicas must be between 1 and 10"
  }
}

variable "code_server_workspace_size" {
  type        = string
  description = "Persistent volume size for workspace data per replica"
  default     = "100Gi"
}

variable "code_server_password" {
  type        = string
  description = "Password for code-server authentication"
  sensitive   = true
  default     = "ChangeMe123!"
  validation {
    condition     = length(var.code_server_password) >= 8
    error_message = "code_server_password must be at least 8 characters"
  }
}

variable "code_server_requests" {
  type = object({
    cpu    = string
    memory = string
  })
  description = "code-server resource requests"
  default = {
    cpu    = "1000m"
    memory = "2Gi"
  }
}

variable "code_server_limits" {
  type = object({
    cpu    = string
    memory = string
  })
  description = "code-server resource limits"
  default = {
    cpu    = "2000m"
    memory = "4Gi"
  }
}

variable "code_server_extensions" {
  type        = list(string)
  description = "VS Code extensions to pre-install"
  default = [
    "GitHub.github-vscode-theme",
    "ms-python.python",
    "golang.Go",
    "rust-lang.rust-analyzer",
    "hashicorp.terraform",
    "ms-azuretools.vscode-docker",
    "ms-kubernetes-tools.vscode-kubernetes-tools",
    "eamodio.gitlens",
    "GitLab.gitlab-workflow",
    "redhat.yaml",
    "ms-vscode.makefile-tools",
    "charliermarsh.ruff"
  ]
}

variable "ingress_domain" {
  type        = string
  description = "Domain for ingress access (if configured)"
  default     = "cluster.local"
}

variable "create_code_server_settings" {
  type        = bool
  description = "Create code-server settings ConfigMap"
  default     = true
}

variable "create_code_server_extensions" {
  type        = bool
  description = "Create code-server extensions ConfigMap"
  default     = true
}

variable "create_code_server_secret" {
  type        = bool
  description = "Create code-server authentication secret"
  default     = true
}
