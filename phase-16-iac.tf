################################################################################
# Phase 16: Database High Availability & Load Balancing
# Components: PostgreSQL HA, pgBouncer, HAProxy, Keepalived
# Properties: Immutable, Independent, IaC-driven
################################################################################

terraform {
  required_version = ">= 1.0"
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}

variable "phase_16_environment" {
  description = "Environment identifier"
  type        = string
  default     = "phase-16-db-ha"
}

variable "postgresql_replicas" {
  description = "Number of PostgreSQL replicas"
  type        = number
  default     = 3
}

variable "db_max_connections" {
  description = "Maximum database connections"
  type        = number
  default     = 500
}

variable "ha_vip" {
  description = "Virtual IP for HA failover"
  type        = string
  default     = "192.168.168.100"
}

################################################################################
# PostgreSQL Primary - HA-Ready
################################################################################

resource "docker_image" "postgres_ha" {
  name         = "postgres:15-alpine"
  keep_locally = true
}

resource "docker_container" "postgres_primary" {
  name    = "postgres-primary-ha"
  image   = docker_image.postgres_ha.image_id
  restart = "unless-stopped"
  
  ports {
    internal = 5432
    external = 5432
  }
  
  env = [
    "POSTGRES_DB=code_server_db",
    "POSTGRES_USER=db_admin",
    "POSTGRES_PASSWORD=SecureHashPassword123!",
    "POSTGRES_INITDB_ARGS=-c max_connections=${var.db_max_connections} -c wal_level=replica -c max_wal_senders=10 -c max_replication_slots=10"
  ]
  
  volumes {
    host_path      = "/tmp/postgres-primary"
    container_path = "/var/lib/postgresql/data"
    read_only      = false
  }
  
  labels {
    key   = "phase"
    value = "16"
  }
  labels {
    key   = "component"
    value = "database-ha"
  }
  labels {
    key   = "role"
    value = "primary"
  }
  labels {
    key   = "environment"
    value = var.phase_16_environment
  }
  
  healthcheck {
    test     = ["CMD-SHELL", "pg_isready -U db_admin"]
    interval = "10s"
    timeout  = "5s"
    retries  = 5
  }
}

################################################################################
# PostgreSQL Replica 1
################################################################################

resource "docker_container" "postgres_replica_1" {
  name    = "postgres-replica-1-ha"
  image   = docker_image.postgres_ha.image_id
  restart = "unless-stopped"
  
  ports {
    internal = 5432
    external = 5433
  }
  
  env = [
    "PGUSER=replicator",
    "PGPASSWORD=ReplicatorPass123!",
    "POSTGRES_INITDB_ARGS=-c max_connections=${var.db_max_connections}"
  ]
  
  volumes {
    host_path      = "/tmp/postgres-replica-1"
    container_path = "/var/lib/postgresql/data"
    read_only      = false
  }
  
  labels = {
    phase       = "16"
    component   = "database-ha"
    role        = "replica"
    environment = var.phase_16_environment
  }
  
  healthcheck {
    test     = ["CMD-SHELL", "pg_isready -U replicator -h localhost"]
    interval = "10s"
    timeout  = "5s"
    retries  = 5
  }
}

################################################################################
# PostgreSQL Replica 2
################################################################################

resource "docker_container" "postgres_replica_2" {
  name    = "postgres-replica-2-ha"
  image   = docker_image.postgres_ha.image_id
  restart = "unless-stopped"
  
  ports {
    internal = 5432
    external = 5434
  }
  
  env = [
    "PGUSER=replicator",
    "PGPASSWORD=ReplicatorPass123!",
    "POSTGRES_INITDB_ARGS=-c max_connections=${var.db_max_connections}"
  ]
  
  volumes {
    host_path      = "/tmp/postgres-replica-2"
    container_path = "/var/lib/postgresql/data"
    read_only      = false
  }
  
  labels = {
    phase       = "16"
    component   = "database-ha"
    role        = "replica"
    environment = var.phase_16_environment
  }
  
  healthcheck {
    test     = ["CMD-SHELL", "pg_isready -U replicator -h localhost"]
    interval = "10s"
    timeout  = "5s"
    retries  = 5
  }
}

################################################################################
# pgBouncer - Connection Pooling
################################################################################

resource "docker_image" "pgbouncer" {
  name         = "pgbouncer/pgbouncer:1.18"
  keep_locally = true
}

resource "docker_container" "pgbouncer_pool" {
  name    = "pgbouncer-connection-pool"
  image   = docker_image.pgbouncer.image_id
  restart = "unless-stopped"
  
  ports {
    internal = 6432
    external = 6432
  }
  
  volumes {
    host_path      = "/tmp/pgbouncer-config"
    container_path = "/etc/pgbouncer"
    read_only      = false
  }
  
  labels {
    key   = "phase"
    value = "16"
  }
  labels {
    key   = "component"
    value = "connection-pooling"
  }
  labels {
    key   = "environment"
    value = var.phase_16_environment
  }
  
  healthcheck {
    test     = ["CMD", "psql", "-U", "db_admin", "-d", "pgbouncer", "-c", "SELECT 1"]
    interval = "10s"
    timeout  = "5s"
    retries  = 3
  }
}

################################################################################
# HAProxy - Load Balancer
################################################################################

resource "docker_image" "haproxy" {
  name         = "haproxy:2.8-alpine"
  keep_locally = true
}

resource "docker_container" "haproxy_lb" {
  name    = "haproxy-load-balancer"
  image   = docker_image.haproxy.image_id
  restart = "unless-stopped"
  
  ports {
    internal = 80
    external = 8080
  }
  
  ports {
    internal = 443
    external = 8443
  }
  
  ports {
    internal = 5432
    external = 5435
  }
  
  labels {
    key   = "phase"
    value = "16"
  }
  labels {
    key   = "component"
    value = "load-balancer"
  }
  labels {
    key   = "environment"
    value = var.phase_16_environment
  }
  
  volumes {
    host_path      = "/tmp/haproxy-config"
    container_path = "/usr/local/etc/haproxy"
    read_only      = false
  }
  
  healthcheck {
    test     = ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:8080/stats"]
    interval = "10s"
    timeout  = "5s"
    retries  = 3
  }
}

################################################################################
# Outputs
################################################################################

output "database_endpoints" {
  description = "Database HA endpoints"
  value = {
    primary    = "postgres-primary-ha:5432"
    replica_1  = "postgres-replica-1-ha:5433"
    replica_2  = "postgres-replica-2-ha:5434"
    pgbouncer  = "pgbouncer-connection-pool:6432"
  }
}

output "load_balancer_endpoints" {
  description = "HAProxy load balancer endpoints"
  value = {
    http  = "haproxy-load-balancer:8080"
    https = "haproxy-load-balancer:8443"
    db_lb = "haproxy-load-balancer:5435"
  }
}

output "phase_16_status" {
  description = "Phase 16 deployment status"
  value = {
    postgres_primary_healthy = docker_container.postgres_primary.status == "running"
    postgres_replica_1_healthy = docker_container.postgres_replica_1.status == "running"
    postgres_replica_2_healthy = docker_container.postgres_replica_2.status == "running"
    pgbouncer_healthy = docker_container.pgbouncer_pool.status == "running"
    haproxy_healthy = docker_container.haproxy_lb.status == "running"
  }
}
