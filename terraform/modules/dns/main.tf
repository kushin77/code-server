# DNS Module Main Configuration
# P2 #418 Phase 2

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

locals {
  dns_labels = merge(
    var.labels,
    {
      module = "dns"
    }
  )
}

# Cloudflare Tunnel (encrypted connection to on-prem)
resource "cloudflare_tunnel" "main" {
  account_id = var.cloudflare_account_id
  name       = var.tunnel_name
  secret     = random_bytes.tunnel_secret.base64
}

# Random tunnel secret
resource "random_bytes" "tunnel_secret" {
  length = 32
}

# Cloudflare Tunnel DNS Records
resource "cloudflare_record" "tunnel" {
  zone_id = var.cloudflare_zone_id
  name    = "@"
  type    = "CNAME"
  value   = cloudflare_tunnel.main.cname
  ttl     = 1
  proxied = true
}

# Primary DNS Record (A record pointing to primary server)
resource "cloudflare_record" "primary" {
  zone_id = var.cloudflare_zone_id
  name    = "@"
  type    = "A"
  value   = var.primary_ip
  ttl     = var.dns_ttl
  proxied = false
}

# Secondary DNS Record (failover)
resource "cloudflare_record" "secondary" {
  zone_id  = var.cloudflare_zone_id
  name     = "@"
  type     = "A"
  value    = var.secondary_ip
  ttl      = var.dns_ttl
  proxied  = false
  priority = 10 # Lower priority for failover
}

# Cloudflare Load Balancer (health checks + failover)
resource "cloudflare_load_balancer" "main" {
  zone_id = var.cloudflare_zone_id
  name    = var.apex_domain
  ttl     = var.dns_ttl

  fallback_pool_id = cloudflare_load_balancer_pool.secondary.id
  default_pool_ids = [cloudflare_load_balancer_pool.primary.id]

  description = "Load balancer with automatic failover"
  proxied     = true

  session_affinity     = "cookie"
  session_affinity_ttl = 82800 # 23 hours
}

# Primary Pool
resource "cloudflare_load_balancer_pool" "primary" {
  account_id = var.cloudflare_account_id
  name       = "${var.apex_domain}-primary"

  origins {
    name    = "primary-server"
    address = var.primary_ip
    enabled = true
  }

  check_regions = ["WNAM", "ENAM", "WEU", "EASIA"]
  description   = "Primary on-premises server"
}

# Secondary Pool (Failover)
resource "cloudflare_load_balancer_pool" "secondary" {
  account_id = var.cloudflare_account_id
  name       = "${var.apex_domain}-secondary"

  origins {
    name    = "secondary-server"
    address = var.secondary_ip
    enabled = true
  }

  check_regions = ["WNAM", "ENAM", "WEU", "EASIA"]
  description   = "Secondary/failover on-premises server"
}

# Health Check for Primary
resource "cloudflare_load_balancer_monitor" "primary_health" {
  account_id = var.cloudflare_account_id

  type        = "http"
  port        = 443
  method      = "GET"
  path        = "/health"
  description = "Health check for primary server"

  interval = var.health_check_interval
  timeout  = 5
  retries  = var.failover_threshold

  allow_insecure   = false
  follow_redirects = false

  expected_codes = "200"
}

# Health Check for Secondary
resource "cloudflare_load_balancer_monitor" "secondary_health" {
  account_id = var.cloudflare_account_id

  type        = "http"
  port        = 443
  method      = "GET"
  path        = "/health"
  description = "Health check for secondary server"

  interval = var.health_check_interval
  timeout  = 5
  retries  = var.failover_threshold

  allow_insecure   = false
  follow_redirects = false

  expected_codes = "200"
}

