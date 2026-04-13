# Kubeconfig configuration
variable "kubeconfig_path" {
  description = "Path to kubeconfig file"
  type        = string
  default     = "~/.kube/config"
}

variable "kubeconfig_context" {
  description = "Kubernetes context to use"
  type        = string
  default     = "kubernetes-admin@kubernetes"
}

# Cluster configuration
variable "cluster_name" {
  description = "Name of the Kubernetes cluster"
  type        = string
  default     = "code-server-enterprise"
}

variable "cluster_version" {
  description = "Kubernetes version to deploy"
  type        = string
  default     = "1.27.0"
}

# Network configuration
variable "pod_cidr" {
  description = "Pod CIDR range"
  type        = string
  default     = "10.244.0.0/16"
}

variable "service_cidr" {
  description = "Service CIDR range"
  type        = string
  default     = "10.96.0.0/12"
}

variable "control_plane_endpoint" {
  description = "Control plane endpoint"
  type        = string
  default     = "k8s-api-lb:6443"
}

# Namespace configuration
variable "namespace_monitoring" {
  description = "Monitoring namespace"
  type        = string
  default     = "monitoring"
}

variable "namespace_security" {
  description = "Security namespace"
  type        = string
  default     = "security"
}

variable "namespace_backup" {
  description = "Backup namespace"
  type        = string
  default     = "backup-system"
}

variable "namespace_code_server" {
  description = "code-server namespace"
  type        = string
  default     = "code-server"
}

variable "namespace_ingress" {
  description = "Ingress namespace"
  type        = string
  default     = "ingress-nginx"
}

variable "namespace_cert_manager" {
  description = "Cert-manager namespace"
  type        = string
  default     = "cert-manager"
}

# Storage configuration
variable "storage_class_name" {
  description = "Storage class name"
  type        = string
  default     = "local-storage"
}

variable "prometheus_storage_size" {
  description = "Prometheus storage size in Gi"
  type        = number
  default     = 50
}

variable "loki_storage_size" {
  description = "Loki storage size in Gi"
  type        = number
  default     = 20
}

variable "code_server_workspace_size" {
  description = "code-server workspace size in Gi"
  type        = number
  default     = 100
}

variable "code_server_config_size" {
  description = "code-server config size in Gi"
  type        = number
  default     = 10
}

variable "velero_storage_size" {
  description = "Velero backup storage size in Gi"
  type        = number
  default     = 500
}

# Replication configuration
variable "prometheus_replicas" {
  description = "Number of Prometheus replicas"
  type        = number
  default     = 2
}

variable "grafana_replicas" {
  description = "Number of Grafana replicas"
  type        = number
  default     = 2
}

variable "loki_replicas" {
  description = "Number of Loki replicas"
  type        = number
  default     = 2
}

variable "alertmanager_replicas" {
  description = "Number of AlertManager replicas"
  type        = number
  default     = 2
}

variable "velero_replicas" {
  description = "Number of Velero replicas"
  type        = number
  default     = 2
}

# Resource request/limit configuration
variable "prometheus_requests" {
  description = "Prometheus resource requests"
  type = object({
    cpu    = string
    memory = string
  })
  default = {
    cpu    = "500m"
    memory = "2Gi"
  }
}

variable "prometheus_limits" {
  description = "Prometheus resource limits"
  type = object({
    cpu    = string
    memory = string
  })
  default = {
    cpu    = "2000m"
    memory = "4Gi"
  }
}

variable "grafana_requests" {
  description = "Grafana resource requests"
  type = object({
    cpu    = string
    memory = string
  })
  default = {
    cpu    = "250m"
    memory = "512Mi"
  }
}

variable "grafana_limits" {
  description = "Grafana resource limits"
  type = object({
    cpu    = string
    memory = string
  })
  default = {
    cpu    = "1000m"
    memory = "2Gi"
  }
}

