# ════════════════════════════════════════════════════════════════════════════════════════════
# P1 #388: IAM Standardization - Identity & Authorization Framework
# 
# Implements three-tier identity model:
#   Tier 1: Human identities (OAuth2 + MFA via oauth2-proxy)
#   Tier 2: Workload identities (service accounts + tokens)
#   Tier 3: Automation identities (CI/CD tokens + GCP OIDC federation)
#
# Status: Implementation Phase
# Date: April 22, 2026
# ════════════════════════════════════════════════════════════════════════════════════════════

# ════════════════════════════════════════════════════════════════════════════════════════════
# TIER 1: HUMAN IDENTITY CONFIGURATION (OAuth2 + MFA)
# ════════════════════════════════════════════════════════════════════════════════════════════

# OAuth2-proxy environment configuration (already deployed, enhanced here)
locals {
  oauth2_config = {
    provider         = "google"
    client_id        = var.oauth2_client_id
    client_secret    = var.oauth2_client_secret
    redirect_url     = "https://${var.apex_domain}/oauth2/callback"
    
    # Session configuration
    session_lifetime = 3600      # 1 hour (developers)
    admin_lifetime   = 14400     # 4 hours (admins)
    refresh_lifetime = 604800    # 7 days
    
    # MFA configuration
    mfa_enabled      = true
    mfa_type         = "totp"    # Time-based One-Time Password
    
    # Cookie security
    cookie_name      = "__Host-oauth2_session"
    cookie_secure    = true
    cookie_samesite  = "Strict"
    cookie_httponly  = true
    
    # Allowed email patterns (allowlist)
    allowed_emails_file = "/etc/oauth2/allowed-emails.txt"
  }
}

# RBAC Role Definitions (3 base roles + 1 break-glass)
locals {
  rbac_roles = {
    viewer = {
      description = "Read-only access to observability and logs"
      permissions = [
        "logs:read",
        "metrics:read",
        "traces:read",
        "dashboards:view",
        "services:view"
      ]
      session_lifetime = 3600    # 1 hour
      mfa_required     = false
    }
    
    developer = {
      description = "Full code-server access, read app secrets"
      permissions = [
        "code-server:full",
        "logs:read",
        "metrics:read",
        "traces:read",
        "secrets:read-app",
        "deployments:view",
        "services:edit"
      ]
      session_lifetime = 7200    # 2 hours
      mfa_required     = false
    }
    
    admin = {
      description = "Full system access, all secrets, infrastructure changes"
      permissions = [
        "code-server:full",
        "logs:read",
        "metrics:read",
        "traces:read",
        "secrets:read-all",
        "secrets:write-all",
        "deployments:approve",
        "infrastructure:full",
        "audit:read",
        "users:manage"
      ]
      session_lifetime = 14400   # 4 hours
      mfa_required     = true
    }
    
    break-glass = {
      description = "Emergency access (15 min duration, full audit logging)"
      permissions = [
        "code-server:full",
        "logs:read",
        "metrics:read",
        "traces:read",
        "secrets:read-all",
        "secrets:write-all",
        "deployments:override",
        "infrastructure:full",
        "audit:read",
        "users:manage",
        "emergency-access:break-glass"
      ]
      session_lifetime = 900     # 15 minutes (emergency only)
      mfa_required     = true
    }
  }
}

# User to Role mapping (provisioned via GitHub teams)
locals {
  user_role_mapping = {
    # Admins (github teams mapped via oauth2-proxy group extraction)
    "kushin77"        = "admin"          # repo owner
    "infrastructure"  = "admin"          # infra team
    
    # Developers
    "backend-team"    = "developer"
    "frontend-team"   = "developer"
    "devops-team"     = "admin"
    
    # Viewers (default)
    # Anyone not in above lists defaults to "viewer"
  }
}

# ════════════════════════════════════════════════════════════════════════════════════════════
# TIER 2: WORKLOAD IDENTITY CONFIGURATION (Service Accounts + Tokens)
# ════════════════════════════════════════════════════════════════════════════════════════════

