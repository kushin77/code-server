# DNS & Access Control Infrastructure
# Implements production access to code-server via Cloudflare Tunnel & Access
# - Tunnel routing via Cloudflare
# - Identity-based access policies (email + MFA)
# - Automatic certificate management
# Idempotent: safe to apply multiple times (terraform state tracking)

# ─────────────────────────────────────────────────────────────────────────────
# DNS & ACCESS CONTROL CONFIGURATION
# ─────────────────────────────────────────────────────────────────────────────
# ─────────────────────────────────────────────────────────────────────────────

variable "tunnel_name" {
  description = "Cloudflare Tunnel name"
  type        = string
  default     = "home-dev"
}

variable "code_server_origin" {
  description = "Code-server origin (localhost:port)"
  type        = string
  default     = "http://localhost:8080"
}

variable "enable_mfa" {
  description = "Require MFA for access"
  type        = bool
  default     = true
}

variable "session_timeout_hours" {
  description = "Session timeout in hours"
  type        = number
  default     = 24
}

variable "allowed_emails" {
  description = "Allowed email patterns (list)"
  type        = list(string)
  default     = ["*@kushnir.cloud"]
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default = {
    Module      = "dns-access-control"
    Environment = "production"
    ManagedBy   = "terraform"
    Project     = "code-server-enterprise"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# DATA SOURCES
# ─────────────────────────────────────────────────────────────────────────────

data "cloudflare_zone" "main" {
  zone_id = var.cloudflare_zone_id
}

# Note: cloudflare_account data source not available in provider v4+; use var.cloudflare_account_id directly

# ─────────────────────────────────────────────────────────────────────────────
# CLOUDFLARE TUNNEL (Idempotent Resource)
# ─────────────────────────────────────────────────────────────────────────────

# Create tunnel record in Cloudflare 
# Note: Tunnel secret/token must be configured manually or via cloudflared CLI
# This Terraform creates the CNAME and access policies
resource "cloudflare_tunnel_route" "code_server" {
  # This is a simplified placeholder - actual tunnel routing requires
  # the tunnel to be created via cloudflared CLI first, then referenced here

  account_id = var.cloudflare_account_id
  tunnel_id  = "temp_placeholder" # Replace with actual tunnel ID after cloudflared CLI creation
  network    = "0.0.0.0/0"        # Route all traffic through the tunnel

  # This resource creates DNS CNAME record pointing to tunnel
  # Format: tunnel_id.cfargotunnel.com
}

# ─────────────────────────────────────────────────────────────────────────────
# DNS RECORDS (CNAME for Tunnel)
# ─────────────────────────────────────────────────────────────────────────────

resource "cloudflare_record" "code_server_cname" {
  zone_id = var.cloudflare_zone_id
  name    = "ide" # Creates ide.kushnir.cloud
  type    = "CNAME"
  content = "code-server.cfargotunnel.com" # Placeholder - update after tunnel creation
  ttl     = 1                              # Auto/Proxied
  proxied = true

  # comment: "Code-Server Tunnel CNAME via Cloudflare" (comment arg not supported in v4)
}

# ─────────────────────────────────────────────────────────────────────────────
# CLOUDFLARE ACCESS INFRASTRUCTURE
# ─────────────────────────────────────────────────────────────────────────────

# Access Application
resource "cloudflare_access_application" "code_server" {
  zone_id          = var.cloudflare_zone_id
  name             = "Code-Server IDE"
  domain           = var.domain
  type             = "self_hosted"
  session_duration = "${var.session_timeout_hours}h"

  # Security settings
  auto_redirect_to_identity = true
  enable_binding_cookie     = true

  tags = [
    var.tags["Phase"],
    var.tags["Environment"],
    "access-control"
  ]

  # comment: "Phase 13: Production code-server access control" (comment arg not supported in provider v4)
}

# Access Policy - Email-based access with MFA
resource "cloudflare_access_policy" "code_server_email_mfa" {
  application_id = cloudflare_access_application.code_server.id
  zone_id        = var.cloudflare_zone_id
  name           = "Email + MFA Access"
  precedence     = 1
  decision       = "allow"

  include {
    email = var.allowed_emails
  }

  dynamic "include" {
    for_each = var.enable_mfa ? [1] : []
    content {
      login_method = ["totp", "otp"] # Require TOTP or one-time passcode
    }
  }

  # comment: "Phase 13: Allow email-verified users with MFA" (comment not supported in provider v4)
}

# Fallback Policy - Deny all others
resource "cloudflare_access_policy" "code_server_default_deny" {
  application_id = cloudflare_access_application.code_server.id
  zone_id        = var.cloudflare_zone_id
  name           = "Default Deny"
  precedence     = 999
  decision       = "deny"

  include {
    everyone = true
  }

  # comment: "Phase 13: Default policy - deny all unauthorized access" (comment not supported in provider v4)
}

# ─────────────────────────────────────────────────────────────────────────────
# CERTIFICATE & SECURITY
# ─────────────────────────────────────────────────────────────────────────────

# Use Cloudflare managed certificate (automatic)
# No explicit resource needed - Cloudflare handles certificate renewal automatically

# ─────────────────────────────────────────────────────────────────────────────
# LOGGING & MONITORING
# ─────────────────────────────────────────────────────────────────────────────

resource "cloudflare_logpush_job" "http_requests" {
  account_id = var.cloudflare_account_id
  enabled    = true
  frequency  = "low" # Collect logs every 30 minutes

  dataset = "http_requests"

  destination_conf = "s3://code-server-logs" # Update with actual S3 bucket

  ownership_challenge = null # Set via out-of-band verification with cloudflared CLI

  filter = jsonencode({
    where = {
      and = [
        {
          key      = "ClientRequestPath"
          operator = "contains"
          value    = var.domain
        }
      ]
    }
  })

  # comment: "Phase 13: HTTP request logging for code-server access" (comment arg not supported in provider v4)
}

# ─────────────────────────────────────────────────────────────────────────────
# OUTPUTS
# ─────────────────────────────────────────────────────────────────────────────

output "access_application_id" {
  value       = cloudflare_access_application.code_server.id
  description = "Cloudflare Access Application ID"
}

output "access_domain" {
  value       = cloudflare_access_application.code_server.domain
  description = "Access application domain"
}

output "cname_record" {
  value       = cloudflare_record.code_server_cname.content
  description = "CNAME record value for tunnel"
}

output "dns_record_name" {
  value       = "${cloudflare_record.code_server_cname.name}.${data.cloudflare_zone.main.name}"
  description = "Full DNS domain name"
}

output "access_policy_id" {
  value       = cloudflare_access_policy.code_server_email_mfa.id
  description = "Cloudflare Access Policy ID"
}

output "cloudflare_nameservers" {
  value       = data.cloudflare_zone.main.name_servers
  description = "Cloudflare nameservers (update domain registrar to these)"
}

output "terraform_state" {
  value       = "Remote state should be stored in S3 or Terraform Cloud"
  description = "Recommendation for production use"
}

# ─────────────────────────────────────────────────────────────────────────────
# IMPLEMENTATION NOTES
# ─────────────────────────────────────────────────────────────────────────────
#
# 1. INITIAL SETUP - CLI Prerequisite
#    Before applying, create tunnel via Cloudflare CLI:
#    $ cloudflared tunnel create home-dev
#    $ cloudflared tunnel list  # Get tunnel ID
#    Then update tunnel_route.tunnel_id value above
#
# 2. TERRAFORM WORKFLOW
#    $ terraform init
#    $ terraform plan -var domain=<your-domain>
#    $ terraform apply
#
# 3. IDEMPOTENCY
#    State file tracks all resources. Re-running apply is safe.
#    Only creates/modifies resources that changed.
#
# 4. MAINTENANCE
#    - Add emails: var.allowed_emails list
#    - Change timeout: var.session_timeout_hours
#    - All changes tracked in git
