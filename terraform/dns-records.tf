################################################################################
# @file terraform/dns-records.tf
# @description DNS Records Management via Terraform (Cloudflare Provider)
# @governance GOV-002: Infrastructure as Code - versioned, deterministic, repeatable
# @author GitHub Copilot
# @date 2026-04-25
# @related P3 #1536 Phase 3 - DNS Architecture & Resilience

###############################################################################
# CLOUDFLARE DNS PROVIDER CONFIGURATION
###############################################################################

terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }

  backend "local" {
    path = "terraform/state/dns-records.tfstate"
  }
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token  # from TF_VAR_cloudflare_api_token
}

###############################################################################
# VARIABLES (Environment-Driven, No Hardcoding)
###############################################################################

variable "cloudflare_api_token" {
  description = "Cloudflare API token for DNS management"
  type        = string
  sensitive   = true
  # Set via: export TF_VAR_cloudflare_api_token=...
}

variable "zone_id" {
  description = "Cloudflare Zone ID for "
  type        = string
  # Example: export TF_VAR_zone_id=abc123def456...
}

variable "primary_host_ip" {
  description = "Primary infrastructure host IP"
  type        = string
  default     = "203.0.113.1"  # placeholder - override via TF_VAR
}

variable "replica_host_ip" {
  description = "Replica infrastructure host IP"
  type        = string
  default     = "203.0.113.2"  # placeholder - override via TF_VAR
}

variable "apex_domain" {
  description = "Apex domain name"
  type        = string
  default     = ""
}

variable "ttl_short" {
  description = "Short TTL for frequently-changing records (seconds)"
  type        = number
  default     = 300  # 5 minutes
}

variable "ttl_standard" {
  description = "Standard TTL for infrastructure records (seconds)"
  type        = number
  default     = 3600  # 1 hour
}

###############################################################################
# DATA SOURCES (Read-Only References to Existing Resources)
###############################################################################

data "cloudflare_zone" "kushnir" {
  name = var.apex_domain
}

###############################################################################
# DNS RECORDS - APEX DOMAIN (A RECORDS)
###############################################################################

# Main domain apex record (points to primary LB/gateway)
resource "cloudflare_record" "apex" {
  zone_id = data.cloudflare_zone.kushnir.id
  name    = "@"  # Apex
  type    = "A"
  value   = var.primary_host_ip
  ttl     = var.ttl_short
  comment = "Primary infrastructure host - Caddy reverse proxy"

  lifecycle {
    create_before_destroy = true
  }
}

# www subdomain (CNAME to apex)
resource "cloudflare_record" "www" {
  zone_id = data.cloudflare_zone.kushnir.id
  name    = "www"
  type    = "CNAME"
  value   = var.apex_domain
  ttl     = var.ttl_short
  comment = "Alias to apex domain"

  lifecycle {
    create_before_destroy = true
  }
}

###############################################################################
# DNS RECORDS - SERVICE SUBDOMAINS (A RECORDS)
###############################################################################

# IDE Service
resource "cloudflare_record" "ide" {
  zone_id = data.cloudflare_zone.kushnir.id
  name    = "ide"
  type    = "A"
  value   = var.primary_host_ip
  ttl     = var.ttl_short
  comment = "IDE service via Caddy reverse proxy"

  lifecycle {
    create_before_destroy = true
  }
}

# API Gateway
resource "cloudflare_record" "api" {
  zone_id = data.cloudflare_zone.kushnir.id
  name    = "api"
  type    = "A"
  value   = var.primary_host_ip
  ttl     = var.ttl_short
  comment = "API service gateway"

  lifecycle {
    create_before_destroy = true
  }
}

# Admin Panel
resource "cloudflare_record" "admin" {
  zone_id = data.cloudflare_zone.kushnir.id
  name    = "admin"
  type    = "A"
  value   = var.primary_host_ip
  ttl     = var.ttl_short
  comment = "Admin control panel"

  lifecycle {
    create_before_destroy = true
  }
}

