#!/usr/bin/env rego
# @file        policies/core/audit.rego
# @module      security/core
# @description Audit logging requirement - all sensitive actions must be logged
# @owner       security
# @status      production-ready
#
# Enforces that all sensitive operations are logged with required metadata

package policy.core.audit

# List of operations that require audit logging
sensitive_operations := [
    "deploy",
    "delete",
    "modify_secret",
    "change_permission",
    "access_pii",
    "ai_inference",
    "budget_adjustment",
]

# Check if operation is sensitive
is_sensitive_operation {
    operation := input.operation
    sensitive_operations[_] == operation
}

# Require audit fields for sensitive operations
allow {
    not is_sensitive_operation
}

allow {
    is_sensitive_operation
    input.audit_metadata != null
    input.audit_metadata.timestamp != null
    input.audit_metadata.user_id != null
    input.audit_metadata.session_id != null
    input.audit_metadata.action != null
}

# Deny if sensitive operation missing audit metadata
deny = is_sensitive_operation and not (
    input.audit_metadata != null and
    input.audit_metadata.timestamp != null and
    input.audit_metadata.user_id != null and
    input.audit_metadata.session_id != null
)

# Reason for denial
deny_reason[reason] {
    deny
    reason := sprintf(
        "Sensitive operation '%s' requires audit metadata (timestamp, user_id, session_id)",
        [input.operation]
    )
}

# Audit context that should be logged
audit_context := {
    "timestamp": input.audit_metadata.timestamp,
    "user_id": input.audit_metadata.user_id,
    "session_id": input.audit_metadata.session_id,
    "action": input.audit_metadata.action,
    "resource": input.audit_metadata.resource,
    "result": "allowed",
}
