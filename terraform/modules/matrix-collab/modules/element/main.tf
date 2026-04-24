terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}

resource "docker_image" "element" {
  name          = var.docker_image
  pull_triggers = [var.docker_image]
}

resource "docker_container" "element" {
  name    = "element-web"
  image   = docker_image.element.image_id
  restart = "unless-stopped"

  ports {
    internal = 80
    external = 8081
  }

  volumes {
    host_path      = "/srv/element/config.json"
    container_path = "/app/config.json"
  }

  env = [
    "ELEMENT_CONFIG_DIR=/app/config",
  ]

  healthcheck {
    test     = ["CMD", "wget", "--spider", "-q", "http://localhost/"]
    interval = "30s"
    timeout  = "5s"
    retries  = 3
  }
}

# Generate Element configuration
resource "local_file" "element_config" {
  filename = "/srv/element/config.json"
  
  content = jsonencode({
    default_server_config = {
      "m.homeserver" = {
        base_url = var.homeserver_url
      }
      "m.identity_server" = {
        base_url = "https://vector.im"
      }
    }
    brand = "Element"
    brand_full_name = "Element"
    bug_report_endpoint_url = ""
    default_theme = "light"
    default_country_code = "US"
    features = {
      "feature_groups_v2_ui" = true
      "feature_pinning" = true
      "feature_custom_themes" = true
    }
    showLabsSettings = false
    permalinkPrefix = var.homeserver_url
  })

  depends_on = [docker_container.element]
}
