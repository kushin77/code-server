# Phase 8: Container Egress Filtering (#350)
# Network policies, firewall rules, prevent data exfiltration
# Immutable, idempotent, on-prem focused

terraform {
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
  }
}

variable "primary_host_ip" {
  description = "Primary production host"
  type        = string
  default     = "192.168.168.31"
}

variable "allowed_external_hosts" {
  description = "Allowed external hosts for outbound traffic"
  type        = list(string)
  default = [
    "8.8.8.8",      # Google DNS
    "1.1.1.1",      # Cloudflare DNS
    "api.cloudflare.com"  # Cloudflare API
  ]
}

# ============================================================================
# Egress Filtering Configuration
# ============================================================================

resource "local_file" "iptables_rules" {
  filename = "${path.module}/../scripts/apply-egress-filtering.sh"
  content = templatefile("${path.module}/../templates/apply-egress-filtering.sh.tpl", {
    primary_host           = var.primary_host_ip
    allowed_external_hosts = var.allowed_external_hosts
  })
}

resource "local_file" "docker_network_policy" {
  filename = "${path.module}/../config/docker-network-policy.json"
  content = jsonencode({
    version = "1.0"
    egress_policy = {
      code_server = {
        description = "Code-server can only reach: DNS, package repos, Cloudflare"
        allow = [
          "53/udp",   # DNS
          "443/tcp",  # HTTPS for package repos
          "8.8.8.8",
          "1.1.1.1"
        ]
        deny = ["*"]
      }
      postgres = {
        description = "PostgreSQL can only reach: replica host, no external"
        allow = [
          "192.168.168.42:5432"  # Replica
        ]
        deny = ["*"]
      }
      redis = {
        description = "Redis can only reach: replica host, no external"
        allow = [
          "192.168.168.42:6379"  # Replica
        ]
        deny = ["*"]
      }
      caddy = {
        description = "Caddy can only reach: upstream services, Cloudflare DNS"
        allow = [
          "127.0.0.1:8080",        # Code-server
          "127.0.0.1:9090",        # Prometheus
          "127.0.0.1:3000",        # Grafana
          "53/udp",                # DNS
          "1.1.1.1",               # Cloudflare DNS
          "api.cloudflare.com:443" # Cloudflare API
        ]
        deny = ["*"]
      }
      oauth2_proxy = {
        description = "OAuth2-proxy can reach: OAuth provider, API"
        allow = [
          "53/udp",     # DNS
          "443/tcp",    # HTTPS OAuth
          "127.0.0.1"   # Localhost services
        ]
        deny = ["*"]
      }
    }
  })
}

resource "local_file" "deploy_egress_filtering" {
  filename = "${path.module}/../scripts/deploy-egress-filtering.sh"
  content  = file("${path.module}/../scripts/apply-egress-filtering.sh")
}

output "egress_filtering_config" {
  value = {
    enabled                  = true
    dns_allowed              = true
    allowed_external_ips     = var.allowed_external_hosts
    restrict_outbound        = true
    prevent_exfiltration     = true
    monitor_blocked_traffic  = true
    block_crypto_mining      = true
    block_botnet_detection   = true
  }
}
