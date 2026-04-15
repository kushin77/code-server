################################################################################
# GoDaddy Public DNS Configuration - kushnir.cloud Domain
# File: terraform/godaddy-dns.tf
# Purpose: Manage kushnir.cloud DNS records via IaC (Terraform)
# Owner: Platform Engineering
# References: Issue #347 - DNS hardening (DNSSEC/CAA/DMARC/SPF)
# Last Updated: April 15, 2026
################################################################################

provider "godaddy" {
  key    = var.godaddy_api_key
  secret = var.godaddy_api_secret
}

################################################################################
# Variables
################################################################################

variable "godaddy_api_key" {
  description = "GoDaddy API key for DNS management"
  type        = string
  sensitive   = true
}

variable "godaddy_api_secret" {
  description = "GoDaddy API secret"
  type        = string
  sensitive   = true
}

variable "public_domain" {
  description = "Public domain name"
  type        = string
  default     = "kushnir.cloud"
}

variable "cloudflare_tunnel_url" {
  description = "Cloudflare Tunnel CNAME endpoint (e.g., home-dev.cfargotunnel.com). Required for production public DNS."
  type        = string
  # Example: home-dev.cfargotunnel.com
  # Get from: https://dash.cloudflare.com/tunnels
}

################################################################################
# DNS Records - Cloudflare Tunnel Only (IP-Independent Architecture)
################################################################################

# Why Cloudflare Tunnel?
# - IP-agnostic: When 192.168.168.31 changes, no DNS update needed
# - Cloudflare Tunnel Agent auto-reconnects with new IP
# - DDoS protection + WAF at edge
# - TLS termination at Cloudflare (not on-prem)
# - No firewall hole-punch needed (outbound-only connection)

resource "godaddy_domain_record" "root_cname_cloudflare" {
  domain = var.public_domain
  name   = "@"
  type   = "CNAME"
  data   = var.cloudflare_tunnel_url
  ttl    = 3600

  lifecycle {
    precondition {
      condition     = can(regex("cfargotunnel\\.com|cloudflare", var.cloudflare_tunnel_url))
      error_message = "cloudflare_tunnel_url must be a Cloudflare tunnel endpoint (e.g., *.cfargotunnel.com), not an IP address"
    }
  }
}

resource "godaddy_domain_record" "ide_cname_cloudflare" {
  domain = var.public_domain
  name   = "ide"
  type   = "CNAME"
  data   = var.cloudflare_tunnel_url
  ttl    = 3600

  lifecycle {
    precondition {
      condition     = can(regex("cfargotunnel\\.com|cloudflare", var.cloudflare_tunnel_url))
      error_message = "cloudflare_tunnel_url must be a Cloudflare tunnel endpoint (e.g., *.cfargotunnel.com), not an IP address"
    }
  }
}

################################################################################
# CAA Records - Restrict Certificate Issuance to Let's Encrypt
################################################################################

# Issue - restrict to Let's Encrypt only
resource "godaddy_domain_record" "caa_issue" {
  domain = var.public_domain
  name   = "@"
  type   = "CAA"
  data   = "0 issue \"letsencrypt.org\""
  ttl    = 3600
}

# Issuewild - wildcard certificates also restricted to Let's Encrypt
resource "godaddy_domain_record" "caa_issuewild" {
  domain = var.public_domain
  name   = "@"
  type   = "CAA"
  data   = "0 issuewild \"letsencrypt.org\""
  ttl    = 3600
}

# IODEF - Report certificate issuance failures to security team
resource "godaddy_domain_record" "caa_iodef" {
  domain = var.public_domain
  name   = "@"
  type   = "CAA"
  data   = "0 iodef \"mailto:security@kushnir.cloud\""
  ttl    = 3600
}

################################################################################
# SPF Record - Email Security
################################################################################

# Hard fail: no authorized mail servers for kushnir.cloud
# Prevents spoofing of noreply@kushnir.cloud for phishing attacks
resource "godaddy_domain_record" "spf_record" {
  domain = var.public_domain
  name   = "@"
  type   = "TXT"
  data   = "v=spf1 -all"
  ttl    = 3600
}

################################################################################
# DMARC Record - Email Authentication Policy
################################################################################

# Reject spoofed email, require strict alignment, send reports to security team
# p=reject: hard reject emails that fail DMARC authentication
# rua=mailto: send aggregate reports (daily summary of pass/fail)
# adkim=s: strict DKIM alignment (signing domain must exactly match From domain)
# aspf=s: strict SPF alignment (SPF domain must exactly match From domain)
resource "godaddy_domain_record" "dmarc_record" {
  domain = var.public_domain
  name   = "_dmarc"
  type   = "TXT"
  data   = "v=DMARC1; p=reject; rua=mailto:security@kushnir.cloud; adkim=s; aspf=s"
  ttl    = 3600
}

################################################################################
# Outputs
################################################################################

output "dns_records" {
  description = "Summary of managed DNS records"
  value = {
    domain = var.public_domain
    records = {
      ide_a         = godaddy_domain_record.ide_a_record.data
      root_a        = godaddy_domain_record.root_a_record.data
      caa_issue     = godaddy_domain_record.caa_issue.data
      caa_issuewild = godaddy_domain_record.caa_issuewild.data
      caa_iodef     = godaddy_domain_record.caa_iodef.data
      spf_record    = godaddy_domain_record.spf_record.data
      dmarc_record  = godaddy_domain_record.dmarc_record.data
    }
  }
}

output "validation_commands" {
  description = "DNS validation commands"
  value = {
    a_record      = "dig +short A ide.kushnir.cloud"
    caa_records   = "dig CAA kushnir.cloud"
    spf_record    = "dig TXT kushnir.cloud | grep spf"
    dmarc_record  = "dig TXT _dmarc.kushnir.cloud"
    dnssec_status = "dig +dnssec kushnir.cloud SOA"
    all_records   = "dig kushnir.cloud ANY"
  }
}
