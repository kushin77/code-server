################################################################################
# terraform/staging.tfvars
# Staging-specific configuration values (for testing Phase 7)
################################################################################

project_name = "kushin77-code-server-staging"
environment  = "staging"
region_count = 3  # Only 3 regions for staging (cost optimization)

regions = [
  {
    name         = "stg-region1-primary"
    ip_primary   = "192.168.169.31"  # Different network for staging
    ip_secondary = "192.168.169.141"
    role         = "primary"
  },
  {
    name         = "stg-region2-failover1"
    ip_primary   = "192.168.169.32"
    ip_secondary = "192.168.169.142"
    role         = "failover"
  },
  {
    name         = "stg-region3-failover2"
    ip_primary   = "192.168.169.33"
    ip_secondary = "192.168.169.143"
    role         = "failover"
  }
]

nas_primary_ip   = "192.168.169.56"
nas_replica_ip   = "192.168.169.57"
load_balancer_ip = "192.168.169.100"

dns_servers = ["192.168.169.10"]  # Single DNS for staging

slo_targets = {
  availability     = 99.9   # Relaxed for staging
  p99_latency_ms   = 150
  error_rate       = 0.5
}

# Network configuration
network_config = {
  base_cidr           = "192.168.169.0/24"
  public_subnet_mask  = "/25"
  private_subnet_mask = "/26"
}

# Compute specifications (smaller for staging)
compute_specs = {
  vcpu       = 2
  memory_gb  = 8
  storage_gb = 100
}

# Database replication (staging: standard)
postgres_replication_config = {
  primary_ip             = "192.168.169.31"
  replica_ips            = ["192.168.169.32", "192.168.169.33"]
  replication_user       = "replicator"
  replication_password   = "OVERRIDE_IN_ENV_VARS"
  port                   = 5432
  max_wal_senders        = 5
  max_replication_slots  = 5
  wal_level              = "replica"
  synchronous_commit     = "on"  # Semi-synchronous for staging
}

# Database backup (staging: daily)
postgres_backup_config = {
  backup_frequency_hours = 24
  retention_days         = 7
  compression            = "gzip"
  backup_location        = "/mnt/nas-169/postgres-backups"
}

# DNS configuration (staging: longer TTL for testing)
dns_config = {
  base_domain             = "code-server-staging.internal"
  load_balancer_ip        = "192.168.169.100"
  health_check_port       = 9090
  health_check_interval_s = 30
  failover_threshold      = 5
  ttl                     = 60  # Longer TTL for staging
}