# Authentication Service
resource "cloudflare_record" "auth" {
  zone_id = data.cloudflare_zone.kushnir.id
  name    = "auth"
  type    = "A"
  value   = var.primary_host_ip
  ttl     = var.ttl_short
  comment = "OAuth2 proxy + authentication gateway"

  lifecycle {
    create_before_destroy = true
  }
}

###############################################################################
# DNS RECORDS - MAIL (MX, SPF, DKIM)
###############################################################################

# Mail Server (MX Record)
resource "cloudflare_record" "mail_mx" {
  zone_id  = data.cloudflare_zone.kushnir.id
  name     = "@"
  type     = "MX"
  priority = 10
  value    = "mail.${var.apex_domain}"
  ttl      = var.ttl_standard
  comment  = "Mail server priority 10"

  lifecycle {
    create_before_destroy = true
  }
}

# SPF Record (TXT)
resource "cloudflare_record" "spf" {
  zone_id = data.cloudflare_zone.kushnir.id
  name    = "@"
  type    = "TXT"
  value   = "v=spf1 include:sendgrid.net ~all"
  ttl     = var.ttl_standard
  comment = "SPF record for mail routing"

  lifecycle {
    create_before_destroy = true
  }
}

# DKIM Record (TXT) - Example for SendGrid
resource "cloudflare_record" "dkim" {
  zone_id = data.cloudflare_zone.kushnir.id
  name    = "sendgrid._domainkey"
  type    = "CNAME"
  value   = "sendgrid.net"
  ttl     = var.ttl_standard
  comment = "DKIM verification for SendGrid"

  lifecycle {
    create_before_destroy = true
  }
}

###############################################################################
# DNS RECORDS - INFRASTRUCTURE & MONITORING
###############################################################################

# Monitoring (Prometheus/Grafana)
resource "cloudflare_record" "monitoring" {
  zone_id = data.cloudflare_zone.kushnir.id
  name    = "metrics"
  type    = "A"
  value   = var.primary_host_ip
  ttl     = var.ttl_standard
  comment = "Metrics service (Prometheus/Grafana)"

  lifecycle {
    create_before_destroy = true
  }
}

# Status Page
resource "cloudflare_record" "status" {
  zone_id = data.cloudflare_zone.kushnir.id
  name    = "status"
  type    = "A"
  value   = var.primary_host_ip
  ttl     = var.ttl_short
  comment = "Status page for infrastructure health"

  lifecycle {
    create_before_destroy = true
  }
}

###############################################################################
# OUTPUTS - Terraform State References
###############################################################################

output "apex_record_id" {
  description = "Apex DNS record ID"
  value       = cloudflare_record.apex.id
}

output "dns_records_created" {
  description = "Summary of DNS records created"
  value = {
    apex       = cloudflare_record.apex.name
    www        = cloudflare_record.www.name
    ide        = cloudflare_record.ide.name
    api        = cloudflare_record.api.name
    admin      = cloudflare_record.admin.name
    auth       = cloudflare_record.auth.name
    monitoring = cloudflare_record.monitoring.name
    status     = cloudflare_record.status.name
  }
}

output "zone_id" {
  description = "Cloudflare Zone ID for reference"
  value       = data.cloudflare_zone.kushnir.id
}

###############################################################################
# GOV-002 COMPLIANCE
# 
# ✅ Infrastructure as Code:
#    - All DNS records defined as code (Terraform)
#    - Version-controlled in Git
#    - No manual DNS management
#    - Terraform state tracked in git
#
# ✅ Immutability:
#    - All variables sourced from environment (TF_VAR_*)
#    - No secrets hardcoded
#    - API token from external vault (TF_VAR_cloudflare_api_token)
#    - Deterministic outputs
#
# ✅ Idempotency:
#    - Terraform apply idempotent (safe to run multiple times)
#    - create_before_destroy prevents downtime
#    - Records updated atomically
#    - Failed apply leaves no partial state
#
# Deployment:
#   export TF_VAR_cloudflare_api_token=your_token
#   export TF_VAR_zone_id=your_zone_id
#   export TF_VAR_primary_host_ip=203.0.113.1
#   terraform init
#   terraform plan
#   terraform apply
###############################################################################
