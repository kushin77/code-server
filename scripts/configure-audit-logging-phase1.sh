#!/usr/bin/env bash
# @file        scripts/configure-audit-logging-phase1.sh
# @module      operations
# @description configure audit logging phase1 — on-prem code-server
# @owner       platform
# @status      active
#
# P1 #388 - IAM Audit Event Schema & Logging Configuration
# Phase 1: Identity & Workload Authentication Standardization
#
# Defines the canonical audit event format and storage configuration
# for all authentication, authorization, and identity management events
#

cat > ./config/iam/audit-event-schema.json <<'SCHEMA_EOF'
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "IAM Audit Event Schema",
  "description": "Canonical audit event format for P1 #388 logging (identity, auth, authz, privilege changes)",
  "version": "1.0",
  "type": "object",
  
  "required": [
    "event_id",
    "timestamp",
    "event_type",
    "actor",
    "resource",
    "action",
    "result",
    "correlation_id"
  ],
  
  "properties": {
    "event_id": {
      "type": "string",
      "description": "Unique event identifier (UUIDv4)",
      "pattern": "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
    },
    
    "timestamp": {
      "type": "string",
      "description": "Event timestamp (ISO 8601 UTC)",
      "format": "date-time"
    },
    
    "event_type": {
      "type": "string",
      "enum": [
        "authentication.login.success",
        "authentication.login.failure",
        "authentication.logout.success",
        "authentication.mfa.required",
        "authentication.mfa.challenge_sent",
        "authentication.mfa.verified",
        "authentication.mfa.failed",
        "authentication.token.created",
        "authentication.token.refreshed",
        "authentication.token.revoked",
        "authentication.token.expired",
        "authentication.session.established",
        "authentication.session.terminated",
        "authentication.session.timeout",
        "authorization.access_granted",
        "authorization.access_denied",
        "authorization.role_checked",
        "authorization.permission_checked",
        "authorization.policy_evaluated",
        "iam.user.created",
        "iam.user.updated",
        "iam.user.deleted",
        "iam.user.disabled",
        "iam.user.enabled",
        "iam.role.assigned",
        "iam.role.revoked",
        "iam.permission.granted",
        "iam.permission.revoked",
        "iam.service_account.created",
        "iam.service_account.deleted",
        "iam.service_account.key_created",
        "iam.service_account.key_rotated",
        "iam.service_account.key_revoked",
        "iam.policy.created",
        "iam.policy.updated",
        "iam.policy.deleted",
        "iam.mfa.enrolled",
        "iam.mfa.unenrolled",
        "iam.mfa.method_added",
        "iam.mfa.method_removed",
        "iam.workload_identity.federated",
        "iam.workload_identity.authenticated",
        "audit.log.exported",
        "audit.log.archived",
        "audit.log.retention_policy.changed",
        "audit.log.access.granted",
        "audit.log.access.denied"
      ],
      "description": "Type of IAM event that occurred"
    },
    
    "actor": {
      "type": "object",
      "description": "The entity (user or service) that performed the action",
      "required": ["identity_type", "id"],
      "properties": {
        "identity_type": {
          "type": "string",
          "enum": ["human", "workload", "automation", "system"],
          "description": "Type of identity that performed the action"
        },
        "id": {
          "type": "string",
          "description": "Unique identifier of the actor (user ID, service account, CI/CD runner)"
        },
        "email": {
          "type": "string",
          "description": "Email address (for human users)"
        },
        "github_login": {
          "type": "string",
          "description": "GitHub username (if applicable)"
        },
        "service_account_name": {
          "type": "string",
          "description": "K8s service account name (if workload)"
        },
        "service_account_namespace": {
          "type": "string",
          "description": "K8s namespace (if workload)"
        },
        "roles": {
          "type": "array",
          "items": {"type": "string"},
          "description": "Roles held by the actor at time of event"
        },
        "ip_address": {
          "type": "string",
          "description": "Source IP address"
        },
        "user_agent": {
          "type": "string",
          "description": "HTTP User-Agent (for web-based actions)"
        }
      }
    },
    
    "resource": {
      "type": "object",
      "description": "The resource that was accessed or modified",
      "required": ["type", "id"],
      "properties": {
        "type": {
          "type": "string",
          "description": "Resource type (e.g., code-server, backstage, user, role, secret)"
        },
        "id": {
          "type": "string",
          "description": "Resource identifier"
        },
        "namespace": {
          "type": "string",
          "description": "Namespace/environment (prod, staging, dev)"
        },
        "labels": {
          "type": "object",
          "description": "Resource labels or metadata"
        }
      }
    },
    
    "action": {
      "type": "string",
      "description": "The action performed (service:action format)",
      "examples": [
        "iam:login",
        "iam:logout",
        "iam:role_assign",
        "code-server:execute",
        "terraform:apply",
        "backstage:catalog_write"
      ]
    },
    
    "result": {
      "type": "object",
      "description": "Outcome of the action",
      "required": ["status"],
      "properties": {
        "status": {
          "type": "string",
          "enum": ["success", "failure", "denied"],
          "description": "Overall result status"
        },
        "reason": {
          "type": "string",
          "description": "Reason for failure or denial"
        },
        "error_code": {
          "type": "string",
          "description": "Application error code (if failure)"
        },
        "details": {
          "type": "object",
          "description": "Additional result details"
        }
      }
    },
    
    "context": {
      "type": "object",
      "description": "Additional context for the event",
      "properties": {
        "session_id": {
          "type": "string",
          "description": "Session identifier for grouping related events"
        },
        "request_id": {
          "type": "string",
          "description": "Request identifier from API/HTTP layer"
        },
        "correlation_id": {
          "type": "string",
          "description": "Distributed trace correlation ID"
        },
        "parent_event_id": {
          "type": "string",
          "description": "Parent event ID (for event chains)"
        },
        "environment": {
          "type": "string",
          "enum": ["development", "staging", "production"],
          "description": "Deployment environment"
        },
        "service": {
          "type": "string",
          "description": "Service that logged this event"
        },
        "severity": {
          "type": "string",
          "enum": ["info", "warning", "error", "critical"],
          "description": "Event severity level"
        }
      }
    },
    
    "authentication": {
      "type": "object",
      "description": "Authentication-specific details",
      "properties": {
        "auth_method": {
          "type": "string",
          "enum": ["oauth2", "mfa", "webauthn", "totp", "sms", "basic", "token", "service_account"],
          "description": "Authentication method used"
        },
        "mfa_method": {
          "type": "string",
          "enum": ["totp", "webauthn", "sms", "email"],
          "description": "MFA method used (if multi-factor)"
        },
        "mfa_verified": {
          "type": "boolean",
          "description": "Whether MFA was successfully verified"
        },
        "provider": {
          "type": "string",
          "enum": ["google", "github", "keycloak", "ldap", "local"],
          "description": "Identity provider used"
        },
        "token_age_seconds": {
          "type": "integer",
          "description": "Age of authentication token when used"
        }
      }
    },
    
    "authorization": {
      "type": "object",
      "description": "Authorization-specific details",
      "properties": {
        "role_required": {
          "type": "string",
          "description": "Role required for the action"
        },
        "role_held": {
          "type": "string",
          "description": "Role held by the actor"
        },
        "permission_required": {
          "type": "string",
          "description": "Specific permission checked"
        },
        "policy_matched": {
          "type": "array",
          "items": {"type": "string"},
          "description": "Policies that matched for this action"
        }
      }
    },
    
    "compliance": {
      "type": "object",
      "description": "Compliance and regulatory information",
      "properties": {
        "requires_audit": {
          "type": "boolean",
          "description": "Whether this event must be audited"
        },
        "pii_involved": {
          "type": "boolean",
          "description": "Whether PII is involved"
        },
        "retention_days": {
          "type": "integer",
          "description": "Required retention period for this audit event"
        }
      }
    }
  },
  
  "examples": [
    {
      "event_id": "550e8400-e29b-41d4-a716-446655440000",
      "timestamp": "2026-04-22T10:30:45Z",
      "event_type": "authentication.login.success",
      "actor": {
        "identity_type": "human",
        "id": "user-123",
        "email": "developer@kushin.cloud",
        "github_login": "alice-dev",
        "roles": ["operator"],
        "ip_address": "192.168.1.100",
        "user_agent": "Mozilla/5.0..."
      },
      "resource": {
        "type": "code-server",
        "id": "code-server-prod",
        "namespace": "prod"
      },
      "action": "iam:login",
      "result": {
        "status": "success"
      },
      "context": {
        "session_id": "sess-abc-123",
        "correlation_id": "req-xyz-789",
        "environment": "production",
        "service": "oauth2-proxy",
        "severity": "info"
      },
      "authentication": {
        "auth_method": "oauth2",
        "provider": "google",
        "mfa_verified": true,
        "mfa_method": "webauthn"
      },
      "compliance": {
        "requires_audit": true,
        "pii_involved": true,
        "retention_days": 365
      }
    },
    {
      "event_id": "660e9500-e39c-51e4-b827-557766551111",
      "timestamp": "2026-04-22T10:35:20Z",
      "event_type": "authorization.access_granted",
      "actor": {
        "identity_type": "human",
        "id": "user-123",
        "roles": ["operator"]
      },
      "resource": {
        "type": "terraform",
        "id": "prod-deployment",
        "namespace": "prod"
      },
      "action": "terraform:plan",
      "result": {
        "status": "success"
      },
      "context": {
        "session_id": "sess-abc-123",
        "correlation_id": "req-xyz-789",
        "environment": "production",
        "service": "rbac-enforcer",
        "severity": "info"
      },
      "authorization": {
        "role_required": "operator",
        "role_held": "operator",
        "permission_required": "terraform:plan",
        "policy_matched": ["rbac-policies-v1.0"]
      },
      "compliance": {
        "requires_audit": true,
        "retention_days": 365
      }
    }
  ]
}
SCHEMA_EOF

