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
    label = "Name"
    value = "code-server-opa"
  }
  labels {
    label = "Environment"
    value = local.standard_tags.Environment
  }
  labels {
    label = "ManagedBy"
    value = local.standard_tags.ManagedBy
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

  labels {
    label = "Name"
    value = "code-server-oauth2-proxy"
  }
  labels {
    label = "Environment"
    value = local.standard_tags.Environment
  }
  labels {
    label = "ManagedBy"
    value = local.standard_tags.ManagedBy
  }
  labels {
    label = "io.elevatediq.component"
    value = "identity-proxy"
  }
  labels {
    label = "io.elevatediq.tier"
    value = "infrastructure"
  }
}

# ── Caddy (Reverse Proxy / Gateway) ──────────────────────────────────────────
resource "docker_container" "caddy" {
  name    = "code-server-caddy"
  image   = docker_image.caddy.image_id
  user    = "101:101"
  restart = "unless-stopped"

  depends_on = [docker_container.caddy_init]

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
    label = "Name"
    value = "code-server-caddy"
  }
  labels {
    label = "Environment"
    value = local.standard_tags.Environment
  }
  labels {
    label = "ManagedBy"
    value = local.standard_tags.ManagedBy
  }
  labels {
    label = "io.elevatediq.component"
    value = "gateway"
  }
  labels {
    label = "io.elevatediq.tier"
    value = "infrastructure"
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

# ── Keepalived (VRRP High Availability) ──────────────────────────────────────
resource "docker_container" "keepalived_init" {
  name      = "code-server-keepalived-init"
  image     = docker_image.alpine.image_id
  user      = "0:0"
  restart   = "no"
  must_run  = false
  network_mode = "host"
  
  command = [
    "sh",
    "-lc",
    <<-EOT
    mkdir -p /etc/keepalived
          iface="$(ip -o -4 route show to default | awk '{print $5; exit}')"
          if [ -z "$iface" ]; then
            iface="$(ip -o link show | awk -F': ' '$2 !~ /lo/ {print $2; exit}')"
    fi
    if [ "${var.host_role}" = "primary" ]; then
      state="MASTER"
      priority="100"
    else
      state="BACKUP"
      priority="90"
    fi
    # Discover Caddy's bridge IP and store it for the keepalived health check script.
    # The keepalived container uses BusyBox nc (no -U) and no curl/socat, so the IP
    # is written once here (Alpine curl supports --unix-socket) and read at check time.
    apk add --no-cache curl >/dev/null 2>&1 || true
    curl -s --unix-socket /var/run/docker.sock \
      'http://localhost/containers/code-server-caddy/json' 2>/dev/null \
      | grep -o '"IPAddress":"[0-9][0-9.]*"' | head -1 | cut -d'"' -f4 \
      > /etc/keepalived/caddy.ip || true
    cat > /etc/keepalived/check-caddy-health.sh << 'SCRIPT'
#!/bin/sh
# Read Caddy's bridge IP stored at init time (avoids needing docker CLI in keepalived)
caddy_ip=$(cat /etc/keepalived/caddy.ip 2>/dev/null | tr -d '[:space:]')
[ -z "$caddy_ip" ] && exit 1
# Caddy is healthy if it responds with any HTTP status (200, 308, etc.)
http_code=$(wget -q --server-response --timeout=3 -O /dev/null \
  "http://$caddy_ip/" 2>&1 | awk '/HTTP\//{print $2}' | tail -1)
[ -n "$http_code" ] && exit 0
exit 1
fi
exit 0
SCRIPT
    chmod 755 /etc/keepalived/check-caddy-health.sh
    cat > /etc/keepalived/notify-vrrp.sh << 'SCRIPT'
#!/bin/sh
STATE="$${1:-unknown}"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
{ echo "[$TIMESTAMP] VRRP State: $STATE on $(hostname)"; } >> /var/log/keepalived-state.log 2>&1 || true
exit 0
SCRIPT
    chmod 755 /etc/keepalived/notify-vrrp.sh
    cat > /etc/keepalived/keepalived.conf << EOF
global_defs {
  router_id CODE_SERVER_HA
  script_user root
  enable_script_security
}
vrrp_script check_caddy {
  script "/etc/keepalived/check-caddy-health.sh"
  interval 3
  fall 3
  rise 2
  weight -20
}
vrrp_instance VI_1 {
  state $state
  interface $iface
  virtual_router_id 51
  priority $priority
  advert_int 1
  authentication {
    auth_type PASS
    auth_pass CODE_SERVER_HA_2026
  }
  virtual_ipaddress {
    192.168.168.30/24
  }
  track_script {
    check_caddy
  }
  notify_master "/etc/keepalived/notify-vrrp.sh master"
  notify_backup "/etc/keepalived/notify-vrrp.sh backup"
}
EOF
    chown -R root:root /etc/keepalived
    chmod 600 /etc/keepalived/keepalived.conf
    EOT
  ]

  volumes {
    volume_name    = docker_volume.keepalived_config.name
    container_path = "/etc/keepalived"
  }

  volumes {
    host_path      = "/var/run/docker.sock"
    container_path = "/var/run/docker.sock"
    read_only      = true
  }

  lifecycle {
    ignore_changes = [image, network_mode]
  }
}

resource "docker_container" "keepalived" {
  name    = "code-server-keepalived"
  image   = docker_image.keepalived.image_id
  user    = "0:0"
  restart = "unless-stopped"

  depends_on = [
    docker_container.keepalived_init,
  ]

  capabilities {
    add  = ["NET_ADMIN", "NET_BROADCAST", "NET_RAW", "SYS_ADMIN"]
    drop = []
  }

  network_mode = "host"

  env = [
    "HOST_ROLE=${var.host_role}",
  ]

  # Config and scripts stored in same volume at /etc/keepalived
  volumes {
    volume_name = docker_volume.keepalived_config.name
    container_path = "/etc/keepalived"
    read_only = true
  }

  volumes {
    host_path = "/var/run/docker.sock"
    container_path = "/var/run/docker.sock"
    read_only = true
  }

  healthcheck {
    test = [
      "CMD",
      "sh",
      "-c",
      "ps aux | grep -v grep | grep keepalived || exit 1"
    ]
    interval     = "30s"
    timeout      = "5s"
    retries      = 3
    start_period = "10s"
  }

  log_driver = "json-file"
  log_opts   = {
    "max-size" = "10m"
    "max-file" = "3"
  }

  labels {
    label = "io.elevatediq.component"
    value = "ha-vrrp"
  }
  labels {
    label = "io.elevatediq.tier"
    value = "infrastructure"
  }

  lifecycle {
    ignore_changes = [image, network_mode, volumes]
  }
}
