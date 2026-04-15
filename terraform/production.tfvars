################################################################################
# terraform/production.tfvars
# Production-specific configuration values
# Source: config/_base-config.env (override hierarchy)
################################################################################

project_name = "kushin77-code-server"
environment  = "production"
region_count = 5

regions = [
  {
    name         = "region1-primary"
    ip_primary   = "192.168.168.31"
    ip_secondary = "192.168.168.141"
    role         = "primary"
  },
  {
    name         = "region2-failover1"
    ip_primary   = "192.168.168.32"
    ip_secondary = "192.168.168.142"
    role         = "failover"
  },
  {
    name         = "region3-failover2"
    ip_primary   = "192.168.168.33"
    ip_secondary = "192.168.168.143"
    role         = "failover"
  },
  {
    name         = "region4-failover3"
    ip_primary   = "192.168.168.34"
    ip_secondary = "192.168.168.144"
    role         = "failover"
  },
  {
    name         = "region5-standby"
    ip_primary   = "192.168.168.35"
    ip_secondary = "192.168.168.145"
    role         = "standby"
  }
]

nas_primary_ip   = "192.168.168.56"
nas_replica_ip   = "192.168.168.57"
load_balancer_ip = "192.168.168.100"

dns_servers = ["192.168.168.10", "192.168.168.11"]

slo_targets = {
  availability   = 99.99
  p99_latency_ms = 100
  error_rate     = 0.1
}

# Network configuration
network_config = {
  base_cidr           = "192.168.168.0/24"
  public_subnet_mask  = "/25"
  private_subnet_mask = "/26"
}

# Compute specifications
compute_specs = {
  vcpu       = 4
  memory_gb  = 16
  storage_gb = 200
}

# Database replication (production: strict)
postgres_replication_config = {
  primary_ip            = "192.168.168.31"
  replica_ips           = ["192.168.168.32", "192.168.168.33", "192.168.168.34"]
  replication_user      = "replicator"
  replication_password  = "OVERRIDE_IN_ENV_VARS" # NEVER hardcode in tfvars
  port                  = 5432
  max_wal_senders       = 10
  max_replication_slots = 10
  wal_level             = "replica"
  synchronous_commit    = "remote_apply" # Synchronous for zero data loss
}

# Database backup (production: aggressive retention)
postgres_backup_config = {
  backup_frequency_hours = 4
  retention_days         = 30
  compression            = "gzip"
  backup_location        = "/mnt/nas-56/postgres-backups"
}

# DNS configuration (production: short TTL for fast failover)
dns_config = {
  base_domain             = "code-server.internal"
  load_balancer_ip        = "192.168.168.100"
  health_check_port       = 9090
  health_check_interval_s = 10
  failover_threshold      = 3
  ttl                     = 10 # Short TTL for quick failover
}