echo "✓ Created audit event schema: ./config/iam/audit-event-schema.json"

# Create audit logging configuration
cat > ./config/iam/audit-logging-config.yaml <<'AUDIT_CONFIG_EOF'
# P1 #388 - Audit Logging Configuration
# Defines where and how audit events are stored and retained

version: "1.0"
iam_issue: "P1 #388"
phase: 1

# Audit event sinks (where audit events are written)
sinks:
  
  # Primary: Loki for searchable audit logs
  loki:
    enabled: true
    priority: 1
    endpoint: "http://loki:3100/loki/api/v1/push"
    batch_size: 100
    flush_interval_seconds: 5
    labels:
      environment: "${ENVIRONMENT}"
      service: "iam-audit"
      component: "audit-logger"
    
    # Event types to send to Loki
    event_types:
      - "authentication.*"
      - "authorization.*"
      - "iam.*"
      - "audit.*"
  
  # Secondary: PostgreSQL for immutable audit trail
  postgresql:
    enabled: true
    priority: 2
    connection_string: "postgresql://audit_user:${AUDIT_DB_PASSWORD}@postgres:5432/audit_logs"
    table_name: "iam_audit_events"
    batch_size: 1000
    flush_interval_seconds: 30
    
    # Column mapping
    columns:
      event_id: "event_id"
      timestamp: "event_timestamp"
      event_type: "event_type"
      actor_id: "actor_id"
      actor_email: "actor_email"
      action: "action"
      resource_type: "resource_type"
      resource_id: "resource_id"
      result_status: "result_status"
      result_reason: "result_reason"
      correlation_id: "correlation_id"
      raw_event: "raw_event_json"
    
    # Retention policy
    retention:
      policy: "immutable_with_archive"
      retention_days: 730  # 2 years
      archive_after_days: 90
      archive_destination: "s3://kushin-audit-archive/"
  
  # Tertiary: AWS S3 for long-term archival
  s3:
    enabled: true
    priority: 3
    bucket: "kushin-audit-archive"
    region: "us-east-1"
    prefix: "iam-audit/"
    
    # Partition key for efficient querying
    partition_key: "year=2026/month=04/day=22"
    
    # Compression
    compression: "gzip"
    
    # Encryption
    encryption: "AES256"
    kms_key_id: "${KMS_KEY_ID}"
    
    # Lifecycle policy
    lifecycle:
      storage_class: "STANDARD"
      transition_to_glacier_days: 90
      delete_after_days: 2555  # 7 years (compliance requirement)

