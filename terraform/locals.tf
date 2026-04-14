# Terraform Locals - Computed Configuration Values

locals {
  service_name = "code-server-enterprise"
  environment  = "production"
  network_name = "${local.service_name}-network"

  # Container configuration
  code_server_port = 8080
  oauth2_port      = 4180
  caddy_http_port  = 80
  caddy_https_port = 443

  # Volume paths
  data_volume    = "${local.service_name}-data"
  workspace_path = "/home/coder/workspace"
  config_path    = "/home/coder/.config/code-server"

  # Image versions (pinned to specific digest for immutability)
  # ✅ These are immutable - won't auto-upgrade
  # ✅ SINGLE SOURCE OF TRUTH - referenced by all modules and infrastructure layers
  docker_images = {
    code_server  = "codercom/code-server:4.115.0"
    oauth2_proxy = "quay.io/oauth2-proxy/oauth2-proxy:v7.5.1"
    caddy        = "caddy:latest" # Built custom in Dockerfile.caddy

    # Observability & Operational Excellence layer
    prometheus    = "prom/prometheus:v2.48.0"
    grafana       = "grafana/grafana:10.2.3"
    alertmanager  = "prom/alertmanager:v0.26.0"
    node_exporter = "prom/node-exporter:v1.7.0"

    # Additional observability (future layers)
    jaeger = "jaegertracing/all-in-one:latest"
    loki   = "grafana/loki:latest"
  }

  # ✅ Immutable tags and labels
  tags = {
    Environment = local.environment
    Service     = local.service_name
    ManagedBy   = "Terraform"
    IaC         = "Yes"
  }

  # ✅ Security configuration
  security = {
    no_new_privileges = true
    read_only_root    = false # code-server needs write access
    drop_capabilities = ["ALL"]
    add_capabilities  = ["NET_BIND_SERVICE"]
  }

  # ✅ Health check configuration
  health_check = {
    code_server = {
      test         = ["CMD", "curl", "-f", "http://localhost:${local.code_server_port}/healthz || exit 1"]
      interval     = "30s"
      timeout      = "10s"
      retries      = 3
      start_period = "30s"
    }
    oauth2_proxy = {
      test         = ["CMD", "wget", "-q", "--spider", "http://localhost:${local.oauth2_port}/ping"]
      interval     = "10s"
      timeout      = "5s"
      retries      = 3
      start_period = "10s"
    }
    caddy = {
      test         = ["CMD", "caddy", "validate", "--config", "/etc/caddy/Caddyfile"]
      interval     = "30s"
      timeout      = "10s"
      retries      = 3
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
    "TZ"                           = "UTC"
    "NODE_ENV"                     = local.environment
    "SERVICE_URL"                  = "https://open-vsx.org/vscode/gallery"
    "ITEM_URL"                     = "https://open-vsx.org/vscode/item"
    "NODE_OPTIONS"                 = "--no-experimental-global-navigator"
    "OAUTH2_PROXY_PROVIDER"        = "google"
    "OAUTH2_PROXY_OIDC_ISSUER_URL" = "https://accounts.google.com"
  }

  # ✅ Service resource limits (DOCKER DEPLOY RESOURCES)
  # Single source of truth for all service resource allocation
  resource_limits = {
    code_server = {
      memory_limit       = "512m"
      cpu_limit          = "1.0"
      memory_reservation = "256m"
      cpu_reservation    = "0.125"
    }
    ollama = {
      memory_limit       = "0"
      cpu_limit          = "0"
      memory_reservation = null
      cpu_reservation    = null
    }
    oauth2_proxy = {
      memory_limit       = "512m"
      cpu_limit          = "0.5"
      memory_reservation = "256m"
      cpu_reservation    = "0.25"
    }
    caddy = {
      memory_limit       = "512m"
      cpu_limit          = "0.5"
      memory_reservation = "256m"
      cpu_reservation    = "0.25"
    }
    prometheus = {
      memory_limit       = "256m"
      cpu_limit          = "0.125"
      memory_reservation = "128m"
      cpu_reservation    = "0.05"
    }
    grafana = {
      memory_limit       = "256m"
      cpu_limit          = "0.1"
      memory_reservation = "128m"
      cpu_reservation    = "0.05"
    }
    alertmanager = {
      memory_limit       = "256m"
      cpu_limit          = "0.25"
      memory_reservation = "128m"
      cpu_reservation    = "0.1"
    }
  }

  # ✅ Version pinning for all components (immutability guarantee)
  versions = {
    code_server  = "4.115.0"
    copilot      = "1.388.0"
    copilot_chat = "0.43.2026040705"
    ollama       = "0.1.27"
    oauth2_proxy = "v7.5.1"
    caddy        = "2.7.6"
    prometheus   = "v2.48.0"
    grafana      = "10.2.3"
  }

  # ✅ Network configuration
  network = {
    name              = "enterprise"
    code_server_port  = 8080
    oauth2_proxy_port = 4180
    caddy_http_port   = 80
    caddy_https_port  = 443
    ollama_port       = 11434
  }

  # ✅ Storage configuration
  storage = {
    data_volume    = "${local.service_name}-data"
    ollama_volume  = "ollama-data"
    workspace_path = "/home/coder/workspace"
    workspace_dir  = "${path.module}/workspace"
  }
}

# ✅ Output computed values for debugging
output "local_configuration" {
  description = "Computed local configuration"
  value = {
    service_name  = local.service_name
    environment   = local.environment
    docker_images = local.docker_images
    security      = local.security
    health_check  = local.health_check
  }
  sensitive = false
}
