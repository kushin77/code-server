# terraform/phase-22-b-cdn-bgp.tf
# Phase 22-B: Advanced Networking - CDN & BGP Configuration
#
# Provisions:
# - CloudFlare CDN for static assets
# - Cache invalidation strategies
# - Origin shielding
# - BGP optimization for multi-region connectivity
#
# IMMUTABILITY: All versions pinned
# IDEMPOTENCY: Safe to re-apply
# INDEPENDENCE: No overlap with Phase 22-A
# NO DUPLICATION: Separate from Istio configuration
# NOTE: Terraform configuration consolidated in main.tf for idempotency

# ═════════════════════════════════════════════════════════════════════════════
# FEATURE FLAG & CONFIGURATION
# Cloudflare variables consolidated in variables.tf
# ═════════════════════════════════════════════════════════════════════════════

variable "phase_22_b_cdn_enabled" {
  description = "Enable Phase 22-B: CDN & BGP"
  type        = bool
  default     = true
}

variable "origin_domain" {
  description = "Origin domain (EKS ALB)"
  type        = string
  default     = "code-server-k8s-prod.example.com"
}

# ═════════════════════════════════════════════════════════════════════════════
# CLOUDFLARE PROVIDER (Consolidated in main.tf)
# NOTE: Provider configuration moved to main.tf for single source of truth
# ═════════════════════════════════════════════════════════════════════════════

# ═════════════════════════════════════════════════════════════════════════════
# CDN CONFIGURATION: ide.kushnir.cloud
# ═════════════════════════════════════════════════════════════════════════════

# DNS record pointing to EKS ALB
resource "cloudflare_record" "ide_cname" {
  count   = var.phase_22_b_cdn_enabled ? 1 : 0
  zone_id = var.cloudflare_zone_id

  name    = "ide"
  type    = "CNAME"
  content = var.origin_domain
  ttl     = 1  # Auto (CloudFlare proxy)
  proxied = true

  comment = "Phase 22-B: CDN origin for code-server"
}

# Cache rules for static assets
resource "cloudflare_cache_rules" "static_assets" {
  count   = var.phase_22_b_cdn_enabled ? 1 : 0
  zone_id = var.cloudflare_zone_id

  rules = [
    {
      # Cache static assets for 1 year
      description = "Cache static assets (JS, CSS, images)"
      action      = "set_cache_settings"
      action_parameters = {
        cache        = true
        cache_on_cookie = ["sessionid", "csrf_token"]
        cache_ttl    = 31536000  # 1 year
        edge_ttl     = 31536000
        browser_ttl  = 3600
      }
      expression = "(cf_mime_type matches \".*font.*\") or (cf_mime_type matches \".*javascript.*\") or (cf_mime_type matches \".*css.*\") or (cf_mime_type matches \".*image.*\")"
    },

    {
      # Cache API responses briefly (10 minutes)
      description = "Cache API responses"
      action      = "set_cache_settings"
      action_parameters = {
        cache       = true
        cache_ttl   = 600  # 10 minutes
        edge_ttl    = 600
        browser_ttl = 300
      }
      expression = "(http.request.uri.path contains \"/api/\") and (http.request.method eq \"GET\")"
    },

    {
      # Don't cache dynamic endpoints
      description = "Bypass cache for dynamic endpoints"
      action      = "set_cache_settings"
      action_parameters = {
        cache = false
      }
      expression = "(http.request.uri.path contains \"/socket\") or (http.request.uri.path contains \"/auth\") or (http.request.method eq \"POST\")"
    }
  ]
}

# ═════════════════════════════════════════════════════════════════════════════
# CLOUDFLARE SECURITY & PERFORMANCE RULES
# ═════════════════════════════════════════════════════════════════════════════

# Rate limiting: Prevent brute force attacks
resource "cloudflare_rate_limit" "auth_endpoints" {
  count   = var.phase_22_b_cdn_enabled ? 1 : 0
  zone_id = var.cloudflare_zone_id

  disabled    = false
  description = "Rate limit auth endpoints"
  match {
    request {
      url_path = {
        path_contains = "/auth"
      }
    }
  }
  threshold = 10
  period    = 60  # 10 requests per 60 seconds
  action    = "challenge"
}

# Rate limiting: API endpoints
resource "cloudflare_rate_limit" "api_endpoints" {
  count   = var.phase_22_b_cdn_enabled ? 1 : 0
  zone_id = var.cloudflare_zone_id

  disabled    = false
  description = "Rate limit API endpoints"
  match {
    request {
      url_path = {
        path_contains = "/api/"
      }
    }
  }
  threshold = 1000
  period    = 60  # 1000 requests per 60 seconds
  action    = "log"
}

# Web Application Firewall (WAF)
resource "cloudflare_waf_rule" "owasp_crs" {
  count   = var.phase_22_b_cdn_enabled ? 1 : 0
  zone_id = var.cloudflare_zone_id
  group_id = "62d9e6f4653bd50014a236e8"  # OWASP ModSecurity Core Rule Set
  mode    = "challenge"
}

