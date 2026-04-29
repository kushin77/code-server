/**
 * @file modules/stack/volumes.tf
 * @description Docker named volumes for this host (matches docker-compose.yml volume definitions).
 *              All volumes use the local driver and persist across container recreations.
 */

resource "docker_volume" "caddy_data" {
  name   = "caddy_data"
  driver = "local"
}

resource "docker_volume" "caddy_config" {
  name   = "caddy_config"
  driver = "local"
}

resource "docker_volume" "prometheus_data" {
  name   = "prometheus_data"
  driver = "local"
}

resource "docker_volume" "grafana_data" {
  name   = "grafana_data"
  driver = "local"
}

resource "docker_volume" "loki_data" {
  name   = "loki_data"
  driver = "local"
}

resource "docker_volume" "alertmanager_data" {
  name   = "alertmanager_data"
  driver = "local"
}

resource "docker_volume" "qdrant_data" {
  name   = "qdrant_data"
  driver = "local"
}

resource "docker_volume" "postgres_data" {
  name   = "postgres_data"
  driver = "local"
}

resource "docker_volume" "redis_data" {
  name   = "redis_data"
  driver = "local"
}

resource "docker_volume" "redpanda_data" {
  name   = "redpanda_data"
  driver = "local"
}

resource "docker_volume" "ollama_models" {
  name   = "ollama_models"
  driver = "local"
}

resource "docker_volume" "tempo_data" {
  name   = "tempo_data"
  driver = "local"
}