# Event routing rules
routing:
  
  # Sensitive events always go to all sinks
  critical:
    event_types:
      - "iam.policy.deleted"
      - "iam.user.deleted"
      - "iam.role.revoked"
      - "authentication.mfa.failed"
      - "authorization.access_denied"
    destinations: ["loki", "postgresql", "s3"]
    alert_on_receipt: true
  
  # Standard IAM events
  standard:
    event_types:
      - "authentication.*"
      - "authorization.*"
      - "iam.*"
    destinations: ["loki", "postgresql"]
    alert_on_receipt: false
  
  # Audit log operations
  audit_log_ops:
    event_types:
      - "audit.*"
    destinations: ["loki", "postgresql", "s3"]
    alert_on_receipt: true

# Alerting rules (integration with Prometheus AlertManager)
alerting:
  
  # Authentication failures
  authentication_failures:
    condition: "rate(authentication_failure_total[5m]) > 10"
    severity: "warning"
    message: "High rate of authentication failures detected"
    
  # Privilege escalation
  privilege_escalation:
    condition: "iam_role_assignment_total{target_role=~'admin|operator'}"
    severity: "critical"
    message: "Privilege escalation detected"
    
  # Policy violations
  policy_violations:
    condition: "authorization_denial_total > 0"
    severity: "info"
    message: "Authorization policy violation occurred"
    
  # Audit log tampering
  audit_log_tampering:
    condition: "audit_event_deletion_total > 0"
    severity: "critical"
    message: "Attempt to delete immutable audit log"

