# terraform/phase-9-cloudflare-tunnel.tf
# Phase 9: Cloudflare Tunnel with Workers & Load Balancing
# Complete tunnel configuration, origin authentication, and traffic management

terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.27"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

# ============================================================================
# TUNNEL CREDENTIALS & SECRETS
# ============================================================================

resource "random_bytes" "tunnel_secret" {
  length = 32
}

# ============================================================================
# CLOUDFLARE TUNNEL (Primary & Replica)
# ============================================================================

resource "cloudflare_tunnel" "code_server_primary" {
  account_id = var.cloudflare_account_id
  name       = "${var.tunnel_name_prefix}-primary"
  secret     = base64encode(random_bytes.tunnel_secret.result)

  depends_on = [random_bytes.tunnel_secret]
}

resource "cloudflare_tunnel" "code_server_replica" {
  account_id = var.cloudflare_account_id
  name       = "${var.tunnel_name_prefix}-replica"
  secret     = base64encode(random_bytes.tunnel_secret.result)

  depends_on = [random_bytes.tunnel_secret]
}

# ============================================================================
# TUNNEL CONFIGURATION - Primary (192.168.168.31)
# ============================================================================

resource "cloudflare_tunnel_config" "code_server_primary" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_tunnel.code_server_primary.id

  config {
    # Code-Server IDE
    ingress_rule {
      hostname = "ide.${var.domain}"
      service  = "http://${var.primary_host_ip}:8080"
      
      origin_request {
        http_host_header = "ide.${var.domain}"
        connect_timeout  = 30
        tlsTimeout       = 30
        tcp_keep_alive   = 30
      }
    }

    # OAuth2-Proxy (Auth Gateway)
    ingress_rule {
      hostname = "auth.${var.domain}"
      service  = "http://${var.primary_host_ip}:4180"
      
      origin_request {
        http_host_header = "auth.${var.domain}"
        connect_timeout  = 10
      }
    }

    # Prometheus
    ingress_rule {
      hostname = "prometheus.${var.domain}"
      service  = "http://${var.primary_host_ip}:9090"
      
      origin_request {
        http_host_header = "prometheus.${var.domain}"
        connect_timeout  = 15
      }
    }

    # Grafana
    ingress_rule {
      hostname = "grafana.${var.domain}"
      service  = "http://${var.primary_host_ip}:3000"
      
      origin_request {
        http_host_header = "grafana.${var.domain}"
        connect_timeout  = 15
      }
    }

    # AlertManager
    ingress_rule {
      hostname = "alerts.${var.domain}"
      service  = "http://${var.primary_host_ip}:9093"
      
      origin_request {
        http_host_header = "alerts.${var.domain}"
        connect_timeout  = 10
      }
    }

    # Jaeger Tracing
    ingress_rule {
      hostname = "tracing.${var.domain}"
      service  = "http://${var.primary_host_ip}:16686"
      
      origin_request {
        http_host_header = "tracing.${var.domain}"
        connect_timeout  = 15
      }
    }

    # Health Check
    ingress_rule {
      hostname = "health.${var.domain}"
      path     = "/ping"
      service  = "http_status:200"
    }

    # Catch-All
    ingress_rule {
      service = "http_status:503"
    }
  }
}

# ============================================================================
# TUNNEL CONFIGURATION - Replica (192.168.168.42)
# ============================================================================

resource "cloudflare_tunnel_config" "code_server_replica" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_tunnel.code_server_replica.id

  config {
    # Replica IDE
    ingress_rule {
      hostname = "ide-replica.${var.domain}"
      service  = "http://${var.replica_host_ip}:8080"
      
      origin_request {
        http_host_header = "ide-replica.${var.domain}"
        connect_timeout  = 30
      }
    }

    # Replica Prometheus
    ingress_rule {
      hostname = "prometheus-replica.${var.domain}"
      service  = "http://${var.replica_host_ip}:9090"
      
      origin_request {
        http_host_header = "prometheus-replica.${var.domain}"
      }
    }

    # Catch-All
    ingress_rule {
      service = "http_status:503"
    }
  }
}

# ============================================================================
# TUNNEL CNAME RECORDS
# ============================================================================

resource "cloudflare_record" "tunnel_cname_primary" {
  zone_id = var.cloudflare_zone_id
  name    = "*.tunnel"
  type    = "CNAME"
  content = cloudflare_tunnel.code_server_primary.cname
  ttl     = 3600
  comment = "Phase 9: Cloudflare Tunnel Primary"
}

resource "cloudflare_record" "tunnel_cname_replica" {
  zone_id = var.cloudflare_zone_id
  name    = "*.tunnel-replica"
  type    = "CNAME"
  content = cloudflare_tunnel.code_server_replica.cname
  ttl     = 3600
  comment = "Phase 9: Cloudflare Tunnel Replica"
}

# ============================================================================
# OUTPUTS
# ============================================================================

output "tunnel_primary_id" {
  value       = cloudflare_tunnel.code_server_primary.id
  description = "Primary tunnel ID for cloudflared configuration"
}

output "tunnel_replica_id" {
  value       = cloudflare_tunnel.code_server_replica.id
  description = "Replica tunnel ID for failover"
}

output "tunnel_primary_cname" {
  value       = cloudflare_tunnel.code_server_primary.cname
  description = "Primary tunnel CNAME endpoint"
}

output "tunnel_replica_cname" {
  value       = cloudflare_tunnel.code_server_replica.cname
  description = "Replica tunnel CNAME endpoint"
}
