# ════════════════════════════════════════════════════════════════════════════════════════════
# P1 #388: RBAC (Role-Based Access Control) Enforcement
#
# Implements fine-grained authorization at multiple layers:
#   - Reverse proxy (Caddy/Kong)
#   - API endpoints
#   - Resource access (files, secrets, databases)
#
# Status: Implementation Phase
# Date: April 22, 2026
# ════════════════════════════════════════════════════════════════════════════════════════════

# ════════════════════════════════════════════════════════════════════════════════════════════
# RBAC POLICY DEFINITIONS (Core rules)
# ════════════════════════════════════════════════════════════════════════════════════════════

locals {
  # Role-to-permission mapping (base definitions)
  rbac_policies = {
    
    # ════════════════════════════════════════════════════════════════════════════════════
    # CODE-SERVER ACCESS CONTROL
    # ════════════════════════════════════════════════════════════════════════════════════
    code_server = {
      endpoint_prefix = "/code-server"
      
      rules = {
        # Public endpoints (no auth required)
        public = {
          paths = [
            "/code-server/healthz",
            "/code-server/version"
          ]
          allowed_roles = ["*"]  # everyone
          methods       = ["GET"]
        }
        
        # Full access (developers and above)
        full_access = {
          paths = [
            "/code-server/**"
          ]
          allowed_roles = ["developer", "admin"]
          methods       = ["GET", "POST", "PUT", "PATCH", "DELETE"]
          rate_limit    = 1000  # req/min per user
        }
        
        # Read-only access (viewers)
        read_only = {
          paths = [
            "/code-server/api/v1/files/**",
            "/code-server/api/v1/extensions",
            "/code-server/api/v1/workspace/info"
          ]
          allowed_roles = ["viewer"]
          methods       = ["GET"]
          rate_limit    = 100   # req/min
        }
        
        # Admin-only operations
        admin_only = {
          paths = [
            "/code-server/api/v1/extensions/install",
            "/code-server/api/v1/server/shutdown",
            "/code-server/api/v1/server/restart",
            "/code-server/api/v1/debug/**"
          ]
          allowed_roles = ["admin"]
          methods       = ["POST", "PUT", "DELETE"]
          requires_mfa  = true
          rate_limit    = 10    # req/min (sensitive operations)
        }
      }
    }
    
    # ════════════════════════════════════════════════════════════════════════════════════
    # OBSERVABILITY ACCESS CONTROL (Prometheus, Grafana, Jaeger, Loki)
    # ════════════════════════════════════════════════════════════════════════════════════
    observability = {
      endpoint_prefixes = ["/prometheus", "/grafana", "/jaeger", "/loki"]
      
      rules = {
        # Public dashboards (viewers can see)
        public_dashboards = {
          paths = [
            "/grafana/api/dashboards/search",
            "/grafana/d/public/**"
          ]
          allowed_roles = ["viewer", "developer", "admin"]
          methods       = ["GET"]
          rate_limit    = 100
        }
        
        # Query access (data view, not admin)
        query_access = {
          paths = [
            "/prometheus/api/v1/query**",
            "/loki/loki/api/v1/query_range",
            "/jaeger/api/traces",
            "/grafana/api/dashboards/**"
          ]
          allowed_roles = ["developer", "admin"]
          methods       = ["GET", "POST"]
          rate_limit    = 500
        }
        
        # Admin access (datasource config, alerts config)
        admin_access = {
          paths = [
            "/prometheus/api/v1/admin/**",
            "/prometheus/api/v1/alerts",
            "/grafana/api/datasources",
            "/grafana/api/alert-rules",
            "/loki/loki/api/v1/label"
          ]
          allowed_roles = ["admin"]
          methods       = ["GET", "POST", "PUT", "DELETE"]
          requires_mfa  = true
          rate_limit    = 100
        }
        
        # Audit log access (sensitive, restricted)
        audit_logs = {
          paths = [
            "/loki/loki/api/v1/query_range?.*audit.*",
            "/loki/api/v1/logs/audit"
          ]
          allowed_roles = ["admin"]
          methods       = ["GET"]
          requires_mfa  = true
          rate_limit    = 50
          log_all       = true  # log every query
        }
      }
    }
    
    # ════════════════════════════════════════════════════════════════════════════════════
    # SECRETS ACCESS CONTROL
    # ════════════════════════════════════════════════════════════════════════════════════
    secrets = {
      endpoint_prefix = "/secrets"
      
      rules = {
        # App secrets (read-only for developers)
        app_secrets = {
          paths = [
            "/secrets/app/**",
            "/secrets/config/**"
          ]
          allowed_roles = ["developer", "admin"]
          methods       = ["GET"]
          rate_limit    = 100
          log_all       = true
        }
        
        # System secrets (admin-only, MFA required)
        system_secrets = {
          paths = [
            "/secrets/vault/**",
            "/secrets/credentials/**",
            "/secrets/keys/**",
            "/secrets/certificates/**"
          ]
          allowed_roles = ["admin"]
          methods       = ["GET", "POST", "PUT", "DELETE"]
          requires_mfa  = true
          rate_limit    = 10
          log_all       = true
          alert_on_write = true  # alert on any write
        }
        
        # Rotating secrets (special handling)
        rotating_secrets = {
          paths = [
            "/secrets/rotating/**"
          ]
          allowed_roles = ["admin"]
          methods       = ["GET", "POST"]  # POST to rotate
          requires_mfa  = true
          rate_limit    = 5
          log_all       = true
          alert_on_access = true
        }
      }
    }
    
    # ════════════════════════════════════════════════════════════════════════════════════
    # DEPLOYMENT & INFRASTRUCTURE CONTROL
    # ════════════════════════════════════════════════════════════════════════════════════
    infrastructure = {
      endpoint_prefix = "/api/v1/infrastructure"
      
      rules = {
        # Viewing infrastructure
        view = {
          paths = [
            "/api/v1/infrastructure/status",
            "/api/v1/infrastructure/services",
            "/api/v1/infrastructure/nodes",
            "/api/v1/infrastructure/networking"
          ]
          allowed_roles = ["developer", "admin"]
          methods       = ["GET"]
          rate_limit    = 100
        }
        
        # Deployment operations
        deployments = {
          paths = [
            "/api/v1/infrastructure/deployments/**",
            "/api/v1/infrastructure/updates/**"
          ]
          allowed_roles = ["admin"]
          methods       = ["GET", "POST", "PATCH"]
          requires_mfa  = true
          requires_approval = true  # needs second approval
          rate_limit    = 10
          log_all       = true
        }
        
        # Destructive operations (delete nodes, scale down, etc)
        destructive = {
          paths = [
            "/api/v1/infrastructure/nodes/delete",
            "/api/v1/infrastructure/scale-down",
            "/api/v1/infrastructure/drain"
          ]
          allowed_roles = ["admin"]
          methods       = ["POST", "DELETE"]
          requires_mfa  = true
          requires_approval = true
          requires_multiple_approvals = 2  # need 2 admins
          rate_limit    = 1
          log_all       = true
          alert_on_use  = true
        }
      }
    }
    
    # ════════════════════════════════════════════════════════════════════════════════════
    # USER MANAGEMENT
    # ════════════════════════════════════════════════════════════════════════════════════
    user_management = {
      endpoint_prefix = "/api/v1/users"
      
      rules = {
        # View own profile
        self_view = {
          paths = [
            "/api/v1/users/me",
            "/api/v1/users/me/**"
          ]
          allowed_roles = ["*"]  # everyone
          methods       = ["GET"]
        }
        
        # Edit own profile (password, etc)
        self_edit = {
          paths = [
            "/api/v1/users/me/password",
            "/api/v1/users/me/mfa"
          ]
          allowed_roles = ["*"]  # everyone
          methods       = ["POST", "PUT"]
          requires_mfa  = false
        }
        
        # View user directory
        user_list = {
          paths = [
            "/api/v1/users",
            "/api/v1/users/search"
          ]
          allowed_roles = ["admin"]
          methods       = ["GET"]
          rate_limit    = 100
        }
        
        # User administration (add/remove/modify)
        admin = {
          paths = [
            "/api/v1/users/**",
            "/api/v1/users/*/role",
            "/api/v1/users/*/disable"
          ]
          allowed_roles = ["admin"]
          methods       = ["GET", "POST", "PUT", "DELETE", "PATCH"]
          requires_mfa  = true
          rate_limit    = 10
          log_all       = true
        }
      }
    }
  }
}