# Access control for audit logs
access_control:
  
  # Who can read audit logs
  readers:
    - role: "admin"
      permissions: ["*"]
    
    - role: "operator"
      permissions:
        - "audit:read"
        - "audit:query"
        # Cannot read: authentication details for other users
        # Cannot export: full audit logs
    
    - role: "security-team"
      permissions:
        - "audit:*"
        - "audit:export"
  
  # Audit log read access must be logged
  log_reads: true
  
  # Time-based access restrictions
  restrictions:
    - time_range: "18:00-06:00"
      role: "operator"
      action: "audit:export"
      effect: "deny"
      reason: "After-hours exports require admin approval"

# Compliance & Retention
compliance:
  
  # Regulations requiring audit logs
  regulations: ["GDPR", "SOC2", "ISO27001"]
  
  # Immutability requirements
  immutability:
    enabled: true
    algorithm: "SHA256"
    verify_on_read: true
    alert_on_tampering: true
  
  # Data residency
  residency:
    allowed_regions: ["us-east-1", "eu-west-1"]
    encryption_required: true
    
  # Retention periods by event type
  retention_matrix:
    "iam.policy.*":
      days: 2555  # 7 years (infrastructure decisions)
    
    "authentication.*":
      days: 730  # 2 years (user activity)
    
    "authorization.*":
      days: 365  # 1 year (access decisions)
    
    "iam.*":
      days: 730  # 2 years (identity changes)

# Audit log query interface
query_interface:
  
  # Query methods available
  methods:
    - type: "LogQL"
      description: "Loki query language for log-based queries"
      enabled: true
    
    - type: "SQL"
      description: "PostgreSQL SQL for structured queries"
      enabled: true
    
    - type: "REST API"
      description: "REST API for programmatic access"
      enabled: true
  
  # Rate limiting on query
  rate_limiting:
    queries_per_minute: 60
    results_per_query: 10000
  
  # Query audit (log who queries audit logs)
  audit_queries: true

# Audit log export
export:
  
  # Export formats
  formats: ["JSON", "CSV", "Parquet"]
  
  # Export destinations
  destinations:
    - type: "local_file"
      enabled: true
      path: "/exports/{date}.json"
    
    - type: "s3"
      enabled: true
      bucket: "kushin-audit-exports"
      prefix: "exports/{date}/"
    
    - type: "email"
      enabled: true
      to: "audit-team@kushin.cloud"
  
  # Scheduled exports
  schedules:
    - name: "daily_export"
      frequency: "0 0 * * *"  # Daily at midnight
      format: "JSON"
      destination: "s3"
    
    - name: "weekly_report"
      frequency: "0 0 * * 0"  # Weekly on Sunday
      format: "CSV"
      destination: "email"
AUDIT_CONFIG_EOF

echo "✓ Created audit logging config: ./config/iam/audit-logging-config.yaml"
