# Module Variables - P2 #418 Phase 3
# Unified variable definitions for all 5 infrastructure modules
# These variables are specific to module configuration and should override defaults in module calls

################################
# CLOUDFLARE & DNS VARIABLES
################################

variable "cloudflare_api_token" {
  description = "Cloudflare API token (Zone:Edit, DNS:Edit permissions required)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "cloudflare_account_id" {
  description = "Cloudflare account ID"
  type        = string
  sensitive   = true
  default     = ""
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID for apex domain"
  type        = string
  sensitive   = true
  default     = ""
}

variable "godaddy_api_key" {
  description = "GoDaddy API key for DNS failover operations"
  type        = string
  sensitive   = true
  default     = ""
}

variable "godaddy_api_secret" {
  description = "GoDaddy API secret"
  type        = string
  sensitive   = true
  default     = ""
}

variable "apex_domain" {
  description = "Apex domain (e.g., kushnir.cloud)"
  type        = string
  default     = "kushnir.cloud"
}

variable "tunnel_name" {
  description = "Cloudflare Tunnel name for on-prem connectivity"
  type        = string
  default     = "code-server-on-prem"
}

variable "primary_ip" {
  description = "Primary server IP address"
  type        = string
  default     = "192.168.168.31"
}

variable "secondary_ip" {
  description = "Secondary/failover server IP address"
  type        = string
  default     = "192.168.168.42"
}

variable "dns_ttl" {
  description = "DNS record TTL (seconds)"
  type        = number
  default     = 300
}

variable "dns_health_check_interval" {
  description = "DNS health check interval (seconds)"
  type        = number
  default     = 30
}

variable "dns_failover_threshold" {
  description = "Consecutive failed checks before DNS failover"
  type        = number
  default     = 3
}

################################
# MONITORING MODULE VARIABLES
################################

variable "monitoring_namespace" {
  description = "Kubernetes namespace for monitoring services"
  type        = string
  default     = "monitoring"
}

variable "prometheus_version" {
  description = "Prometheus version"
  type        = string
  default     = "v2.48.0"
}

variable "prometheus_storage_size" {
  description = "Prometheus persistent volume size"
  type        = string
  default     = "50Gi"
}

variable "prometheus_retention_days" {
  description = "Prometheus metric retention period (days)"
  type        = number
  default     = 30
}

variable "prometheus_scrape_interval" {
  description = "Prometheus scrape interval (seconds)"
  type        = number
  default     = 15
}

variable "grafana_version" {
  description = "Grafana version"
  type        = string
  default     = "10.2.3"
}

variable "grafana_admin_password" {
  description = "Grafana admin password"
  type        = string
  sensitive   = true
  default     = "admin123"  # CHANGE IN PRODUCTION
}

variable "grafana_storage_size" {
  description = "Grafana persistent volume size"
  type        = string
  default     = "10Gi"
}

variable "alertmanager_version" {
  description = "AlertManager version"
  type        = string
  default     = "v0.26.0"
}

variable "alertmanager_slack_webhook" {
  description = "Slack webhook URL for alert notifications"
  type        = string
  sensitive   = true
  default     = ""
}

variable "alertmanager_pagerduty_key" {
  description = "PagerDuty integration key"
  type        = string
  sensitive   = true
  default     = ""
}

variable "slo_error_budget_percentage" {
  description = "SLO error budget percentage (0.1 = 99.9% uptime)"
  type        = number
  default     = 0.1
}

################################
# NETWORKING MODULE VARIABLES
################################

variable "networking_namespace" {
  description = "Kubernetes namespace for networking services"
  type        = string
  default     = "networking"
}

variable "kong_version" {
  description = "Kong API Gateway version"
  type        = string
  default     = "3.4.0"
}

variable "kong_database_password" {
  description = "Kong PostgreSQL database password"
  type        = string
  sensitive   = true
  default     = "change-me"  # CHANGE IN PRODUCTION
}

variable "kong_storage_size" {
  description = "Kong persistent volume size"
  type        = string
  default     = "20Gi"
}

variable "coredns_version" {
  description = "CoreDNS version"
  type        = string
  default     = "1.10.1"
}

variable "coredns_config" {
  description = "CoreDNS configuration block"
  type        = string
  default     = "."
}

variable "load_balancer_algorithm" {
  description = "Load balancer algorithm (round_robin, least_connections, ip_hash)"
  type        = string
  default     = "round_robin"
}

variable "load_balancer_health_check_interval" {
  description = "Load balancer health check interval (seconds)"
  type        = number
  default     = 10
}

variable "service_upstream_timeout" {
  description = "Upstream service timeout (seconds)"
  type        = number
  default     = 60
}

variable "rate_limiting_requests_per_second" {
  description = "Rate limiting threshold (requests per second)"
  type        = number
  default     = 1000
}