variable "loki_requests" {
  description = "Loki resource requests"
  type = object({
    cpu    = string
    memory = string
  })
  default = {
    cpu    = "250m"
    memory = "512Mi"
  }
}

variable "loki_limits" {
  description = "Loki resource limits"
  type = object({
    cpu    = string
    memory = string
  })
  default = {
    cpu    = "1000m"
    memory = "2Gi"
  }
}

variable "code_server_requests" {
  description = "code-server resource requests"
  type = object({
    cpu    = string
    memory = string
  })
  default = {
    cpu    = "1000m"
    memory = "2Gi"
  }
}

variable "code_server_limits" {
  description = "code-server resource limits"
  type = object({
    cpu    = string
    memory = string
  })
  default = {
    cpu    = "4000m"
    memory = "8Gi"
  }
}

# Credential configuration
variable "grafana_admin_password" {
  description = "Initial Grafana admin password (CHANGE IN PRODUCTION)"
  type        = string
  sensitive   = true
  default     = "ChangeMe@123456789"
}

variable "code_server_password" {
  description = "Initial code-server password (CHANGE IN PRODUCTION)"
  type        = string
  sensitive   = true
  default     = "ChangeMe@123456789"
}

# Domain configuration
variable "domain" {
  description = "Base domain for ingress"
  type        = string
  default     = "enterprise.local"
}

variable "code_server_hostname" {
  description = "code-server hostname"
  type        = string
  default     = "code-server.enterprise.local"
}

variable "monitoring_hostname" {
  description = "Monitoring hostname"
  type        = string
  default     = "monitoring.enterprise.local"
}

variable "logs_hostname" {
  description = "Logs hostname"
  type        = string
  default     = "logs.enterprise.local"
}

# Tags and labels
variable "common_tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default = {
    Environment = "production"
    Managed     = "terraform"
    Version     = "1.0.0"
  }
}

variable "enable_monitoring" {
  description = "Enable monitoring stack"
  type        = bool
  default     = true
}

variable "enable_backup" {
  description = "Enable backup system"
  type        = bool
  default     = true
}

variable "enable_ingress" {
  description = "Enable ingress controller"
  type        = bool
  default     = true
}

variable "enable_code_server" {
  description = "Enable code-server"
  type        = bool
  default     = true
}

# code-server configuration
variable "code_server_version" {
  description = "code-server container version"
  type        = string
  default     = "4.28.1"
}

variable "code_server_replicas" {
  description = "Number of code-server replicas"
  type        = number
  default     = 2
}

variable "code_server_extensions" {
  description = "VS Code extensions to pre-install"
  type        = list(string)
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

# Ingress configuration
variable "grafana_hostname" {
  description = "Grafana ingress hostname"
  type        = string
  default     = "grafana.enterprise.local"
}

variable "prometheus_hostname" {
  description = "Prometheus ingress hostname"
  type        = string
  default     = "prometheus.enterprise.local"
}

variable "certmanager_email" {
  description = "Email for Let's Encrypt certificate notifications"
  type        = string
  default     = "admin@enterprise.local"
}

# Verification configuration
variable "namespaces_to_verify" {
  description = "Namespaces to include in verification checks"
  type        = list(string)
  default = [
    "monitoring",
    "security",
    "backup",
    "code-server",
    "ingress-nginx",
    "cert-manager",
    "kube-system",
    "default"
  ]
}

# State management
variable "terraform_state_file" {
  description = "Terraform state file location"
  type        = string
  default     = "terraform.tfstate"
}

variable "terraform_state_backup" {
  description = "Terraform state backup file location"
  type        = string
  default     = "terraform.tfstate.backup"
}

# ===== PHASE 10: ON-PREMISES OPTIMIZATION =====

variable "cluster_node_count" {
  description = "Number of nodes in on-premises cluster"
  type        = number
  default     = 3
}

variable "code_server_hpa_max" {
  description = "Maximum number of code-server replicas (HPA)"
  type        = number
  default     = 10
}
