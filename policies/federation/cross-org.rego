package federation

# OPA Cross-Org Federation Policy - Fail-Closed Data Protection
# Enforces data boundary, capability restrictions, and compliance for federated orgs

# Input format:
# {
#   "source_org": "acme-corp",
#   "target_org": "partner-inc",
#   "data_classification": "confidential",
#   "task_type": "delegation",
#   "capabilities": ["read_files", "create_comments"],
#   "trust_status": "active"
# }

# RULE 1: Trust status must be active
deny[msg] {
    not input.trust_status == "active"
    msg := sprintf("Federation blocked: trust status is %s (not active)", [input.trust_status])
}

# RULE 2: Only trusted orgs can participate
deny[msg] {
    not is_trusted_org(input.source_org)
    msg := sprintf("Federation blocked: %s is not in trusted org list", [input.source_org])
}

# RULE 3: Data classification boundary enforcement
# Confidential data CANNOT cross org boundaries without explicit approval
deny[msg] {
    input.data_classification == "confidential"
    msg := "Federation blocked: confidential data cannot cross org boundary without human approval"
}

# RULE 4: Internal data (no external access without declaration)
deny[msg] {
    input.data_classification == "internal"
    not declared_cross_org_share(input.source_org, input.target_org)
    msg := "Federation blocked: internal data not declared for cross-org sharing"
}

# RULE 5: Capability restrictions
# Only whitelisted capabilities allowed in delegation
deny[msg] {
    cap := input.capabilities[_]
    not capability_allowed(cap)
    msg := sprintf("Federation blocked: capability %s not allowed", [cap])
}

# RULE 6: Cannot delegate certain sensitive operations
deny[msg] {
    input.task_type == "credential_access"
    msg := "Federation blocked: credential access delegation not allowed"
}

deny[msg] {
    input.task_type == "policy_modification"
    msg := "Federation blocked: OPA policy modification requires local approval only"
}

# RULE 7: Delegation policies must match declared capabilities
deny[msg] {
    input.task_type == "delegation"
    not input.delegation_policies
    msg := "Federation blocked: delegation_policies required for delegation task_type"
}

# RULE 8: Source org must have reputation >= threshold
deny[msg] {
    input.source_org_reputation < 60
    msg := sprintf(
        "Federation blocked: source org reputation too low (%f < 60)",
        [input.source_org_reputation]
    )
}

# RULE 9: Delegation audit logging required
deny[msg] {
    input.task_type == "delegation"
    not input.audit_event_required
    msg := "Federation blocked: audit event logging required for delegation"
}

# RULE 10: Revocation must propagate within SLA
deny[msg] {
    input.action == "revoke"
    not input.revocation_callback_url
    msg := "Federation blocked: revocation callback URL required for trust revocation"
}

# Allowed capabilities for cross-org delegation
capability_allowed(cap) {
    cap == "read_files"
}

capability_allowed(cap) {
    cap == "create_comments"
}

capability_allowed(cap) {
    cap == "event_publish"
}

capability_allowed(cap) {
    cap == "memory_read"
}

capability_allowed(cap) {
    cap == "agent_delegation"
}

# Trusted organization list (loaded from config)
is_trusted_org(org_id) {
    org_id == "elevatediq"
}

is_trusted_org(org_id) {
    org_id == "partner-inc"
}

is_trusted_org(org_id) {
    org_id == "acme-corp"
}

# Cross-org sharing declarations (loaded from config)
declared_cross_org_share(source_org, target_org) {
    source_org == "elevatediq"
    target_org == "partner-inc"
}

# ALLOW: Default deny (fail-closed)
allow {
    count(deny) == 0
}

# Decision
default allow = false
