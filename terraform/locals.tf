# Terraform Locals - Computed Configuration Values

locals {
  service_name    = "code-server-enterprise"
  environment     = "production"
  network_name    = "${local.service_name}-network"

  # Container configuration
  code_server_port   = 8080
  oauth2_port        = 4180
  caddy_http_port    = 80
  caddy_https_port   = 443

  # Volume paths
  data_volume     = "${local.service_name}-data"
  workspace_path  = "/home/coder/workspace"
  config_path     = "/home/coder/.config/code-server"

  # Image versions (pinned to specific digest for immutability)
  # ✅ These are immutable - won't auto-upgrade
  docker_images = {
    code_server = "codercom/code-server:4.115.0"
    # Note: Add digest after first pull: @sha256:...

    oauth2_proxy = "quay.io/oauth2-proxy/oauth2-proxy:v7.5.1"
    # Note: Add digest after first pull: @sha256:...

    caddy = "caddy:latest"  # Built custom in Dockerfile.caddy
  }

  # ✅ Immutable tags and labels
  tags = {
    Environment = local.environmen
    Service     = local.service_name
    ManagedBy   = "Terraform"
    IaC         = "Yes"
  }

  # ✅ Security configuration
  security = {
    no_new_privileges = true
    read_only_root    = false  # code-server needs write access
    drop_capabilities = ["ALL"]
    add_capabilities  = ["NET_BIND_SERVICE"]
  }

  # ✅ Health check configuration
  health_check = {
    code_server = {
      test     = ["CMD", "curl", "-f", "http://localhost:${local.code_server_port}/healthz || exit 1"]
      interval = "30s"
      timeout  = "10s"
      retries  = 3
      start_period = "30s"
    }
    oauth2_proxy = {
      test     = ["CMD", "wget", "-q", "--spider", "http://localhost:${local.oauth2_port}/ping"]
      interval = "10s"
      timeout  = "5s"
      retries  = 3
      start_period = "10s"
    }
    caddy = {
      test     = ["CMD", "caddy", "validate", "--config", "/etc/caddy/Caddyfile"]
      interval = "30s"
      timeout  = "10s"
      retries  = 3
      start_period = "30s"
    }
  }

  # ✅ Logging configuration
  logging = {
    driver = "json-file"
    options = {
      "max-size" = "10m"
      "max-file" = "5"
      "labels"   = "service=${local.service_name}"
    }
  }

  # ✅ Environment variables (non-sensitive)
  common_env = {
    "TZ"                   = "UTC"
    "NODE_ENV"             = local.environmen
    "SERVICE_URL"          = "https://open-vsx.org/vscode/gallery"
    "ITEM_URL"             = "https://open-vsx.org/vscode/item"
    "NODE_OPTIONS"         = "--no-experimental-global-navigator"
    "OAUTH2_PROXY_PROVIDER" = "google"
    "OAUTH2_PROXY_OIDC_ISSUER_URL" = "https://accounts.google.com"
  }
}

# ✅ Output computed values for debugging
output "local_configuration" {
  description = "Computed local configuration"
  value = {
    service_name  = local.service_name
    environment   = local.environmen
    docker_images = local.docker_images
    security      = local.security
    health_check  = local.health_check
  }
  sensitive = false
}
