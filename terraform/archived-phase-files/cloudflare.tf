# terraform/cloudflare.tf
# Consolidated Cloudflare Configuration
# Manages: Tunnels (Primary/Replica), DNS Records, Security Policies, Load Balancing
# Status: Production-Ready, Immutable, Duplicate-Free
# Consolidates: cloudflare.tf + phase-9-cloudflare-tunnel.tf + phase-9-cloudflare-dns.tf

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
# CLOUDFLARE TUNNELS - Primary & Replica
# ============================================================================

# Primary Tunnel (192.168.168.31)
resource "cloudflare_tunnel" "code_server_primary" {
  account_id = var.cloudflare_account_id
  name       = "${var.tunnel_name_prefix}-primary"
  secret     = base64encode(random_bytes.tunnel_secret.result)

  depends_on = [random_bytes.tunnel_secret]
}

# Replica Tunnel (192.168.168.42)
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
# DATA SOURCE - Zone Information
# ============================================================================

data "cloudflare_zone" "main" {
  name = var.domain
}

# ============================================================================
# DNSSEC CONFIGURATION
# ============================================================================

resource "cloudflare_zone_dnssec" "main" {
  zone_id = data.cloudflare_zone.main.id
  status  = var.dnssec_enabled ? "active" : "inactive"
}

# ============================================================================
# DNS RECORDS - Tunnel CNAMEs
# ============================================================================

resource "cloudflare_record" "tunnel_cname_primary" {
  zone_id = data.cloudflare_zone.main.id
  name    = "*.tunnel"
  type    = "CNAME"
  content = cloudflare_tunnel.code_server_primary.cname
  ttl     = 3600
  comment = "Primary Tunnel CNAME"
}

resource "cloudflare_record" "tunnel_cname_replica" {
  zone_id = data.cloudflare_zone.main.id
  name    = "*.tunnel-replica"
  type    = "CNAME"
  content = cloudflare_tunnel.code_server_replica.cname
  ttl     = 3600
  comment = "Replica Tunnel CNAME"
}

# ============================================================================
# DNS RECORDS - Service Endpoints
# ============================================================================

resource "cloudflare_record" "ide" {
  zone_id = data.cloudflare_zone.main.id
  name    = "ide"
  type    = "CNAME"
  content = cloudflare_tunnel.code_server_primary.cname
  ttl     = 3600
  proxied = true
  comment = "Code-Server IDE"
}

resource "cloudflare_record" "prometheus" {
  zone_id = data.cloudflare_zone.main.id
  name    = "prometheus"
  type    = "CNAME"
  content = cloudflare_tunnel.code_server_primary.cname
  ttl     = 3600
  proxied = true
  comment = "Prometheus metrics"
}

resource "cloudflare_record" "grafana" {
  zone_id = data.cloudflare_zone.main.id
  name    = "grafana"
  type    = "CNAME"
  content = cloudflare_tunnel.code_server_primary.cname
  ttl     = 3600
  proxied = true
  comment = "Grafana dashboards"
}

resource "cloudflare_record" "alertmanager" {
  zone_id = data.cloudflare_zone.main.id
  name    = "alerts"
  type    = "CNAME"
  content = cloudflare_tunnel.code_server_primary.cname
  ttl     = 3600
  proxied = true
  comment = "AlertManager"
}

resource "cloudflare_record" "jaeger" {
  zone_id = data.cloudflare_zone.main.id
  name    = "tracing"
  type    = "CNAME"
  content = cloudflare_tunnel.code_server_primary.cname
  ttl     = 3600
  proxied = true
  comment = "Jaeger tracing"
}

resource "cloudflare_record" "auth" {
  zone_id = data.cloudflare_zone.main.id
  name    = "auth"
  type    = "CNAME"
  content = cloudflare_tunnel.code_server_primary.cname
  ttl     = 3600
  proxied = true
  comment = "OAuth2-Proxy authentication"
}

# ============================================================================
# DNS RECORDS - CAA (Certificate Authority Authorization)
# ============================================================================

resource "cloudflare_record" "caa_letsencrypt" {
  zone_id = data.cloudflare_zone.main.id
  name    = "@"
  type    = "CAA"

  data {
    flags = 0
    tag   = "issue"
    value = "letsencrypt.org"
  }

  comment = "Let's Encrypt CAA"
}

resource "cloudflare_record" "caa_cloudflare" {
  zone_id = data.cloudflare_zone.main.id
  name    = "@"
  type    = "CAA"

  data {
    flags = 0
    tag   = "issue"
    value = "cloudflare.com"
  }

  comment = "Cloudflare CAA"
}

