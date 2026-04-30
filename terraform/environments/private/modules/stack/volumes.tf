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

resource "docker_volume" "keepalived_config" {
  name   = "keepalived_config"
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

# ── App-tier volumes ──────────────────────────────────────────────────────────
resource "docker_volume" "code_server_data" {
  name   = "code_server_data"
  driver = "local"
}

resource "docker_volume" "gitlab_config" {
  name   = "gitlab_config"
  driver = "local"
}

resource "docker_volume" "gitlab_logs" {
  name   = "gitlab_logs"
  driver = "local"
}

resource "docker_volume" "gitlab_data" {
  name   = "gitlab_data"
  driver = "local"
}

resource "docker_volume" "gitlab_runner_data" {
  name   = "gitlab_runner_data"
  driver = "local"
}

resource "docker_volume" "appsmith_stacks" {
  name   = "appsmith_stacks"
  driver = "local"
}

resource "docker_volume" "minio_data" {
  name   = "minio_data"
  driver = "local"
}

resource "docker_volume" "nexus_data" {
  name   = "nexus_data"
  driver = "local"
}
