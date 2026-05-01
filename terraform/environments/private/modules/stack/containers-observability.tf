/**
 * @file modules/stack/containers-observability.tf
 * @description Observability stack: prometheus, grafana, loki, alertmanager, otel-collector, tempo.
 */

# ── Prometheus ────────────────────────────────────────────────────────────────
resource "docker_container" "prometheus" {
  name    = "code-server-prometheus"
  image   = docker_image.prometheus.image_id
  user    = "65534:65534"
  restart = "unless-stopped"

  depends_on = [docker_container.prometheus_init]

  command = [
    "--config.file=/prometheus-config/prometheus.yml",
    "--storage.tsdb.path=/prometheus",
    "--storage.tsdb.retention.time=${var.prometheus_retention_days}d",
    "--web.enable-remote-write-receiver",
  ]

  ports {
    internal = 9090
    external = 9090
  }

  env = ["TZ=UTC"]

  mounts {
    target    = "/prometheus-config"
    source    = "${local.repo}/config"
    type      = "bind"
    read_only = true
  }

  mounts {
    target    = "/etc/prometheus/rules"
    source    = "${local.repo}/monitoring/alerts"
    type      = "bind"
    read_only = true
  }

  mounts {
    target = "/prometheus"
    source = docker_volume.prometheus_data.name
    type   = "volume"
  }

  healthcheck {
    test         = ["CMD-SHELL", "wget -qO- http://localhost:9090/-/healthy || exit 1"]
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
  labels {
    label = "Environment"
    value = local.standard_tags.Environment
  }
  labels {
    label = "ManagedBy"
    value = local.standard_tags.ManagedBy
  }
  lifecycle {
    ignore_changes = [image, network_mode, mounts]
  }

}

# ── Grafana ───────────────────────────────────────────────────────────────────
resource "docker_container" "grafana" {
  name    = "code-server-grafana"
  image   = docker_image.grafana.image_id
  user    = "472:472"
  restart = "unless-stopped"

  depends_on = [
    docker_container.grafana_init,
    docker_container.prometheus,
  ]

  ports {
    internal = 3000
    external = 3000
  }

  env = [
    "GF_SECURITY_ADMIN_USER=${var.grafana_admin_user}",
    "GF_SECURITY_ADMIN_PASSWORD=${var.grafana_admin_password}",
    "GF_USERS_ALLOW_SIGN_UP=false",
    "GF_INSTALL_PLUGINS=grafana-piechart-panel",
  ]

  mounts {
    target = "/var/lib/grafana"
    source = docker_volume.grafana_data.name
    type   = "volume"
  }

  mounts {
    target    = "/etc/grafana/provisioning/dashboards"
    source    = "${local.repo}/config/grafana/provisioning/dashboards"
    type      = "bind"
    read_only = true
  }

  mounts {
    target    = "/etc/grafana/provisioning/datasources"
    source    = "${local.repo}/config/grafana/provisioning/datasources"
    type      = "bind"
    read_only = true
  }

  healthcheck {
    test         = ["CMD", "curl", "-f", "http://localhost:3000/api/health"]
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
  labels {
    label = "Environment"
    value = local.standard_tags.Environment
  }
  labels {
    label = "ManagedBy"
    value = local.standard_tags.ManagedBy
  }
  lifecycle {
    ignore_changes = [image, network_mode, mounts]
  }

}

# ── Loki ──────────────────────────────────────────────────────────────────────
resource "docker_container" "loki" {
  name    = "code-server-loki"
  image   = docker_image.loki.image_id
  user    = "10001:10001"
  restart = "unless-stopped"

  depends_on = [docker_container.loki_init]

  command = ["-config.file=/etc/loki/loki-config.yaml"]

  ports {
    internal = 3100
    external = 3100
  }

  env = ["LOG_LEVEL=info"]

  mounts {
    target    = "/etc/loki"
    source    = "${local.repo}/config/loki"
    type      = "bind"
    read_only = true
  }

  mounts {
    target = "/loki"
    source = docker_volume.loki_data.name
    type   = "volume"
  }

  healthcheck {
    test         = ["CMD-SHELL", "wget -qO- http://localhost:3100/ready || exit 1"]
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
  labels {
    label = "Environment"
    value = local.standard_tags.Environment
  }
  labels {
    label = "ManagedBy"
    value = local.standard_tags.ManagedBy
  }
  lifecycle {
    ignore_changes = [image, network_mode, mounts]
  }

}

# ── Alertmanager ──────────────────────────────────────────────────────────────
resource "docker_container" "alertmanager" {
  name    = "code-server-alertmanager"
  image   = docker_image.alertmanager.image_id
  user    = "65534:65534"
  restart = "unless-stopped"

  depends_on = [
    docker_container.alertmanager_init,
    docker_container.prometheus,
  ]

  command = [
    "--config.file=/etc/alertmanager/alertmanager.yml",
    "--storage.path=/alertmanager",
    "--web.external-url=http://alertmanager:9093",
  ]

  ports {
    internal = 9093
    external = 9093
  }

  mounts {
    target    = "/etc/alertmanager/alertmanager.yml"
    source    = "${local.repo}/monitoring/alertmanager.yml"
    type      = "bind"
    read_only = true
  }

  mounts {
    target = "/alertmanager"
    source = docker_volume.alertmanager_data.name
    type   = "volume"
  }

  healthcheck {
    test         = ["CMD-SHELL", "amtool --version >/dev/null && echo OK || exit 1"]
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
  labels {
    label = "Environment"
    value = local.standard_tags.Environment
  }
  labels {
    label = "ManagedBy"
    value = local.standard_tags.ManagedBy
  }
  lifecycle {
    ignore_changes = [image, network_mode, mounts]
  }

}

# ── Prometheus Alert Relay ────────────────────────────────────────────────────

# ── OpenTelemetry Collector ───────────────────────────────────────────────────
resource "docker_container" "otel_collector" {
  name    = "code-server-otel-collector"
  image   = docker_image.otel_collector.image_id
  user    = "65534:65534"
  restart = "unless-stopped"

  depends_on = [
    docker_container.loki,
    docker_container.prometheus,
    docker_container.tempo,
  ]

  command = ["--config=/etc/otel-collector.yaml"]

  ports {
    internal = 4317
    external = 4317
  }
  ports {
    internal = 4318
    external = 4318
  }
  ports {
    internal = 9200
    external = 9200
  }
  ports {
    internal = 13133
    external = 13133
  }

  env = ["DEPLOYMENT_ENV=production"]

  mounts {
    target    = "/etc/otel-collector.yaml"
    source    = "${local.repo}/config/otel-collector.config.yaml"
    type      = "bind"
    read_only = true
  }

  healthcheck {
    test         = ["CMD", "/otelcol-contrib", "--version"]
    interval     = "30s"
    timeout      = "5s"
    retries      = 3
    start_period = "15s"
  }

  networks_advanced {
    name = docker_network.services.id
  }

  log_driver = "json-file"
  log_opts   = local.log_json_file
  labels {
    label = "Environment"
    value = local.standard_tags.Environment
  }
  labels {
    label = "ManagedBy"
    value = local.standard_tags.ManagedBy
  }
  lifecycle {
    ignore_changes = [image, network_mode, mounts]
  }

}

# ── Grafana Tempo ─────────────────────────────────────────────────────────────
resource "docker_container" "tempo" {
  name    = "code-server-tempo"
  image   = docker_image.tempo.image_id
  user    = "10001:10001"
  restart = "unless-stopped"

  depends_on = [docker_container.tempo_init]

  command = ["-config.file=/etc/tempo.yaml"]

  ports {
    internal = 3201
    external = 3201
  }
  ports {
    internal = 3200
    external = 3200
  }

  mounts {
    target    = "/etc/tempo.yaml"
    source    = "${local.repo}/config/tempo.config.yaml"
    type      = "bind"
    read_only = true
  }

  mounts {
    target = "/var/tempo"
    source = docker_volume.tempo_data.name
    type   = "volume"
  }

  healthcheck {
    test         = ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:3200/status"]
    interval     = "30s"
    timeout      = "5s"
    retries      = 3
    start_period = "30s"
  }

  networks_advanced {
    name = docker_network.services.id
  }

  log_driver = "json-file"
  log_opts   = local.log_json_file
  labels {
    label = "Environment"
    value = local.standard_tags.Environment
  }
  labels {
    label = "ManagedBy"
    value = local.standard_tags.ManagedBy
  }
  lifecycle {
    ignore_changes = [image, network_mode, mounts]
  }

}
