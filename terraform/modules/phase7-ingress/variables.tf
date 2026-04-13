# Phase 7: Variables for Ingress & Load Balancing

variable "namespace_ingress" {
  type        = string
  description = "Kubernetes namespace for ingress controller"
  default     = "ingress-nginx"
}

variable "namespace_cert_manager" {
  type        = string
  description = "Kubernetes namespace for cert-manager"
  default     = "cert-manager"
}

variable "namespace_monitoring" {
  type        = string
  description = "Kubernetes namespace for monitoring (for ingress rules)"
  default     = "monitoring"
}

variable "namespace_code_server" {
  type        = string
  description = "Kubernetes namespace for code-server (for ingress rules)"
  default     = "code-server"
}

variable "environment" {
  type        = string
  description = "Environment name for labels"
  default     = "production"
}

# ===== INGRESS CONTROLLER =====

variable "enable_ingress_controller" {
  type        = bool
  description = "Enable NGINX Ingress Controller deployment"
  default     = true
}

variable "ingress_nginx_chart_version" {
  type        = string
  description = "NGINX Ingress Controller Helm chart version"
  default     = "4.9.1"
}

variable "ingress_http_nodeport" {
  type        = number
  description = "NodePort for HTTP traffic"
  default     = 30080
  validation {
    condition     = var.ingress_http_nodeport >= 30000 && var.ingress_http_nodeport <= 32767
    error_message = "NodePort must be between 30000 and 32767"
  }
}

variable "ingress_https_nodeport" {
  type        = number
  description = "NodePort for HTTPS traffic"
  default     = 30443
  validation {
    condition     = var.ingress_https_nodeport >= 30000 && var.ingress_https_nodeport <= 32767
    error_message = "NodePort must be between 30000 and 32767"
  }
}

variable "ingress_default_class" {
  type        = bool
  description = "Make nginx the default ingress class"
  default     = true
}

variable "ingress_requests" {
  type = object({
    cpu    = string
    memory = string
  })
  description = "NGINX Ingress Controller resource requests"
  default = {
    cpu    = "500m"
    memory = "512Mi"
  }
}

variable "ingress_limits" {
  type = object({
    cpu    = string
    memory = string
  })
  description = "NGINX Ingress Controller resource limits"
  default = {
    cpu    = "1000m"
    memory = "1Gi"
  }
}

variable "enable_ingress_autoscaling" {
  type        = bool
  description = "Enable HPA for NGINX Ingress Controller"
  default     = false
}

variable "enable_modsecurity" {
  type        = bool
  description = "Enable ModSecurity and OWASP Core Rules"
  default     = true
}

# ===== CERT-MANAGER =====

variable "enable_cert_manager" {
  type        = bool
  description = "Enable cert-manager for SSL/TLS certificate management"
  default     = true
}

variable "cert_manager_chart_version" {
  type        = string
  description = "cert-manager Helm chart version"
  default     = "v1.13.2"
}

variable "cert_manager_requests" {
  type = object({
    cpu    = string
    memory = string
  })
  description = "cert-manager resource requests"
  default = {
    cpu    = "100m"
    memory = "128Mi"
  }
}

variable "cert_manager_limits" {
  type = object({
    cpu    = string
    memory = string
  })
  description = "cert-manager resource limits"
  default = {
    cpu    = "500m"
    memory = "512Mi"
  }
}

variable "enable_letsencrypt_staging" {
  type        = bool
  description = "Create Let's Encrypt staging issuer for certificate testing"
  default     = true
}

variable "enable_letsencrypt_production" {
  type        = bool
  description = "Create Let's Encrypt production issuer for real certificates"
  default     = true
}

variable "certmanager_email" {
  type        = string
  description = "Email address for Let's Encrypt certificate notifications"
  default     = "admin@cluster.local"
}

# ===== INGRESS RULES =====

variable "cert_issuer_name" {
  type        = string
  description = "Name of the ClusterIssuer to use for TLS certificates"
  default     = "letsencrypt-prod"
}

variable "enable_grafana_ingress" {
  type        = bool
  description = "Create Ingress rule for Grafana"
  default     = true
}

variable "grafana_hostname" {
  type        = string
  description = "Hostname for Grafana access"
  default     = "grafana.cluster.local"
}

variable "enable_prometheus_ingress" {
  type        = bool
  description = "Create Ingress rule for Prometheus"
  default     = true
}

variable "prometheus_hostname" {
  type        = string
  description = "Hostname for Prometheus access"
  default     = "prometheus.cluster.local"
}

variable "enable_code_server_ingress" {
  type        = bool
  description = "Create Ingress rule for code-server"
  default     = true
}

variable "code_server_hostname" {
  type        = string
  description = "Hostname for code-server IDE access"
  default     = "code-server.cluster.local"
}
