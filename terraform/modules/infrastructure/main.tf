# Infrastructure Module - Network and Volumes
# Foundational infrastructure for cluster deployment

terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = ">= 3.0, < 4.0"
    }
  }
}

# ============================================================================
# VARIABLES
# ============================================================================

variable "cluster_name" {
  description = "Cluster name"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "common_tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default = {
    Project     = "infrastructure-modernization"
    ManagedBy   = "Terraform"
    Phase       = "3"
    CreatedDate = "2026-04-28"
  }
}

# ============================================================================
# DOCKER NETWORK
# ============================================================================

resource "docker_network" "main" {
  name   = "${var.cluster_name}-network"
  driver = "bridge"

  labels = merge(var.common_tags, {
    Name        = "${var.cluster_name}-network"
    Environment = var.environment
    Component   = "networking"
  })
}

# ============================================================================
# PERSISTENT VOLUMES
# ============================================================================

resource "docker_volume" "postgresql" {
  name = "${var.cluster_name}-postgres-data"

  labels = merge(var.common_tags, {
    Name        = "PostgreSQL Data"
    Component   = "database"
    Environment = var.environment
  })
}

resource "docker_volume" "redis" {
  name = "${var.cluster_name}-redis-data"

  labels = merge(var.common_tags, {
    Name        = "Redis Data"
    Component   = "cache"
    Environment = var.environment
  })
}

resource "docker_volume" "mongodb" {
  name = "${var.cluster_name}-mongodb-data"

  labels = merge(var.common_tags, {
    Name        = "MongoDB Data"
    Component   = "database"
    Environment = var.environment
  })
}

resource "docker_volume" "elasticsearch" {
  name = "${var.cluster_name}-elasticsearch-data"

  labels = merge(var.common_tags, {
    Name        = "Elasticsearch Data"
    Component   = "search"
    Environment = var.environment
  })
}

resource "docker_volume" "qdrant" {
  name = "${var.cluster_name}-qdrant-data"

  labels = merge(var.common_tags, {
    Name        = "Qdrant Data"
    Component   = "vector-database"
    Environment = var.environment
  })
}

resource "docker_volume" "prometheus" {
  name = "${var.cluster_name}-prometheus-data"

  labels = merge(var.common_tags, {
    Name        = "Prometheus Data"
    Component   = "monitoring"
    Environment = var.environment
  })
}

resource "docker_volume" "grafana" {
  name = "${var.cluster_name}-grafana-data"

  labels = merge(var.common_tags, {
    Name        = "Grafana Data"
    Component   = "monitoring"
    Environment = var.environment
  })
}

resource "docker_volume" "loki" {
  name = "${var.cluster_name}-loki-data"

  labels = merge(var.common_tags, {
    Name        = "Loki Data"
    Component   = "logging"
    Environment = var.environment
  })
}

resource "docker_volume" "tempo" {
  name = "${var.cluster_name}-tempo-data"

  labels = merge(var.common_tags, {
    Name        = "Tempo Data"
    Component   = "tracing"
    Environment = var.environment
  })
}

resource "docker_volume" "alertmanager" {
  name = "${var.cluster_name}-alertmanager-data"

  labels = merge(var.common_tags, {
    Name        = "AlertManager Data"
    Component   = "monitoring"
    Environment = var.environment
  })
}

resource "docker_volume" "caddy" {
  name = "${var.cluster_name}-caddy-data"

  labels = merge(var.common_tags, {
    Name        = "Caddy Data"
    Component   = "gateway"
    Environment = var.environment
  })
}

resource "docker_volume" "caddy_config" {
  name = "${var.cluster_name}-caddy-config"

  labels = merge(var.common_tags, {
    Name        = "Caddy Config"
    Component   = "gateway"
    Environment = var.environment
  })
}

# ============================================================================
# OUTPUTS
# ============================================================================

output "network_id" {
  description = "Docker network ID"
  value       = docker_network.main.id
}

output "network_name" {
  description = "Docker network name"
  value       = docker_network.main.name
}

output "volumes" {
  description = "All created volumes"
  value = {
    postgresql    = docker_volume.postgresql.name
    redis         = docker_volume.redis.name
    mongodb       = docker_volume.mongodb.name
    elasticsearch = docker_volume.elasticsearch.name
    qdrant        = docker_volume.qdrant.name
    prometheus    = docker_volume.prometheus.name
    grafana       = docker_volume.grafana.name
    loki          = docker_volume.loki.name
    tempo         = docker_volume.tempo.name
    alertmanager  = docker_volume.alertmanager.name
    caddy         = docker_volume.caddy.name
    caddy_config  = docker_volume.caddy_config.name
  }
}
