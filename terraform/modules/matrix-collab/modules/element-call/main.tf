terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}

resource "docker_image" "element_call" {
  name          = "vectorim/element-call:latest"
  pull_triggers = ["latest"]
}

resource "docker_container" "element_call" {
  name    = "element-call"
  image   = docker_image.element_call.image_id
  restart = "unless-stopped"

  ports {
    internal = 3000
    external = 3000
  }

  env = [
    "MATRIX_HOMESERVER_URL=${var.homeserver_url}",
    "ENVIRONMENT=${var.environment}",
  ]

  healthcheck {
    test     = ["CMD", "curl", "-f", "http://localhost:3000/"]
    interval = "30s"
    timeout  = "5s"
    retries  = 3
  }
}
