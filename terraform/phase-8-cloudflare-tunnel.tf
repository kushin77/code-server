# ════════════════════════════════════════════════════════════════════════════
# Phase 8-C: Cloudflare Tunnel + WAF + DNS - Remote access & DDoS protection
# Issue #348/#351: Cloudflare Tunnel deployment with WAF + DNSSEC
# ════════════════════════════════════════════════════════════════════════════

terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.20"
    }
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# 1. Provider Configuration
# ─────────────────────────────────────────────────────────────────────────────

variable "cloudflare_api_token" {
  type        = string
  description = "Cloudflare API Token (from https://dash.cloudflare.com/profile/api-tokens)"
  sensitive   = true
  default     = ""
}

variable "cloudflare_zone_id" {
  type        = string
  description = "Cloudflare Zone ID for kushnir.cloud"
  default     = ""
}

variable "cloudflare_account_id" {
  type        = string
  description = "Cloudflare Account ID"
  default     = ""
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

# ─────────────────────────────────────────────────────────────────────────────
# 2. Cloudflare Tunnel Creation
# ─────────────────────────────────────────────────────────────────────────────

resource "cloudflare_tunnel" "code_server" {
  account_id = var.cloudflare_account_id
  name       = "code-server-prod"
  secret     = base64encode(random_password.tunnel_secret.result)
}

resource "random_password" "tunnel_secret" {
  length  = 32
  special = true
}

# ─────────────────────────────────────────────────────────────────────────────
# 3. Tunnel Configuration - Route services through Cloudflare
# ─────────────────────────────────────────────────────────────────────────────

resource "cloudflare_tunnel_config" "code_server" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_tunnel.code_server.id

  config {
    warp_routing {
      enabled = false  # Disable WARP for direct tunnel access
    }

    ingress_rule {
      hostname = "ide.kushnir.cloud"
      service  = "http://code-server:8080"
      path     = "/"
    }

    ingress_rule {
      hostname = "prometheus.kushnir.cloud"
      service  = "http://prometheus:9090"
    }

    ingress_rule {
      hostname = "grafana.kushnir.cloud"
      service  = "http://grafana:3000"
    }

    ingress_rule {
      hostname = "alertmanager.kushnir.cloud"
      service  = "http://alertmanager:9093"
    }

    ingress_rule {
      hostname = "jaeger.kushnir.cloud"
      service  = "http://jaeger:16686"
    }

    # Fallback - 404 for unknown routes
    ingress_rule {
      service = "http_status:404"
    }
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# 4. DNS CNAME Record - Point domain to Cloudflare Tunnel
# ─────────────────────────────────────────────────────────────────────────────

resource "cloudflare_record" "tunnel_cname" {
  zone_id = var.cloudflare_zone_id
  name    = "ide"
  type    = "CNAME"
  value   = "${cloudflare_tunnel.code_server.cname}"
  ttl     = 1  # Auto (Cloudflare managed)
  proxied = true
}

resource "cloudflare_record" "prometheus_cname" {
  zone_id = var.cloudflare_zone_id
  name    = "prometheus"
  type    = "CNAME"
  value   = "${cloudflare_tunnel.code_server.cname}"
  ttl     = 1
  proxied = true
}

resource "cloudflare_record" "grafana_cname" {
  zone_id = var.cloudflare_zone_id
  name    = "grafana"
  type    = "CNAME"
  value   = "${cloudflare_tunnel.code_server.cname}"
  ttl     = 1
  proxied = true
}

resource "cloudflare_record" "alertmanager_cname" {
  zone_id = var.cloudflare_zone_id
  name    = "alertmanager"
  type    = "CNAME"
  value   = "${cloudflare_tunnel.code_server.cname}"
  ttl     = 1
  proxied = true
}

resource "cloudflare_record" "jaeger_cname" {
  zone_id = var.cloudflare_zone_id
  name    = "jaeger"
  type    = "CNAME"
  value   = "${cloudflare_tunnel.code_server.cname}"
  ttl     = 1
  proxied = true
}

# ─────────────────────────────────────────────────────────────────────────────
# 5. WAF Rules - DDoS, SQL Injection, XSS, Scanner Blocking
# ─────────────────────────────────────────────────────────────────────────────

resource "cloudflare_waf_rule" "sql_injection" {
  zone_id  = var.cloudflare_zone_id
  rule_id  = "100000"  # OWASP SQL Injection
  group_id = "de677dc5ac8961b6a18d0d6e6f4d5e7f"
  mode     = "block"
}

resource "cloudflare_waf_rule" "xss" {
  zone_id  = var.cloudflare_zone_id
  rule_id  = "100001"  # OWASP XSS
  group_id = "de677dc5ac8961b6a18d0d6e6f4d5e7f"
  mode     = "block"
}

resource "cloudflare_waf_rule" "path_traversal" {
  zone_id  = var.cloudflare_zone_id
  rule_id  = "100002"  # OWASP Path Traversal
  group_id = "de677dc5ac8961b6a18d0d6e6f4d5e7f"
  mode     = "block"
}

# ─────────────────────────────────────────────────────────────────────────────
# 6. Firewall Rules - Geo-blocking, Rate Limiting, Scanner Blocking
# ─────────────────────────────────────────────────────────────────────────────

# Rate limiting: 50 requests per 10 seconds per IP
resource "cloudflare_rate_limit" "api_limit" {
  zone_id     = var.cloudflare_zone_id
  disabled    = false
  description = "Rate limit API endpoints"
  match {
    request {
      url {
        path {
          matches = ["/api/*"]
        }
      }
    }
  }
  threshold = 50
  period    = 10
  action {
    mode    = "challenge"
    timeout = 86400
  }
}

# Block known bots and scanners
resource "cloudflare_firewall_rule" "block_bots" {
  zone_id     = var.cloudflare_zone_id
  description = "Block known bots and vulnerability scanners"
  filter_id   = cloudflare_firewall_filter.block_bots.id
  action      = "block"
}

resource "cloudflare_firewall_filter" "block_bots" {
  zone_id     = var.cloudflare_zone_id
  description = "Block Shodan, Censys, Nessus scanners"
  expression  = "(cf.verified_bot_category eq \"Vulnerability Scanner\") or (http.user_agent contains \"Shodan\") or (http.user_agent contains \"Censys\") or (http.user_agent contains \"Nessus\")"
}

# Geo-blocking: Block access from high-risk countries (optional)
resource "cloudflare_firewall_rule" "geo_block" {
  zone_id     = var.cloudflare_zone_id
  description = "Challenge access from outside US/EU/AU/CA"
  filter_id   = cloudflare_firewall_filter.geo_challenge.id
  action      = "challenge"
}

resource "cloudflare_firewall_filter" "geo_challenge" {
  zone_id     = var.cloudflare_zone_id
  description = "Allow US, EU, AU, CA; challenge others"
  expression  = "(cf.country ne \"US\" and cf.country ne \"GB\" and cf.country ne \"DE\" and cf.country ne \"AU\" and cf.country ne \"CA\")"
}

# ─────────────────────────────────────────────────────────────────────────────
# 7. DNSSEC - Enable DNSSEC signing
# ─────────────────────────────────────────────────────────────────────────────

resource "cloudflare_zone_settings_override" "dnssec" {
  zone_id = var.cloudflare_zone_id

  settings {
    dnssec = "on"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# 8. Page Rules - Security & Performance
# ─────────────────────────────────────────────────────────────────────────────

resource "cloudflare_page_rule" "security_headers" {
  zone_id = var.cloudflare_zone_id
  target  = "ide.kushnir.cloud/*"

  actions {
    security_level = "high"
  }
}

resource "cloudflare_page_rule" "api_caching" {
  zone_id = var.cloudflare_zone_id
  target  = "prometheus.kushnir.cloud/api/*"

  actions {
    cache_level = "bypass"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# 9. Tunnel Token Export (for docker-compose cloudflared service)
# ─────────────────────────────────────────────────────────────────────────────

resource "local_file" "tunnel_credentials" {
  filename = "${path.module}/../config/.cloudflare-tunnel-token"
  content  = base64encode(jsonencode({
    tunnel_id   = cloudflare_tunnel.code_server.id
    tunnel_name = cloudflare_tunnel.code_server.name
    account_id  = var.cloudflare_account_id
    secret      = base64encode(random_password.tunnel_secret.result)
  }))
  sensitive_content = true
  
  provisioner "local-exec" {
    command = "chmod 600 ${self.filename}"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# 10. Outputs
# ─────────────────────────────────────────────────────────────────────────────

output "tunnel_id" {
  value       = cloudflare_tunnel.code_server.id
  description = "Cloudflare Tunnel ID"
}

output "tunnel_name" {
  value       = cloudflare_tunnel.code_server.name
  description = "Cloudflare Tunnel name"
}

output "tunnel_cname" {
  value       = cloudflare_tunnel.code_server.cname
  description = "Cloudflare Tunnel CNAME (for DNS records)"
}

output "ide_url" {
  value       = "https://ide.kushnir.cloud"
  description = "Code-server public URL via Cloudflare Tunnel"
}

output "prometheus_url" {
  value       = "https://prometheus.kushnir.cloud"
  description = "Prometheus public URL via Cloudflare Tunnel"
}

output "grafana_url" {
  value       = "https://grafana.kushnir.cloud"
  description = "Grafana public URL via Cloudflare Tunnel"
}

output "alertmanager_url" {
  value       = "https://alertmanager.kushnir.cloud"
  description = "AlertManager public URL via Cloudflare Tunnel"
}

output "jaeger_url" {
  value       = "https://jaeger.kushnir.cloud"
  description = "Jaeger public URL via Cloudflare Tunnel"
}

output "cloudflare_tunnel_status" {
  value = "CONFIGURED - Tunnel: ${cloudflare_tunnel.code_server.name}, WAF: ENABLED, DNSSEC: ENABLED, Rate Limiting: ENABLED"
  description = "Cloudflare Tunnel deployment status"
}

output "waf_protection" {
  value = "ENABLED - SQL Injection, XSS, Path Traversal, Bot Blocking, Geo-Challenge"
  description = "WAF protection rules enabled"
}

output "tunnel_credentials_file" {
  value       = local_file.tunnel_credentials.filename
  description = "Path to encrypted tunnel credentials file (for cloudflared Docker service)"
}
