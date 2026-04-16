
// ═══════════════════════════════════════════════════════════════════════════
// NEW MONITORING MODULE VARIABLES (Prometheus, Grafana, Loki, Jaeger, AlertManager)
// ═══════════════════════════════════════════════════════════════════════════

variable "prometheus_version" {
  description = "Prometheus version"
  type        = string
  default     = "v2.48.0"
}

variable "prometheus_port" {
  description = "Prometheus metrics port"
  type        = number
  default     = 9090
}

variable "prometheus_retention" {
  description = "Prometheus data retention period"
  type        = string
  default     = "30d"
}

variable "prometheus_memory_limit" {
  description = "Prometheus container memory limit"
  type        = string
  default     = "2g"
}

variable "prometheus_cpu_limit" {
  description = "Prometheus container CPU limit"
  type        = string
  default     = "1.0"
}

variable "grafana_version" {
  description = "Grafana version"
  type        = string
  default     = "10.2.3"
}

variable "grafana_port" {
  description = "Grafana HTTP port"
  type        = number
  default     = 3000
}

variable "grafana_admin_user" {
  description = "Grafana admin username"
  type        = string
  default     = "admin"
}

variable "grafana_memory_limit" {
  description = "Grafana container memory limit"
  type        = string
  default     = "512m"
}

variable "grafana_cpu_limit" {
  description = "Grafana container CPU limit"
  type        = string
  default     = "0.5"
}

variable "alertmanager_version" {
  description = "AlertManager version"
  type        = string
  default     = "v0.26.0"
}

variable "alertmanager_port" {
  description = "AlertManager port"
  type        = number
  default     = 9093
}

variable "alertmanager_memory_limit" {
  description = "AlertManager container memory limit"
  type        = string
  default     = "256m"
}

variable "alertmanager_cpu_limit" {
  description = "AlertManager container CPU limit"
  type        = string
  default     = "0.25"
}

variable "loki_version" {
  description = "Loki log aggregation version"
  type        = string
  default     = "2.9.5"
}

variable "loki_port" {
  description = "Loki port"
  type        = number
  default     = 3100
}

variable "loki_memory_limit" {
  description = "Loki container memory limit"
  type        = string
  default     = "1g"
}

variable "loki_cpu_limit" {
  description = "Loki container CPU limit"
  type        = string
  default     = "0.5"
}

variable "jaeger_version" {
  description = "Jaeger distributed tracing version"
  type        = string
  default     = "1.50"
}

variable "jaeger_port" {
  description = "Jaeger UI port"
  type        = number
  default     = 16686
}

variable "jaeger_otlp_port" {
  description = "Jaeger OTLP receiver port"
  type        = number
  default     = 4317
}

variable "jaeger_memory_limit" {
  description = "Jaeger container memory limit"
  type        = string
  default     = "1g"
}

variable "jaeger_cpu_limit" {
  description = "Jaeger container CPU limit"
  type        = string
  default     = "0.5"
}

variable "slo_target_availability" {
  description = "Service availability SLO target (percentage)"
  type        = number
  default     = 99.9
}

variable "slo_target_latency_p99" {
  description = "Service latency P99 SLO target (milliseconds)"
  type        = number
  default     = 500
}

variable "slo_target_error_rate" {
  description = "Service error rate SLO target (percentage)"
  type        = number
  default     = 0.1
}

variable "alert_severity_critical_enabled" {
  description = "Enable critical severity alerts"
  type        = bool
  default     = true
}

variable "alert_severity_high_enabled" {
  description = "Enable high severity alerts"
  type        = bool
  default     = true
}

variable "alert_severity_medium_enabled" {
  description = "Enable medium severity alerts"
  type        = bool
  default     = true
}

// ═══════════════════════════════════════════════════════════════════════════
// NEW NETWORKING MODULE VARIABLES (Kong, CoreDNS)
// ═══════════════════════════════════════════════════════════════════════════

variable "kong_version" {
  description = "Kong API Gateway version"
  type        = string
  default     = "3.4.0-alpine"
}

variable "kong_proxy_port" {
  description = "Kong proxy HTTP port"
  type        = number
  default     = 8000
}

variable "kong_proxy_ssl_port" {
  description = "Kong proxy HTTPS port"
  type        = number
  default     = 8443
}

variable "kong_admin_port" {
  description = "Kong admin API port (loopback only)"
  type        = number
  default     = 8001
}

variable "kong_memory_limit" {
  description = "Kong container memory limit"
  type        = string
  default     = "512m"
}