# Kubernetes: External DNS operator (syncs DNS records with cluster)
resource "kubernetes_deployment" "external_dns" {
  metadata {
    name      = "external-dns"
    namespace = "default"
  }

  spec {
    replicas = 1

    selector {
      match_labels = { app = "external-dns" }
    }

    template {
      metadata {
        labels = { app = "external-dns" }
      }

      spec {
        service_account_name = kubernetes_service_account.external_dns.metadata[0].name

        container {
          name  = "external-dns"
          image = "registry.k8s.io/external-dns/external-dns:v0.13.6"

          # SECURITY: API token moved to env var, not command args
          env {
            name = "CF_API_TOKEN"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.cloudflare_api.metadata[0].name
                key  = "api-token"
              }
            }
          }

          args = [
            "--source=ingress",
            "--source=service",
            "--provider=cloudflare",
            "--cloudflare-api-token=$(CF_API_TOKEN)",
            "--cloudflare-zones-per-page=50",
            "--zone-id-filter=${var.cloudflare_zone_id}",
            "--txt-owner-id=external-dns",
            "--log-level=info"
          ]

          resources {
            requests = {
              cpu    = "50m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "100m"
              memory = "256Mi"
            }
          }
        }
      }
    }
  }
}

# ServiceAccount for External DNS
resource "kubernetes_service_account" "external_dns" {
  metadata {
    name      = "external-dns"
    namespace = "default"
  }
}

# Secret for Cloudflare API token used by External DNS
resource "kubernetes_secret" "cloudflare_api" {
  metadata {
    name      = "cloudflare-api-token"
    namespace = "default"
  }

  data = {
    "api-token" = var.cloudflare_api_token
  }
}

# ClusterRole for External DNS
resource "kubernetes_cluster_role" "external_dns" {
  metadata {
    name = "external-dns"
  }

  rule {
    api_groups = [""]
    resources  = ["services", "endpoints"]
    verbs      = ["get", "watch", "list"]
  }

  rule {
    api_groups = ["extensions"]
    resources  = ["ingresses"]
    verbs      = ["get", "watch", "list"]
  }
}

# ClusterRoleBinding for External DNS
resource "kubernetes_cluster_role_binding" "external_dns" {
  metadata {
    name = "external-dns"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.external_dns.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.external_dns.metadata[0].name
    namespace = "default"
  }
}

# DNS Security: DNSSEC (Cloudflare managed)
resource "cloudflare_zone_dnssec" "main" {
  zone_id = var.cloudflare_zone_id
}

# Edge hardening: enforce HTTPS, modern TLS, and security posture defaults
resource "cloudflare_zone_setting" "always_use_https" {
  zone_id    = var.cloudflare_zone_id
  setting_id = "always_use_https"
  value      = "on"
}

resource "cloudflare_zone_setting" "automatic_https_rewrites" {
  zone_id    = var.cloudflare_zone_id
  setting_id = "automatic_https_rewrites"
  value      = "on"
}

resource "cloudflare_zone_setting" "min_tls_version" {
  zone_id    = var.cloudflare_zone_id
  setting_id = "min_tls_version"
  value      = "1.2"
}

resource "cloudflare_zone_setting" "tls_1_3" {
  zone_id    = var.cloudflare_zone_id
  setting_id = "tls_1_3"
  value      = "on"
}

resource "cloudflare_zone_setting" "ssl" {
  zone_id    = var.cloudflare_zone_id
  setting_id = "ssl"
  value      = "strict"
}

resource "cloudflare_zone_setting" "security_level" {
  zone_id    = var.cloudflare_zone_id
  setting_id = "security_level"
  value      = "high"
}

resource "cloudflare_zone_setting" "browser_check" {
  zone_id    = var.cloudflare_zone_id
  setting_id = "browser_check"
  value      = "on"
}

# Bot protections: enable Cloudflare bot controls on the zone
resource "cloudflare_bot_management" "main" {
  zone_id                   = var.cloudflare_zone_id
  ai_bots_protection        = "block"
  bm_cookie_enabled         = true
  cf_robots_variant         = "policy_only"
  crawler_protection        = "enabled"
  enable_js                 = true
  fight_mode                = true
  is_robots_txt_managed     = true
  sbfm_definitely_automated = "block"
  sbfm_likely_automated     = "managed_challenge"
  sbfm_static_resource_protection = true
  sbfm_verified_bots        = "allow"
}

