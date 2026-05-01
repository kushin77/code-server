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

# ============================================================================
# DOCKER NETWORK
# ============================================================================

resource "docker_network" "main" {
  name   = "${var.cluster_name}-network"
  driver = "bridge"

  labels = {
    Name        = "${var.cluster_name}-network"
    Environment = var.environment
    Component   = "networking"
    ManagedBy   = "terraform"
  }
}

# ============================================================================
# PERSISTENT VOLUMES
# ============================================================================

resource "docker_volume" "postgresql" {
  name = "${var.cluster_name}-postgres-data"

  labels = {
    Name        = "PostgreSQL Data"
    Component   = "database"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "docker_volume" "redis" {
  name = "${var.cluster_name}-redis-data"

  labels = {
    Name        = "Redis Data"
    Component   = "cache"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "docker_volume" "mongodb" {
  name = "${var.cluster_name}-mongodb-data"

  labels = {
    Name        = "MongoDB Data"
    Component   = "database"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "docker_volume" "elasticsearch" {
  name = "${var.cluster_name}-elasticsearch-data"

  labels = {
    Name        = "Elasticsearch Data"
    Component   = "search"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "docker_volume" "qdrant" {
  name = "${var.cluster_name}-qdrant-data"

  labels = {
    Name        = "Qdrant Data"
    Component   = "vector-database"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "docker_volume" "prometheus" {
  name = "${var.cluster_name}-prometheus-data"

  labels = {
    Name        = "Prometheus Data"
    Component   = "monitoring"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "docker_volume" "grafana" {
  name = "${var.cluster_name}-grafana-data"

  labels = {
    Name        = "Grafana Data"
    Component   = "monitoring"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "docker_volume" "loki" {
  name = "${var.cluster_name}-loki-data"

  labels = {
    Name        = "Loki Data"
    Component   = "logging"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "docker_volume" "tempo" {
  name = "${var.cluster_name}-tempo-data"

  labels = {
    Name        = "Tempo Data"
    Component   = "tracing"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "docker_volume" "alertmanager" {
  name = "${var.cluster_name}-alertmanager-data"

  labels = {
    Name        = "AlertManager Data"
    Component   = "monitoring"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "docker_volume" "caddy" {
  name = "${var.cluster_name}-caddy-data"

  labels = {
    Name        = "Caddy Data"
    Component   = "gateway"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "docker_volume" "caddy_config" {
  name = "${var.cluster_name}-caddy-config"

  labels = {
    Name        = "Caddy Config"
    Component   = "gateway"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
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
    postgresql   = docker_volume.postgresql.name
    redis        = docker_volume.redis.name
    mongodb      = docker_volume.mongodb.name
    elasticsearch = docker_volume.elasticsearch.name
    qdrant       = docker_volume.qdrant.name
    prometheus   = docker_volume.prometheus.name
    grafana      = docker_volume.grafana.name
    loki         = docker_volume.loki.name
    tempo        = docker_volume.tempo.name
    alertmanager = docker_volume.alertmanager.name
    caddy        = docker_volume.caddy.name
    caddy_config = docker_volume.caddy_config.name
  }
}
