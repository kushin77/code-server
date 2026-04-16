# ════════════════════════════════════════════════════════════════════════════════════════════
# P1 #388: Audit Logging Infrastructure
#
# Implements comprehensive audit trail for all authentication, authorization, and privileged
# operations across all tiers (human, workload, automation).
#
# Status: Implementation Phase
# Date: April 22, 2026
# ════════════════════════════════════════════════════════════════════════════════════════════

# ════════════════════════════════════════════════════════════════════════════════════════════
# AUDIT LOGGING CONFIGURATION
# ════════════════════════════════════════════════════════════════════════════════════════════

locals {
  audit_logging = {
    enabled = true
    
    # Log collection (via Loki)
    loki_config = {
      endpoint     = "http://loki:3100"
      tenant_id    = "audit"
      
      # Labels for audit logs
      labels = {
        component    = "audit"
        environment  = var.environment
        cluster      = var.cluster_name
        retention    = "audit"  # triggers special retention policy
      }
    }
    
    # Audit log streams by category
    log_streams = {
      authentication = {
        name        = "audit_authentication"
        description = "User login/logout, session creation/termination, MFA events"
        retention   = "90 days"
        level       = "info"
      }
      
      authorization = {
        name        = "audit_authorization"
        description = "Permission checks, access grants/denials, RBAC decisions"
        retention   = "90 days"
        level       = "info"
      }
      
      privileged_operations = {
        name        = "audit_privileged"
        description = "Admin actions, secret access, infrastructure changes, emergency access"
        retention   = "1 year"
        level       = "warning"
      }
      
      security_events = {
        name        = "audit_security"
        description = "Unauthorized access attempts, policy violations, token revocations"
        retention   = "3 years"
        level       = "error"
      }
      
      token_lifecycle = {
        name        = "audit_tokens"
        description = "Token creation, rotation, expiration, revocation"
        retention   = "1 year"
        level       = "info"
      }
      
      service_accounts = {
        name        = "audit_service_accounts"
        description = "Service account creation, modification, deletion"
        retention   = "1 year"
        level       = "info"
      }
    }
  }
}

# ════════════════════════════════════════════════════════════════════════════════════════════
# AUDIT LOG INDEXING & QUERYING (Loki index strategy)
# ════════════════════════════════════════════════════════════════════════════════════════════

locals {
  loki_index_strategy = {
    # Index labels for efficient querying
    indexed_labels = {
      # Always indexed
      component        = "audit"
      log_stream       = "authentication|authorization|privileged_operations|security_events|token_lifecycle|service_accounts"
      
      # Indexed for common queries
      human_identity   = "email pattern"
      human_role       = "admin|developer|viewer"
      workload_identity = "service-account-name"
      action_type      = "READ|WRITE|DELETE|EXECUTE|ADMIN"
      result_status    = "allowed|denied|error"
      
      # Indexed for security alerts
      severity         = "info|warning|error|critical"
    }
    
    # Query retention (how long each index is kept)
    index_retention = {
      hot_index   = 24         # hours (fast query)
      warm_index  = 30         # days (medium query)
      cold_index  = 365        # days (slow query, immutable)
    }
  }
}

# ════════════════════════════════════════════════════════════════════════════════════════════
# AUDIT LOG SINK CONFIGURATIONS (Multi-sink for compliance)
# ════════════════════════════════════════════════════════════════════════════════════════════

locals {
  audit_sinks = {
    loki_primary = {
      type          = "loki"
      endpoint      = "http://loki:3100"
      batch_size    = 100
      flush_interval = "5s"
      
      # Retry configuration
      retry = {
        enabled      = true
        max_retries  = 3
        backoff_multiplier = 2
        initial_interval = "100ms"
        max_interval = "30s"
      }
    }
    
    file_immutable = {
      type          = "file"
      path          = "/var/log/audit-immutable"
      format        = "json"
      rotation = {
        max_size_mb = 100
        max_age_days = 1      # daily rotation
        max_backups  = 1095   # 3 years of daily logs
      }
      permissions = {
        file_mode = "0400"    # read-only
        owner     = "root"
        group     = "root"
      }
      # Prevent deletion/modification
      immutable    = true     # requires filesystem support (ext4 with chattr +i)
    }
    
    postgres_audit = {
      type          = "postgresql"
      connection    = "postgresql://audit_user:${var.audit_db_password}@postgres:5432/audit_logs"
      table         = "audit_events"
      batch_size    = 500
      flush_interval = "10s"
      
      # Data retention in DB
      retention = {
        retention_days = 365
        archive_after  = 90   # move to cold storage
      }
    }
  }
}

# ════════════════════════════════════════════════════════════════════════════════════════════
# AUDIT ALERTING RULES (Real-time security alerts)
# ════════════════════════════════════════════════════════════════════════════════════════════