# ═════════════════════════════════════════════════════════════════════════════
# ORIGIN SHIELDING (Cache layer before reaching origin)
# ═════════════════════════════════════════════════════════════════════════════

resource "cloudflare_zone_settings_override" "origin_shield" {
  count = var.phase_22_b_cdn_enabled ? 1 : 0

  zone_id = var.cloudflare_zone_id

  settings {
    origin_shield = "on"
    origin_shield_region = "auto"  # Auto-select nearest region
  }
}

# ═════════════════════════════════════════════════════════════════════════════
# TLS/SSL CONFIGURATION
# ═════════════════════════════════════════════════════════════════════════════

resource "cloudflare_zone_settings_override" "ssl_tls" {
  count = var.phase_22_b_cdn_enabled ? 1 : 0

  zone_id = var.cloudflare_zone_id

  settings {
    ssl           = "full"         # Full SSL/TLS to origin
    min_tls_version = "1.3"        # Minimum TLS 1.3
    tls_1_3       = "on"           # Enable TLS 1.3
    always_use_https = "on"        # Redirect HTTP to HTTPS
    opportunistic_encryption = "on"
  }
}

# ═════════════════════════════════════════════════════════════════════════════
# PERFORMANCE OPTIMIZATION
# ═════════════════════════════════════════════════════════════════════════════

resource "cloudflare_zone_settings_override" "performance" {
  count = var.phase_22_zone_id

  zone_id = var.cloudflare_zone_id

  settings {
    minify {
      css  = "on"
      html = "on"
      js   = "on"
    }

    rocket_loader      = "on"          # Defer JS loading
    auto_minify        = "on"
    brotli_compression = "on"          # Brotli compression
    polish             = "lossy"       # Image optimization
    adaptive_ddos      = "on"
    http2              = "on"
    http3              = "on"          # HTTP/3 support
  }
}

# ═════════════════════════════════════════════════════════════════════════════
# BGP CONFIGURATION (AWS Transit Gateway)
# For multi-region connectivity with BGP dynamic routing
# ═════════════════════════════════════════════════════════════════════════════

# Note: BGP configuration is typically managed at the network infrastructure level
# This section demonstrates the Terraform resources for multi-region BGP setup

variable "transit_gateway_id" {
  description = "AWS Transit Gateway ID for multi-region BGP"
  type        = string
  default     = ""
}

variable "autonomous_system_number" {
  description = "BGP Autonomous System Number (ASN)"
  type        = number
  default     = 64512  # Private ASN
}

# Create BGP peer for multi-region connectivity
# (This is a template; actual BGP setup varies by AWS region/architecture)

resource "aws_ec2_network_interface" "bgp_gateway" {
  count           = var.phase_22_b_cdn_enabled && var.transit_gateway_id != "" ? 1 : 0
  subnet_id       = "subnet-xxxxx"  # Specify subnet
  security_groups = ["sg-xxxxx"]    # Specify security group

  tags = {
    Name  = "code-server-bgp-gateway"
    Phase = "22-b"
  }
}

# ═════════════════════════════════════════════════════════════════════════════
# MONITORING: CACHE HIT RATIO & PERFORMANCE
# ═════════════════════════════════════════════════════════════════════════════

# CloudFlare exports cache metrics to Prometheus via API
# These are queried by monitoring stack (Phase 21)

output "cdn_cache_url" {
  value       = try("https://${cloudflare_record.ide_cname[0].name}.kushnir.cloud", "")
  description = "CDN-enabled URL for code-server"
}

output "origin_shield_status" {
  value       = try(cloudflare_zone_settings_override.origin_shield[0].settings[0].origin_shield, "")
  description = "Origin Shield status"
}

output "cloudflare_zone_id" {
  value       = var.cloudflare_zone_id
  description = "CloudFlare Zone ID"
  sensitive   = true
}

# ═════════════════════════════════════════════════════════════════════════════
# DEPLOYMENT CHECKLIST
# ═════════════════════════════════════════════════════════════════════════════
#
# Pre-deployment:
# 1. Domain registered and delegated to CloudFlare nameservers
# 2. CloudFlare API token created
# 3. Zone ID obtained
#
# Deployment:
# terraform init
# terraform validate
# terraform plan -out=tfplan-22b-cdn
# terraform apply tfplan-22b-cdn
#
# Verification:
# 1. DNS resolution:
#    nslookup ide.kushnir.cloud
#
# 2. Cache headers:
#    curl -I https://ide.kushnir.cloud/app.js
#    # Should see: cf-cache-status: HIT
#
# 3. CDN performance:
#    curl -w "Total time: %{time_total}s\n" https://ide.kushnir.cloud/app.js
#
# 4. Rate limiting:
#    for i in {1..15}; do curl https://ide.kushnir.cloud/auth; done
#    # Should see challenge on requests 11-15
#
# Rollback:
# terraform destroy -auto-approve
