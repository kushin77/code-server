terraform {
  required_version = ">= 1.0"
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

variable "domain" { type = string }
variable "code_server_password" { type = string }
variable "google_client_id" { type = string }
variable "google_client_secret" { type = string }
variable "oauth2_proxy_cookie_secret" { type = string }
variable "github_token" { type = string }

resource "local_file" "docker_compose_yml" {
  filename = "${path.module}/docker-compose.yml"
  content  = file("${path.module}/../docker-compose.yml")
}

resource "local_file" "env_file" {
  filename = "${path.module}/.env"
  content  = <<-EOT
DOMAIN=${var.domain}
CODE_SERVER_PASSWORD=${var.code_server_password}
GOOGLE_CLIENT_ID=${var.google_client_id}
GOOGLE_CLIENT_SECRET=${var.google_client_secret}
OAUTH2_PROXY_COOKIE_SECRET=${var.oauth2_proxy_cookie_secret}
GITHUB_TOKEN=${var.github_token}
EOT
}
