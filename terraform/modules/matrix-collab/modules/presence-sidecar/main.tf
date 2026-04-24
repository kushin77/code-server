terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}

resource "docker_image" "presence_sidecar" {
  name          = "matrix-presence-sidecar:latest"
  pull_triggers = ["latest"]
}

resource "docker_container" "presence_sidecar" {
  name    = "presence-sidecar"
  image   = docker_image.presence_sidecar.image_id
  restart = "unless-stopped"

  ports {
    internal = 9000
    external = 9000
  }

  env = [
    "MATRIX_HOMESERVER=${var.homeserver_url}",
    "SYNAPSE_ADMIN_TOKEN=${var.synapse_admin_token}",
    "REDIS_URL=${var.redis_url}",
    "PROMETHEUS_URL=${var.prometheus_url}",
    "ENVIRONMENT=${var.environment}",
  ]

  healthcheck {
    test     = ["CMD", "curl", "-f", "http://localhost:9000/health"]
    interval = "30s"
    timeout  = "5s"
    retries  = 3
  }
}
