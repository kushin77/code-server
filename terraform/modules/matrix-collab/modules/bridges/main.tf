# Slack bridge
terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}

resource "docker_image" "slack_bridge" {
  count         = var.enable_slack_bridge ? 1 : 0
  name          = "halfshot/matrix-appservice-slack:latest"
  pull_triggers = ["latest"]
}

resource "docker_container" "slack_bridge" {
  count   = var.enable_slack_bridge ? 1 : 0
  name    = "bridge-slack"
  image   = docker_image.slack_bridge[0].image_id
  restart = "unless-stopped"

  ports {
    internal = 8080
    external = 8082
  }

  env = [
    "MATRIX_HOMESERVER=${var.homeserver_url}",
    "SLACK_BOT_TOKEN=${var.synapse_admin_token}",
  ]

  healthcheck {
    test     = ["CMD", "curl", "-f", "http://localhost:8080/health"]
    interval = "30s"
    timeout  = "5s"
    retries  = 3
  }
}

# Teams bridge
resource "docker_image" "teams_bridge" {
  count         = var.enable_teams_bridge ? 1 : 0
  name          = "halfshot/matrix-appservice-teams:latest"
  pull_triggers = ["latest"]
}

resource "docker_container" "teams_bridge" {
  count   = var.enable_teams_bridge ? 1 : 0
  name    = "bridge-teams"
  image   = docker_image.teams_bridge[0].image_id
  restart = "unless-stopped"

  ports {
    internal = 8080
    external = 8083
  }

  env = [
    "MATRIX_HOMESERVER=${var.homeserver_url}",
    "TEAMS_BOT_TOKEN=${var.synapse_admin_token}",
  ]

  healthcheck {
    test     = ["CMD", "curl", "-f", "http://localhost:8080/health"]
    interval = "30s"
    timeout  = "5s"
    retries  = 3
  }
}

# Google Chat bridge
resource "docker_image" "google_chat_bridge" {
  count         = var.enable_google_chat_bridge ? 1 : 0
  name          = "halfshot/matrix-appservice-google-chat:latest"
  pull_triggers = ["latest"]
}

resource "docker_container" "google_chat_bridge" {
  count   = var.enable_google_chat_bridge ? 1 : 0
  name    = "bridge-google-chat"
  image   = docker_image.google_chat_bridge[0].image_id
  restart = "unless-stopped"

  ports {
    internal = 8080
    external = 8084
  }

  env = [
    "MATRIX_HOMESERVER=${var.homeserver_url}",
    "GOOGLE_CHAT_BOT_TOKEN=${var.synapse_admin_token}",
  ]

  healthcheck {
    test     = ["CMD", "curl", "-f", "http://localhost:8080/health"]
    interval = "30s"
    timeout  = "5s"
    retries  = 3
  }
}
