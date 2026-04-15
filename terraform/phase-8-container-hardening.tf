# Phase 8: Container Hardening (#354)
# Drop capabilities, read-only filesystems, security options, apparmor
# Immutable, idempotent, on-prem focused

variable "primary_host_ip" {
  description = "Primary production host"
  type        = string
  default     = "192.168.168.31"
}

# ============================================================================
# Container Hardening Configuration
# ============================================================================

resource "local_file" "docker_compose_hardened" {
  filename = "${path.module}/../docker-compose.hardened.yml"
  content = templatefile("${path.module}/../templates/docker-compose.hardened.tpl", {
    code_server_image    = "codercom/code-server:4.115.0"
    postgres_image       = "postgres:15-alpine"
    redis_image          = "redis:7-alpine"
    caddy_image          = "caddy:2.7.6-alpine"
    prometheus_image     = "prom/prometheus:v2.48.0"
    grafana_image        = "grafana/grafana:10.2.3"
    jaeger_image         = "jaegertracing/all-in-one:1.50"
    alertmanager_image   = "prom/alertmanager:v0.26.0"
    oauth2_proxy_image   = "quay.io/oauth2-proxy/oauth2-proxy:v7.5.1"
  })
}

resource "local_file" "apparmor_profile" {
  filename = "${path.module}/../config/apparmor.d-code-server"
  content = file("${path.module}/../config/apparmor.d-code-server")
}

resource "local_file" "seccomp_profile" {
  filename = "${path.module}/../config/seccomp-default.json"
  content = file("${path.module}/../config/seccomp-default.json")
}

resource "local_file" "deploy_container_hardening" {
  filename = "${path.module}/../scripts/deploy-container-hardening.sh"
  content  = templatefile("${path.module}/../templates/deploy-container-hardening.sh.tpl", {
    primary_host = var.primary_host_ip
  })
}

output "container_hardening_config" {
  value = {
    capabilities_dropped = [
      "NET_RAW",
      "SYS_CHROOT",
      "KILL",
      "SETFCAP",
      "SYS_MODULE",
      "SYS_BOOT",
      "SYS_PTRACE"
    ]
    read_only_filesystem = true
    security_options = [
      "no-new-privileges",
      "apparmor=docker-default"
    ]
    seccomp_profile = "default"
    resource_limits = {
      memory     = "512M"
      cpus       = "1"
      pids_limit = 256
    }
  }
}