resource "cloudflare_record" "caa_iodef" {
  zone_id = data.cloudflare_zone.main.id
  name    = "@"
  type    = "CAA"

  data {
    flags = 0
    tag   = "iodef"
    value = "mailto:${var.security_email}"
  }

  comment = "Security reporting email"
}

# ============================================================================
# DNS RECORDS - Email Authentication (SPF, DMARC)
# ============================================================================

resource "cloudflare_record" "spf" {
  zone_id = data.cloudflare_zone.main.id
  name    = "@"
  type    = "TXT"
  content = "v=spf1 include:_spf.google.com ~all"
  comment = "SPF record for email authentication"
}

resource "cloudflare_record" "dmarc" {
  zone_id = data.cloudflare_zone.main.id
  name    = "_dmarc"
  type    = "TXT"
  content = "v=DMARC1; p=quarantine; rua=mailto:${var.security_email}"
  comment = "DMARC policy for email authentication"
}

# ============================================================================
# LOAD BALANCER - DNS-level Failover
# ============================================================================

resource "cloudflare_load_balancer_monitor" "health" {
  account_id = var.cloudflare_account_id
  type       = "http"
  port       = 8080
  method     = "GET"
  path       = "/health"
  interval   = 60
  timeout    = 5
  retries    = 2

  allow_insecure = true
  description    = "Health check for IDE endpoints"
}

resource "cloudflare_load_balancer_pool" "primary" {
  account_id = var.cloudflare_account_id
  name       = "ide-primary"

  origins {
    name    = "primary"
    address = "${var.primary_host_ip}:8080"
    enabled = true
  }

  description = "Primary production pool (192.168.168.31)"
  monitor     = cloudflare_load_balancer_monitor.health.id
}

resource "cloudflare_load_balancer_pool" "replica" {
  account_id = var.cloudflare_account_id
  name       = "ide-replica"

  origins {
    name    = "replica"
    address = "${var.replica_host_ip}:8080"
    enabled = true
  }

  description = "Replica failover pool (192.168.168.42)"
  monitor     = cloudflare_load_balancer_monitor.health.id
}

resource "cloudflare_load_balancer" "ide_main" {
  zone_id = data.cloudflare_zone.main.id
  name    = "ide.${var.domain}"

  default_pool_ids = [cloudflare_load_balancer_pool.primary.id]
  fallback_pool_id = cloudflare_load_balancer_pool.replica.id

  description          = "IDE load balancer with failover"
  ttl                  = 30
  steering_policy      = "dynamic_latency"
  session_affinity     = "ip_cookie"
  session_affinity_ttl = 1800

  depends_on = [
    cloudflare_load_balancer_pool.primary,
    cloudflare_load_balancer_pool.replica
  ]
}

# ============================================================================
# SECURITY POLICIES
# ============================================================================

# WAF rules for tunnel
resource "cloudflare_waf_rules" "tunnel_protection" {
  zone_id = data.cloudflare_zone.main.id

  # Enable OWASP Core Rule Set
  group_id = "62d9e08876a4b126530b7115" # OWASP ModSecurity Core Rule Set
  mode     = "block"                    # Block suspicious requests
}

# Rate limiting
resource "cloudflare_rate_limit" "tunnel_rate_limit" {
  zone_id    = data.cloudflare_zone.main.id
  disabled   = false
  threshold  = 100 # 100 requests per period
  period     = 60  # Per 60 seconds
  match_type = "request"

  match {
    request {
      url_path = "/*"
    }
  }

  action {
    mode    = "block"
    timeout = 300 # Block for 5 minutes
  }

  description = "Rate limit tunnel to prevent abuse"
}

# ============================================================================
# Outputs
# ============================================================================

output "tunnel_id_primary" {
  value       = cloudflare_tunnel.code_server_primary.id
  description = "Primary Cloudflare Tunnel ID"
}

output "tunnel_cname_primary" {
  value       = cloudflare_tunnel.code_server_primary.cname
  description = "Primary Tunnel CNAME target for DNS"
}

output "tunnel_id_replica" {
  value       = cloudflare_tunnel.code_server_replica.id
  description = "Replica Cloudflare Tunnel ID"
}

output "tunnel_cname_replica" {
  value       = cloudflare_tunnel.code_server_replica.cname
  description = "Replica Tunnel CNAME target for DNS"
}

output "ide_url_primary" {
  value       = "https://ide.${var.domain}"
  description = "Primary IDE URL"
}

output "ide_url_replica" {
  value       = "https://ide-replica.${var.domain}"
  description = "Replica IDE URL"
}
