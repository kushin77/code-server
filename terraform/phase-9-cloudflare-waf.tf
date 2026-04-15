# terraform/phase-9-cloudflare-waf.tf
# Phase 9: WAF Rules + Rate Limiting + DDoS Protection

# ============================================================================
# WAF RULES
# ============================================================================

resource "cloudflare_waf_rules" "owasp_crs" {
  zone_id = var.cloudflare_zone_id
  group_id = "de677d446b59101dbf91cb1eba3c690f"  # OWASP Core Rule Set

  rules = {
    "100000" = "on"    # SQLi Protection
    "100001" = "on"    # Local File Inclusion
    "100002" = "on"    # Remote File Inclusion
    "100003" = "on"    # PHP Injection
    "100004" = "on"    # Cross-Site Scripting
    "100005" = "on"    # CSRF
    "100006" = "on"    # Session Fixation
    "100007" = "on"    # Scanner Detection
  }
}

# ============================================================================
# RATE LIMITING
# ============================================================================

resource "cloudflare_rate_limit" "auth_endpoint" {
  zone_id = var.cloudflare_zone_id
  enabled = true
  
  threshold = 10
  period    = 60

  match {
    request {
      url_path = {
        path_contains = "/auth"
      }
    }
  }

  action {
    mode    = "challenge"
    timeout = 86400
  }

  description = "Phase 9: Rate limit auth endpoints"
}

resource "cloudflare_rate_limit" "api_general" {
  zone_id = var.cloudflare_zone_id
  enabled = true
  
  threshold = 100
  period    = 60

  match {
    request {
      url_path = {
        path_contains = "/api"
      }
    }
  }

  action {
    mode    = "challenge"
    timeout = 3600
  }

  description = "Phase 9: Rate limit general API"
}

# ============================================================================
# FIREWALL RULES
# ============================================================================

resource "cloudflare_firewall_rule" "block_suspicious_user_agents" {
  zone_id     = var.cloudflare_zone_id
  description = "Phase 9: Block known malicious user agents"
  filter_id   = cloudflare_filter.malicious_user_agents.id
  action      = "block"
  priority    = 1
}

resource "cloudflare_filter" "malicious_user_agents" {
  zone_id = var.cloudflare_zone_id
  description = "Malicious user agents"
  expression  = "(cf.http.request.headers[\"user-agent\"] contains \"bot\") or (cf.http.request.headers[\"user-agent\"] contains \"sqlmap\")"
}

resource "cloudflare_firewall_rule" "block_path_traversal" {
  zone_id     = var.cloudflare_zone_id
  description = "Phase 9: Block path traversal attempts"
  filter_id   = cloudflare_filter.path_traversal.id
  action      = "block"
  priority    = 2
}

resource "cloudflare_filter" "path_traversal" {
  zone_id = var.cloudflare_zone_id
  description = "Path traversal attempts"
  expression  = "(http.request.uri.path contains \"../\") or (http.request.uri.path contains \"..\\\\\")"
}

# ============================================================================
# ZONE SETTINGS - DDoS & Security
# ============================================================================

resource "cloudflare_zone_settings_override" "ddos_protection" {
  zone_id = var.cloudflare_zone_id

  settings {
    advanced_ddos           = "on"
    min_tls_version         = "1.3"
    ssl                     = "strict"
    http3                   = "on"
    http2                   = "on"
    brotli                  = "on"
    gzip                    = "on"
    cache_level             = "cache_everything"
    browser_cache_ttl       = 14400
    security_level          = "medium"
    challenge_passage       = 1800
    browser_check           = "on"
    ip_geolocation          = "on"
    waf                     = "on"
    disable_universal_ssl   = false
  }
}

# ============================================================================
# OUTPUTS
# ============================================================================

output "waf_enabled" {
  value = true
}

output "rate_limits_configured" {
  value = 2
}

output "firewall_rules_configured" {
  value = 2
}
