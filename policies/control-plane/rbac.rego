package control_plane.rbac

import data.federation.orgs

# Role definitions
roles := {
    "global_admin": {
        "permissions": [
            "read:all-orgs",
            "write:all-orgs",
            "read:compliance-reports",
            "write:compliance-reports",
            "read:policies",
            "write:policies",
            "read:risk-scores",
            "write:risk-rules",
        ]
    },
    "org_admin": {
        "permissions": [
            "read:own-org",
            "write:own-org",
            "read:own-org-compliance",
            "read:own-org-policies",
            "write:own-org-policies",
            "read:own-org-risk",
        ]
    },
    "auditor": {
        "permissions": [
            "read:all-orgs",
            "read:compliance-reports",
            "read:audit-logs",
            "read:policies",
            "read:risk-scores",
        ]
    },
    "read_only": {
        "permissions": [
            "read:own-org",
        ]
    }
}

# User role assignment (federated from each org)
user_roles[org_id] := role {
    user_org := input.user.org_id
    user_role := input.user.role
    org_id := user_org
    role := user_role
}

# Permission check
has_permission(perm) {
    user_role := input.user.role
    roles[user_role].permissions[_] == perm
}

# Global admin bypass
is_global_admin {
    input.user.role == "global_admin"
}

# Org admin can only act on own org
is_org_admin {
    input.user.role == "org_admin"
    input.user.org_id == input.target_org
}

# Auditor read-only access
is_auditor {
    input.user.role == "auditor"
}

# Deny-by-default: all requests blocked unless explicitly allowed
default allow := false

# Allow global admin all actions
allow {
    is_global_admin
}

# Allow org admin to read/write own org
allow {
    is_org_admin
    input.action in ["read", "write", "update"]
}

# Allow auditor read-only
allow {
    is_auditor
    input.action == "read"
}

# Allow read-only role
allow {
    input.user.role == "read_only"
    input.action == "read"
    input.user.org_id == input.target_org
}

# Specific endpoint controls
# /dashboard - global_admin and auditor only
allow {
    input.path == "/dashboard"
    (is_global_admin or is_auditor)
}

# /policy/propagate - global_admin only
allow {
    input.path == "/policy/propagate"
    is_global_admin
}

# /risk/score - all authenticated users
allow {
    input.path == "/risk/score"
    input.user.authenticated
}

# /compliance/report - global_admin and auditor
allow {
    input.path == "/compliance/report"
    (is_global_admin or is_auditor)
}

# /health - public, no auth required
allow {
    input.path == "/health"
}

# Audit: log all permission checks
audit_event[event] {
    event := {
        "timestamp": now,
        "user": input.user.id,
        "action": input.action,
        "resource": input.target_org,
        "result": allow,
    }
}

# Deny with reason (used for audit)
deny[reason] {
    not allow
    reason := sprintf("User %v does not have permission for action %v on resource %v", [input.user.id, input.action, input.target_org])
}