locals {
  audit_alerts = {
    # Authentication alerts
    "UnauthorizedLoginAttempt" = {
      description = "Failed login attempt after 3 retries"
      condition   = "rate(failed_auth[5m]) > 3"
      severity    = "warning"
      action      = "log|alert|block-ip"
    }
    
    "AdminLoginOutsideBusinessHours" = {
      description = "Admin user logging in outside business hours (unless on-call)"
      condition   = "admin_login AND (hour < 6 OR hour > 20)"
      severity    = "info"
      action      = "log|notify"
    }
    
    # Authorization alerts
    "UnauthorizedPrivilegeEscalation" = {
      description = "User attempting to elevate from developer to admin"
      condition   = "authorization_denied AND (admin_permission_required)"
      severity    = "critical"
      action      = "log|alert|revoke-session|notify-security"
    }
    
    "UnusualSecretAccess" = {
      description = "Service account accessing secrets outside normal pattern"
      condition   = "secrets_read > 10 OR secrets_write > 0"  # read limit, write alert
      severity    = "critical"
      action      = "log|alert|revoke-token|notify-security"
    }
    
    # Privileged operation alerts
    "AdminActionInProduction" = {
      description = "Admin modifying production infrastructure"
      condition   = "admin_action AND environment=production"
      severity    = "warning"
      action      = "log|alert|notify"
    }
    
    "BreakGlassUsed" = {
      description = "Emergency break-glass account activated"
      condition   = "action_type=break-glass"
      severity    = "critical"
      action      = "log|alert|immediate-notify-all-admins|audit-review-required"
    }
    
    # Token lifecycle alerts
    "TokenLeakDetected" = {
      description = "Token used from multiple IPs within short timeframe"
      condition   = "distinct(source_ip) > 1 AND time_delta < 5m"
      severity    = "critical"
      action      = "log|alert|revoke-token|notify-security"
    }
    
    "ExpiredTokenUsageAttempt" = {
      description = "Attempt to use expired token"
      condition   = "token_expired AND usage_attempt"
      severity    = "warning"
      action      = "log|deny-request"
    }
  }
}

# ════════════════════════════════════════════════════════════════════════════════════════════
# AUDIT LOG RETENTION POLICIES (Compliance & Cost)
# ════════════════════════════════════════════════════════════════════════════════════════════

locals {
  retention_policies = {
    authentication_logs = {
      hot_storage   = "7 days"      # Fast query
      warm_storage  = "83 days"     # Slower, less frequent
      cold_storage  = 0             # Purge after warm period
      description   = "User sessions, login/logout events"
    }
    
    authorization_logs = {
      hot_storage   = "7 days"
      warm_storage  = "83 days"
      cold_storage  = 0
      description   = "Permission checks, RBAC decisions"
    }
    
    privileged_operations = {
      hot_storage   = "30 days"     # Longer hot for admin audit
      warm_storage  = "330 days"    # 1 year total
      cold_storage  = 0
      description   = "Admin actions, critical operations"
    }
    
    security_events = {
      hot_storage   = "30 days"     # Security-sensitive
      warm_storage  = "1095 days"   # 3 years total (compliance requirement)
      cold_storage  = "permanent"   # Archive to S3 WORM
      description   = "Unauthorized access, breaches, incidents"
    }
    
    token_lifecycle = {
      hot_storage   = "14 days"     # Token operations
      warm_storage  = "351 days"    # 1 year total
      cold_storage  = 0
      description   = "Token creation, rotation, revocation"
    }
  }
}

# ════════════════════════════════════════════════════════════════════════════════════════════
# AUDIT DATABASE SCHEMA (PostgreSQL)
# ════════════════════════════════════════════════════════════════════════════════════════════

locals {
  audit_db_schema = {
    table_name = "audit_events"
    columns = {
      id                 = "BIGSERIAL PRIMARY KEY"
      timestamp          = "TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()"
      correlation_id     = "UUID NOT NULL"
      request_id         = "UUID NOT NULL"
      
      human_identity     = "TEXT"
      human_role         = "VARCHAR(50)"
      workload_identity  = "TEXT"
      workload_type      = "VARCHAR(50)"
      
      action_type        = "VARCHAR(50) NOT NULL"
      action_resource    = "TEXT"
      action_method      = "VARCHAR(10)"
      action_details     = "JSONB"
      
      result_status      = "VARCHAR(50) NOT NULL"
      result_code        = "INTEGER"
      result_message     = "TEXT"
      
      source_ip          = "INET"
      source_user_agent  = "TEXT"
      session_id         = "UUID"
      mfa_verified       = "BOOLEAN"
      
      latency_ms         = "BIGINT"
      size_bytes         = "BIGINT"
      
      severity           = "VARCHAR(50)"
      category           = "VARCHAR(50) NOT NULL"
      environment        = "VARCHAR(50)"
    }
    
    indexes = [
      "CREATE INDEX idx_audit_timestamp ON audit_events(timestamp DESC)"
      "CREATE INDEX idx_audit_correlation_id ON audit_events(correlation_id)"
      "CREATE INDEX idx_audit_human_identity ON audit_events(human_identity)"
      "CREATE INDEX idx_audit_workload_identity ON audit_events(workload_identity)"
      "CREATE INDEX idx_audit_action_type ON audit_events(action_type)"
      "CREATE INDEX idx_audit_result_status ON audit_events(result_status)"
      "CREATE INDEX idx_audit_timestamp_category ON audit_events(timestamp DESC, category)"
    ]
    
    retention_trigger = {
      name = "audit_retention"
      query = "DELETE FROM audit_events WHERE timestamp < NOW() - INTERVAL '${lookup(local.retention_policies[current_category], 'cold_storage', '90 days')}'"
      schedule = "0 2 * * *"  # 2 AM daily
    }
  }
}

# ════════════════════════════════════════════════════════════════════════════════════════════
# OUTPUTS: Audit configuration for deployment
# ════════════════════════════════════════════════════════════════════════════════════════════

output "audit_logging_config" {
  description = "Complete audit logging configuration"
  value       = local.audit_logging
}

output "audit_log_streams" {
  description = "Audit log stream definitions"
  value       = local.audit_logging.log_streams
}

output "audit_alerts" {
  description = "Audit alerting rules for security monitoring"
  value       = local.audit_alerts
}

output "retention_policies" {
  description = "Data retention policies by log type"
  value       = local.retention_policies
}

output "loki_index_strategy" {
  description = "Loki indexing and query optimization strategy"
  value       = local.loki_index_strategy
}

output "audit_db_schema" {
  description = "PostgreSQL audit events table schema"
  value       = local.audit_db_schema
}