################################
# SECURITY MODULE VARIABLES
################################

variable "security_namespace" {
  description = "Kubernetes namespace for security services"
  type        = string
  default     = "security"
}

variable "falco_version" {
  description = "Falco runtime security version"
  type        = string
  default     = "0.36.0"
}

variable "opa_version" {
  description = "OPA policy engine version"
  type        = string
  default     = "0.55.0"
}

variable "vault_version" {
  description = "HashiCorp Vault version"
  type        = string
  default     = "1.15.0"
}

variable "vault_storage_size" {
  description = "Vault persistent volume size"
  type        = string
  default     = "10Gi"
}

variable "vault_unseal_keys" {
  description = "Number of Vault unseal keys to generate"
  type        = number
  default     = 5
}

variable "vault_key_threshold" {
  description = "Number of keys required to unseal Vault"
  type        = number
  default     = 3
}

variable "os_hardening_level" {
  description = "OS hardening level (minimal, standard, strict)"
  type        = string
  default     = "standard"

  validation {
    condition     = contains(["minimal", "standard", "strict"], var.os_hardening_level)
    error_message = "Must be minimal, standard, or strict"
  }
}

variable "selinux_enabled" {
  description = "Enable SELinux enforcement"
  type        = bool
  default     = true
}

variable "auditd_enabled" {
  description = "Enable Linux audit daemon"
  type        = bool
  default     = true
}

variable "file_integrity_scan_interval" {
  description = "File integrity check interval (hours)"
  type        = number
  default     = 24
}

variable "vulnerability_scan_schedule" {
  description = "Vulnerability scan schedule (cron format)"
  type        = string
  default     = "0 2 * * *"
}

################################
# FAILOVER/HA MODULE VARIABLES
################################

variable "failover_namespace" {
  description = "Kubernetes namespace for failover/HA services"
  type        = string
  default     = "failover"
}

variable "patroni_version" {
  description = "Patroni cluster manager version"
  type        = string
  default     = "3.0.0"
}

variable "postgres_version" {
  description = "PostgreSQL version"
  type        = string
  default     = "15.3"
}

variable "postgres_storage_size" {
  description = "PostgreSQL persistent volume size"
  type        = string
  default     = "100Gi"
}

variable "etcd_version" {
  description = "etcd distributed consensus version"
  type        = string
  default     = "3.5.9"
}

variable "backup_retention_days" {
  description = "Backup retention period (days)"
  type        = number
  default     = 30
}

variable "backup_schedule" {
  description = "Backup schedule (cron format, default 2 AM UTC)"
  type        = string
  default     = "0 2 * * *"
}

variable "rpo_seconds" {
  description = "Recovery Point Objective in seconds (max data loss tolerance)"
  type        = number
  default     = 300  # 5 minutes
}

variable "rto_seconds" {
  description = "Recovery Time Objective in seconds (max downtime tolerance)"
  type        = number
  default     = 60   # 1 minute
}

variable "replication_slots" {
  description = "Number of PostgreSQL logical replication slots"
  type        = number
  default     = 3
}

variable "wal_level" {
  description = "PostgreSQL WAL level (replica, logical)"
  type        = string
  default     = "replica"

  validation {
    condition     = contains(["replica", "logical"], var.wal_level)
    error_message = "Must be replica or logical"
  }
}

variable "max_wal_senders" {
  description = "Maximum number of WAL senders"
  type        = number
  default     = 10
}

variable "s3_backup_bucket" {
  description = "S3 bucket for backup archival (optional)"
  type        = string
  default     = ""
}

variable "s3_backup_region" {
  description = "S3 region for backup bucket"
  type        = string
  default     = "us-east-1"
}

################################
# KUBERNETES/DOCKER PROVIDER VARIABLES
################################

variable "kubernetes_host" {
  description = "Kubernetes API server endpoint (leave blank to use kubeconfig)"
  type        = string
  default     = ""
}

variable "kubernetes_config_path" {
  description = "Path to kubeconfig file"
  type        = string
  default     = "~/.kube/config"
}

variable "kubernetes_client_certificate" {
  description = "Kubernetes client certificate"
  type        = string
  sensitive   = true
  default     = ""
}

variable "kubernetes_client_key" {
  description = "Kubernetes client key"
  type        = string
  sensitive   = true
  default     = ""
}

variable "kubernetes_cluster_ca_certificate" {
  description = "Kubernetes cluster CA certificate"
  type        = string
  sensitive   = true
  default     = ""
}

################################
# DEPLOYMENT ENVIRONMENT
################################

variable "deployment_environment" {
  description = "Deployment environment (dev, staging, production)"
  type        = string
  default     = "production"

  validation {
    condition     = contains(["dev", "staging", "production"], var.deployment_environment)
    error_message = "Must be dev, staging, or production"
  }
}
