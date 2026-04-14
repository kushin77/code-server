################################################################################
# Phase 15: Advanced Performance & Load Testing Infrastructure
# Purpose: Redis caching layer, advanced observability, load testing harness
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

variable "phase_15_environment" {
  description = "Environment identifier"
  type        = string
  default     = "phase-15-advanced-performance"
}

variable "redis_replicas" {
  description = "Number of Redis replicas for clustering"
  type        = number
  default     = 3
}

variable "cache_ttl_seconds" {
  description = "Cache TTL in seconds"
  type        = number
  default     = 3600
}

variable "load_test_users_concurrent" {
  description = "Number of concurrent test users"
  type        = number
  default     = 500
}

################################################################################
# Redis Cluster - Advanced Caching
################################################################################

resource "docker_image" "redis_cluster" {
  name         = "redis:7-alpine"
  keep_locally = true
}

resource "docker_container" "redis_cluster_node_1" {
  name    = "redis-cluster-node-1"
  image   = docker_image.redis_cluster.image_id
  restart = "unless-stopped"
  
  ports {
    internal = 6379
    external = 6379
  }
  
  command = [
    "redis-server",
    "--cluster-enabled", "yes",
    "--cluster-config-file", "/data/nodes.conf",
    "--cluster-node-timeout", "5000",
    "--appendonly", "yes"
  ]
  
  volumes {
    host_path      = "/tmp/redis-cluster-1"
    container_path = "/data"
    read_only      = false
  }
  
  healthcheck {
    test     = ["CMD", "redis-cli", "ping"]
    interval = "10s"
    timeout  = "5s"
    retries  = 5
  }
}

resource "docker_container" "redis_cluster_node_2" {
  name    = "redis-cluster-node-2"
  image   = docker_image.redis_cluster.image_id
  restart = "unless-stopped"
  
  ports {
    internal = 6379
    external = 6380
  }
  
  command = [
    "redis-server",
    "--cluster-enabled", "yes",
    "--cluster-config-file", "/data/nodes.conf",
    "--cluster-node-timeout", "5000",
    "--appendonly", "yes"
  ]
  
  volumes {
    host_path      = "/tmp/redis-cluster-2"
    container_path = "/data"
    read_only      = false
  }
  
  labels {
    key   = "phase"
    value = "15"
  }
  labels {
    key   = "component"
    value = "redis-cluster"
  }
  labels {
    key   = "environment"
    value = var.phase_15_environment
  }
  
  healthcheck {
    test     = ["CMD", "redis-cli", "-p", "6379", "ping"]
    interval = "10s"
    timeout  = "5s"
    retries  = 5
  }
}

resource "docker_container" "redis_cluster_node_3" {
  name    = "redis-cluster-node-3"
  image   = docker_image.redis_cluster.image_id
  restart = "unless-stopped"
  
  ports {
    internal = 6379
    external = 6381
  }
  
  command = [
    "redis-server",
    "--cluster-enabled", "yes",
    "--cluster-config-file", "/data/nodes.conf",
    "--cluster-node-timeout", "5000",
    "--appendonly", "yes"
  ]
  
  volumes {
    host_path      = "/tmp/redis-cluster-3"
    container_path = "/data"
    read_only      = false
  }
  
  labels {
    key   = "phase"
    value = "15"
  }
  labels {
    key   = "component"
    value = "redis-cluster"
  }
  labels {
    key   = "environment"
    value = var.phase_15_environment
  }
  
  healthcheck {
    test     = ["CMD", "redis-cli", "-p", "6379", "ping"]
    interval = "10s"
    timeout  = "5s"
    retries  = 5
  }
}

################################################################################
# Observability Stack - Advanced Monitoring
################################################################################

resource "docker_image" "prometheus" {
  name         = "prom/prometheus:latest"
  keep_locally = true
}

resource "docker_container" "prometheus_observability" {
  name    = "prometheus-phase15"
  image   = docker_image.prometheus.image_id
  restart = "unless-stopped"
  
  ports {
    internal = 9090
    external = 9090
  }
  
  volumes {
    host_path      = "/tmp/prometheus-config"
    container_path = "/etc/prometheus"
    read_only      = false
  }
  
  labels {
    key   = "phase"
    value = "15"
  }
  labels {
    key   = "component"
    value = "observability"
  }
  labels {
    key   = "environment"
    value = var.phase_15_environment
  }
  
  healthcheck {
    test     = ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:9090/-/healthy"]
    interval = "15s"
    timeout  = "5s"
    retries  = 3
  }
}

################################################################################
# Load Testing Harness - Locust
################################################################################

resource "docker_image" "locust" {
  name         = "locustio/locust:latest"
  keep_locally = true
}

resource "docker_container" "load_test_master" {
  name    = "locust-load-test-master"
  image   = docker_image.locust.image_id
  restart = "unless-stopped"
  
  ports {
    internal = 8089
    external = 8089
  }
  
  env = [
    "LOCUST_MODE=master",
    "LOCUST_HEADLESS=1",
    "LOCUST_USERS=${var.load_test_users_concurrent}",
    "LOCUST_SPAWN_RATE=50",
    "LOCUST_RUN_TIME=1h"
  ]
  
  volumes {
    host_path      = "/tmp/locustfiles"
    container_path = "/home/locust"
    read_only      = false
  }
  
  labels {
    key   = "phase"
    value = "15"
  }
  labels {
    key   = "component"
    value = "load-testing"
  }
  labels {
    key   = "environment"
    value = var.phase_15_environment
  }
  
  healthcheck {
    test     = ["CMD", "curl", "-f", "http://localhost:8089/"]
    interval = "20s"
    timeout  = "5s"
    retries  = 3
  }
}

################################################################################
# Outputs
################################################################################

output "redis_cluster_endpoints" {
  description = "Redis cluster node endpoints"
  value = {
    node_1 = "redis-cluster-node-1:6379"
    node_2 = "redis-cluster-node-2:6380"
    node_3 = "redis-cluster-node-3:6381"
  }
}

output "prometheus_endpoint" {
  description = "Prometheus observability endpoint"
  value       = "http://localhost:9090"
}

output "load_test_endpoint" {
  description = "Load testing master endpoint"
  value       = "http://localhost:8089"
}

output "phase_15_status" {
  description = "Phase 15 deployment status"
  value = {
    redis_cluster_healthy = docker_container.redis_cluster_node_1.status == "running"
    prometheus_healthy    = docker_container.prometheus_observability.status == "running"
    locust_healthy        = docker_container.load_test_master.status == "running"
  }
}