variable "kong_cpu_limit" {
  description = "Kong container CPU limit"
  type        = string
  default     = "0.5"
}

variable "kong_rate_limit_minute" {
  description = "Kong global rate limit (requests per minute)"
  type        = number
  default     = 60
}

variable "kong_rate_limit_hour" {
  description = "Kong global rate limit (requests per hour)"
  type        = number
  default     = 1000
}

variable "kong_rate_limit_auth_minute" {
  description = "Kong rate limit on auth endpoints (requests per minute)"
  type        = number
  default     = 10
}

variable "coredns_version" {
  description = "CoreDNS version"
  type        = string
  default     = "1.10.1"
}

variable "coredns_port" {
  description = "CoreDNS DNS port"
  type        = number
  default     = 53
}

variable "coredns_memory_limit" {
  description = "CoreDNS container memory limit"
  type        = string
  default     = "128m"
}

variable "coredns_cpu_limit" {
  description = "CoreDNS container CPU limit"
  type        = string
  default     = "0.25"
}

variable "enable_tls_termination" {
  description = "Enable TLS termination on Caddy"
  type        = bool
  default     = true
}

variable "enable_rate_limiting" {
  description = "Enable Kong rate limiting"
  type        = bool
  default     = true
}

variable "enable_service_discovery" {
  description = "Enable CoreDNS service discovery"
  type        = bool
  default     = true
}

variable "load_balancing_algorithm" {
  description = "Load balancing algorithm (round_robin/least_conn/random/ip_hash)"
  type        = string
  default     = "round_robin"
}

// ═══════════════════════════════════════════════════════════════════════════
// NEW SECURITY MODULE VARIABLES (Falco, OPA)
// ═══════════════════════════════════════════════════════════════════════════

variable "falco_version" {
  description = "Falco runtime security engine version"
  type        = string
  default     = "0.37.1"
}

variable "falco_mode" {
  description = "Falco execution mode (modern-bpf/legacy)"
  type        = string
  default     = "modern-bpf"
}

variable "falco_memory_limit" {
  description = "Falco container memory limit"
  type        = string
  default     = "512m"
}

variable "falco_cpu_limit" {
  description = "Falco container CPU limit"
  type        = string
  default     = "0.5"
}

variable "opa_version" {
  description = "Open Policy Agent version"
  type        = string
  default     = "0.58.0"
}

variable "opa_port" {
  description = "OPA HTTP port"
  type        = number
  default     = 8181
}

variable "opa_memory_limit" {
  description = "OPA container memory limit"
  type        = string
  default     = "256m"
}

variable "opa_cpu_limit" {
  description = "OPA container CPU limit"
  type        = string
  default     = "0.25"
}

variable "enable_apparmor" {
  description = "Enable AppArmor security profiles"
  type        = bool
  default     = true
}

variable "enable_seccomp" {
  description = "Enable seccomp system call filtering"
  type        = bool
  default     = true
}

variable "enable_selinux" {
  description = "Enable SELinux (if available on OS)"
  type        = bool
  default     = false
}

variable "enable_runtime_monitoring" {
  description = "Enable Falco runtime security monitoring"
  type        = bool
  default     = true
}

variable "enable_policy_enforcement" {
  description = "Enable OPA policy enforcement"
  type        = bool
  default     = true
}

variable "enable_secret_management" {
  description = "Enable Vault secret management"
  type        = bool
  default     = true
}

variable "audit_log_retention_days" {
  description = "Security audit log retention (days)"
  type        = number
  default     = 90
}

variable "vulnerability_scan_enabled" {
  description = "Enable automated vulnerability scanning"
  type        = bool
  default     = true
}

variable "container_image_scan_enabled" {
  description = "Enable container image scanning"
  type        = bool
  default     = true
}

// ═══════════════════════════════════════════════════════════════════════════
// NEW DNS MODULE VARIABLES (CloudFlare, GoDaddy DNS Failover)
// ═══════════════════════════════════════════════════════════════════════════

variable "cloudflare_enabled" {
  description = "Enable Cloudflare tunnel and CDN"
  type        = bool
  default     = true
}

variable "cloudflare_dns_proxy_enabled" {
  description = "Enable Cloudflare DNS proxy (orange cloud)"
  type        = bool
  default     = true
}

variable "cloudflare_waf_enabled" {
  description = "Enable Cloudflare WAF"
  type        = bool
  default     = true
}

