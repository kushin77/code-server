/**
 * @file terraform/environments/private/cloudflare.tf
 * @description Cloudflare DNS + WAF IaC — resolves #3178
 *
 * SETUP: Set CLOUDFLARE_API_TOKEN env var or add to terraform.tfvars:
 *   cloudflare_api_token = "..."
 *   cloudflare_zone_id   = "..."
 *
 * Then: terraform init && terraform plan
 */

# ---------------------------------------------------------------------------
# Provider (declared here; add to required_providers in versions.tf when ready)
# ---------------------------------------------------------------------------
terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = ">= 4.0, < 5.0"
    }
  }
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

# ---------------------------------------------------------------------------
# Variables
# ---------------------------------------------------------------------------
variable "cloudflare_api_token" {
  description = "Cloudflare API token with Zone:Edit + DNS:Edit permissions"
  type        = string
  sensitive   = true
  default     = ""  # Set via CLOUDFLARE_API_TOKEN env var or tfvars
}

variable "cloudflare_zone_id" {
  description = "Cloudflare Zone ID for apex domain"
  type        = string
  default     = ""  # Set in terraform.tfvars
}

# ---------------------------------------------------------------------------
# DNS Records (apex + subdomains)
# ---------------------------------------------------------------------------
locals {
  # Skip all Cloudflare resources if zone_id not configured
  cloudflare_enabled = var.cloudflare_zone_id != "" && var.cloudflare_api_token != ""
}

resource "cloudflare_record" "apex" {
  count   = local.cloudflare_enabled ? 1 : 0
  zone_id = var.cloudflare_zone_id
  name    = "@"
  value   = var.primary_host
  type    = "A"
  ttl     = 1      # Auto (proxied)
  proxied = true

  comment = "Managed by Terraform — do not edit in dashboard"

  lifecycle {
    prevent_destroy = true
  }
}

resource "cloudflare_record" "ide" {
  count   = local.cloudflare_enabled ? 1 : 0
  zone_id = var.cloudflare_zone_id
  name    = "ide"
  value   = var.primary_host
  type    = "A"
  ttl     = 1
  proxied = true

  comment = "Managed by Terraform — code-server IDE endpoint"
}

resource "cloudflare_record" "auth" {
  count   = local.cloudflare_enabled ? 1 : 0
  zone_id = var.cloudflare_zone_id
  name    = "auth"
  value   = var.primary_host
  type    = "A"
  ttl     = 1
  proxied = true

  comment = "Managed by Terraform — OAuth2 proxy / auth endpoint"
}

resource "cloudflare_record" "api" {
  count   = local.cloudflare_enabled ? 1 : 0
  zone_id = var.cloudflare_zone_id
  name    = "api"
  value   = var.primary_host
  type    = "A"
  ttl     = 1
  proxied = true

  comment = "Managed by Terraform — API endpoint"
}

# ---------------------------------------------------------------------------
# Zone Settings — Security hardening
# ---------------------------------------------------------------------------
resource "cloudflare_zone_settings_override" "security" {
  count   = local.cloudflare_enabled ? 1 : 0
  zone_id = var.cloudflare_zone_id

  settings {
    ssl                      = "strict"
    min_tls_version          = "1.2"
    tls_1_3                  = "on"
    automatic_https_rewrites = "on"
    always_use_https         = "on"
    security_level           = "medium"
    browser_check            = "on"
    challenge_ttl            = 1800
    privacy_pass             = "on"
    http3                    = "on"
  }
}

# ---------------------------------------------------------------------------
# WAF — Block known bad actors
# ---------------------------------------------------------------------------
resource "cloudflare_ruleset" "waf" {
  count       = local.cloudflare_enabled ? 1 : 0
  zone_id     = var.cloudflare_zone_id
  name        = "code-server WAF rules"
  description = "Managed by Terraform — resolves #3178"
  kind        = "zone"
  phase       = "http_request_firewall_custom"

  rules {
    action      = "block"
    description = "Block requests with known malicious user agents"
    expression  = "(http.user_agent contains \"sqlmap\") or (http.user_agent contains \"nikto\") or (http.user_agent contains \"masscan\")"
    enabled     = true
  }

  rules {
    action      = "managed_challenge"
    description = "Challenge aggressive scrapers"
    expression  = "(http.request.uri.path contains \"/.env\") or (http.request.uri.path contains \"/wp-admin\") or (http.request.uri.path contains \"/phpmyadmin\")"
    enabled     = true
  }
}

# ---------------------------------------------------------------------------
# Outputs
# ---------------------------------------------------------------------------
output "cloudflare_dns_records" {
  description = "Deployed Cloudflare DNS records"
  value = local.cloudflare_enabled ? {
    apex = try(cloudflare_record.apex[0].hostname, "not deployed")
    ide  = try(cloudflare_record.ide[0].hostname, "not deployed")
    auth = try(cloudflare_record.auth[0].hostname, "not deployed")
    api  = try(cloudflare_record.api[0].hostname, "not deployed")
  } : {}
}