# ════════════════════════════════════════════════════════════════════════════════════════════
# RATE LIMITING BY ROLE & ENDPOINT
# ════════════════════════════════════════════════════════════════════════════════════════════

locals {
  rate_limits = {
    viewer = {
      default        = 100       # req/min
      bulk_ops       = 10
      auth_attempts  = 5
      secret_access  = 10
    }
    
    developer = {
      default        = 1000
      bulk_ops       = 100
      auth_attempts  = 20
      secret_access  = 100
    }
    
    admin = {
      default        = 10000
      bulk_ops       = 1000
      auth_attempts  = 50
      secret_access  = 500
    }
    
    service_account = {
      default        = 1000      # per service
      bulk_ops       = 100
      auth_attempts  = 10
      secret_access  = 100
    }
  }
}

# ════════════════════════════════════════════════════════════════════════════════════════════
# ENFORCEMENT POINTS (Where RBAC is checked)
# ════════════════════════════════════════════════════════════════════════════════════════════

locals {
  rbac_enforcement_points = {
    
    # Reverse proxy (first line of defense)
    caddy = {
      type = "reverse_proxy"
      location = "Caddyfile"
      checks = [
        "token_valid",
        "token_not_expired",
        "role_has_permission",
        "rate_limit_check",
        "mfa_verified (if required)"
      ]
      on_deny = "log|403|alert_if_suspicious"
    }
    
    # Kong API Gateway (secondary enforcement)
    kong = {
      type = "api_gateway"
      location = "Kong plugins"
      checks = [
        "token_valid",
        "rate_limit_check",
        "request_validation",
        "audit_log"
      ]
      on_deny = "log|403|alert"
    }
    
    # Application-level RBAC
    application = {
      type = "application_code"
      location = "Each service endpoint"
      checks = [
        "role_has_permission (in-app check)",
        "resource_ownership_check",
        "data_filtering_by_role"
      ]
      on_deny = "log|403|alert"
    }
    
    # Database-level (final safety check)
    database = {
      type = "row_level_security"
      location = "PostgreSQL RLS policies"
      checks = [
        "row_ownership_check",
        "role_based_visibility"
      ]
      on_deny = "log|403"
    }
  }
}

# ════════════════════════════════════════════════════════════════════════════════════════════
# OUTPUTS: RBAC configuration for deployment
# ════════════════════════════════════════════════════════════════════════════════════════════

output "rbac_policies" {
  description = "Complete RBAC policy definitions"
  value       = local.rbac_policies
}

output "rate_limits" {
  description = "Rate limiting configuration by role"
  value       = local.rate_limits
}

output "enforcement_points" {
  description = "RBAC enforcement points and checks"
  value       = local.rbac_enforcement_points
}
