# terraform/phase-9-cloudflare-dns.tf
# Phase 9: DNS + DNSSEC + CAA + Load Balancing

terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.27"
    }
  }
}

# ============================================================================
# DNSSEC CONFIGURATION
# ============================================================================

resource "cloudflare_zone_dnssec" "main" {
  zone_id = var.cloudflare_zone_id
  status  = var.dnssec_enabled ? "active" : "inactive"
}

# ============================================================================
# DNS RECORDS - Service Endpoints
# ============================================================================

resource "cloudflare_record" "ide" {
  zone_id = var.cloudflare_zone_id
  name    = "ide"
  type    = "CNAME"
  content = cloudflare_tunnel.code_server_primary.cname
  ttl     = 3600
  proxied = true
  comment = "Phase 9: Code-Server IDE"
}

resource "cloudflare_record" "prometheus" {
  zone_id = var.cloudflare_zone_id
  name    = "prometheus"
  type    = "CNAME"
  content = cloudflare_tunnel.code_server_primary.cname
  ttl     = 3600
  proxied = true
  comment = "Phase 9: Prometheus metrics"
}

resource "cloudflare_record" "grafana" {
  zone_id = var.cloudflare_zone_id
  name    = "grafana"
  type    = "CNAME"
  content = cloudflare_tunnel.code_server_primary.cname
  ttl     = 3600
  proxied = true
  comment = "Phase 9: Grafana dashboards"
}

resource "cloudflare_record" "alertmanager" {
  zone_id = var.cloudflare_zone_id
  name    = "alerts"
  type    = "CNAME"
  content = cloudflare_tunnel.code_server_primary.cname
  ttl     = 3600
  proxied = true
  comment = "Phase 9: AlertManager"
}

resource "cloudflare_record" "jaeger" {
  zone_id = var.cloudflare_zone_id
  name    = "tracing"
  type    = "CNAME"
  content = cloudflare_tunnel.code_server_primary.cname
  ttl     = 3600
  proxied = true
  comment = "Phase 9: Jaeger tracing"
}

resource "cloudflare_record" "auth" {
  zone_id = var.cloudflare_zone_id
  name    = "auth"
  type    = "CNAME"
  content = cloudflare_tunnel.code_server_primary.cname
  ttl     = 3600
  proxied = true
  comment = "Phase 9: OAuth2-Proxy"
}

# ============================================================================
# CAA RECORDS - Certificate Authority Authorization
# ============================================================================

resource "cloudflare_record" "caa_letsencrypt" {
  zone_id = var.cloudflare_zone_id
  name    = "@"
  type    = "CAA"
  
  data {
    flags = 0
    tag   = "issue"
    value = "letsencrypt.org"
  }

  comment = "Phase 9: Let's Encrypt CAA"
}

resource "cloudflare_record" "caa_cloudflare" {
  zone_id = var.cloudflare_zone_id
  name    = "@"
  type    = "CAA"
  
  data {
    flags = 0
    tag   = "issue"
    value = "cloudflare.com"
  }

  comment = "Phase 9: Cloudflare CAA"
}

resource "cloudflare_record" "caa_iodef" {
  zone_id = var.cloudflare_zone_id
  name    = "@"
  type    = "CAA"
  
  data {
    flags = 0
    tag   = "iodef"
    value = "mailto:${var.security_email}"
  }

  comment = "Phase 9: Security reporting"
}

# ============================================================================
# TXT RECORDS - Email Authentication
# ============================================================================

resource "cloudflare_record" "spf" {
  zone_id = var.cloudflare_zone_id
  name    = "@"
  type    = "TXT"
  content = "v=spf1 include:_spf.google.com ~all"
  comment = "Phase 9: SPF record"
}

resource "cloudflare_record" "dmarc" {
  zone_id = var.cloudflare_zone_id
  name    = "_dmarc"
  type    = "TXT"
  content = "v=DMARC1; p=quarantine; rua=mailto:${var.security_email}"
  comment = "Phase 9: DMARC policy"
}

# ============================================================================
# LOAD BALANCER - DNS-level failover
# ============================================================================

resource "cloudflare_load_balancer" "ide_primary" {
  zone_id = var.cloudflare_zone_id
  name    = "ide.${var.domain}"
  
  default_pool_ids = [cloudflare_load_balancer_pool.primary.id]
  fallback_pool_id = cloudflare_load_balancer_pool.replica.id
  
  description       = "Phase 9: IDE load balancer"
  ttl               = 30
  steering_policy   = "dynamic_latency"
  session_affinity  = "ip_cookie"
  session_affinity_ttl = 1800

  depends_on = [
    cloudflare_load_balancer_pool.primary,
    cloudflare_load_balancer_pool.replica
  ]
}

resource "cloudflare_load_balancer_pool" "primary" {
  account_id = var.cloudflare_account_id
  name       = "ide-primary"
  
  origins {
    name    = "primary"
    address = "${var.primary_host_ip}:8080"
    enabled = true
  }
  
  description = "Primary pool"
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
  
  description = "Replica pool"
  monitor     = cloudflare_load_balancer_monitor.health.id
}

resource "cloudflare_load_balancer_monitor" "health" {
  account_id = var.cloudflare_account_id
  
  type        = "http"
  port        = 8080
  method      = "GET"
  uri         = "/health"
  interval    = 60
  timeout     = 5
  retries     = 2
  
  description = "Health check"
  allow_insecure = true
}

# ============================================================================
# OUTPUTS
# ============================================================================

output "dnssec_status" {
  value = var.dnssec_enabled ? "enabled" : "disabled"
}

output "caa_records_configured" {
  value = 3
}

output "dns_records_configured" {
  value = 6
}

output "load_balancer_pools" {
  value = 2
}