variable "godaddy_enabled" {
  description = "Enable GoDaddy DNS failover"
  type        = bool
  default     = true
}

variable "godaddy_api_key" {
  description = "GoDaddy API key"
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

variable "domain_primary" {
  description = "Primary domain name"
  type        = string
  default     = "kushnir.cloud"
}

variable "domain_secondary" {
  description = "Secondary domain for failover"
  type        = string
  default     = "code-server.kushnir.cloud"
}

variable "dns_ttl_default" {
  description = "Default DNS TTL (seconds)"
  type        = number
  default     = 300
}

variable "dns_ttl_short" {
  description = "Short DNS TTL for failover (seconds)"
  type        = number
  default     = 60
}

variable "dns_failover_enabled" {
  description = "Enable automatic DNS failover"
  type        = bool
  default     = true
}

variable "dns_failover_health_check_interval" {
  description = "DNS failover health check interval (seconds)"
  type        = number
  default     = 30
}

variable "dns_failover_threshold" {
  description = "Failed checks before failover"
  type        = number
  default     = 3
}

variable "acme_provider" {
  description = "ACME TLS certificate provider (letsencrypt/zerossl)"
  type        = string
  default     = "letsencrypt"
}

variable "enable_dns_dnssec" {
  description = "Enable DNSSEC signing"
  type        = bool
  default     = true
}

variable "enable_dns_rate_limiting" {
  description = "Enable DNS query rate limiting"
  type        = bool
  default     = true
}

// ═══════════════════════════════════════════════════════════════════════════
// NEW FAILOVER MODULE VARIABLES (Patroni, Replication, Backup, DR)
// ═══════════════════════════════════════════════════════════════════════════

variable "patroni_enabled" {
  description = "Enable Patroni for PostgreSQL HA"
  type        = bool
  default     = true
}

variable "patroni_version" {
  description = "Patroni version"
  type        = string
  default     = "3.0"
}

variable "replication_slot_enabled" {
  description = "Enable PostgreSQL replication slots"
  type        = bool
  default     = true
}

variable "replication_slot_name" {
  description = "Replication slot name"
  type        = string
  default     = "replica_slot"
}

variable "wal_level" {
  description = "PostgreSQL WAL level (minimal/replica/logical)"
  type        = string
  default     = "replica"
}

variable "max_wal_senders" {
  description = "Maximum WAL sender connections"
  type        = number
  default     = 10
}

variable "wal_keep_size" {
  description = "WAL segments to keep (GB)"
  type        = number
  default     = 10
}

variable "hot_standby_enabled_failover" {
  description = "Enable hot standby mode on replica"
  type        = bool
  default     = true
}

variable "synchronous_replica_count" {
  description = "Number of replicas to wait for in sync replication"
  type        = number
  default     = 1
}

variable "backup_method" {
  description = "Backup method (pg_basebackup/pgbackrest/wal-g)"
  type        = string
  default     = "pg_basebackup"
}

variable "backup_compression_enabled" {
  description = "Enable backup compression"
  type        = bool
  default     = true
}

variable "point_in_time_recovery_days" {
  description = "Point-in-time recovery window (days)"
  type        = number
  default     = 7
}

variable "redis_sentinel_enabled" {
  description = "Enable Redis Sentinel for HA"
  type        = bool
  default     = true
}

variable "redis_sentinel_port" {
  description = "Redis Sentinel port"
  type        = number
  default     = 26379
}

variable "redis_sentinel_quorum" {
  description = "Sentinel quorum size"
  type        = number
  default     = 2
}

variable "redis_sentinel_down_after_ms" {
  description = "Sentinel marks replica down after (ms)"
  type        = number
  default     = 30000
}

variable "disaster_recovery_enabled" {
  description = "Enable disaster recovery procedures"
  type        = bool
  default     = true
}

variable "rto_target_minutes" {
  description = "Recovery Time Objective (minutes)"
  type        = number
  default     = 15
}

variable "rpo_target_seconds" {
  description = "Recovery Point Objective (seconds)"
  type        = number
  default     = 60
}

variable "backup_storage_backend" {
  description = "Backup storage (local/s3/minio)"
  type        = string
  default     = "minio"
}

variable "enable_cross_region_replication" {
  description = "Enable cross-region backup replication"
  type        = bool
  default     = false
}

variable "failover_auto_enabled" {
  description = "Enable automatic failover"
  type        = bool
  default     = true
}

variable "failover_timeout_seconds" {
  description = "Failover timeout (seconds)"
  type        = number
  default     = 300
}
