package core.audit

# All sensitive actions must be audited
# Audit trail must include: who, what, when, why, and outcome

import future.keywords.if

# Sensitive actions requiring audit
sensitive_actions := [
    "deploy",
    "destroy",
    "modify_policy",
    "rotate_credentials",
    "grant_access",
    "delete_data",
    "export_secrets"
]

# Deny sensitive action if no audit information
deny[msg] {
    action := sensitive_actions[_]
    input.action == action
    not input.audit_id
    msg := sprintf("Audit policy violation: sensitive action '%s' requires audit_id", [action])
}

# Deny if no actor identity
deny[msg] {
    action := sensitive_actions[_]
    input.action == action
    not input.actor_id
    msg := "Audit policy violation: sensitive action requires actor_id"
}

# Deny if no timestamp
deny[msg] {
    action := sensitive_actions[_]
    input.action == action
    not input.timestamp
    msg := "Audit policy violation: sensitive action requires timestamp"
}

# Allow sensitive action with complete audit trail
allow[msg] {
    action := sensitive_actions[_]
    input.action == action
    input.audit_id
    input.actor_id
    input.timestamp
    input.reason
    msg := sprintf("Audit approved: %s by %s (audit_id: %s)", [input.action, input.actor_id, input.audit_id])
}

# Allow non-sensitive actions without audit
allow[msg] {
    action := sensitive_actions[_]
    input.action != action
    msg := sprintf("Non-sensitive action '%s' permitted without audit", [input.action])
}
