# terraform/cloudflare.tf
# Cloudflare Tunnel Configuration for ide.kushnir.cloud
# Manages tunnel, DNS routing, and origin authentication

terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

# ============================================================================
# Cloudflare Tunnel
# ============================================================================

resource "cloudflare_tunnel" "code_server" {
  account_id = var.cloudflare_account_id
  name       = "code-server-production"
  secret     = base64encode(random_bytes.tunnel_secret.result)
}

resource "random_bytes" "tunnel_secret" {
  length = 32
}

# ============================================================================
# Tunnel Configuration
# ============================================================================

resource "cloudflare_tunnel_config" "code_server" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_tunnel.code_server.id

  config {
    # Main code-server endpoint
    ingress_rule {
      hostname = "ide.kushnir.cloud"
      path     = ""
      service  = "http://${var.primary_host_ip}:8080"

      origin_request {
        http_host_header = "ide.kushnir.cloud"
      }
    }

    # Prometheus monitoring
    ingress_rule {
      hostname = "prometheus.ide.kushnir.cloud"
      service  = "http://${var.primary_host_ip}:9090"

      origin_request {
        http_host_header = "prometheus.ide.kushnir.cloud"
      }
    }

    # Grafana dashboards
    ingress_rule {
      hostname = "grafana.ide.kushnir.cloud"
      service  = "http://${var.primary_host_ip}:3000"

      origin_request {
        http_host_header = "grafana.ide.kushnir.cloud"
      }
    }

    # Jaeger tracing
    ingress_rule {
      hostname = "jaeger.ide.kushnir.cloud"
      service  = "http://${var.primary_host_ip}:16686"

      origin_request {
        http_host_header = "jaeger.ide.kushnir.cloud"
      }
    }

    # AlertManager
    ingress_rule {
      hostname = "alertmanager.ide.kushnir.cloud"
      service  = "http://${var.primary_host_ip}:9093"

      origin_request {
        http_host_header = "alertmanager.ide.kushnir.cloud"
      }
    }

    # Catch-all: return 503
    ingress_rule {
      service = "http_status:503"
    }
  }
}

# ============================================================================
# DNS Records
# ============================================================================

data "cloudflare_zone" "kushnir_cloud" {
  name = "kushnir.cloud"
}

# ide.kushnir.cloud CNAME -> tunnel endpoint
resource "cloudflare_record" "ide_main" {
  zone_id = data.cloudflare_zone.kushnir_cloud.id
  name    = "ide"
  type    = "CNAME"
  content = "${cloudflare_tunnel.code_server.id}.cfargotunnel.com"
  ttl     = 1  # Auto (Cloudflare)
  proxied = true
}

# Wildcard subdomains (prometheus, grafana, jaeger, alertmanager)
resource "cloudflare_record" "ide_wildcard" {
  zone_id = data.cloudflare_zone.kushnir_cloud.id
  name    = "*.ide"
  type    = "CNAME"
  content = "${cloudflare_tunnel.code_server.id}.cfargotunnel.com"
  ttl     = 1
  proxied = true
}

# ============================================================================
# Security Policies
# ============================================================================

# WAF rules for tunnel
resource "cloudflare_waf_rules" "tunnel_protection" {
  zone_id = data.cloudflare_zone.kushnir_cloud.id

  # Enable OWASP Core Rule Set
  group_id = "62d9e08876a4b126530b7115"  # OWASP ModSecurity Core Rule Set
  mode     = "block"  # Block suspicious requests
}

# Rate limiting
resource "cloudflare_rate_limit" "tunnel_rate_limit" {
  zone_id    = data.cloudflare_zone.kushnir_cloud.id
  disabled   = false
  threshold  = 100  # 100 requests per period
  period     = 60   # Per 60 seconds
  match_type = "request"

  match {
    request {
      url_path = "/*"
    }
  }

  action {
    mode    = "block"
    timeout = 300  # Block for 5 minutes
  }

  description = "Rate limit tunnel to prevent abuse"
}

# ============================================================================
# Outputs
# ============================================================================

output "tunnel_id" {
  value       = cloudflare_tunnel.code_server.id
  description = "Cloudflare Tunnel ID"
}

output "tunnel_token" {
  value       = cloudflare_tunnel.code_server.id
  sensitive   = true
  description = "Tunnel credentials (use in systemd service)"
}

output "tunnel_cname" {
  value       = "${cloudflare_tunnel.code_server.id}.cfargotunnel.com"
  description = "Tunnel CNAME target for DNS"
}

output "ide_url" {
  value       = "https://ide.kushnir.cloud"
  description = "Public IDE URL"
}