# Service account definitions (for container-to-container auth)
locals {
  workload_identities = {
    code_server = {
      name        = "code-server"
      description = "IDE application service account"
      permissions = [
        "workspace:read",
        "workspace:write",
        "logs:write",
        "metrics:write",
        "docker-exec:allowed",
        "config:read"
      ]
      token_lifetime = 3600   # 1 hour
      rate_limit     = 1000   # req/min
    }
    
    loki = {
      name        = "loki"
      description = "Log aggregation service account"
      permissions = [
        "logs:write",
        "logs:query",
        "metrics:write"
      ]
      token_lifetime = 3600
      rate_limit     = 10000  # high volume
    }
    
    prometheus = {
      name        = "prometheus"
      description = "Metrics scraper service account"
      permissions = [
        "metrics:write",
        "services:discover",
        "endpoints:list"
      ]
      token_lifetime = 3600
      rate_limit     = 5000
    }
    
    kong = {
      name        = "kong"
      description = "API gateway service account"
      permissions = [
        "auth:verify",
        "auth:validate-token",
        "logs:write",
        "metrics:write",
        "backend:access-all"
      ]
      token_lifetime = 3600
      rate_limit     = 50000  # high throughput gateway
    }
    
    ollama = {
      name        = "ollama"
      description = "AI/ML model serving service account"
      permissions = [
        "models:read",
        "models:list",
        "logs:write",
        "metrics:write"
      ]
      token_lifetime = 3600
      rate_limit     = 5000
    }
    
    appsmith = {
      name        = "appsmith"
      description = "Operational portal service account"
      permissions = [
        "datasources:read",
        "workflows:execute-limited",
        "logs:write",
        "metrics:write",
        "audit:read"
      ]
      token_lifetime = 3600
      rate_limit     = 1000
    }
  }
}

# ════════════════════════════════════════════════════════════════════════════════════════════
# TIER 3: AUTOMATION IDENTITY CONFIGURATION (CI/CD + GCP OIDC)
# ════════════════════════════════════════════════════════════════════════════════════════════

locals {
  automation_identities = {
    github_actions = {
      name           = "github-actions"
      description    = "GitHub Actions CI/CD automation"
      provider       = "github"
      token_lifetime = 900        # 15 minutes
      permissions = [
        "terraform:apply",
        "docker:push",
        "secrets:read-limited",
        "deployments:deploy-staging"
      ]
      rate_limit     = 100
    }
  }
}

# ════════════════════════════════════════════════════════════════════════════════════════════
# SERVICE ACCOUNT TOKEN GENERATION
# ════════════════════════════════════════════════════════════════════════════════════════════

# Generate service account tokens (secrets stored in .env)
resource "random_password" "workload_tokens" {
  for_each = local.workload_identities
  
  length  = 32
  special = true
}

# ════════════════════════════════════════════════════════════════════════════════════════════
# AUDIT EVENT SCHEMA DEFINITION
# ════════════════════════════════════════════════════════════════════════════════════════════

locals {
  audit_event_schema = {
    version = "1.0"
    
    fields = {
      timestamp           = "RFC3339 ISO8601"
      correlation_id      = "UUID v4 (propagated across all services)"
      request_id          = "Unique per request"
      
      # Identity information
      human_identity      = "user@domain.com"
      human_role          = "admin|developer|viewer"
      workload_identity   = "service-account-name"
      workload_type       = "container|kubernetes|ci-cd"
      
      # Action information
      action_type         = "READ|WRITE|DELETE|EXECUTE|ADMIN"
      action_resource     = "/path/to/resource"
      action_method       = "GET|POST|PATCH|DELETE"
      action_details      = "free-form action description"
      
      # Result information
      result_status       = "allowed|denied|error"
      result_code         = "200|403|500"
      result_message      = "authorization reason"
      
      # Context information
      source_ip           = "client IP address"
      source_user_agent   = "browser/client identifier"
      session_id          = "session identifier"
      mfa_verified        = "boolean"
      
      # Performance
      latency_ms          = "request latency"
      size_bytes          = "request/response size"
    }
    
    retention_policy = {
      normal   = "90 days"
      admin    = "1 year"
      security = "3 years (immutable)"
    }
    
    sampling_rules = {
      read_operations     = "5% sampling (high volume)"
      write_operations    = "100% (audit required)"
      privileged_operations = "100% (admin required)"
      failed_operations   = "100% (security required)"
    }
  }
}

# ════════════════════════════════════════════════════════════════════════════════════════════
# OUTPUTS: Configuration for docker-compose and other systems
# ════════════════════════════════════════════════════════════════════════════════════════════

output "oauth2_provider_config" {
  description = "OAuth2 configuration for oauth2-proxy container"
  value       = local.oauth2_config
  sensitive   = true
}

output "rbac_roles" {
  description = "RBAC role definitions"
  value       = local.rbac_roles
}

output "workload_service_accounts" {
  description = "Service account names and permissions"
  value = {
    for name, config in local.workload_identities :
    name => {
      name        = config.name
      permissions = config.permissions
      token_lifetime = config.token_lifetime
      rate_limit  = config.rate_limit
    }
  }
}

output "workload_tokens_secret_keys" {
  description = "Token keys to be stored in .env (DO NOT COMMIT)"
  value = {
    for name, token in random_password.workload_tokens :
    "WORKLOAD_TOKEN_${upper(name)}" => token.result
  }
  sensitive = true
}

output "audit_schema" {
  description = "Audit event schema for logging"
  value       = local.audit_event_schema
}
