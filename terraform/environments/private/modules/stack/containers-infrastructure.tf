/**
 * @file modules/stack/containers-infrastructure.tf
 * @description Core infrastructure containers: opa, oauth2-proxy, caddy, ollama.
 */

# ── OPA (Open Policy Agent) ───────────────────────────────────────────────────
resource "docker_container" "opa" {
  name    = "code-server-opa"
  image   = docker_image.opa.image_id
  user    = "101:101"
  restart = "unless-stopped"

  command = ["run", "--server", "--log-level=info", "--set", "decision_logs.console=true"]

  ports {
    internal = 8181
    external = 18181
  }

  env = [
    "OPA_ADDR=0.0.0.0:8181",
    "LOG_LEVEL=info",
  ]

  mounts {
    target    = "/policies"
    source    = "${local.repo}/policies"
    type      = "bind"
    read_only = true
  }

  mounts {
    target    = "/opa-src"
    source    = local.repo
    type      = "bind"
    read_only = true
  }

  healthcheck {
    test         = ["CMD", "/opa", "version"]
    interval     = "30s"
    timeout      = "5s"
    retries      = 3
    start_period = "10s"
  }

  networks_advanced {
    name = docker_network.services.id
  }

  log_driver = "json-file"
  log_opts   = local.log_json_file

  lifecycle {
    ignore_changes = [image, network_mode, mounts]
  }

  labels {
    label = "io.elevatediq.component"
    value = "policy-engine"
  }
  labels {
    label = "io.elevatediq.tier"
    value = "infrastructure"
  }
}

# ── OAuth2 Proxy ──────────────────────────────────────────────────────────────
resource "docker_container" "oauth2_proxy" {
  name    = "code-server-oauth2-proxy"
  image   = docker_image.oauth2_proxy.image_id
  user    = "65534:65534"
  restart = "unless-stopped"

  command = ["--config=/etc/oauth2-proxy/oauth2-proxy.cfg"]

  ports {
    internal = 4180
    external = 4180
  }

  env = [
    "OAUTH2_PROXY_CLIENT_ID=${var.oauth2_client_id}",
    "OAUTH2_PROXY_CLIENT_SECRET=${var.oauth2_client_secret}",
    "OAUTH2_PROXY_COOKIE_SECRET=${var.oauth2_cookie_secret}",
    "OAUTH2_PROXY_UPSTREAMS=http://code-server-caddy:9088/",
  ]

  mounts {
    target    = "/etc/oauth2-proxy/oauth2-proxy.cfg"
    source    = "${local.repo}/config/oauth2-proxy/oauth2-proxy.cfg"
    type      = "bind"
    read_only = true
  }

  healthcheck {
    test         = ["CMD", "/bin/oauth2-proxy", "--version"]
    interval     = "30s"
    timeout      = "5s"
    retries      = 3
    start_period = "10s"
  }

  networks_advanced {
    name = docker_network.services.id
  }

  log_driver = "json-file"
  log_opts   = local.log_json_file

  lifecycle {
    ignore_changes = [image, network_mode, mounts]
  }
}

# ── Caddy (Reverse Proxy / Gateway) ──────────────────────────────────────────
resource "docker_container" "caddy" {
  name    = "code-server-caddy"
  image   = docker_image.caddy.image_id
  user    = "101:101"
  restart = "unless-stopped"

  depends_on = [docker_container.caddy_init]

  ports {
    internal = 80
    external = 80
  }
  ports {
    internal = 443
    external = 443
    protocol = "tcp"
  }
  ports {
    internal = 443
    external = 443
    protocol = "udp"
  }

  env = [
    "APEX_DOMAIN=${var.apex_domain}",
    "TLS_EMAIL=${var.tls_email}",
    "LOG_LEVEL=${var.log_level}",
  ]

  mounts {
    target    = "/etc/caddy"
    source    = "${local.repo}/config/caddy"
    type      = "bind"
    read_only = true
  }

  mounts {
    target = "/data"
    source = docker_volume.caddy_data.name
    type   = "volume"
  }

  mounts {
    target = "/config"
    source = docker_volume.caddy_config.name
    type   = "volume"
  }

  healthcheck {
    test         = ["CMD", "caddy", "version"]
    interval     = "30s"
    timeout      = "5s"
    retries      = 3
    start_period = "10s"
  }

  networks_advanced {
    name = docker_network.services.id
  }

  log_driver = "json-file"
  log_opts   = local.log_json_file_large

  lifecycle {
    ignore_changes = [image, network_mode, mounts]
  }

  labels {
    label = "io.elevatediq.component"
    value = "gateway"
  }
  labels {
    label = "io.elevatediq.tier"
    value = "infrastructure"
  }
}

# ── Ollama (LLM Model Server) ────────────────────────────────────────────────
resource "docker_container" "ollama" {
  name    = "code-server-ollama"
  image   = docker_image.ollama.image_id
  user    = "11434:11434"
  restart = "unless-stopped"

  depends_on = [docker_container.ollama_init]

  env = [
    "HOME=/home/ollama",
    "OLLAMA_HOST=0.0.0.0:11434",
    "OLLAMA_MODELS=/home/ollama/.ollama/models",
  ]

  mounts {
    target = "/home/ollama/.ollama"
    source = docker_volume.ollama_models.name
    type   = "volume"
  }

  healthcheck {
    test         = ["CMD", "ollama", "--version"]
    interval     = "1m0s"
    timeout      = "10s"
    retries      = 3
    start_period = "30s"
  }

  lifecycle {
    ignore_changes = [image, network_mode]
  }

  networks_advanced {
    name = docker_network.services.id
  }

  log_driver = "json-file"
  log_opts   = local.log_json_file_large

  labels {
    label = "io.elevatediq.component"
    value = "llm-server"
  }
  labels {
    label = "io.elevatediq.tier"
    value = "ai"
  }
}