# WAF custom rules: block common scanner behavior and path traversal attempts
resource "cloudflare_ruleset" "custom_waf" {
  zone_id     = var.cloudflare_zone_id
  name        = "code-server-enterprise custom WAF"
  phase       = "http_request_firewall_custom"
  kind        = "zone"
  description = "Free-tier WAF rules for scanner blocking and suspicious request patterns"

  rules = [
    {
      ref         = "block-path-traversal"
      description = "Block path traversal attempts"
      expression  = "http.request.uri.path contains \"../\" or http.request.uri.path contains \"..%2F\" or http.request.uri.path contains \"..%2f\""
      action      = "block"
      enabled     = true
    },
    {
      ref         = "challenge-suspicious-user-agents"
      description = "Challenge common automated scanners"
      expression  = "lower(http.user_agent) contains \"sqlmap\" or lower(http.user_agent) contains \"nikto\" or lower(http.user_agent) contains \"nuclei\" or lower(http.user_agent) contains \"dirbuster\""
      action      = "managed_challenge"
      enabled     = true
    },
    {
      ref         = "challenge-suspicious-post-bodies"
      description = "Challenge suspicious XML-like POST bodies"
      expression  = "http.request.method eq \"POST\" and (http.request.body.raw contains \"<!DOCTYPE\" or http.request.body.raw contains \"<script\" or http.request.body.raw contains \"<?xml\")"
      action      = "managed_challenge"
      enabled     = true
    }
  ]
}

# Rate limiting: /api for public API traffic and /auth for OAuth endpoints
resource "cloudflare_rate_limit" "api" {
  zone_id    = var.cloudflare_zone_id
  threshold  = 100
  period     = 60
  description = "Rate limit /api at 100 requests per minute per IP"

  action = {
    mode    = "ban"
    timeout = 300
  }

  match = {
    request = {
      methods = ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"]
      schemes = ["HTTP", "HTTPS"]
      url     = "${var.apex_domain}/api/*"
    }
  }
}

resource "cloudflare_rate_limit" "auth" {
  zone_id    = var.cloudflare_zone_id
  threshold  = 20
  period     = 60
  description = "Rate limit /auth and oauth2 endpoints at 20 requests per minute per IP"

  action = {
    mode    = "ban"
    timeout = 300
  }

  match = {
    request = {
      methods = ["GET", "POST", "OPTIONS"]
      schemes = ["HTTP", "HTTPS"]
      url     = "${var.apex_domain}/auth/*"
    }
  }
}

# Response header hardening via transform rules
resource "cloudflare_ruleset" "security_headers" {
  zone_id     = var.cloudflare_zone_id
  name        = "code-server-enterprise security headers"
  phase       = "http_response_headers_transform"
  kind        = "zone"
  description = "Set security response headers when the origin omits them"

  rules = [
    {
      ref         = "set-security-headers"
      description = "Apply security headers on all responses"
      expression  = "true"
      action      = "rewrite"
      enabled     = true
      action_parameters = {
        headers = {
          "Strict-Transport-Security" = {
            operation = "set"
            value     = "max-age=63072000; includeSubDomains; preload"
          }
          "X-Content-Type-Options" = {
            operation = "set"
            value     = "nosniff"
          }
          "X-Frame-Options" = {
            operation = "set"
            value     = "SAMEORIGIN"
          }
          "Referrer-Policy" = {
            operation = "set"
            value     = "strict-origin-when-cross-origin"
          }
          "Permissions-Policy" = {
            operation = "set"
            value     = "geolocation=(), microphone=(), camera=()"
          }
        }
      }
    }
  ]
}
